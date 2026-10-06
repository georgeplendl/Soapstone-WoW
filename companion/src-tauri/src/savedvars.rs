//! What the companion reads from an account's `Soapstone.lua`.
//!
//! WoW writes the file in one go on logout, `/reload` and disconnect. A file
//! changed in the last couple of seconds may still be mid-write, so it's
//! read only once it has settled.

use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

use serde::Serialize;

use crate::lua::{self, Value};

/// How long a file must go unchanged before it's read.
pub const SETTLE: Duration = Duration::from_secs(2);

/// `SoapstoneDB.meta`, written by the addon (0.5 and later).
#[derive(Debug, Clone, Serialize, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Meta {
    pub flavor: Option<String>,
    pub region: Option<String>,
    pub build: Option<String>,
    pub addon: Option<String>,
    /// Characters seen logging in on this account (`Mad-Decent`): the only
    /// names the companion may claim on the server.
    pub characters: Vec<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    /// None until the addon records it; older addons don't.
    pub meta: Option<Meta>,
    /// Live stones (not tombstones) in the file, from every game type.
    pub stones: usize,
    /// Changes waiting to upload: every entry in `pending` (stones, and each
    /// character's votes and unlocks), or the older `outbox` before the
    /// addon had `pending`.
    pub waiting: usize,
    pub modified: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Read {
    Missing,
    /// Changed too recently to trust; try again shortly.
    Settling,
    Ok(Summary),
    Unreadable(String),
}

pub fn read(path: &Path) -> Read {
    let Ok(meta) = fs::metadata(path) else { return Read::Missing };
    let modified = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
    if SystemTime::now().duration_since(modified).unwrap_or_default() < SETTLE {
        return Read::Settling;
    }
    let bytes = match fs::read(path) {
        Ok(b) => b,
        Err(e) => return Read::Unreadable(e.to_string()),
    };
    let modified = modified.duration_since(SystemTime::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    match summarize(&String::from_utf8_lossy(&bytes), modified) {
        Ok(s) => Read::Ok(s),
        Err(e) => Read::Unreadable(e),
    }
}

pub fn summarize(source: &str, modified: u64) -> Result<Summary, String> {
    let vars = lua::parse(source).map_err(|e| e.to_string())?;
    let db = match vars.get("SoapstoneDB") {
        Some(Value::Table(t)) => t,
        Some(_) => return Err("SoapstoneDB is not a table".into()),
        // The addon is installed but hasn't saved anything yet.
        None => return Ok(Summary { meta: None, stones: 0, waiting: 0, modified }),
    };
    let text = |t: &lua::Table, k: &str| t.get(k).and_then(Value::as_str).map(str::to_owned);
    let meta = db.get("meta").and_then(Value::as_table).map(|m| Meta {
        flavor: text(m, "flavor"),
        region: text(m, "region"),
        build: text(m, "build"),
        addon: text(m, "addon"),
        characters: m
            .get("characters")
            .and_then(Value::as_table)
            .map(|t| t.entries.iter().filter_map(|(k, _)| match k {
                lua::Key::Str(s) => Some(s.clone()),
                lua::Key::Int(_) => None,
            }).collect())
            .unwrap_or_default(),
    });
    let stones = db
        .get("stones")
        .and_then(Value::as_table)
        .map(|t| {
            t.entries
                .iter()
                .filter(|(_, s)| s.as_table().is_some_and(|s| s.get("deleted").and_then(Value::as_bool) != Some(true)))
                .count()
        })
        .unwrap_or(0);
    let waiting = match db.get("pending").and_then(Value::as_table) {
        Some(p) => {
            let list = |k: &str| p.get(k).and_then(Value::as_table).map(|t| t.entries.as_slice()).unwrap_or_default();
            let per_character = |k: &str| list(k).iter().filter_map(|(_, v)| v.as_table()).map(|t| t.entries.len()).sum::<usize>();
            list("stones").len() + per_character("votes") + per_character("unlocks")
        }
        None => db.get("outbox").and_then(Value::as_table).map(|t| t.entries.len()).unwrap_or(0),
    };
    Ok(Summary { meta, stones, waiting, modified })
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../tests/fixtures/Soapstone.lua");

    #[test]
    fn reads_a_real_file() {
        let s = summarize(FIXTURE, 0).unwrap();
        assert_eq!(s.meta, None);
        assert_eq!(s.stones, 3);
        assert_eq!(s.waiting, 2);
    }

    #[test]
    fn reads_meta_and_pending() {
        let src = r#"
SoapstoneDB = {
["meta"] = { ["flavor"] = "forever", ["region"] = "us", ["build"] = "1.60.1.70009", ["addon"] = "0.5.0",
  ["characters"] = { ["Mad-Decent"] = { ["name"] = "Mad Decent", ["seen"] = 1791234567, }, }, },
["pending"] = {
  ["stones"] = { ["Mad-Decent-1-1"] = 2, },
  ["votes"] = { ["Zug-Zug-1-1"] = { ["Mad-Decent"] = 1, ["Osha-Compliant"] = 0, }, },
  ["unlocks"] = { ["Zug-Zug-1-1"] = { ["Mad-Decent"] = 1791234567, }, },
},
["outbox"] = { ["old"] = true, ["older"] = true, },
["stones"] = { ["a"] = { ["v"] = 1, }, ["b"] = { ["deleted"] = true, }, },
}
"#;
        let s = summarize(src, 0).unwrap();
        let meta = s.meta.unwrap();
        assert_eq!(meta.flavor.as_deref(), Some("forever"));
        assert_eq!(meta.region.as_deref(), Some("us"));
        assert_eq!(meta.characters, ["Mad-Decent"]);
        assert_eq!(s.stones, 1);
        assert_eq!(s.waiting, 4, "1 stone, 2 votes, 1 unlock; the outbox is ignored once pending exists");
    }

    #[test]
    fn empty_and_broken_files() {
        assert_eq!(summarize("", 0).unwrap().stones, 0);
        assert!(summarize("SoapstoneDB = { oops }", 0).is_err());
    }

    #[test]
    fn settling_and_missing() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("Soapstone.lua");
        assert_eq!(read(&path), Read::Missing);
        fs::write(&path, "SoapstoneDB = {}").unwrap();
        assert_eq!(read(&path), Read::Settling);
    }
}
