//! Writing `SoapstoneData\Stones.lua`, the file the addon reads at login and
//! `/reload` (`Soapstone/Companion.lua` documents the format and reads it).
//!
//! WoW runs the file as Lua, so it must never carry text as Lua strings: one
//! escaping slip, or a hostile server, would put code in every player's
//! game. Every string in it is base64, which can't close a Lua string, and
//! that's checked again before anything is returned. Inside each base64
//! record, fields are joined by `~` and escaped the way `Soapstone/Codec.lua`
//! does, and a stone's words are scrambled so sealed stones can't be read in
//! Notepad.

use std::fmt::Write as _;

pub const FORMAT: u32 = 1;

#[derive(Debug, Clone, PartialEq)]
pub struct DataFile {
    pub flavor: String,
    pub region: String,
    pub written_at: u64,
    pub records: Vec<Record>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Record {
    Stone { stone: Stone, score: i64, found: i64 },
    Removed { id: String, v: i64, zone: i64, why: Removal },
    AckStone { id: String, v: i64 },
    AckVote { id: String, char_key: String, value: i64 },
    AckUnlock { id: String, char_key: String },
    Refused { kind: Kind, id: String, char_key: String, reason: String, retry: bool },
    Unlock { char_key: String, stone_id: String, unlocked_at: i64 },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Removal {
    Deleted,
    Hidden,
    Rejected,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Kind {
    Stone,
    Vote,
    Unlock,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Stone {
    pub id: String,
    pub v: i64,
    pub author_key: String,
    pub t: Option<i64>,
    pub zone: i64,
    pub instance: Option<i64>,
    pub wx: Option<f64>,
    pub wy: Option<f64>,
    pub map_id: Option<i64>,
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub edited: Option<i64>,
    pub content: Content,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Content {
    Text(String),
    /// A drawing, named by its sketch id (`sk_` + 16 hex); the drawing goes in Sketches.lua.
    Sketch(String),
    Deleted { deleted_at: Option<i64> },
}

/// `Codec.Escape`: `%`, `~`, `;`, `|` and control characters as `%XX`,
/// byte by byte, so other UTF-8 characters pass through untouched.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if matches!(c, '%' | '~' | ';' | '|') || (c as u32) < 32 || c as u32 == 127 {
            let _ = write!(out, "%{:02X}", c as u32);
        } else {
            out.push(c);
        }
    }
    out
}

/// `Codec.Hash`: djb2 kept to 24 bits.
fn hash(s: &str) -> u32 {
    s.bytes().fold(5381u32, |h, b| (h * 33 + u32::from(b)) % 16_777_216)
}

fn xor_stream(id: &str, bytes: &[u8]) -> Vec<u8> {
    let mut seed = hash(id);
    bytes
        .iter()
        .enumerate()
        .map(|(i, b)| {
            seed = (seed * 33 + 7 + (i as u32 + 1)) % 16_777_216;
            b ^ ((seed >> 16) & 0xff) as u8
        })
        .collect()
}

/// `Codec.Scramble`.
pub fn scramble(id: &str, text: &str) -> String {
    base64(&xor_stream(id, text.as_bytes()))
}

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn base64(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16) | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8) | u32::from(*chunk.get(2).unwrap_or(&0));
        out.push(B64[(n >> 18) as usize & 63] as char);
        out.push(B64[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { B64[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { B64[n as usize & 63] as char } else { '=' });
    }
    out
}

fn is_base64(s: &str) -> bool {
    s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'='))
}

fn opt<T: ToString>(v: Option<T>) -> String {
    v.map(|v| v.to_string()).unwrap_or_default()
}

fn fixed(v: Option<f64>, places: usize) -> String {
    v.map(|v| format!("{v:.places$}")).unwrap_or_default()
}

