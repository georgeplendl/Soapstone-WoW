//! The Soapstone companion: a tray app that sits next to WoW, uploads what
//! the Soapstone addon has waiting, and writes everyone's stones back into
//! the game (`SoapstoneData`). Design: `docs/Ideas/Idea - Companion App (WoW).md`.
//!
//! One background thread does all the work. Every couple of minutes, when a
//! SavedVariables file changes (a /reload or logout), or when asked, it scans
//! for WoW folders, reads each account, checks in with the server and syncs
//! (engine.rs). The tray menu and the window only show what it found.

pub mod account;
pub mod api;
pub mod config;
pub mod datafiles;
pub mod engine;
pub mod files;
pub mod installs;
pub mod lua;
pub mod savedvars;
pub mod soapdata;
pub mod sync;

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime};

use serde::Serialize;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, RunEvent, WindowEvent, Wry};

use crate::installs::{AddonFolder, GameFolder};
use crate::savedvars::{Read, Summary};

const SCAN_EVERY: Duration = Duration::from_secs(120);
/// How often SavedVariables files are checked for a /reload or logout.
const WATCH_EVERY: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub server: String,
    pub connected: bool,
    /// One plain line about the server, for the tray and the window.
    pub connection: String,
    /// What actually happened (errors included), for troubleshooting.
    pub connection_detail: String,
    /// This install's id on the server (not the secret token).
    pub install_id: Option<String>,
    pub folders: Vec<FolderStatus>,
    pub scanned_at: u64,
    pub config_path: PathBuf,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FolderStatus {
    pub name: String,
    pub path: PathBuf,
    pub addon: Option<AddonFolder>,
    pub accounts: Vec<AccountStatus>,
    pub sync: Option<engine::FolderSync>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountStatus {
    pub name: String,
    pub saved_variables: PathBuf,
    /// "missing", "settling", "ok" or "unreadable".
    pub state: &'static str,
    pub summary: Option<Summary>,
    pub error: Option<String>,
}

impl Status {
    fn waiting(&self) -> usize {
        self.folders.iter().flat_map(|f| &f.accounts).filter_map(|a| a.summary.as_ref()).map(|s| s.waiting).sum()
    }

    /// The first line of the tray menu.
    fn headline(&self) -> String {
        if self.folders.is_empty() {
            return "Couldn't find World of Warcraft".into();
        }
        match self.waiting() {
            0 => "Everything's shared".into(),
            1 => "1 change waiting to upload".into(),
            n => format!("{n} changes waiting to upload"),
        }
    }
}

struct Shared {
    status: Mutex<Status>,
    wake: Mutex<Sender<()>>,
}

#[tauri::command]
fn status(state: tauri::State<'_, Shared>) -> Status {
    state.status.lock().unwrap().clone()
}

#[tauri::command]
fn rescan(state: tauri::State<'_, Shared>) {
    let _ = state.wake.lock().unwrap().send(());
}

fn unix_now() -> u64 {
    SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

pub(crate) fn folder_status(folder: GameFolder) -> FolderStatus {
    let accounts = folder
        .accounts
        .into_iter()
        .map(|a| {
            let (state, summary, error) = match savedvars::read(&a.saved_variables) {
                Read::Missing => ("missing", None, None),
                Read::Settling => ("settling", None, None),
                Read::Ok(s) => ("ok", Some(s), None),
                Read::Unreadable(e) => ("unreadable", None, Some(e)),
            };
            AccountStatus { name: a.name, saved_variables: a.saved_variables, state, summary, error }
        })
        .collect();
    FolderStatus { name: folder.name, path: folder.path, addon: folder.addon, accounts, sync: None }
}

/// Makes sure this install is registered with the server and its token
/// still works. Returns (connected, one line for the tray).
fn check_in(config: &mut config::Config) -> (bool, String) {
    if let Some(reg) = config.registration().cloned() {
        // The cheapest authenticated call: a pull for no zones.
        let client = api::Client::new(&config.server, Some(&reg));
        match client.get::<serde_json::Value>("/v1/pull?flavor=forever&region=us") {
            Ok(_) => return (true, format!("Connected (install {})", &reg.install_id[..reg.install_id.len().min(8)])),
            // The server doesn't know this token (a wiped dev database, or an
            // admin reset): register again below.
            Err(api::ApiError::Server { status: 401, .. }) => {
                config.registrations.retain(|(s, _)| *s != config.server);
            }
            Err(e) => return (false, format!("Not connected: {e}")),
        }
    }
    match api::Client::new(&config.server, None).register() {
        Ok(reg) => {
            let id = reg.install_id.clone();
            config.set_registration(reg);
            match config::save(config) {
                Ok(()) => (true, format!("Connected (new install {})", &id[..id.len().min(8)])),
                Err(e) => (false, format!("Registered, but couldn't save {}: {e}", config::path().display())),
            }
        }
        Err(e) => (false, format!("Not connected: {e}")),
    }
}

/// When each SavedVariables file last changed, to notice a /reload or logout.
fn stamps(folders: &[FolderStatus]) -> BTreeMap<PathBuf, SystemTime> {
    folders
        .iter()
        .flat_map(|f| &f.accounts)
        .filter_map(|a| Some((a.saved_variables.clone(), std::fs::metadata(&a.saved_variables).ok()?.modified().ok()?)))
        .collect()
}

/// A file changed since `known` and has finished being written.
fn saved_since(known: &BTreeMap<PathBuf, SystemTime>) -> bool {
    known.keys().any(|path| {
        let Ok(modified) = std::fs::metadata(path).and_then(|m| m.modified()) else { return false };
        let settled = SystemTime::now().duration_since(modified).unwrap_or_default() >= savedvars::SETTLE;
        settled && known.get(path) != Some(&modified)
    })
}

/// One scan and sync, without any UI. `SOAPSTONE_WOW_ONLY` limits the scan
/// to one WoW folder (for testing against a copy).
pub fn gather(config: &mut config::Config) -> Status {
    let found = match std::env::var_os("SOAPSTONE_WOW_ONLY") {
        Some(root) => installs::scan_root(std::path::Path::new(&root)),
        None => installs::find(&config.wow_folders),
    };
    let mut folders: Vec<FolderStatus> = found.into_iter().map(folder_status).collect();
    let (connected, detail) = check_in(config);
    let line = if connected { "Connected to the Soapstone server" } else { "Can't reach the Soapstone server" }.to_string();
    let client = config.registration().map(|r| api::Client::new(&config.server, Some(r)));
    let server: Option<&dyn sync::Server> = if connected { client.as_ref().map(|c| c as &dyn sync::Server) } else { None };
    engine::sync_all(server, &mut folders, &config::dir(), unix_now());
    Status {
        server: config.server.clone(),
        connected,
        connection: line,
        connection_detail: detail,
        install_id: config.registration().map(|r| r.install_id.clone()),
        folders,
        scanned_at: unix_now(),
        config_path: config::path(),
    }
}

/// `soapstone-companion --sync-once`: one cycle, the result printed as JSON.
pub fn sync_once() {
    let mut config = config::load();
    let status = gather(&mut config);
    println!("{}", serde_json::to_string_pretty(&status).unwrap_or_default());
}

fn cycle(app: &AppHandle, config: &mut config::Config, headline: &MenuItem<Wry>, connection: &MenuItem<Wry>) -> Status {
    let status = gather(config);
    let _ = headline.set_text(status.headline());
    let _ = connection.set_text(&status.connection);
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_tooltip(Some(format!("Soapstone
{}
{}", status.headline(), status.connection)));
    }
    let _ = app.emit("status", &status);
    *app.state::<Shared>().status.lock().unwrap() = status.clone();
    status
}

fn work(app: AppHandle, wake: mpsc::Receiver<()>, headline: MenuItem<Wry>, connection: MenuItem<Wry>) {
    let mut config = config::load();
    let mut status = cycle(&app, &mut config, &headline, &connection);
    let mut known = stamps(&status.folders);
    let mut last = Instant::now();
    loop {
        let asked = match wake.recv_timeout(WATCH_EVERY) {
            Ok(()) => {
                // Drain repeated requests so one cycle answers them all.
                while wake.try_recv().is_ok() {}
                true
            }
            Err(RecvTimeoutError::Timeout) => false,
            Err(RecvTimeoutError::Disconnected) => return,
        };
        let settling = status.folders.iter().flat_map(|f| &f.accounts).any(|a| a.state == "settling");
        if asked || last.elapsed() >= SCAN_EVERY || saved_since(&known) || (settling && last.elapsed() >= savedvars::SETTLE * 2) {
            status = cycle(&app, &mut config, &headline, &connection);
            known = stamps(&status.folders);
            last = Instant::now();
        }
    }
}

fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn run() {
    let (wake_tx, wake_rx) = mpsc::channel();
    let app = tauri::Builder::default()
        .manage(Shared { status: Mutex::new(Status::default()), wake: Mutex::new(wake_tx) })
        .invoke_handler(tauri::generate_handler![status, rescan])
        .setup(move |app| {
            let headline = MenuItem::with_id(app, "headline", "Looking for WoW…", false, None::<&str>)?;
            let connection = MenuItem::with_id(app, "connection", "Connecting…", false, None::<&str>)?;
            let open = MenuItem::with_id(app, "open", "Open Soapstone", true, None::<&str>)?;
            let rescan = MenuItem::with_id(app, "rescan", "Check now", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(
                app,
                &[&headline, &connection, &PredefinedMenuItem::separator(app)?, &open, &rescan, &PredefinedMenuItem::separator(app)?, &quit],
            )?;
            let mut tray = TrayIconBuilder::with_id("main")
                .tooltip("Soapstone")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show_window(app),
                    "rescan" => {
                        let _ = app.state::<Shared>().wake.lock().unwrap().send(());
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        show_window(tray.app_handle());
                    }
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;

            let handle = app.handle().clone();
            std::thread::Builder::new().name("sync".into()).spawn(move || work(handle, wake_rx, headline, connection))?;
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window keeps the companion running in the tray.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .build(tauri::generate_context!())
        .expect("error while starting the Soapstone companion");

    app.run(|app, event| match event {
        // Only Quit (an explicit exit code) ends the app, not closing its window.
        RunEvent::ExitRequested { api, code: None, .. } => api.prevent_exit(),
        // Drawings are only shown while the companion runs.
        RunEvent::Exit => {
            let status = app.state::<Shared>().status.lock().unwrap().clone();
            for folder in status.folders.iter().filter(|f| f.sync.as_ref().is_some_and(|s| s.wrote)) {
                let _ = datafiles::clear_sketches(&folder.path);
            }
        }
        _ => {}
    });
}
