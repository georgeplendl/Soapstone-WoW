// Runs the Soapstone test suite outside the game.
//
//   cd tests && npm install && npm test        # everything
//   node run.js store sync                     # only files whose name matches
//   node run.js -v                             # print every passing check too
//
// 1. Syntax-checks every addon .lua file as Lua 5.1 (what WoW runs).
// 2. Runs each tests/*.test.lua in a fresh Lua state (fengari, Lua 5.3).
//    Tests get ROOT (the addon folder), TESTS, FIXTURES and VERBOSE, stub the
//    WoW API they need, load addon files, and report through lib/harness.lua.

const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const TESTS = __dirname;
const ROOT = path.resolve(TESTS, '..', 'Soapstone');
const FIXTURES = path.join(TESTS, 'fixtures');
const args = process.argv.slice(2);
const verbose = args.includes('-v');
const filters = args.filter((a) => a !== '-v');

let failedFiles = 0;
let totalPassed = 0;
let totalFailed = 0;

// 1. Syntax
const sources = fs.readdirSync(ROOT).filter((f) => f.endsWith('.lua')).sort();
let syntaxErrors = 0;
for (const file of sources) {
  try {
    luaparse.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'), { luaVersion: '5.1' });
  } catch (err) {
    syntaxErrors++;
    console.log(`FAIL syntax ${file}: ${err.message}`);
  }
}
console.log(`${syntaxErrors ? 'FAIL' : 'ok  '} syntax: ${sources.length} addon files`);
if (syntaxErrors) failedFiles++;

// 2. Tests
const setString = (L, name, value) => {
  lua.lua_pushstring(L, to_luastring(value));
  lua.lua_setglobal(L, to_luastring(name));
};
const getNumber = (L, name) => {
  lua.lua_getglobal(L, to_luastring(name));
  const n = lua.lua_isnumber(L, -1) ? lua.lua_tonumber(L, -1) : null;
  lua.lua_pop(L, 1);
  return n;
};

const tests = fs
  .readdirSync(TESTS)
  .filter((f) => f.endsWith('.test.lua'))
  .filter((f) => filters.length === 0 || filters.some((x) => f.includes(x)))
  .sort();

for (const file of tests) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  setString(L, 'ROOT', ROOT);
  setString(L, 'TESTS', TESTS);
  setString(L, 'FIXTURES', FIXTURES);
  lua.lua_pushboolean(L, verbose);
  lua.lua_setglobal(L, to_luastring('VERBOSE'));

  if (verbose) console.log(`${file}`);
  const status = lauxlib.luaL_dofile(L, to_luastring(path.join(TESTS, file)));
  if (status !== lua.LUA_OK) {
    failedFiles++;
    totalFailed++;
    console.log(`FAIL ${file}: ${lua.lua_tojsstring(L, -1)}`);
    continue;
  }
  const passed = getNumber(L, 'TEST_PASSED');
  const failed = getNumber(L, 'TEST_FAILURES');
  if (passed === null || failed === null) {
    failedFiles++;
    console.log(`FAIL ${file}: never called done()`);
    continue;
  }
  totalPassed += passed;
  totalFailed += failed;
  if (failed > 0) failedFiles++;
  console.log(`${failed ? 'FAIL' : 'ok  '} ${file}: ${passed} passed${failed ? `, ${failed} failed` : ''}`);
}

console.log(`\n${totalPassed} checks passed, ${totalFailed} failed, across ${tests.length} test files.`);
process.exit(failedFiles ? 1 : 0);
