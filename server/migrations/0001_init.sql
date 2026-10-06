-- Soapstone server, first schema. See docs/Ideas/Idea - Companion App (WoW).md.
-- Every table that holds game data is split by (flavor, region): Forever,
-- Retail and Classic never mix, and neither do US, EU, KR, TW and CN.

-- One row per companion install. The token itself is never stored.
CREATE TABLE installs (
  id          TEXT PRIMARY KEY,
  token_hash  TEXT NOT NULL,
  ip_hash     TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  status      TEXT NOT NULL DEFAULT 'ok'   -- ok | limited (shadow) | banned
);
CREATE INDEX installs_ip ON installs (ip_hash, created_at);

-- Who owns a character name: the first install to write as it.
CREATE TABLE characters (
  flavor      TEXT NOT NULL,
  region      TEXT NOT NULL,
  char_key    TEXT NOT NULL,
  install_id  TEXT NOT NULL,
  claimed_at  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,
  PRIMARY KEY (flavor, region, char_key)
);
CREATE INDEX characters_install ON characters (install_id);

CREATE TABLE stones (
  flavor       TEXT NOT NULL,
  region       TEXT NOT NULL,
  id           TEXT NOT NULL,
  author_key   TEXT NOT NULL,
  zone         INTEGER NOT NULL,
  instance     INTEGER,
  wx           REAL,
  wy           REAL,
  map_id       INTEGER,
  x            REAL,
  y            REAL,
  kind         TEXT,                        -- text | sketch (null once deleted)
  text         TEXT,
  sketch_id    TEXT,
  v            INTEGER NOT NULL,
  t            INTEGER,                     -- dropped (the player's clock)
  edited       INTEGER,
  deleted_at   INTEGER,
  status       TEXT NOT NULL DEFAULT 'live', -- live | hidden (reported) | rejected
  reason       TEXT,                        -- why it was rejected
  install_id   TEXT NOT NULL,
  score        INTEGER NOT NULL DEFAULT 0,
  found_count  INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,            -- first seen by the server
  updated_seq  INTEGER NOT NULL,
  PRIMARY KEY (flavor, region, id)
);
CREATE INDEX stones_changes ON stones (flavor, region, zone, updated_seq);
CREATE INDEX stones_place   ON stones (flavor, region, instance, wx, wy);
CREATE INDEX stones_author  ON stones (flavor, region, author_key, zone);
CREATE INDEX stones_install ON stones (install_id, created_at);

-- Drawings, named by their content (sk_ + 16 hex of SHA-256).
CREATE TABLE sketches (
  id          TEXT PRIMARY KEY,
  w           INTEGER NOT NULL,
  h           INTEGER NOT NULL,
  data        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE votes (
  flavor      TEXT NOT NULL,
  region      TEXT NOT NULL,
  stone_id    TEXT NOT NULL,
  char_key    TEXT NOT NULL,
  value       INTEGER NOT NULL,             -- 1 appraise, -1 disparage
  install_id  TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (flavor, region, stone_id, char_key)
);

-- Private: only the install that owns char_key ever downloads these.
CREATE TABLE unlocks (
  flavor       TEXT NOT NULL,
  region       TEXT NOT NULL,
  char_key     TEXT NOT NULL,
  stone_id     TEXT NOT NULL,
  unlocked_at  INTEGER NOT NULL,
  install_id   TEXT NOT NULL,
  updated_seq  INTEGER NOT NULL,
  PRIMARY KEY (flavor, region, char_key, stone_id)
);
CREATE INDEX unlocks_changes ON unlocks (flavor, region, char_key, updated_seq);

CREATE TABLE reports (
  flavor      TEXT NOT NULL,
  region      TEXT NOT NULL,
  stone_id    TEXT NOT NULL,
  install_id  TEXT NOT NULL,
  reason      TEXT,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (flavor, region, stone_id, install_id)
);

-- Daily counters for rate limits: (install or ip, UTC day, what) -> count.
CREATE TABLE usage (
  subject  TEXT NOT NULL,
  day      INTEGER NOT NULL,
  kind     TEXT NOT NULL,
  n        INTEGER NOT NULL,
  PRIMARY KEY (subject, day, kind)
);

-- The word filter, adjustable without an app update.
CREATE TABLE blocked_words (
  word  TEXT PRIMARY KEY
);

-- Global change counter: every change to a stone or unlock takes the next
-- value, and companions ask for "changes since" the highest they've seen.
CREATE TABLE counters (
  name   TEXT PRIMARY KEY,
  value  INTEGER NOT NULL
);
INSERT INTO counters (name, value) VALUES ('seq', 0);
