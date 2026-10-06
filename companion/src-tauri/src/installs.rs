//! Finding WoW installs and the Soapstone files inside them.
//!
//! A WoW folder ("D:\Games\World of Warcraft") holds one folder per game
//! type (`_retail_`, `_classic_`, `_classic_era_`, `_classic_beta_` for WoW
//! Forever, ...), each with its own `Interface\AddOns` and `WTF\Account\<ACCOUNT>`.
//! Folder names don't say which game type a folder is; the addon records
//! that in its SavedVariables (`SoapstoneDB.meta`).
//!
//! Where WoW folders come from, in order: Blizzard's registry key, the paths
//! Battle.net lists in `product.db`, common locations on every drive, and
//! folders the player chose. Every candidate is checked on disk, since both
//! the registry and `product.db` can point at folders that are long gone.
//!
//! This is the only module with per-platform paths; the macOS build adds its
//! own `candidate_roots`.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GameFolder {
    /// `_classic_beta_`
    pub name: String,
    pub path: PathBuf,
    pub accounts: Vec<Account>,
    /// `Interface\AddOns\Soapstone`, if the addon is installed.
    pub addon: Option<AddonFolder>,
    /// The game version this folder runs ("1.60.1.70235"), from the WoW
    /// folder's `.build.info`, if it says.
    pub build: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    /// `12345678#1`
    pub name: String,
    /// `WTF\Account\<ACCOUNT>\SavedVariables\Soapstone.lua`; may not exist yet.
    pub saved_variables: PathBuf,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AddonFolder {
    pub path: PathBuf,
    /// A link (junction or symlink) to somewhere else, such as a developer's
    /// git checkout. The companion never overwrites one.
    pub linked: bool,
}

/// Every game folder under the known WoW folders, deduplicated.
pub fn find(extra_roots: &[PathBuf]) -> Vec<GameFolder> {
    let mut roots: Vec<PathBuf> = candidate_roots();
    roots.extend(extra_roots.iter().cloned());
    let mut seen = Vec::new();
    let mut out = Vec::new();
    for root in roots {
        for folder in scan_root(&root) {
            let key = canonical(&folder.path);
            if !seen.contains(&key) {
                seen.push(key);
                out.push(folder);
            }
        }
    }
    out
}

fn canonical(path: &Path) -> String {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf()).to_string_lossy().to_lowercase()
}

fn is_game_folder_name(name: &str) -> bool {
    name.len() > 2 && name.starts_with('_') && name.ends_with('_')
}

/// The game folders inside a WoW folder. A game folder itself (or a path
/// inside one, as the registry sometimes gives) is taken back to its parent.
pub fn scan_root(root: &Path) -> Vec<GameFolder> {
    let mut root = root.to_path_buf();
    for _ in 0..3 {
        let inside_game_folder = root.file_name().and_then(|n| n.to_str()).is_some_and(is_game_folder_name);
        if !inside_game_folder {
            break;
        }
        match root.parent() {
            Some(parent) => root = parent.to_path_buf(),
            None => break,
        }
    }
    let Ok(entries) = fs::read_dir(&root) else { return Vec::new() };
    let mut out: Vec<GameFolder> = entries
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let path = e.path();
            let looks_like_wow = path.join("WTF").is_dir() || path.join("Interface").is_dir();
            (is_game_folder_name(&name) && looks_like_wow).then(|| game_folder(name, path))
        })
        .collect();
    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
}

fn game_folder(name: String, path: PathBuf) -> GameFolder {
    let accounts_dir = path.join("WTF").join("Account");
    let mut accounts: Vec<Account> = fs::read_dir(&accounts_dir)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
                .map(|e| e.file_name().to_string_lossy().into_owned())
                // `WTF\Account\SavedVariables` holds account-wide data for
                // every account, not an account of its own.
                .filter(|n| !n.eq_ignore_ascii_case("SavedVariables"))
                .map(|n| Account {
                    saved_variables: accounts_dir.join(&n).join("SavedVariables").join("Soapstone.lua"),
                    name: n,
                })
                .collect()
        })
        .unwrap_or_default();
    accounts.sort_by(|a, b| a.name.cmp(&b.name));
    let addon_path = path.join("Interface").join("AddOns").join("Soapstone");
    let addon = fs::symlink_metadata(&addon_path).ok().map(|meta| AddonFolder {
        linked: meta.file_type().is_symlink() || is_junction(&addon_path),
        path: addon_path,
    });
    let build = path.parent().and_then(|root| fs::read_to_string(root.join(".build.info")).ok()).and_then(|info| build_of(&info, &name));
    GameFolder { name, path, accounts, addon, build }
}

/// The version `.build.info` lists for a game folder. The folder name maps
/// to Battle.net's product: `_retail_` is `wow`, `_classic_beta_` is
/// `wow_classic_beta`.
pub fn build_of(info: &str, folder: &str) -> Option<String> {
    let inner = folder.trim_matches('_');
    let product = if inner == "retail" { "wow".to_owned() } else { format!("wow_{inner}") };
    let mut lines = info.lines();
    let header: Vec<&str> = lines.next()?.split('|').map(|h| h.split('!').next().unwrap_or("")).collect();
    let col = |name: &str| header.iter().position(|h| *h == name);
    let (p, v) = (col("Product")?, col("Version")?);
    lines.map(|l| l.split('|').collect::<Vec<_>>()).find(|row| row.get(p) == Some(&product.as_str())).and_then(|row| row.get(v).map(|s| s.to_string())).filter(|v| !v.is_empty())
}

#[cfg(windows)]
fn is_junction(path: &Path) -> bool {
    use std::os::windows::fs::MetadataExt;
    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
    fs::symlink_metadata(path).is_ok_and(|m| m.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0)
}

