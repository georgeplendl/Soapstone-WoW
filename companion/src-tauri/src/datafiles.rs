//! The helper addon the companion writes into each game folder:
//!
//! ```text
//! Interface\AddOns\SoapstoneData\
//!   SoapstoneData.toc   written once (again if the game's Interface number changes)
//!   Stones.lua          rewritten every sync (soapdata.rs)
//!   Sketches.lua        drawings, rewritten every sync and emptied when the companion quits
//! ```
//!
//! WoW only notices new files when it starts, so both .lua files are created
//! with the folder and from then on only replaced. A fresh install needs one
//! game restart; after that a `/reload` picks up every rewrite.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::files;

pub const FOLDER: &str = "SoapstoneData";

const SKETCHES_PLACEHOLDER: &str =
    "-- Drawings from the Soapstone companion. Written by the companion; don't edit.\nSoapstoneData_Sketches = {\nformat = 1,\nwrittenAt = 0,\nrecords = {\n},\n}\n";

pub fn folder(game: &Path) -> PathBuf {
    game.join("Interface").join("AddOns").join(FOLDER)
}

/// `## Interface:` from the installed Soapstone addon, so SoapstoneData loads
/// on the same client without "out of date". Digits, commas and spaces only.
pub fn interface_of(game: &Path) -> Option<String> {
    let toc = fs::read_to_string(game.join("Interface").join("AddOns").join("Soapstone").join("Soapstone.toc")).ok()?;
    let value = toc.lines().find_map(|l| l.trim().strip_prefix("## Interface:"))?.trim().to_owned();
    (!value.is_empty() && value.chars().all(|c| c.is_ascii_digit() || c == ',' || c == ' ')).then_some(value)
}

fn toc(interface: &str) -> String {
    format!(
        "## Interface: {interface}\n## Title: Soapstone Data\n## Notes: Stones from the Soapstone companion app. The companion keeps this up to date.\n## Author: George Plendl\n## Version: 1\n\nStones.lua\nSketches.lua\n"
    )
}

/// Writes `Stones.lua` and `Sketches.lua`, installing the folder first if
/// it's missing. Returns true if the folder was new (the game must restart
/// to see it).
pub fn write(game: &Path, interface: &str, stones_lua: &str, sketches_lua: &str) -> io::Result<bool> {
    let dir = folder(game);
    let toc_path = dir.join(format!("{FOLDER}.toc"));
    let new = !toc_path.exists();
    let wanted = toc(interface);
    if fs::read_to_string(&toc_path).ok().as_deref() != Some(wanted.as_str()) {
        files::write_atomic(&toc_path, wanted.as_bytes())?;
    }
    files::write_atomic(&dir.join("Sketches.lua"), sketches_lua.as_bytes())?;
    files::write_atomic(&dir.join("Stones.lua"), stones_lua.as_bytes())?;
    Ok(new)
}

/// Empties `Sketches.lua` (the companion is quitting), if the folder exists.
pub fn clear_sketches(game: &Path) -> io::Result<()> {
    let path = folder(game).join("Sketches.lua");
    if path.exists() {
        files::write_atomic(&path, SKETCHES_PLACEHOLDER.as_bytes())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn game() -> (tempfile::TempDir, PathBuf) {
        let tmp = tempfile::tempdir().unwrap();
        let game = tmp.path().join("_classic_beta_");
        fs::create_dir_all(game.join("Interface/AddOns/Soapstone")).unwrap();
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001\n## Title: Soapstone\n").unwrap();
        (tmp, game)
    }

    #[test]
    fn installs_once_then_only_rewrites_stones() {
        let (_tmp, game) = game();
        let interface = interface_of(&game).unwrap();
        assert_eq!(interface, "16001");
        assert!(write(&game, &interface, "SoapstoneData_Stones = nil\n", "SoapstoneData_Sketches = nil\n").unwrap(), "first write installs the folder");
        let dir = folder(&game);
        assert!(fs::read_to_string(dir.join("SoapstoneData.toc")).unwrap().starts_with("## Interface: 16001\n"));
        assert!(!write(&game, &interface, "SoapstoneData_Stones = { format = 1, }\n", "SoapstoneData_Sketches = { format = 1, }\n").unwrap(), "later writes aren't new");
        assert_eq!(fs::read_to_string(dir.join("Stones.lua")).unwrap(), "SoapstoneData_Stones = { format = 1, }\n");
        assert_eq!(fs::read_to_string(dir.join("Sketches.lua")).unwrap(), "SoapstoneData_Sketches = { format = 1, }\n");
        clear_sketches(&game).unwrap();
        let cleared = fs::read_to_string(dir.join("Sketches.lua")).unwrap();
        assert!(cleared.contains("writtenAt = 0") && crate::lua::parse(&cleared).is_ok(), "quitting empties the drawings");
    }

    #[test]
    fn interface_must_be_plain_numbers() {
        let (_tmp, game) = game();
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001\nStones.lua\n## Interface: x\n").unwrap();
        assert_eq!(interface_of(&game).as_deref(), Some("16001"));
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001\n\nEvil.lua\n").unwrap();
        assert_eq!(interface_of(&game).as_deref(), Some("16001"));
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 1\nEvil.lua\n").unwrap();
        assert_eq!(interface_of(&game).as_deref(), Some("1"));
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001\r\nEvil.lua\n").unwrap();
        assert_eq!(interface_of(&game).as_deref(), Some("16001"));
        fs::write(game.join("Interface/AddOns/Soapstone/Soapstone.toc"), "## Interface: 16001 Evil.lua\n").unwrap();
        assert_eq!(interface_of(&game), None);
    }
}