/// The 16 fields of `Codec.EncodeStone`, with scrambled text (kind T) or a
/// sketch id (kind K) as `Codec.DecodeRemoteStone` expects.
fn stone_fields(s: &Stone) -> String {
    let (kind, a, b, c) = match &s.content {
        Content::Text(text) => ("T", scramble(&s.id, text), String::new(), String::new()),
        Content::Sketch(id) => ("K", String::new(), String::new(), id.clone()),
        Content::Deleted { deleted_at } => ("D", opt(*deleted_at), String::new(), String::new()),
    };
    [
        s.id.clone(),
        s.v.to_string(),
        s.author_key.clone(),
        opt(s.t),
        s.zone.to_string(),
        opt(s.instance),
        fixed(s.wx, 1),
        fixed(s.wy, 1),
        opt(s.map_id),
        fixed(s.x, 4),
        fixed(s.y, 4),
        opt(s.edited),
        kind.to_string(),
        a,
        b,
        c,
    ]
    .iter()
    .map(|f| escape(f))
    .collect::<Vec<_>>()
    .join("~")
}

fn record_text(r: &Record) -> String {
    let e = |s: &str| escape(s);
    match r {
        Record::Stone { stone, score, found } => format!("S~{score}~{found}~{}", stone_fields(stone)),
        Record::Removed { id, v, zone, why } => {
            let why = match why {
                Removal::Deleted => "deleted",
                Removal::Hidden => "hidden",
                Removal::Rejected => "rejected",
            };
            format!("R~{}~{v}~{zone}~{why}", e(id))
        }
        Record::AckStone { id, v } => format!("A~s~{}~{v}", e(id)),
        Record::AckVote { id, char_key, value } => format!("A~v~{}~{}~{value}", e(id), e(char_key)),
        Record::AckUnlock { id, char_key } => format!("A~u~{}~{}", e(id), e(char_key)),
        Record::Refused { kind, id, char_key, reason, retry } => {
            let kind = match kind {
                Kind::Stone => "s",
                Kind::Vote => "v",
                Kind::Unlock => "u",
            };
            format!("X~{kind}~{}~{}~{}~{}", e(id), e(char_key), e(reason), if *retry { "1" } else { "" })
        }
        Record::Unlock { char_key, stone_id, unlocked_at } => format!("U~{}~{}~{unlocked_at}", e(char_key), e(stone_id)),
    }
}