#[cfg(not(windows))]
fn is_junction(_path: &Path) -> bool {
    false
}

/// Pulls folder paths out of Battle.net's `product.db`. It's a protobuf file;
/// rather than decode it, take every run of text that looks like an absolute
/// path. `scan_root` then ignores anything that isn't a WoW folder.
pub fn paths_in_product_db(bytes: &[u8]) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let windows_path = i + 2 < bytes.len()
            && bytes[i].is_ascii_alphabetic()
            && bytes[i + 1] == b':'
            && matches!(bytes[i + 2], b'/' | b'\\');
        let unix_path = bytes[i] == b'/' && (i == 0 || !bytes[i - 1].is_ascii_graphic());
        if windows_path || unix_path {
            let start = i;
            while i < bytes.len() && (bytes[i] == b' ' || bytes[i].is_ascii_graphic()) {
                i += 1;
            }
            let text = String::from_utf8_lossy(&bytes[start..i]);
            let path = PathBuf::from(text.trim_end());
            if !out.contains(&path) {
                out.push(path);
            }
        } else {
            i += 1;
        }
    }
    out
}

#[cfg(windows)]
fn candidate_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();

    use winreg::enums::HKEY_LOCAL_MACHINE;
    use winreg::RegKey;
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    for key in [
        r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
        r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
    ] {
        if let Ok(k) = hklm.open_subkey(key) {
            if let Ok(path) = k.get_value::<String, _>("InstallPath") {
                roots.push(PathBuf::from(path));
            }
        }
    }

    let program_data = std::env::var_os("ProgramData").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
    if let Ok(bytes) = fs::read(program_data.join(r"Battle.net\Agent\product.db")) {
        roots.extend(paths_in_product_db(&bytes));
    }

    for drive in b'C'..=b'Z' {
        let drive = format!("{}:\\", drive as char);
        if !Path::new(&drive).exists() {
            continue;
        }
        for rel in ["World of Warcraft", r"Games\World of Warcraft", r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft"] {
            roots.push(Path::new(&drive).join(rel));
        }
    }
    roots
}

#[cfg(not(windows))]
fn candidate_roots() -> Vec<PathBuf> {
    let mut roots = vec![PathBuf::from("/Applications/World of Warcraft")];
    if let Ok(bytes) = fs::read("/Users/Shared/Battle.net/Agent/product.db") {
        roots.extend(paths_in_product_db(&bytes));
    }
    roots
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_wow(dir: &Path) -> PathBuf {
        let root = dir.join("World of Warcraft");
        fs::create_dir_all(root.join("_classic_beta_/WTF/Account/12345678#1/SavedVariables")).unwrap();
        fs::create_dir_all(root.join("_classic_beta_/WTF/Account/SavedVariables")).unwrap();
        fs::create_dir_all(root.join("_classic_beta_/Interface/AddOns/Soapstone")).unwrap();
        fs::create_dir_all(root.join("_retail_/WTF/Account/OTHER")).unwrap();
        fs::create_dir_all(root.join("_not_wow_")).unwrap();
        fs::create_dir_all(root.join("Data")).unwrap();
        root
    }

    #[test]
    fn finds_game_folders_and_accounts() {
        let tmp = tempfile::tempdir().unwrap();
        let root = make_wow(tmp.path());
        let found = scan_root(&root);
        let names: Vec<&str> = found.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["_classic_beta_", "_retail_"]);

        let forever = &found[0];
        assert_eq!(forever.accounts.len(), 1);
        assert_eq!(forever.accounts[0].name, "12345678#1");
        assert!(forever.accounts[0].saved_variables.ends_with("12345678#1/SavedVariables/Soapstone.lua"));
        assert_eq!(forever.addon.as_ref().map(|a| a.linked), Some(false));
        assert_eq!(found[1].addon, None);
    }

    #[test]
    fn a_path_inside_a_game_folder_finds_its_siblings() {
        let tmp = tempfile::tempdir().unwrap();
        let root = make_wow(tmp.path());
        assert_eq!(scan_root(&root.join("_retail_")).len(), 2);
    }

    #[test]
    fn missing_folders_are_ignored() {
        assert!(scan_root(Path::new(r"C:\Games\OctoWoW\")).is_empty());
    }

    #[test]
    fn find_deduplicates() {
        let tmp = tempfile::tempdir().unwrap();
        let root = make_wow(tmp.path());
        let found = find(&[root.clone(), root.join("_retail_")]);
        let ours = found.iter().filter(|f| f.path.starts_with(&root)).count();
        assert_eq!(ours, 2);
    }

    #[test]
    fn build_info_versions() {
        let info = "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0\nus|1|1.60.1.70235|wow_classic_beta\nus|1|11.2.5.63906|wow\n";
        assert_eq!(build_of(info, "_classic_beta_").as_deref(), Some("1.60.1.70235"));
        assert_eq!(build_of(info, "_retail_").as_deref(), Some("11.2.5.63906"));
        assert_eq!(build_of(info, "_classic_era_"), None);
        assert_eq!(build_of("", "_retail_"), None);
    }

    #[test]
    fn product_db_paths() {
        let bytes = b"\x0a\x12wow\x12\x18D:/Games/World of Warcraft\x1a\x02enUS\x22\x1fC:/Program Files (x86)/Battle.net\x00";
        let paths = paths_in_product_db(bytes);
        assert!(paths.contains(&PathBuf::from("D:/Games/World of Warcraft")));
        assert!(paths.contains(&PathBuf::from("C:/Program Files (x86)/Battle.net")));
    }
}
