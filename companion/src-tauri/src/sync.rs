//! One sync for one game type and region: upload what the accounts have
//! waiting, download what changed in the zones they've visited, and keep the
//! result in a cache that `Stones.lua` is written from.
//!
//! - **Up:** `pending` stones, deletes, votes and unlocks, only as the
//!   characters that logged in on those accounts. The server's answers
//!   (acknowledgements and refusals) are kept as *outcomes* until the addon
//!   has seen them, i.e. until the entry is gone from `pending`.
//! - **Down:** per-zone changes since a cursor, and this install's unlocks.
//!   A stone leaves the cache only when the server says it's gone.
//!
//! Everything goes through [`Server`], so the logic is tested without a
//! network (see the tests at the bottom).

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value as Json};

use crate::account::{self, Account, Upload};
use crate::api::{ApiError, Client};
use crate::soapdata::{self, Content, DataFile, Kind, Record, Removal};

const MAX_STONES: usize = 100;
const MAX_VOTES: usize = 500;
const MAX_ZONES: usize = 50;
const MAX_PAGES: usize = 20;
/// Others' stones kept in `Stones.lua`, as the addon keeps them (`Store.lua`).
const PER_ZONE: usize = 200;
const TOTAL: usize = 5000;
/// Removals are passed on this long, so a stone gone from the server goes
/// from every player's game.
const KEEP_REMOVALS: u64 = 30 * 86400;
/// A refusal marked "try again" is retried after this long.
const RETRY_AFTER: u64 = 6 * 3600;

pub trait Server {
    fn push(&self, body: &Json) -> Result<PushResponse, ApiError>;
    fn pull(&self, query: &str) -> Result<PullResponse, ApiError>;
}

