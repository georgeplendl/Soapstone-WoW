//! Installing and updating the Soapstone addon in each WoW Forever folder, so
//! players install one thing.
//!
//! The companion carries the addon (`Soapstone/` from this repo, built in)
//! and copies it into `Interface\AddOns\Soapstone`. It's careful with copies
//! it didn't put there:
//!
//! - **Linked folders** (a junction or symlink to a git checkout) are never touched.
//! - **Its own copies** carry a marker (`.soapstone-companion`) with a hash of
//!   what it wrote. It updates one only while the files still match that
//!   hash; a copy changed by hand is left alone.
//! - **Copies installed by hand** are replaced only by a newer version.
//!
//! SavedVariables live elsewhere (`WTF\`), so nothing here can touch a
//! player's stones. The new folder is written beside the old one and swapped
//! in with renames, so the game never sees half an addon.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use include_dir::{include_dir, Dir, DirEntry};
use sha2::{Digest, Sha256};

static BUNDLE: Dir<'static> = include_dir!("$CARGO_MANIFEST_DIR/../../Soapstone");

pub const MARKER: &str = ".soapstone-companion";

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Installed,
    Updated { from: Option<String> },
    UpToDate,
    /// Left alone, and why.
    Kept(Keep),
    /// Not a WoW Forever folder (or its version is unknown): nothing installed.
    NotForever,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Keep {
    Linked,
    ChangedByHand,
    InstalledByHand,
}

/// `## Version:` of a .toc's text.
fn toc_version(toc: &str) -> Option<String> {
    toc.lines().find_map(|l| l.trim().strip_prefix("## Version:")).map(|v| v.trim().to_owned()).filter(|v| !v.is_empty())
}

pub fn bundled_version() -> Option<String> {
    BUNDLE.get_file("Soapstone.toc").and_then(|f| f.contents_utf8()).and_then(toc_version)
}

/// "0.4.1" < "0.10.0": compared number by number.
fn older(a: &str, b: &str) -> bool {
    let parts = |v: &str| v.split(|c: char| !c.is_ascii_digit()).filter(|p| !p.is_empty()).map(|p| p.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>();
    parts(a) < parts(b)
}

/// WoW Forever builds are 1.60 and later (Classic Era is 1.15).
pub fn is_forever_build(build: &str) -> bool {
    let mut parts = build.split('.').map(|p| p.parse::<u64>().ok());
    matches!((parts.next(), parts.next()), (Some(Some(1)), Some(Some(minor))) if minor >= 60)
}

fn bundle_files() -> Vec<(String, &'static [u8])> {
    fn walk(dir: &'static Dir<'static>, out: &mut Vec<(String, &'static [u8])>) {
        for entry in dir.entries() {
            match entry {
                DirEntry::Dir(d) => walk(d, out),
                DirEntry::File(f) => out.push((f.path().to_string_lossy().replace('\\', "/"), f.contents())),
            }
        }
    }
    let mut out = Vec::new();
    walk(&BUNDLE, &mut out);
    out.retain(|(p, _)| p != MARKER);
    out.sort();
    out
}

fn hash_files<'a>(files: impl IntoIterator<Item = (String, &'a [u8])>) -> String {
    let mut h = Sha256::new();
    for (path, bytes) in files {
        h.update(path.to_lowercase().as_bytes());
        h.update([0]);
        h.update((bytes.len() as u64).to_le_bytes());
        h.update(bytes);
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

pub fn bundle_hash() -> String {
    hash_files(bundle_files())
}

/// The hash of an installed folder, computed like `bundle_hash`.
fn folder_hash(dir: &Path) -> io::Result<String> {
    fn walk(base: &Path, dir: &Path, out: &mut Vec<(String, Vec<u8>)>) -> io::Result<()> {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if entry.file_type()?.is_dir() {
                walk(base, &path, out)?;
            } else {
                let rel = path.strip_prefix(base).unwrap_or(&path).to_string_lossy().replace('\\', "/");
                if rel != MARKER {
                    out.push((rel, fs::read(&path)?));
                }
            }
        }
        Ok(())
    }
    let mut files = Vec::new();
    walk(dir, dir, &mut files)?;
    files.sort();
    Ok(hash_files(files.iter().map(|(p, b)| (p.clone(), b.as_slice()))))
}

fn write_bundle(dir: &Path) -> io::Result<()> {
    for (rel, bytes) in bundle_files() {
        let path = dir.join(&rel);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, bytes)?;
    }
    fs::write(dir.join(MARKER), format!("hash={}\nversion={}\n", bundle_hash(), bundled_version().unwrap_or_default()))
}

