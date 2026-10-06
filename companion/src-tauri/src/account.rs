//! What the sync needs from one account's `Soapstone.lua`: which game and
//! region it plays, its characters, the changes waiting in `pending`, and the
//! stones they refer to. Shapes are documented in `Soapstone/Store.lua`.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value as Json};

use crate::lua::{self, Key, Table, Value};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Account {
    pub flavor: Option<String>,
    pub region: Option<String>,
    /// Characters seen logging in here (`Mad-Decent`): the only names this
    /// install may write as.
    pub characters: Vec<String>,
    /// Zones visited, most recent first.
    pub zones: Vec<i64>,
    pub pending_stones: Vec<(String, i64)>,
    /// (stone id, character, 1 | 0 | -1)
    pub pending_votes: Vec<(String, String, i64)>,
    /// (stone id, character, unlocked at)
    pub pending_unlocks: Vec<(String, String, i64)>,
    /// The records `pending_stones` and `catch_up_stones` refer to.
    pub stones: BTreeMap<String, Table>,
    /// Everything this account's characters already have, pending or not,
    /// for a server the companion hasn't synced with before (sync.rs
    /// "catch-up"): their own live stones (id, version), their votes on
    /// others' stones (from `ratings`) and their unlocks (from `heardBy`).
    pub catch_up_stones: Vec<(String, i64)>,
    pub catch_up_votes: Vec<(String, String, i64)>,
    pub catch_up_unlocks: Vec<(String, String, i64)>,
}

fn str_key(k: &Key) -> Option<&str> {
    match k {
        Key::Str(s) => Some(s),
        Key::Int(_) => None,
    }
}

fn int(v: &Value) -> Option<i64> {
    v.as_f64().filter(|n| n.fract() == 0.0 && n.abs() < 9.0e15).map(|n| n as i64)
}

pub fn parse(source: &str) -> Result<Account, String> {
    let vars = lua::parse(source).map_err(|e| e.to_string())?;
    let Some(Value::Table(db)) = vars.get("SoapstoneDB") else { return Ok(Account::default()) };
    let mut a = Account::default();
    let tbl = |t: &Table, k: &str| t.get(k).and_then(Value::as_table).cloned().unwrap_or_default();

    let meta = tbl(db, "meta");
    a.flavor = meta.get("flavor").and_then(Value::as_str).map(str::to_owned);
    a.region = meta.get("region").and_then(Value::as_str).map(str::to_owned);
    a.characters = tbl(&meta, "characters").entries.iter().filter_map(|(k, _)| str_key(k).map(str::to_owned)).collect();

    let mut zones: Vec<(i64, i64)> = tbl(db, "zones")
        .entries
        .iter()
        .filter_map(|(k, v)| match k {
            Key::Int(zone) => Some((*zone, v.as_table().and_then(|t| t.get("visited")).and_then(int).unwrap_or(0))),
            Key::Str(_) => None,
        })
        .collect();
    zones.sort_by(|x, y| y.1.cmp(&x.1).then(x.0.cmp(&y.0)));
    a.zones = zones.into_iter().map(|(z, _)| z).collect();

    let pending = tbl(db, "pending");
    let stones = tbl(db, "stones");
    for (k, v) in &tbl(&pending, "stones").entries {
        let (Some(id), Some(v)) = (str_key(k), int(v)) else { continue };
        a.pending_stones.push((id.to_owned(), v));
        if let Some(rec) = stones.get(id).and_then(Value::as_table) {
            a.stones.insert(id.to_owned(), rec.clone());
        }
    }
    let per_char = |list: &str| -> Vec<(String, String, i64)> {
        tbl(&pending, list)
            .entries
            .iter()
            .filter_map(|(k, v)| Some((str_key(k)?, v.as_table()?)))
            .flat_map(|(id, chars)| {
                chars.entries.iter().filter_map(move |(c, v)| Some((id.to_owned(), str_key(c)?.to_owned(), int(v)?)))
            })
            .collect()
    };
    a.pending_votes = per_char("votes");
    a.pending_unlocks = per_char("unlocks");

    // Catch-up: what the characters have, from the stones and ratings themselves.
    let characters = a.characters.clone();
    let ours = |key: &str| characters.iter().any(|c| c == key);
    let author_of = |rec: &Table| rec.get("authorKey").and_then(Value::as_str).map(str::to_owned);
    // Ids the server takes: "<author>-<time>-<n>".
    let shareable = |id: &str, rec: &Table| {
        author_of(rec).is_some_and(|author| id.starts_with(&format!("{author}-")))
            && rec.get("localOnly").and_then(Value::as_bool) != Some(true)
    };
    let mut catch_up_stones = Vec::new();
    let mut catch_up_unlocks = Vec::new();
    for (k, v) in &stones.entries {
        let (Some(id), Some(rec)) = (str_key(k), v.as_table()) else { continue };
        if !shareable(id, rec) || rec.get("deleted").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let author = author_of(rec).unwrap_or_default();
        if ours(&author) {
            catch_up_stones.push((id.to_owned(), rec.get("v").and_then(int).unwrap_or(1)));
            a.stones.entry(id.to_owned()).or_insert_with(|| rec.clone());
        } else if let Some(heard) = rec.get("heardBy").and_then(Value::as_table) {
            for (c, at) in &heard.entries {
                if let (Some(c), Some(at)) = (str_key(c), int(at)) {
                    if ours(c) {
                        catch_up_unlocks.push((id.to_owned(), c.to_owned(), at));
                    }
                }
            }
        }
    }
    let mut catch_up_votes = Vec::new();
    for (k, v) in &tbl(db, "ratings").entries {
        let (Some(id), Some(chars)) = (str_key(k), v.as_table()) else { continue };
        let Some(rec) = stones.get(id).and_then(Value::as_table) else { continue };
        if !shareable(id, rec) || author_of(rec).is_some_and(|author| ours(&author)) {
            continue; // votes on this account's own stones stay local
        }
        for (c, value) in &chars.entries {
            if let (Some(c), Some(value)) = (str_key(c), int(value)) {
                if ours(c) && matches!(value, -1 | 1) {
                    catch_up_votes.push((id.to_owned(), c.to_owned(), value));
                }
            }
        }
    }
    a.catch_up_stones = catch_up_stones;
    a.catch_up_votes = catch_up_votes;
    a.catch_up_unlocks = catch_up_unlocks;
    Ok(a)
}

