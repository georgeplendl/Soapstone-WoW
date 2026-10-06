//! One cycle of the companion's work, after a scan: read every account,
//! sync each game type and region once, and write `SoapstoneData` into each
//! game folder that has the addon.
//!
//! A game folder's accounts can in theory play different regions; the folder
//! gets the stones of its most recently saved account's game type and region
//! (one `SoapstoneData` per folder). Without a server (offline, or not
//! registered) the files are still written from the cache, so the last
//! synced stones keep showing.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::account::{self, Account};
use crate::sync::{self, Cache, Report, Server};
use crate::{datafiles, files, soapdata, FolderStatus};

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FolderSync {
    /// "forever · test"
    pub scope: Option<String>,
    pub synced_at: Option<u64>,
    pub report: Option<Report>,
    /// SoapstoneData was installed just now: the game needs a restart to see it.
    pub installed: bool,
    pub wrote: bool,
    /// Anything the player should know: why nothing synced, or what failed.
    pub note: Option<String>,
}

type Scope = (String, String);

fn safe(part: &str) -> bool {
    !part.is_empty() && part.len() <= 20 && part.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

fn cache_path(dir: &Path, (flavor, region): &Scope) -> PathBuf {
    dir.join("cache").join(format!("{flavor}-{region}.json"))
}

fn load_cache(dir: &Path, scope: &Scope) -> Cache {
    fs::read(cache_path(dir, scope)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn save_cache(dir: &Path, scope: &Scope, cache: &Cache) -> std::io::Result<()> {
    let json = serde_json::to_vec(cache).map_err(std::io::Error::other)?;
    files::write_atomic(&cache_path(dir, scope), &json)
}

pub fn sync_all(server: Option<&dyn Server>, folders: &mut [FolderStatus], data_dir: &Path, now: u64) {
    // Read every account; pick each folder's game type and region.
    let mut folder_scope: Vec<Option<Scope>> = Vec::new();
    let mut by_scope: BTreeMap<Scope, Vec<Account>> = BTreeMap::new();
    for folder in folders.iter_mut() {
        let mut newest: Option<(u64, Scope)> = None;
        let mut without_meta = false;
        for a in folder.accounts.iter().filter(|a| a.state == "ok") {
            let Ok(source) = fs::read(&a.saved_variables) else { continue };
            let Ok(parsed) = account::parse(&String::from_utf8_lossy(&source)) else { continue };
            let modified = a.summary.as_ref().map_or(0, |s| s.modified);
            match (&parsed.flavor, &parsed.region) {
                (Some(f), Some(r)) if safe(f) && safe(r) => {
                    let scope = (f.clone(), r.clone());
                    if newest.as_ref().is_none_or(|(m, _)| modified > *m) {
                        newest = Some((modified, scope.clone()));
                    }
                    by_scope.entry(scope).or_default().push(parsed);
                }
                _ => without_meta = true,
            }
        }
        let scope = newest.map(|(_, s)| s);
        folder.sync = Some(FolderSync {
            scope: scope.as_ref().map(|(f, r)| format!("{f} · {r}")),
            note: match (&scope, without_meta) {
                (None, true) => Some("Log in once with Soapstone 0.5 or later so it can record the game type and region".into()),
                (None, false) => Some("Nothing to sync yet: log in once with the addon enabled".into()),
                _ => None,
            },
            ..FolderSync::default()
        });
        folder_scope.push(scope);
    }

    // Sync each game type and region once.
    let mut reports: BTreeMap<Scope, Report> = BTreeMap::new();
    let mut caches: BTreeMap<Scope, Cache> = BTreeMap::new();
    for (scope, accounts) in &by_scope {
        let mut cache = load_cache(data_dir, scope);
        if let Some(server) = server {
            let report = sync::run(server, &scope.0, &scope.1, accounts, &mut cache, now);
            if let Err(e) = save_cache(data_dir, scope, &cache) {
                reports.insert(scope.clone(), Report { error: Some(format!("couldn't save the cache: {e}")), ..report });
            } else {
                reports.insert(scope.clone(), report);
            }
        }
        caches.insert(scope.clone(), cache);
    }

    // Write each folder's SoapstoneData.
    for (folder, scope) in folders.iter_mut().zip(folder_scope) {
        let Some(scope) = scope else { continue };
        let sync = folder.sync.get_or_insert_with(FolderSync::default);
        if let Some(report) = reports.get(&scope) {
            sync.report = Some(report.clone());
            if report.error.is_none() {
                sync.synced_at = Some(now);
            }
        } else {
            sync.note = Some("Not connected: showing the last synced stones".into());
        }
        if folder.addon.is_none() {
            sync.note = Some("Install the Soapstone addon in this folder to see the stones".into());
            continue;
        }
        let Some(interface) = datafiles::interface_of(&folder.path) else {
            sync.note = Some("Couldn't read Soapstone.toc".into());
            continue;
        };
        let accounts = &by_scope[&scope];
        let file = sync::data_file(&scope.0, &scope.1, accounts, &caches[&scope], now);
        match soapdata::stones_lua(&file).and_then(|text| datafiles::write(&folder.path, &interface, &text).map_err(|e| e.to_string())) {
            Ok(installed) => {
                sync.wrote = true;
                sync.installed = installed;
            }
            Err(e) => sync.note = Some(format!("Couldn't write SoapstoneData: {e}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::ApiError;
    use crate::sync::{Acks, PullResponse, PulledStone, PushResponse, ZonePage};
    use serde_json::Value as Json;

    struct Fake;
    impl Server for Fake {
        fn push(&self, body: &Json) -> Result<PushResponse, ApiError> {
            let ids = body.get("stones").and_then(Json::as_array).map(|a| a.iter().map(|s| s["id"].as_str().unwrap().to_owned()).collect()).unwrap_or_default();
            Ok(PushResponse { acks: Acks { stones: ids, ..Acks::default() }, rejected: vec![] })
        }
        fn pull(&self, _query: &str) -> Result<PullResponse, ApiError> {
            let mut res = PullResponse::default();
            let stone = PulledStone {
                id: "Zug-Zug-1791200000-1".into(), v: 1, author_key: "Zug-Zug".into(), t: Some(1791200000), zone: 1413,
                instance: Some(1), wx: Some(1.0), wy: Some(2.0), map_id: Some(1413), x: Some(0.5), y: Some(0.5), edited: None,
                text: Some("Praise the sun!".into()), sketch_id: None, score: 2, found: 1,
            };
            res.zones.insert("1413".into(), ZonePage { stones: vec![stone], removed: vec![], cursor: 4, more: false });
            Ok(res)
        }
    }

    const SV: &str = r#"SoapstoneDB = {
["meta"] = { ["flavor"] = "forever", ["region"] = "test", ["characters"] = { ["Mad-Decent"] = {}, }, },
["zones"] = { [1413] = { ["visited"] = 5, }, },
["pending"] = { ["stones"] = { ["Mad-Decent-1-1"] = 1, }, },
["stones"] = { ["Mad-Decent-1-1"] = { ["id"] = "Mad-Decent-1-1", ["v"] = 1, ["authorKey"] = "Mad-Decent", ["t"] = 1791000000,
  ["zone"] = 1413, ["instance"] = 1, ["wx"] = 1.5, ["wy"] = 2.5, ["text"] = "mine", }, },
}"#;

    fn setup(sv: &str) -> (tempfile::TempDir, Vec<FolderStatus>) {
        let tmp = tempfile::tempdir().unwrap();
        let game = tmp.path().join("World of Warcraft/_classic_beta_");
        fs::create_dir_all(game.join("Interface/AddOns/Soapstone")).unwrap();
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001\n").unwrap();
        let sv_path = game.join("WTF/Account/1#1/SavedVariables/Soapstone.lua");
        fs::create_dir_all(sv_path.parent().unwrap()).unwrap();
        fs::write(&sv_path, sv).unwrap();
        let folders = crate::installs::scan_root(&tmp.path().join("World of Warcraft"))
            .into_iter()
            .map(|f| {
                let mut status = crate::folder_status(f);
                // As if the file had settled.
                for a in &mut status.accounts {
                    a.state = "ok";
                    a.summary = savedvars_summary(sv);
                }
                status
            })
            .collect();
        (tmp, folders)
    }

    fn savedvars_summary(sv: &str) -> Option<crate::savedvars::Summary> {
        crate::savedvars::summarize(sv, 1).ok()
    }

    #[test]
    fn a_cycle_uploads_downloads_and_writes_soapstone_data() {
        let (tmp, mut folders) = setup(SV);
        let data = tmp.path().join("appdata");
        sync_all(Some(&Fake), &mut folders, &data, 1791234567);
        let sync = folders[0].sync.clone().unwrap();
        assert_eq!(sync.scope.as_deref(), Some("forever · test"));
        assert_eq!(sync.report.as_ref().map(|r| (r.uploaded, r.downloaded)), Some((1, 1)));
        assert!(sync.wrote && sync.installed && sync.synced_at == Some(1791234567));

        let stones = fs::read_to_string(datafiles::folder(&folders[0].path).join("Stones.lua")).unwrap();
        assert!(stones.contains("writtenAt = 1791234567,"));
        assert!(!stones.contains("Praise"), "no stone text in the clear");
        let vars = crate::lua::parse(&stones).unwrap();
        let records = vars["SoapstoneData_Stones"].path(&["records"]).unwrap().as_table().unwrap().entries.len();
        assert_eq!(records, 2, "Zug's stone and the ack for Mad's");
        assert!(cache_path(&data, &("forever".into(), "test".into())).exists(), "the cache is saved");

        // Offline next time: the file is still written, from the cache.
        sync_all(None, &mut folders, &data, 1791234667);
        let sync = folders[0].sync.clone().unwrap();
        assert!(sync.wrote && !sync.installed);
        assert_eq!(sync.note.as_deref(), Some("Not connected: showing the last synced stones"));
        let again = fs::read_to_string(datafiles::folder(&folders[0].path).join("Stones.lua")).unwrap();
        assert_eq!(again.replace("1791234667", "1791234567"), stones);
    }

    #[test]
    fn an_old_addon_gets_a_hint_and_no_files() {
        let (tmp, mut folders) = setup("SoapstoneDB = { [\"stones\"] = {}, }");
        sync_all(Some(&Fake), &mut folders, &tmp.path().join("appdata"), 1);
        let sync = folders[0].sync.clone().unwrap();
        assert!(sync.note.unwrap().contains("Soapstone 0.5"));
        assert!(!datafiles::folder(&folders[0].path).exists());
    }

    #[test]
    fn odd_game_or_region_names_never_become_paths() {
        assert!(safe("forever") && safe("classic-18") && safe("test"));
        assert!(!safe("../x") && !safe("") && !safe("US") && !safe("a/b"));
    }
}
