-- A starter word filter: unambiguous slurs, matched as whole words or
-- phrases (src/push.ts isBlocked). Add or remove words with
--   npx wrangler d1 execute soapstone --remote --command "INSERT INTO blocked_words (word) VALUES ('...')"
-- and the moderation page will manage it later.
INSERT OR IGNORE INTO blocked_words (word) VALUES
  ('nigger'), ('niggers'), ('nigga'), ('niggas'),
  ('faggot'), ('faggots'), ('fag'), ('fags'),
  ('retard'), ('retards'), ('tranny'), ('trannies'),
  ('kike'), ('kikes'), ('spic'), ('spics'), ('chink'), ('chinks'),
  ('gook'), ('gooks'), ('wetback'), ('wetbacks'), ('raghead'), ('ragheads'),
  ('coon'), ('coons'), ('dyke'), ('dykes'),
  ('kill yourself'), ('kys');