/// A pending stone as `/v1/push` takes it: `stones` for live ones, `deletes`
/// for tombstones. None if the record is missing or not something to upload.
pub enum Upload {
    Stone(Json),
    Delete(Json),
}

pub fn upload(rec: &Table) -> Option<(Upload, i64)> {
    let s = |k: &str| rec.get(k).and_then(Value::as_str);
    let n = |k: &str| rec.get(k).and_then(Value::as_f64);
    let i = |k: &str| rec.get(k).and_then(int);
    let id = s("id")?;
    let v = i("v").unwrap_or(1);
    let author = s("authorKey")?;
    if rec.get("localOnly").and_then(Value::as_bool) == Some(true) {
        return None;
    }
    if rec.get("deleted").and_then(Value::as_bool) == Some(true) {
        let mut d = json!({ "id": id, "v": v, "authorKey": author, "zone": i("zone")? });
        if let Some(at) = i("deletedAt") {
            d["deletedAt"] = json!(at);
        }
        return Some((Upload::Delete(d), v));
    }
    let mut m = Map::new();
    m.insert("id".into(), json!(id));
    m.insert("v".into(), json!(v));
    m.insert("authorKey".into(), json!(author));
    m.insert("t".into(), json!(i("t")?));
    m.insert("zone".into(), json!(i("zone")?));
    m.insert("instance".into(), json!(i("instance")?));
    m.insert("wx".into(), json!(n("wx")?));
    m.insert("wy".into(), json!(n("wy")?));
    for (k, val) in [("mapID", i("mapID").map(Json::from)), ("x", n("x").map(Json::from)), ("y", n("y").map(Json::from)), ("edited", i("edited").map(Json::from))] {
        if let Some(val) = val {
            m.insert(k.into(), val);
        }
    }
    if let Some(text) = s("text") {
        m.insert("text".into(), json!(text));
    } else if let Some(sk) = rec.get("sketch").and_then(Value::as_table) {
        let w = sk.get("w").and_then(int)?;
        let h = sk.get("h").and_then(int)?;
        let data = sk.get("data").and_then(Value::as_str)?;
        m.insert("sketch".into(), json!({ "w": w, "h": h, "data": data }));
    } else {
        return None;
    }
    Some((Upload::Stone(Json::Object(m)), v))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRC: &str = r#"
SoapstoneDB = {
["meta"] = { ["flavor"] = "forever", ["region"] = "test", ["characters"] = { ["Mad-Decent"] = { ["seen"] = 1, }, ["Osha-Compliant"] = { ["seen"] = 2, }, }, },
["zones"] = { [1413] = { ["visited"] = 5, }, [1411] = { ["visited"] = 9, }, },
["pending"] = {
  ["stones"] = { ["Mad-Decent-1-1"] = 1, ["Mad-Decent-1-2"] = 2, ["Gone-1-1"] = 1, },
  ["votes"] = { ["Zug-Zug-1-1"] = { ["Mad-Decent"] = -1, }, },
  ["unlocks"] = { ["Zug-Zug-1-1"] = { ["Osha-Compliant"] = 1791210000, }, },
},
["stones"] = {
  ["Mad-Decent-1-1"] = { ["id"] = "Mad-Decent-1-1", ["v"] = 1, ["authorKey"] = "Mad-Decent", ["t"] = 1791000000, ["zone"] = 1413,
    ["instance"] = 1, ["wx"] = -1450.25, ["wy"] = -3750.5, ["mapID"] = 1413, ["x"] = 0.5, ["y"] = 0.25, ["text"] = "Praise the sun!",
    ["heardBy"] = { ["Mad-Decent"] = 1791000000, }, ["mine"] = true, },
  ["Mad-Decent-1-2"] = { ["id"] = "Mad-Decent-1-2", ["v"] = 2, ["authorKey"] = "Mad-Decent", ["deleted"] = true, ["deletedAt"] = 1791000100, ["zone"] = 1413, },
},
}
"#;

    #[test]
    fn reads_what_sync_needs() {
        let a = parse(SRC).unwrap();
        assert_eq!(a.flavor.as_deref(), Some("forever"));
        assert_eq!(a.region.as_deref(), Some("test"));
        assert_eq!(a.characters, ["Mad-Decent", "Osha-Compliant"]);
        assert_eq!(a.zones, [1411, 1413], "most recently visited first");
        assert_eq!(a.pending_stones.len(), 3);
        assert_eq!(a.pending_votes, [("Zug-Zug-1-1".into(), "Mad-Decent".into(), -1)]);
        assert_eq!(a.pending_unlocks, [("Zug-Zug-1-1".into(), "Osha-Compliant".into(), 1791210000)]);
        assert_eq!(a.stones.len(), 2, "a pending id without a record is left out");
    }

    #[test]
    fn uploads_match_the_server_shapes() {
        let a = parse(SRC).unwrap();
        let (Upload::Stone(s), v) = upload(&a.stones["Mad-Decent-1-1"]).unwrap() else { panic!("expected a stone") };
        assert_eq!(v, 1);
        assert_eq!(s, json!({ "id": "Mad-Decent-1-1", "v": 1, "authorKey": "Mad-Decent", "t": 1791000000, "zone": 1413,
            "instance": 1, "wx": -1450.25, "wy": -3750.5, "mapID": 1413, "x": 0.5, "y": 0.25, "text": "Praise the sun!" }));
        let (Upload::Delete(d), v) = upload(&a.stones["Mad-Decent-1-2"]).unwrap() else { panic!("expected a delete") };
        assert_eq!(v, 2);
        assert_eq!(d, json!({ "id": "Mad-Decent-1-2", "v": 2, "authorKey": "Mad-Decent", "zone": 1413, "deletedAt": 1791000100 }));
    }

    #[test]
    fn catch_up_takes_what_the_characters_already_have() {
        let src = r#"
SoapstoneDB = {
["meta"] = { ["flavor"] = "forever", ["region"] = "test", ["characters"] = { ["Mad-Decent"] = {}, }, },
["stones"] = {
  ["Mad-Decent-1-1"] = { ["id"] = "Mad-Decent-1-1", ["v"] = 2, ["authorKey"] = "Mad-Decent", ["text"] = "mine", },
  ["Mad-Decent-1-2"] = { ["id"] = "Mad-Decent-1-2", ["v"] = 3, ["authorKey"] = "Mad-Decent", ["deleted"] = true, },
  ["1790363195-7862"] = { ["id"] = "1790363195-7862", ["authorKey"] = "Mad-Decent", ["text"] = "old id", },
  ["Zug-Zug-1-1"] = { ["id"] = "Zug-Zug-1-1", ["authorKey"] = "Zug-Zug", ["text"] = "theirs",
    ["heardBy"] = { ["Mad-Decent"] = 1791000000, ["Zug-Zug"] = 5, }, },
  ["local-1-1"] = { ["id"] = "local-1-1", ["localOnly"] = true, ["heardBy"] = { ["Mad-Decent"] = 1, }, },
},
["ratings"] = {
  ["Zug-Zug-1-1"] = { ["Mad-Decent"] = 1, ["Someone-Else"] = -1, },
  ["Mad-Decent-1-1"] = { ["Mad-Decent"] = -1, },
},
}"#;
        let a = parse(src).unwrap();
        assert_eq!(a.catch_up_stones, [("Mad-Decent-1-1".to_string(), 2)], "own live stones with author ids; not tombstones or old ids");
        assert!(a.stones.contains_key("Mad-Decent-1-1"), "with their records");
        assert_eq!(a.catch_up_votes, [("Zug-Zug-1-1".to_string(), "Mad-Decent".to_string(), 1)], "own characters' votes on others' stones");
        assert_eq!(a.catch_up_unlocks, [("Zug-Zug-1-1".to_string(), "Mad-Decent".to_string(), 1791000000)], "own characters' unlocks of others' stones");
    }

    #[test]
    fn older_saves_have_nothing_to_sync() {
        let a = parse("SoapstoneDB = { [\"stones\"] = {}, [\"outbox\"] = { [\"x\"] = true, }, }").unwrap();
        assert_eq!(a.flavor, None);
        assert!(a.pending_stones.is_empty());
    }
}