/// The whole `Stones.lua`. Errors only if something that must be base64
/// isn't, which would be a bug here, never something to write anyway.
pub fn stones_lua(file: &DataFile) -> Result<String, String> {
    let scope = base64(format!("{}~{}", escape(&file.flavor), escape(&file.region)).as_bytes());
    let records: Vec<String> = file.records.iter().map(|r| base64(record_text(r).as_bytes())).collect();
    if let Some(bad) = std::iter::once(&scope).chain(&records).find(|s| !is_base64(s)) {
        return Err(format!("refusing to write a string that isn't base64: {bad:?}"));
    }
    let mut out = String::new();
    out.push_str("-- Written by the Soapstone companion; it's replaced every few minutes, so don't edit it.\n");
    out.push_str("SoapstoneData_Stones = {\n");
    let _ = writeln!(out, "format = {FORMAT},");
    let _ = writeln!(out, "writtenAt = {},", file.written_at);
    let _ = writeln!(out, "scope = \"{scope}\",");
    out.push_str("records = {\n");
    for r in &records {
        let _ = writeln!(out, "\"{r}\",");
    }
    out.push_str("},\n}\n");
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The file both sides test against: this test writes it (with
    /// `UPDATE_FIXTURES=1`) or checks it, and `tests/companion.test.lua`
    /// reads it in the addon.
    const FIXTURE: &str = "../../tests/fixtures/companion/Stones.lua";

    pub fn sample() -> DataFile {
        let stone = |id: &str, author: &str, content: Content| Stone {
            id: id.into(),
            v: 1,
            author_key: author.into(),
            t: Some(1791200000),
            zone: 1413,
            instance: Some(1),
            wx: Some(-1450.25),
            wy: Some(-3750.5),
            map_id: Some(1413),
            x: Some(0.5123),
            y: Some(0.4567),
            edited: None,
            content,
        };
        DataFile {
            flavor: "forever".into(),
            region: "test".into(),
            written_at: 1791234567,
            records: vec![
                Record::Stone { stone: stone("Zug-Zug-1791200000-1", "Zug-Zug", Content::Text("Praise the sun! ~;|% \"quotes\" café".into())), score: 3, found: 14 },
                Record::Stone {
                    stone: Stone { v: 2, edited: Some(1791200100), ..stone("Zug-Zug-1791200000-2", "Zug-Zug", Content::Sketch("sk_9f2c41e07ab35d18".into())) },
                    score: 1,
                    found: 0,
                },
                Record::Stone { stone: stone("Mad-Decent-1791100000-1", "Mad-Decent", Content::Text("Restored from the database".into())), score: 5, found: 2 },
                Record::Stone { stone: Stone { v: 3, ..stone("Osha-Compliant-1790000000-1", "Osha-Compliant", Content::Text("ignored: yours".into())) }, score: 9, found: 9 },
                Record::Removed { id: "Gone-Away-1791000000-1".into(), v: 2, zone: 1413, why: Removal::Deleted },
                Record::Removed { id: "Rude-Person-1791000000-1".into(), v: 1, zone: 1413, why: Removal::Hidden },
                Record::Removed { id: "Mad-Decent-1791000000-9".into(), v: 1, zone: 1413, why: Removal::Rejected },
                Record::AckStone { id: "Mad-Decent-1791000000-1".into(), v: 1 },
                Record::AckStone { id: "Mad-Decent-1791000000-2".into(), v: 1 },
                Record::AckVote { id: "Zug-Zug-1791200000-1".into(), char_key: "Mad-Decent".into(), value: 1 },
                Record::AckUnlock { id: "Zug-Zug-1791200000-1".into(), char_key: "Mad-Decent".into() },
                Record::Refused { kind: Kind::Stone, id: "Mad-Decent-1791000000-3".into(), char_key: String::new(), reason: "too many nearby".into(), retry: false },
                Record::Refused { kind: Kind::Vote, id: "Gone-Away-1791000000-1".into(), char_key: "Mad-Decent".into(), reason: "too many votes today".into(), retry: true },
                Record::Unlock { char_key: "Osha-Compliant".into(), stone_id: "Zug-Zug-1791200000-1".into(), unlocked_at: 1791210000 },
            ],
        }
    }

    #[test]
    fn matches_the_shared_fixture() {
        let text = stones_lua(&sample()).unwrap();
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(FIXTURE);
        if std::env::var_os("UPDATE_FIXTURES").is_some() {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, &text).unwrap();
        }
        let expected = std::fs::read_to_string(&path).expect("fixture missing: run with UPDATE_FIXTURES=1");
        assert_eq!(text, expected.replace("\r\n", "\n"), "Stones.lua format changed: rerun with UPDATE_FIXTURES=1 and update the addon");
    }

    #[test]
    fn only_numbers_and_base64_strings() {
        let text = stones_lua(&sample()).unwrap();
        let mut in_string = false;
        let mut current = String::new();
        for c in text.chars().skip_while(|c| *c != '\n') {
            if c == '"' {
                if in_string {
                    assert!(is_base64(&current), "not base64: {current}");
                    current.clear();
                }
                in_string = !in_string;
            } else if in_string {
                current.push(c);
            }
        }
        assert!(!in_string);
        // And the companion's own parser reads it back as plain data.
        let vars = crate::lua::parse(&text).unwrap();
        assert!(vars["SoapstoneData_Stones"].path(&["records"]).is_some());
    }

    #[test]
    fn escapes_like_the_addon() {
        assert_eq!(escape("a~b;c|d%e\nf"), "a%7Eb%3Bc%7Cd%25e%0Af");
        assert_eq!(escape("café ☀"), "café ☀");
    }

    #[test]
    fn base64_and_scrambling() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        let s = scramble("Zug-Zug-1-1", "Praise the sun!");
        assert!(is_base64(&s));
        assert_eq!(xor_stream("Zug-Zug-1-1", &xor_stream("Zug-Zug-1-1", b"Praise the sun!")), b"Praise the sun!");
        assert_ne!(scramble("Zug-Zug-1-1", "Praise the sun!"), scramble("Zug-Zug-1-2", "Praise the sun!"));
    }
}
