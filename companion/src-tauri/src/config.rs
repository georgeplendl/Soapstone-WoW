//! The companion's own settings and its install token, in
//! `%APPDATA%\Soapstone\companion.json` (`~/Library/Application Support/Soapstone`
//! on macOS). Losing this file means losing the names this install owns, so
//! it's only ever replaced whole.

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::api::Registration;
use crate::files;

/// The Soapstone server (`server/`, deployed on Cloudflare Workers).
pub const DEFAULT_SERVER: &str = "https://soapstone-server.george-plendl.workers.dev";

/// What companion 0.1.0 used and saved before the server was deployed: a
/// local `wrangler dev`. A saved config still on it moves to DEFAULT_SERVER
/// (`SOAPSTONE_SERVER=http://127.0.0.1:8787` still points it at a local one).
pub const OLD_LOCAL_SERVER: &str = "http://127.0.0.1:8787";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    pub server: String,
    /// Registrations by server URL, so pointing at a test server doesn't
    /// lose the real token.
    pub registrations: Vec<(String, Registration)>,
    /// WoW folders the player chose by hand.
    pub wow_folders: Vec<PathBuf>,
    /// Install and update the Soapstone addon (src/addon.rs).
    pub manage_addon: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config { server: DEFAULT_SERVER.into(), registrations: Vec::new(), wow_folders: Vec::new(), manage_addon: true }
    }
}

impl Config {
    pub fn registration(&self) -> Option<&Registration> {
        self.registrations.iter().find(|(s, _)| *s == self.server).map(|(_, r)| r)
    }

    pub fn set_registration(&mut self, r: Registration) {
        self.registrations.retain(|(s, _)| *s != self.server);
        self.registrations.push((self.server.clone(), r));
    }
}

/// `SOAPSTONE_DATA_DIR` overrides it, to run a second test install.
pub fn dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("SOAPSTONE_DATA_DIR") {
        return PathBuf::from(dir);
    }
    dirs::config_dir().unwrap_or_else(std::env::temp_dir).join("Soapstone")
}

pub fn path() -> PathBuf {
    dir().join("companion.json")
}

/// The saved config, with `SOAPSTONE_SERVER` overriding the server URL.
pub fn load() -> Config {
    let mut config: Config = fs::read(path()).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    upgrade(&mut config);
    if let Ok(server) = std::env::var("SOAPSTONE_SERVER") {
        if !server.is_empty() {
            config.server = server;
        }
    }
    config
}

/// Moves a config saved by companion 0.1.0 (local test server) to the real
/// server. Its local registration is kept, filed under the local address.
fn upgrade(config: &mut Config) {
    if config.server == OLD_LOCAL_SERVER {
        config.server = DEFAULT_SERVER.into();
    }
}

pub fn save(config: &Config) -> std::io::Result<()> {
    let json = serde_json::to_vec_pretty(config).map_err(std::io::Error::other)?;
    files::write_atomic(&path(), &json)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registrations_are_per_server() {
        let mut c = Config::default();
        c.set_registration(Registration { install_id: "a".into(), token: "1".into() });
        c.server = "https://example.test".into();
        assert_eq!(c.registration(), None);
        c.set_registration(Registration { install_id: "b".into(), token: "2".into() });
        c.server = DEFAULT_SERVER.into();
        assert_eq!(c.registration().map(|r| r.install_id.as_str()), Some("a"));
    }

    #[test]
    fn a_0_1_config_moves_to_the_real_server() {
        let mut c: Config = serde_json::from_str(r#"{ "server": "http://127.0.0.1:8787", "registrations": [["http://127.0.0.1:8787", { "installId": "a", "token": "1" }]] }"#).unwrap();
        upgrade(&mut c);
        assert_eq!(c.server, DEFAULT_SERVER);
        assert_eq!(c.registration(), None, "it registers afresh with the real server");
        assert_eq!(c.registrations.len(), 1, "the local registration is kept for local testing");
        let mut custom = Config { server: "https://my.test".into(), ..Config::default() };
        upgrade(&mut custom);
        assert_eq!(custom.server, "https://my.test", "a server chosen on purpose stays");
    }

    #[test]
    fn old_or_partial_files_still_load() {
        let c: Config = serde_json::from_str(r#"{ "server": "https://x.test" }"#).unwrap();
        assert_eq!(c.server, "https://x.test");
        assert!(c.registrations.is_empty());
    }
}