impl Server for Client {
    fn push(&self, body: &Json) -> Result<PushResponse, ApiError> {
        self.post("/v1/push", body)
    }
    fn pull(&self, query: &str) -> Result<PullResponse, ApiError> {
        self.get(&format!("/v1/pull?{query}"))
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct PushResponse {
    pub acks: Acks,
    pub rejected: Vec<Rejection>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct Acks {
    pub stones: Vec<String>,
    pub deletes: Vec<String>,
    pub votes: Vec<String>,
    pub unlocks: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Rejection {
    pub kind: String,
    pub id: String,
    pub reason: String,
    #[serde(default)]
    pub retry: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct PullResponse {
    pub zones: BTreeMap<String, ZonePage>,
    pub unlocks: UnlockPage,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct ZonePage {
    pub stones: Vec<PulledStone>,
    pub removed: Vec<PulledRemoval>,
    pub cursor: u64,
    pub more: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct UnlockPage {
    pub items: Vec<PulledUnlock>,
    pub cursor: u64,
    pub more: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PulledStone {
    pub id: String,
    pub v: i64,
    pub author_key: String,
    pub t: Option<i64>,
    pub zone: i64,
    pub instance: Option<i64>,
    pub wx: Option<f64>,
    pub wy: Option<f64>,
    #[serde(rename = "mapID", default)]
    pub map_id: Option<i64>,
    #[serde(default)]
    pub x: Option<f64>,
    #[serde(default)]
    pub y: Option<f64>,
    #[serde(default)]
    pub edited: Option<i64>,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub sketch_id: Option<String>,
    #[serde(default)]
    pub score: i64,
    #[serde(default)]
    pub found: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PulledRemoval {
    pub id: String,
    pub v: i64,
    pub zone: i64,
    pub why: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PulledUnlock {
    pub char_key: String,
    pub stone_id: String,
    pub unlocked_at: i64,
}

/// The server's answer to one upload, kept until the addon has seen it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Outcome {
    AckStone { id: String, v: i64 },
    AckVote { id: String, char_key: String, value: i64 },
    AckUnlock { id: String, char_key: String },
    /// `v`: the stone version refused (0 for votes and unlocks), so an edit
    /// made afterwards is tried.
    Refused { kind: String, id: String, char_key: String, v: i64, reason: String, retry: bool },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Kept<T> {
    pub item: T,
    pub at: u64,
}

/// Everything known for one game type and region, saved between runs in
/// `%APPDATA%\Soapstone\cache\<flavor>-<region>.json`.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Cache {
    pub cursors: BTreeMap<i64, u64>,
    pub unlock_cursor: u64,
    pub stones: BTreeMap<String, PulledStone>,
    pub removed: BTreeMap<String, Kept<PulledRemoval>>,
    /// "char|stoneId" -> unlocked at
    pub unlocks: BTreeMap<String, i64>,
    /// "s|id", "v|id|char", "u|id|char" -> outcome
    pub outcomes: BTreeMap<String, Kept<Outcome>>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub uploaded: usize,
    pub refused: usize,
    pub downloaded: usize,
    pub removed: usize,
    /// Why the sync stopped early, if it did.
    pub error: Option<String>,
}

fn stone_key(id: &str) -> String {
    format!("s|{id}")
}

fn char_key(kind: &str, id: &str, char: &str) -> String {
    format!("{kind}|{id}|{char}")
}

/// What to upload: everything pending that's ours to send and doesn't
/// already have an answer waiting for the addon.
struct Batch {
    stones: Vec<(Json, String, i64)>,
    deletes: Vec<(Json, String, i64)>,
    votes: Vec<(Json, String, String, i64)>,
    unlocks: Vec<(Json, String, String)>,
}

/// Whether `key` already has an answer that covers what's pending now
/// (`same` decides for acknowledgements and final refusals). A refusal
/// marked "try again" covers it until RETRY_AFTER has passed.
fn answered(cache: &Cache, key: &str, now: u64, same: impl Fn(&Outcome) -> bool) -> bool {
    match cache.outcomes.get(key) {
        Some(Kept { item: Outcome::Refused { retry: true, .. }, at }) => now < at + RETRY_AFTER,
        Some(Kept { item, .. }) => same(item),
        None => false,
    }
}

fn batch(accounts: &[Account], cache: &Cache, now: u64) -> Batch {
    let mut b = Batch { stones: Vec::new(), deletes: Vec::new(), votes: Vec::new(), unlocks: Vec::new() };
    let mut seen = BTreeSet::new();
    for a in accounts {
        let ours = |key: &str| a.characters.iter().any(|c| c == key);
        for (id, _) in &a.pending_stones {
            let Some(rec) = a.stones.get(id) else { continue };
            let Some(author) = rec.get("authorKey").and_then(|v| v.as_str()) else { continue };
            if !ours(author) || !seen.insert(stone_key(id)) {
                continue;
            }
            let Some((upload, v)) = account::upload(rec) else { continue };
            let covered = |o: &Outcome| match o {
                Outcome::AckStone { v: done, .. } | Outcome::Refused { v: done, .. } => *done >= v,
                _ => false,
            };
            if answered(cache, &stone_key(id), now, covered) {
                continue;
            }
            match upload {
                Upload::Stone(s) => b.stones.push((s, id.clone(), v)),
                Upload::Delete(d) => b.deletes.push((d, id.clone(), v)),
            }
        }
        for (id, char, value) in &a.pending_votes {
            let key = char_key("v", id, char);
            if !ours(char) || !seen.insert(key.clone()) {
                continue;
            }
            let covered = |o: &Outcome| match o {
                Outcome::AckVote { value: done, .. } => done == value,
                Outcome::Refused { .. } => true,
                _ => false,
            };
            if answered(cache, &key, now, covered) {
                continue;
            }
            b.votes.push((json!({ "stoneId": id, "charKey": char, "value": value }), id.clone(), char.clone(), *value));
        }
        for (id, char, at) in &a.pending_unlocks {
            let key = char_key("u", id, char);
            if !ours(char) || !seen.insert(key.clone()) || answered(cache, &key, now, |_| true) {
                continue;
            }
            b.unlocks.push((json!({ "stoneId": id, "charKey": char, "unlockedAt": at }), id.clone(), char.clone()));
        }
    }
    b
}

fn record_answers(cache: &mut Cache, res: &PushResponse, sent: &Sent, now: u64, report: &mut Report) {
    let keep = |cache: &mut Cache, key: String, item: Outcome| {
        cache.outcomes.insert(key, Kept { item, at: now });
    };
    for id in res.acks.stones.iter().chain(&res.acks.deletes) {
        if let Some(v) = sent.stones.get(id) {
            keep(cache, stone_key(id), Outcome::AckStone { id: id.clone(), v: *v });
            report.uploaded += 1;
        }
    }
    for key in &res.acks.votes {
        if let Some((id, char, value)) = sent.votes.get(key) {
            keep(cache, char_key("v", id, char), Outcome::AckVote { id: id.clone(), char_key: char.clone(), value: *value });
            report.uploaded += 1;
        }
    }
    for key in &res.acks.unlocks {
        if let Some((id, char)) = sent.unlocks.get(key) {
            keep(cache, char_key("u", id, char), Outcome::AckUnlock { id: id.clone(), char_key: char.clone() });
            report.uploaded += 1;
        }
    }
    for r in &res.rejected {
        // A name owned by another computer: keep it waiting here (v1 has one
        // computer per character; pairing will let this one upload later).
        let retry = r.retry || r.reason == "name belongs to another install";
        let (kind, id, char) = match r.kind.as_str() {
            "stones" | "deletes" => ("s", r.id.clone(), String::new()),
            "votes" | "unlocks" => {
                let (id, char) = r.id.split_once('|').unwrap_or((&r.id, ""));
                (if r.kind == "votes" { "v" } else { "u" }, id.to_owned(), char.to_owned())
            }
            _ => continue,
        };
        let key = if kind == "s" { stone_key(&id) } else { char_key(kind, &id, &char) };
        let v = if kind == "s" { sent.stones.get(&id).copied().unwrap_or(0) } else { 0 };
        keep(cache, key, Outcome::Refused { kind: kind.into(), id, char_key: char, v, reason: r.reason.clone(), retry });
        report.refused += 1;
    }
}

#[derive(Default)]
struct Sent {
    stones: BTreeMap<String, i64>,
    votes: BTreeMap<String, (String, String, i64)>,
    unlocks: BTreeMap<String, (String, String)>,
}

fn push_all(server: &dyn Server, flavor: &str, region: &str, b: Batch, cache: &mut Cache, now: u64, report: &mut Report) -> Result<(), ApiError> {
    let base = || json!({ "flavor": flavor, "region": region });
    let mut send = |list: &str, items: Vec<Json>, sent: Sent| -> Result<(), ApiError> {
        if items.is_empty() {
            return Ok(());
        }
        let mut body = base();
        body[list] = Json::Array(items);
        let res = server.push(&body)?;
        record_answers(cache, &res, &sent, now, report);
        Ok(())
    };
    for chunk in b.stones.chunks(MAX_STONES) {
        let sent = Sent { stones: chunk.iter().map(|(_, id, v)| (id.clone(), *v)).collect(), ..Sent::default() };
        send("stones", chunk.iter().map(|(s, ..)| s.clone()).collect(), sent)?;
    }
    for chunk in b.deletes.chunks(MAX_STONES) {
        let sent = Sent { stones: chunk.iter().map(|(_, id, v)| (id.clone(), *v)).collect(), ..Sent::default() };
        send("deletes", chunk.iter().map(|(d, ..)| d.clone()).collect(), sent)?;
    }
    for chunk in b.votes.chunks(MAX_VOTES) {
        let sent = Sent { votes: chunk.iter().map(|(_, id, c, v)| (format!("{id}|{c}"), (id.clone(), c.clone(), *v))).collect(), ..Sent::default() };
        send("votes", chunk.iter().map(|(v, ..)| v.clone()).collect(), sent)?;
    }
    for chunk in b.unlocks.chunks(MAX_VOTES) {
        let sent = Sent { unlocks: chunk.iter().map(|(_, id, c)| (format!("{id}|{c}"), (id.clone(), c.clone()))).collect(), ..Sent::default() };
        send("unlocks", chunk.iter().map(|(u, ..)| u.clone()).collect(), sent)?;
    }
    Ok(())
}

fn pull_all(server: &dyn Server, flavor: &str, region: &str, zones: &[i64], cache: &mut Cache, now: u64, report: &mut Report) -> Result<(), ApiError> {
    let groups: Vec<&[i64]> = if zones.is_empty() { vec![&[]] } else { zones.chunks(MAX_ZONES).collect() };
    for (i, group) in groups.into_iter().enumerate() {
        let mut todo: Vec<i64> = group.to_vec();
        for _ in 0..MAX_PAGES {
            let zones_param = todo.iter().map(|z| format!("{z}:{}", cache.cursors.get(z).copied().unwrap_or(0))).collect::<Vec<_>>().join(",");
            let mut query = format!("flavor={flavor}&region={region}&unlocks={}", cache.unlock_cursor);
            if !zones_param.is_empty() {
                query.push_str(&format!("&zones={zones_param}"));
            }
            let res = server.pull(&query)?;
            let mut more = Vec::new();
            for (zone, page) in res.zones {
                let Ok(zone) = zone.parse::<i64>() else { continue };
                for s in page.stones {
                    let newer = cache.stones.get(&s.id).is_none_or(|have| have.v <= s.v);
                    let gone = cache.removed.get(&s.id).is_some_and(|r| r.item.v >= s.v);
                    if newer && !gone {
                        cache.removed.remove(&s.id);
                        cache.stones.insert(s.id.clone(), s);
                        report.downloaded += 1;
                    }
                }
                for r in page.removed {
                    cache.stones.remove(&r.id);
                    cache.removed.insert(r.id.clone(), Kept { item: r, at: now });
                    report.removed += 1;
                }
                cache.cursors.insert(zone, page.cursor);
                if page.more {
                    more.push(zone);
                }
            }
            // Unlocks come with every pull; take them from the first group only.
            if i == 0 {
                for u in &res.unlocks.items {
                    let key = format!("{}|{}", u.char_key, u.stone_id);
                    let at = cache.unlocks.get(&key).map_or(u.unlocked_at, |&have| have.min(u.unlocked_at));
                    cache.unlocks.insert(key, at);
                }
                cache.unlock_cursor = res.unlocks.cursor;
            }
            if more.is_empty() && !(i == 0 && res.unlocks.more) {
                break;
            }
            todo = more;
        }
    }
    Ok(())
}

/// Drops outcomes the addon has acted on (their entry is gone from every
/// account's `pending`) and removals old enough to have reached everyone.
fn tidy(cache: &mut Cache, accounts: &[Account], now: u64) {
    let mut waiting = BTreeSet::new();
    for a in accounts {
        waiting.extend(a.pending_stones.iter().map(|(id, _)| stone_key(id)));
        waiting.extend(a.pending_votes.iter().map(|(id, c, _)| char_key("v", id, c)));
        waiting.extend(a.pending_unlocks.iter().map(|(id, c, _)| char_key("u", id, c)));
    }
    cache.outcomes.retain(|key, kept| {
        // A stone refusal is also how the addon learns to mark it "not
        // shared", so keep it a while even once pending is clear.
        let refused_stone = matches!(kept.item, Outcome::Refused { ref kind, .. } if kind == "s");
        waiting.contains(key) || (refused_stone && now < kept.at + KEEP_REMOVALS)
    });
    cache.removed.retain(|_, kept| now < kept.at + KEEP_REMOVALS);
}

/// One full sync. Uploads, then downloads; stops at the first network error
/// (nothing is lost: pending stays in the addon, cursors only move forward
/// on success). The cache is updated in place either way.
pub fn run(server: &dyn Server, flavor: &str, region: &str, accounts: &[Account], cache: &mut Cache, now: u64) -> Report {
    let mut report = Report::default();
    tidy(cache, accounts, now);
    let b = batch(accounts, cache, now);
    if let Err(e) = push_all(server, flavor, region, b, cache, now, &mut report) {
        report.error = Some(e.to_string());
        return report;
    }
    let mut zones: Vec<i64> = Vec::new();
    for a in accounts {
        for z in &a.zones {
            if !zones.contains(z) {
                zones.push(*z);
            }
        }
    }
    if let Err(e) = pull_all(server, flavor, region, &zones, cache, now, &mut report) {
        report.error = Some(e.to_string());
    }
    report
}

/// The `Stones.lua` for these accounts: the cache's stones (capped like the
/// addon caps them), removals, outcomes, and the accounts' characters'
/// unlocks.
pub fn data_file(flavor: &str, region: &str, accounts: &[Account], cache: &Cache, now: u64) -> DataFile {
    let characters: BTreeSet<&str> = accounts.iter().flat_map(|a| a.characters.iter().map(String::as_str)).collect();
    let mut records = Vec::new();

    let mut by_zone: BTreeMap<i64, Vec<&PulledStone>> = BTreeMap::new();
    let mut own = Vec::new();
    for s in cache.stones.values() {
        if characters.contains(s.author_key.as_str()) {
            own.push(s);
        } else {
            by_zone.entry(s.zone).or_default().push(s);
        }
    }
    let mut others: Vec<&PulledStone> = by_zone
        .into_values()
        .flat_map(|mut list| {
            list.sort_by(|a, b| b.t.cmp(&a.t).then(a.id.cmp(&b.id)));
            list.truncate(PER_ZONE);
            list
        })
        .collect();
    others.sort_by(|a, b| b.t.cmp(&a.t).then(a.id.cmp(&b.id)));
    others.truncate(TOTAL);
    for s in own.into_iter().chain(others) {
        let content = match (&s.text, &s.sketch_id) {
            (Some(text), _) => Content::Text(text.clone()),
            (None, Some(id)) => Content::Sketch(id.clone()),
            (None, None) => continue,
        };
        records.push(Record::Stone {
            stone: soapdata::Stone {
                id: s.id.clone(),
                v: s.v,
                author_key: s.author_key.clone(),
                t: s.t,
                zone: s.zone,
                instance: s.instance,
                wx: s.wx,
                wy: s.wy,
                map_id: s.map_id,
                x: s.x,
                y: s.y,
                edited: s.edited,
                content,
            },
            score: s.score,
            found: s.found,
        });
    }
    for kept in cache.removed.values() {
        let r = &kept.item;
        let why = match r.why.as_str() {
            "deleted" => Removal::Deleted,
            "hidden" => Removal::Hidden,
            _ => Removal::Rejected,
        };
        records.push(Record::Removed { id: r.id.clone(), v: r.v, zone: r.zone, why });
    }
    for kept in cache.outcomes.values() {
        records.push(match &kept.item {
            Outcome::AckStone { id, v } => Record::AckStone { id: id.clone(), v: *v },
            Outcome::AckVote { id, char_key, value } => Record::AckVote { id: id.clone(), char_key: char_key.clone(), value: *value },
            Outcome::AckUnlock { id, char_key } => Record::AckUnlock { id: id.clone(), char_key: char_key.clone() },
            Outcome::Refused { kind, id, char_key, reason, retry, .. } => Record::Refused {
                kind: match kind.as_str() {
                    "v" => Kind::Vote,
                    "u" => Kind::Unlock,
                    _ => Kind::Stone,
                },
                id: id.clone(),
                char_key: char_key.clone(),
                reason: reason.clone(),
                retry: *retry,
            },
        });
    }
    for (key, at) in &cache.unlocks {
        if let Some((char, stone)) = key.split_once('|') {
            if characters.contains(char) {
                records.push(Record::Unlock { char_key: char.into(), stone_id: stone.into(), unlocked_at: *at });
            }
        }
    }
    DataFile { flavor: flavor.into(), region: region.into(), written_at: now, records }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// A server that answers from a script and records what it was sent.
    #[derive(Default)]
    struct Fake {
        pushes: RefCell<Vec<Json>>,
        pulls: RefCell<Vec<String>>,
        push_answer: RefCell<Option<Box<dyn Fn(&Json) -> Result<PushResponse, ApiError>>>>,
        pull_answers: RefCell<Vec<PullResponse>>,
    }

    impl Server for Fake {
        fn push(&self, body: &Json) -> Result<PushResponse, ApiError> {
            self.pushes.borrow_mut().push(body.clone());
            match &*self.push_answer.borrow() {
                Some(f) => f(body),
                None => Ok(ack_everything(body)),
            }
        }
        fn pull(&self, query: &str) -> Result<PullResponse, ApiError> {
            self.pulls.borrow_mut().push(query.to_owned());
            let mut answers = self.pull_answers.borrow_mut();
            Ok(if answers.is_empty() { PullResponse::default() } else { answers.remove(0) })
        }
    }

    fn ack_everything(body: &Json) -> PushResponse {
        let ids = |list: &str, f: &dyn Fn(&Json) -> String| -> Vec<String> {
            body.get(list).and_then(Json::as_array).map(|a| a.iter().map(f).collect()).unwrap_or_default()
        };
        let id = |j: &Json| j["id"].as_str().unwrap().to_owned();
        let pair = |j: &Json| format!("{}|{}", j["stoneId"].as_str().unwrap(), j["charKey"].as_str().unwrap());
        PushResponse {
            acks: Acks { stones: ids("stones", &id), deletes: ids("deletes", &id), votes: ids("votes", &pair), unlocks: ids("unlocks", &pair) },
            rejected: Vec::new(),
        }
    }

    const SV: &str = r#"
SoapstoneDB = {
["meta"] = { ["flavor"] = "forever", ["region"] = "test", ["characters"] = { ["Mad-Decent"] = {}, ["Osha-Compliant"] = {}, }, },
["zones"] = { [1413] = { ["visited"] = 5, }, [1411] = { ["visited"] = 9, }, },
["pending"] = {
  ["stones"] = { ["Mad-Decent-1-1"] = 1, ["Mad-Decent-1-2"] = 2, ["Zug-Zug-1-1"] = 1, },
  ["votes"] = { ["Zug-Zug-2-1"] = { ["Mad-Decent"] = -1, ["Stranger-Name"] = 1, }, },
  ["unlocks"] = { ["Zug-Zug-2-1"] = { ["Osha-Compliant"] = 1791210000, }, },
},
["stones"] = {
  ["Mad-Decent-1-1"] = { ["id"] = "Mad-Decent-1-1", ["v"] = 1, ["authorKey"] = "Mad-Decent", ["t"] = 1791000000, ["zone"] = 1413,
    ["instance"] = 1, ["wx"] = 1.5, ["wy"] = 2.5, ["text"] = "Praise the sun!", },
  ["Mad-Decent-1-2"] = { ["id"] = "Mad-Decent-1-2", ["v"] = 2, ["authorKey"] = "Mad-Decent", ["deleted"] = true, ["zone"] = 1413, },
  ["Zug-Zug-1-1"] = { ["id"] = "Zug-Zug-1-1", ["v"] = 1, ["authorKey"] = "Zug-Zug", ["t"] = 1, ["zone"] = 1413, ["instance"] = 1, ["wx"] = 0, ["wy"] = 0, ["text"] = "not ours", },
},
}
"#;

    fn pulled(id: &str, author: &str, v: i64, t: i64, zone: i64) -> PulledStone {
        PulledStone {
            id: id.into(), v, author_key: author.into(), t: Some(t), zone, instance: Some(1), wx: Some(1.0), wy: Some(2.0),
            map_id: Some(zone), x: Some(0.5), y: Some(0.5), edited: None, text: Some(format!("words of {id}")), sketch_id: None,
            score: 1, found: 0,
        }
    }

    #[test]
    fn uploads_only_our_pending_and_keeps_the_answers() {
        let accounts = [account::parse(SV).unwrap()];
        let fake = Fake::default();
        let mut cache = Cache::default();
        let report = run(&fake, "forever", "test", &accounts, &mut cache, 1000);
        assert_eq!(report.error, None);
        let pushes = fake.pushes.borrow();
        let lists: Vec<&str> = pushes.iter().map(|p| ["stones", "deletes", "votes", "unlocks"].into_iter().find(|k| p.get(*k).is_some()).unwrap()).collect();
        assert_eq!(lists, ["stones", "deletes", "votes", "unlocks"], "stones first, then deletes, votes, unlocks");
        assert_eq!(pushes[0]["stones"].as_array().unwrap().len(), 1, "Zug's stone isn't ours to upload");
        assert_eq!(pushes[0]["flavor"], "forever");
        assert_eq!(pushes[0]["region"], "test");
        assert_eq!(pushes[2]["votes"], json!([{ "stoneId": "Zug-Zug-2-1", "charKey": "Mad-Decent", "value": -1 }]), "only our characters vote");
        assert_eq!(report.uploaded, 4);
        assert_eq!(cache.outcomes["s|Mad-Decent-1-1"].item, Outcome::AckStone { id: "Mad-Decent-1-1".into(), v: 1 });
        assert_eq!(cache.outcomes["s|Mad-Decent-1-2"].item, Outcome::AckStone { id: "Mad-Decent-1-2".into(), v: 2 });

        // Until the addon has seen the answers, nothing is sent twice.
        drop(pushes);
        run(&fake, "forever", "test", &accounts, &mut cache, 1100);
        assert_eq!(fake.pushes.borrow().len(), 4, "a second sync with the same pending uploads nothing");

        // Once the addon has cleared pending, the answers go too.
        let cleared = Account { pending_stones: vec![], pending_votes: vec![], pending_unlocks: vec![], ..accounts[0].clone() };
        run(&fake, "forever", "test", &[cleared], &mut cache, 1200);
        assert!(cache.outcomes.is_empty());
    }

    #[test]
    fn an_edit_after_the_upload_goes_up_again() {
        let mut accounts = [account::parse(SV).unwrap()];
        let fake = Fake::default();
        let mut cache = Cache::default();
        run(&fake, "forever", "test", &accounts, &mut cache, 1000);
        let rec = accounts[0].stones.get_mut("Mad-Decent-1-1").unwrap();
        for (k, v) in rec.entries.iter_mut() {
            if *k == crate::lua::Key::Str("v".into()) {
                *v = crate::lua::Value::Number(2.0);
            }
        }
        let before = fake.pushes.borrow().len();
        run(&fake, "forever", "test", &accounts, &mut cache, 1100);
        let pushes = fake.pushes.borrow();
        assert_eq!(pushes.len(), before + 1);
        assert_eq!(pushes[before]["stones"][0]["v"], 2);
    }

    #[test]
    fn refusals_are_kept_and_retried_only_when_the_server_says_so() {
        let accounts = [account::parse(SV).unwrap()];
        let fake = Fake::default();
        *fake.push_answer.borrow_mut() = Some(Box::new(|body: &Json| {
            let mut res = PushResponse::default();
            if body.get("stones").is_some() {
                res.rejected.push(Rejection { kind: "stones".into(), id: "Mad-Decent-1-1".into(), reason: "too many nearby".into(), retry: false });
            }
            if body.get("votes").is_some() {
                res.rejected.push(Rejection { kind: "votes".into(), id: "Zug-Zug-2-1|Mad-Decent".into(), reason: "too many votes today".into(), retry: true });
            }
            if body.get("unlocks").is_some() {
                res.rejected.push(Rejection { kind: "unlocks".into(), id: "Zug-Zug-2-1|Osha-Compliant".into(), reason: "name belongs to another install".into(), retry: false });
            }
            Ok(res)
        }));
        let mut cache = Cache::default();
        let report = run(&fake, "forever", "test", &accounts, &mut cache, 1000);
        assert_eq!(report.refused, 3);
        assert_eq!(
            cache.outcomes["v|Zug-Zug-2-1|Mad-Decent"].item,
            Outcome::Refused { kind: "v".into(), id: "Zug-Zug-2-1".into(), char_key: "Mad-Decent".into(), v: 0, reason: "too many votes today".into(), retry: true }
        );
        assert!(matches!(&cache.outcomes["u|Zug-Zug-2-1|Osha-Compliant"].item, Outcome::Refused { retry: true, .. }), "another computer's name stays waiting");

        let pushed = |fake: &Fake, list: &str| fake.pushes.borrow().iter().filter(|p| p.get(list).is_some()).count();
        run(&fake, "forever", "test", &accounts, &mut cache, 2000);
        assert_eq!((pushed(&fake, "stones"), pushed(&fake, "votes")), (1, 1), "nothing is retried an hour later");
        run(&fake, "forever", "test", &accounts, &mut cache, 1000 + RETRY_AFTER);
        assert_eq!((pushed(&fake, "stones"), pushed(&fake, "votes")), (1, 2), "the vote is retried later; the refused stone never is");
    }

    #[test]
    fn pulls_visited_zones_from_their_cursors_and_removes_only_on_the_servers_word() {
        let accounts = [account::parse(SV).unwrap()];
        let fake = Fake::default();
        let page = |stones: Vec<PulledStone>, removed: Vec<PulledRemoval>, cursor, more| ZonePage { stones, removed, cursor, more };
        let mut first = PullResponse::default();
        first.zones.insert("1411".into(), page(vec![pulled("Zug-Zug-2-1", "Zug-Zug", 1, 10, 1411)], vec![], 5, false));
        first.zones.insert("1413".into(), page(vec![pulled("Gone-Away-1-1", "Gone-Away", 1, 10, 1413)], vec![], 7, true));
        first.unlocks = UnlockPage { items: vec![PulledUnlock { char_key: "Osha-Compliant".into(), stone_id: "Zug-Zug-2-1".into(), unlocked_at: 50 }], cursor: 3, more: false };
        let mut second = PullResponse::default();
        second.zones.insert("1413".into(), page(vec![], vec![], 8, false));
        second.unlocks.cursor = 3;
        *fake.pull_answers.borrow_mut() = vec![first, second];
        *fake.push_answer.borrow_mut() = Some(Box::new(|_| Ok(PushResponse::default())));

        let mut cache = Cache::default();
        let report = run(&fake, "forever", "test", &accounts, &mut cache, 1000);
        let pulls = fake.pulls.borrow().clone();
        assert_eq!(pulls[0], "flavor=forever&region=test&unlocks=0&zones=1411:0,1413:0", "most recent zone first, from 0");
        assert_eq!(pulls[1], "flavor=forever&region=test&unlocks=3&zones=1413:7", "a zone with more comes back from its cursor");
        assert_eq!(report.downloaded, 2);
        assert_eq!(cache.cursors, BTreeMap::from([(1411, 5), (1413, 8)]));
        assert_eq!(cache.unlocks["Osha-Compliant|Zug-Zug-2-1"], 50);

        // A later pull that doesn't mention a stone leaves it alone; a removal takes it out.
        let mut third = PullResponse::default();
        third.zones.insert("1413".into(), page(vec![], vec![PulledRemoval { id: "Gone-Away-1-1".into(), v: 2, zone: 1413, why: "deleted".into() }], 9, false));
        *fake.pull_answers.borrow_mut() = vec![PullResponse::default(), third];
        run(&fake, "forever", "test", &accounts, &mut cache, 1100);
        assert!(cache.stones.contains_key("Gone-Away-1-1"), "not mentioned: kept");
        run(&fake, "forever", "test", &accounts, &mut cache, 1200);
        assert!(!cache.stones.contains_key("Gone-Away-1-1") && cache.removed.contains_key("Gone-Away-1-1"), "removed on the server's word");
        // An old copy arriving after the removal doesn't bring it back.
        let mut stale = PullResponse::default();
        stale.zones.insert("1413".into(), page(vec![pulled("Gone-Away-1-1", "Gone-Away", 1, 10, 1413)], vec![], 9, false));
        *fake.pull_answers.borrow_mut() = vec![stale];
        run(&fake, "forever", "test", &accounts, &mut cache, 1300);
        assert!(!cache.stones.contains_key("Gone-Away-1-1"));
    }

    #[test]
    fn a_network_error_stops_the_sync_without_losing_anything() {
        let accounts = [account::parse(SV).unwrap()];
        let fake = Fake::default();
        *fake.push_answer.borrow_mut() = Some(Box::new(|_| Err(ApiError::Unreachable("offline".into()))));
        let mut cache = Cache::default();
        let report = run(&fake, "forever", "test", &accounts, &mut cache, 1000);
        assert!(report.error.unwrap().contains("offline"));
        assert!(cache.outcomes.is_empty() && fake.pulls.borrow().is_empty());
    }

    #[test]
    fn writes_the_cache_as_the_addon_reads_it() {
        let accounts = [account::parse(SV).unwrap()];
        let mut cache = Cache::default();
        for i in 0..(PER_ZONE as i64 + 5) {
            let s = pulled(&format!("Zug-Zug-9-{i}"), "Zug-Zug", 1, i, 1413);
            cache.stones.insert(s.id.clone(), s);
        }
        let own = pulled("Mad-Decent-0-1", "Mad-Decent", 1, -1, 1413);
        cache.stones.insert(own.id.clone(), own);
        let sketch = PulledStone { text: None, sketch_id: Some("sk_9f2c41e07ab35d18".into()), ..pulled("Zug-Zug-8-1", "Zug-Zug", 1, 0, 1411) };
        cache.stones.insert(sketch.id.clone(), sketch);
        cache.unlocks.insert("Osha-Compliant|Zug-Zug-9-1".into(), 50);
        cache.unlocks.insert("Someone-Else|Zug-Zug-9-1".into(), 50);
        cache.outcomes.insert("s|Mad-Decent-1-1".into(), Kept { item: Outcome::AckStone { id: "Mad-Decent-1-1".into(), v: 1 }, at: 1 });

        let file = data_file("forever", "test", &accounts, &cache, 1000);
        let stones: Vec<&soapdata::Stone> = file.records.iter().filter_map(|r| match r { Record::Stone { stone, .. } => Some(stone), _ => None }).collect();
        assert_eq!(stones.iter().filter(|s| s.zone == 1413 && s.author_key == "Zug-Zug").count(), PER_ZONE, "others' stones capped per zone");
        assert!(stones.iter().any(|s| s.id == "Mad-Decent-0-1"), "your own oldest stone is never capped away");
        assert!(!stones.iter().any(|s| s.id == "Zug-Zug-9-0"), "the oldest others' stones go first");
        assert!(stones.iter().any(|s| s.content == Content::Sketch("sk_9f2c41e07ab35d18".into())));
        let unlocks: Vec<&Record> = file.records.iter().filter(|r| matches!(r, Record::Unlock { .. })).collect();
        assert_eq!(unlocks.len(), 1, "only this account's characters' unlocks");
        assert!(file.records.contains(&Record::AckStone { id: "Mad-Decent-1-1".into(), v: 1 }));
        assert!(soapdata::stones_lua(&file).is_ok());
    }
}