fn marker_hash(dir: &Path) -> Option<String> {
    let text = fs::read_to_string(dir.join(MARKER)).ok()?;
    text.lines().find_map(|l| l.strip_prefix("hash=")).map(str::to_owned)
}

/// Writes the bundle beside `target` and swaps it in.
fn replace(target: &Path) -> io::Result<()> {
    let parent = target.parent().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "no AddOns folder"))?;
    fs::create_dir_all(parent)?;
    let fresh: PathBuf = parent.join(".Soapstone.installing");
    let old: PathBuf = parent.join(".Soapstone.old");
    for leftover in [&fresh, &old] {
        if leftover.exists() {
            fs::remove_dir_all(leftover)?;
        }
    }
    write_bundle(&fresh)?;
    if target.exists() {
        fs::rename(target, &old)?;
        if let Err(e) = fs::rename(&fresh, target) {
            let _ = fs::rename(&old, target); // put the old one back
            return Err(e);
        }
        fs::remove_dir_all(&old)?;
    } else {
        fs::rename(&fresh, target)?;
    }
    Ok(())
}

/// Installs or updates the addon in one game folder. `build` is the
/// folder's game version from `.build.info`, if known.
pub fn ensure(game: &Path, build: Option<&str>, linked: bool) -> io::Result<Action> {
    let target = game.join("Interface").join("AddOns").join("Soapstone");
    if linked {
        return Ok(Action::Kept(Keep::Linked));
    }
    let installed = fs::symlink_metadata(&target).is_ok();
    if !installed {
        if !build.is_some_and(is_forever_build) {
            return Ok(Action::NotForever);
        }
        replace(&target)?;
        return Ok(Action::Installed);
    }
    let bundle = bundle_hash();
    let current = folder_hash(&target)?;
    if current == bundle {
        return Ok(Action::UpToDate);
    }
    let version = fs::read_to_string(target.join("Soapstone.toc")).ok().as_deref().and_then(toc_version);
    let bundled = bundled_version().unwrap_or_default();
    match marker_hash(&target) {
        // Ours, untouched since: keep it current (never downgraded by an
        // older companion).
        Some(written) if written == current && version.as_deref().is_none_or(|v| !older(&bundled, v)) => {
            replace(&target)?;
            Ok(Action::Updated { from: version })
        }
        Some(written) if written == current => Ok(Action::UpToDate),
        Some(_) => Ok(Action::Kept(Keep::ChangedByHand)),
        None if version.as_deref().is_none_or(|v| older(v, &bundled)) => {
            replace(&target)?;
            Ok(Action::Updated { from: version })
        }
        None => Ok(Action::Kept(Keep::InstalledByHand)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn game() -> (tempfile::TempDir, PathBuf) {
        let tmp = tempfile::tempdir().unwrap();
        let game = tmp.path().join("_classic_beta_");
        fs::create_dir_all(game.join("Interface/AddOns")).unwrap();
        (tmp, game)
    }

    fn addon(game: &Path) -> PathBuf {
        game.join("Interface/AddOns/Soapstone")
    }

    #[test]
    fn the_bundle_is_the_addon() {
        assert!(bundle_files().iter().any(|(p, _)| p == "Soapstone.toc"));
        assert!(bundle_files().iter().any(|(p, _)| p == "Media/Soapstone.tga"), "subfolders come too");
        assert!(bundled_version().is_some());
    }

    #[test]
    fn versions_and_builds() {
        assert!(older("0.4.1", "0.5.0") && older("0.9.0", "0.10.0") && !older("0.5.0", "0.5.0") && !older("1.0", "0.9"));
        assert!(is_forever_build("1.60.1.70235") && is_forever_build("1.61.0"));
        assert!(!is_forever_build("1.15.7.61582") && !is_forever_build("11.2.5.1234") && !is_forever_build(""));
    }

    #[test]
    fn installs_where_missing_only_on_forever() {
        let (_tmp, game) = game();
        assert_eq!(ensure(&game, Some("11.2.5.1"), false).unwrap(), Action::NotForever);
        assert_eq!(ensure(&game, None, false).unwrap(), Action::NotForever);
        assert!(!addon(&game).exists());
        assert_eq!(ensure(&game, Some("1.60.1.70235"), false).unwrap(), Action::Installed);
        assert!(addon(&game).join("Soapstone.toc").exists() && addon(&game).join("Media/Soapstone.tga").exists());
        assert!(addon(&game).join(MARKER).exists());
        assert_eq!(ensure(&game, Some("1.60.1.70235"), false).unwrap(), Action::UpToDate);
        let leftovers: Vec<_> = fs::read_dir(game.join("Interface/AddOns")).unwrap().flatten().map(|e| e.file_name()).collect();
        assert_eq!(leftovers, ["Soapstone"], "no temporary folders left behind");
    }

    #[test]
    fn updates_its_own_copy_but_not_one_changed_by_hand() {
        let (_tmp, game) = game();
        ensure(&game, Some("1.60.1"), false).unwrap();
        // An older companion installed it: a file differs, the marker matches.
        fs::write(addon(&game).join("Core.lua"), "-- old version\n").unwrap();
        let old_hash = folder_hash(&addon(&game)).unwrap();
        fs::write(addon(&game).join(MARKER), format!("hash={old_hash}\nversion=0.4.0\n")).unwrap();
        assert!(matches!(ensure(&game, Some("1.60.1"), false).unwrap(), Action::Updated { .. }));
        assert_ne!(fs::read_to_string(addon(&game).join("Core.lua")).unwrap(), "-- old version\n");

        // Someone edits a file: hands off.
        fs::write(addon(&game).join("Core.lua"), "-- my tweak\n").unwrap();
        assert_eq!(ensure(&game, Some("1.60.1"), false).unwrap(), Action::Kept(Keep::ChangedByHand));
        assert_eq!(fs::read_to_string(addon(&game).join("Core.lua")).unwrap(), "-- my tweak\n");
    }

    #[test]
    fn a_copy_installed_by_hand_is_replaced_only_by_a_newer_version() {
        let (_tmp, game) = game();
        let bundled = bundled_version().unwrap();
        fs::create_dir_all(addon(&game)).unwrap();
        fs::write(addon(&game).join("Soapstone.toc"), format!("## Version: {bundled}\n")).unwrap();
        fs::write(addon(&game).join("Mine.lua"), "-- a developer's copy\n").unwrap();
        assert_eq!(ensure(&game, Some("1.60.1"), false).unwrap(), Action::Kept(Keep::InstalledByHand), "same version: left alone");
        fs::write(addon(&game).join("Soapstone.toc"), "## Version: 0.0.1\n").unwrap();
        assert_eq!(ensure(&game, Some("1.60.1"), false).unwrap(), Action::Updated { from: Some("0.0.1".into()) });
        assert!(!addon(&game).join("Mine.lua").exists(), "replaced whole, not merged");
    }

    #[test]
    fn a_linked_folder_is_never_touched() {
        let (_tmp, game) = game();
        assert_eq!(ensure(&game, Some("1.60.1"), true).unwrap(), Action::Kept(Keep::Linked));
        assert!(!addon(&game).exists());
    }
}
