//! The Soapstone companion: a tray app that sits next to WoW, finds the
//! Soapstone addon's files and (in later steps) syncs them with the server.
//! Design: `docs/Ideas/Idea - Companion App (WoW).md`.
//!
//! One background thread does all the work: every couple of minutes, or when
//! asked, it scans for WoW folders, reads each account's SavedVariables and
//! checks in with the server. The tray menu and the window only show what it
//! found.

pub mod api;
pub mod config;
pub mod files;
pub mod installs;
pub mod lua;
pub mod savedvars;
pub mod soapdata;

use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use serde::Serialize;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, RunEvent, WindowEvent, Wry};

use crate::installs::{AddonFolder, GameFolder};
use crate::savedvars::{Read, Summary};

const SCAN_EVERY: Duration = Duration::from_secs(120);

#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub server: String,
    pub connected: bool,
    /// One line about the server: connected, or why not.
    pub connection: String,
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
        match self.folders.len() {
            0 => "No WoW folders found".into(),
            n => {
                let folders = if n == 1 { "1 WoW folder".to_string() } else { format!("{n} WoW folders") };
                match self.waiting() {
                    0 => folders,
                    1 => format!("{folders} · 1 change waiting"),
                    w => format!("{folders} · {w} changes waiting"),
                }
            }
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

fn folder_status(folder: GameFolder) -> FolderStatus {
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
    FolderStatus { name: folder.name, path: folder.path, addon: folder.addon, accounts }
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

fn work(app: AppHandle, wake: mpsc::Receiver<()>, headline: MenuItem<Wry>, connection: MenuItem<Wry>) {
    let mut config = config::load();
    loop {
        let folders: Vec<FolderStatus> = installs::find(&config.wow_folders).into_iter().map(folder_status).collect();
        let (connected, line) = check_in(&mut config);
        let status = Status {
            server: config.server.clone(),
            connected,
            connection: line,
            folders,
            scanned_at: unix_now(),
            config_path: config::path(),
        };
        let _ = headline.set_text(status.headline());
        let _ = connection.set_text(&status.connection);
        if let Some(tray) = app.tray_by_id("main") {
            let _ = tray.set_tooltip(Some(format!("Soapstone\n{}\n{}", status.headline(), status.connection)));
        }
        let _ = app.emit("status", &status);
        *app.state::<Shared>().status.lock().unwrap() = status;

        // A settling file is read again soon, not in two minutes.
        let settling = app.state::<Shared>().status.lock().unwrap().folders.iter().flat_map(|f| &f.accounts).any(|a| a.state == "settling");
        let wait = if settling { savedvars::SETTLE * 2 } else { SCAN_EVERY };
        match wake.recv_timeout(wait) {
            Ok(()) | Err(RecvTimeoutError::Timeout) => {
                // Drain repeated requests so one scan answers them all.
                while wake.try_recv().is_ok() {}
            }
            Err(RecvTimeoutError::Disconnected) => return,
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

    app.run(|_app, event| {
        // Only Quit (an explicit exit code) ends the app, not closing its window.
        if let RunEvent::ExitRequested { api, code: None, .. } = event {
            api.prevent_exit();
        }
    });
}
