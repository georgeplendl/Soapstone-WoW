//! Reads SavedVariables files without running them.
//!
//! WoW writes SavedVariables as Lua assignments of table literals:
//!
//! ```lua
//! SoapstoneDB = {
//! ["stones"] = { ["Mad-Decent-1791258800-1"] = { ["v"] = 1, ... }, },
//! [1411] = true,
//! "positional", -- [1]
//! }
//! ```
//!
//! This parser accepts exactly that: `Name = value` statements whose values
//! are nil, booleans, numbers, strings and tables. Anything else (function
//! calls, operators, variables) is an error, so a hand-edited or hostile file
//! can never make the companion do more than fail to read it.

use std::collections::BTreeMap;
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Nil,
    Bool(bool),
    Number(f64),
    Str(String),
    Table(Table),
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Key {
    Int(i64),
    Str(String),
}

/// A table's entries in file order. Later duplicates win on lookup, as in Lua.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Table {
    pub entries: Vec<(Key, Value)>,
}

impl Table {
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.find(|k| matches!(k, Key::Str(s) if s == key))
    }

    pub fn get_int(&self, key: i64) -> Option<&Value> {
        self.find(|k| matches!(k, Key::Int(n) if *n == key))
    }

    fn find(&self, pred: impl Fn(&Key) -> bool) -> Option<&Value> {
        self.entries.iter().rev().find(|(k, _)| pred(k)).map(|(_, v)| v)
    }
}

impl Value {
    pub fn as_table(&self) -> Option<&Table> {
        match self {
            Value::Table(t) => Some(t),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    /// Follows a path of string keys through nested tables.
    pub fn path(&self, keys: &[&str]) -> Option<&Value> {
        keys.iter().try_fold(self, |v, k| v.as_table()?.get(k))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

impl std::error::Error for ParseError {}

const MAX_DEPTH: usize = 100;

/// Parses a whole SavedVariables file into its top-level assignments.
pub fn parse(source: &str) -> Result<BTreeMap<String, Value>, ParseError> {
    let mut p = Parser { src: source.as_bytes(), pos: 0, line: 1 };
    // A UTF-8 byte order mark, which some editors add.
    if p.src.starts_with(&[0xEF, 0xBB, 0xBF]) {
        p.pos = 3;
    }
    let mut out = BTreeMap::new();
    loop {
        p.skip_space()?;
        if p.peek().is_none() {
            return Ok(out);
        }
        if p.eat(b';') {
            continue;
        }
        let name = p.name().ok_or_else(|| p.error("expected a variable name"))?;
        p.skip_space()?;
        if !p.eat(b'=') {
            return Err(p.error(format!("expected '=' after {name}")));
        }
        let value = p.value(0)?;
        out.insert(name, value);
    }
}

struct Parser<'a> {
    src: &'a [u8],
    pos: usize,
    line: usize,
}

impl Parser<'_> {
    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError { line: self.line, message: message.into() }
    }

    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn peek_at(&self, offset: usize) -> Option<u8> {
        self.src.get(self.pos + offset).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let c = self.peek()?;
        self.pos += 1;
        if c == b'\n' {
            self.line += 1;
        }
        Some(c)
    }

    fn eat(&mut self, c: u8) -> bool {
        if self.peek() == Some(c) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn skip_space(&mut self) -> Result<(), ParseError> {
        loop {
            match self.peek() {
                Some(b' ' | b'\t' | b'\r' | b'\n') => {
                    self.bump();
                }
                Some(b'-') if self.peek_at(1) == Some(b'-') => {
                    self.pos += 2;
                    if let Some(level) = self.long_bracket_level() {
                        self.long_bracket_body(level)?;
                    } else {
                        while !matches!(self.peek(), None | Some(b'\n')) {
                            self.bump();
                        }
                    }
                }
                _ => return Ok(()),
            }
        }
    }

    /// At `[[` or `[==[`: consumes it and returns the number of `=`.
    fn long_bracket_level(&mut self) -> Option<usize> {
        if self.peek() != Some(b'[') {
            return None;
        }
        let mut level = 0;
        while self.peek_at(1 + level) == Some(b'=') {
            level += 1;
        }
        if self.peek_at(1 + level) != Some(b'[') {
            return None;
        }
        self.pos += level + 2;
        Some(level)
    }

    fn long_bracket_body(&mut self, level: usize) -> Result<Vec<u8>, ParseError> {
        let mut out = Vec::new();
        // A newline straight after the opening bracket is skipped.
        if self.peek() == Some(b'\r') {
            self.bump();
        }
        if self.peek() == Some(b'\n') {
            self.bump();
        }
        loop {
            match self.bump() {
                None => return Err(self.error("unfinished long string or comment")),
                Some(b']') => {
                    let closes = (0..level).all(|i| self.peek_at(i) == Some(b'='))
                        && self.peek_at(level) == Some(b']');
                    if closes {
                        self.pos += level + 1;
                        return Ok(out);
                    }
                    out.push(b']');
                }
                Some(c) => out.push(c),
            }
        }
    }

    fn name(&mut self) -> Option<String> {
        let start = self.pos;
        match self.peek() {
            Some(c) if c.is_ascii_alphabetic() || c == b'_' => {}
            _ => return None,
        }
        while matches!(self.peek(), Some(c) if c.is_ascii_alphanumeric() || c == b'_') {
            self.pos += 1;
        }
        Some(String::from_utf8_lossy(&self.src[start..self.pos]).into_owned())
    }

    fn value(&mut self, depth: usize) -> Result<Value, ParseError> {
        self.skip_space()?;
        match self.peek() {
            Some(b'{') => {
                if depth >= MAX_DEPTH {
                    return Err(self.error("tables nested too deeply"));
                }
                self.table(depth + 1).map(Value::Table)
            }
            Some(b'"' | b'\'') => self.quoted().map(Value::Str),
            Some(b'[') => match self.long_bracket_level() {
                Some(level) => {
                    let bytes = self.long_bracket_body(level)?;
                    Ok(Value::Str(String::from_utf8_lossy(&bytes).into_owned()))
                }
                None => Err(self.error("unexpected '['")),
            },
            Some(c) if c == b'-' || c == b'.' || c.is_ascii_digit() => self.number().map(Value::Number),
            Some(c) if c.is_ascii_alphabetic() || c == b'_' => {
                let word = self.name().unwrap_or_default();
                match word.as_str() {
                    "nil" => Ok(Value::Nil),
                    "true" => Ok(Value::Bool(true)),
                    "false" => Ok(Value::Bool(false)),
                    _ => Err(self.error(format!("unexpected name '{word}'"))),
                }
            }
            Some(c) => Err(self.error(format!("unexpected '{}'", c as char))),
            None => Err(self.error("unexpected end of file")),
        }
    }

    fn table(&mut self, depth: usize) -> Result<Table, ParseError> {
        self.bump(); // {
        let mut table = Table::default();
        let mut next_index = 1i64;
        loop {
            self.skip_space()?;
            if self.eat(b'}') {
                return Ok(table);
            }
            let key = if self.peek() == Some(b'[') && !matches!(self.peek_at(1), Some(b'[' | b'=')) {
                self.bump();
                let key = match self.value(depth)? {
                    Value::Str(s) => Key::Str(s),
                    Value::Number(n) if n.fract() == 0.0 && n.abs() < 9.0e15 => Key::Int(n as i64),
                    _ => return Err(self.error("table keys must be strings or whole numbers")),
                };
                self.skip_space()?;
                if !self.eat(b']') {
                    return Err(self.error("expected ']'"));
                }
                self.expect_equals()?;
                Some(key)
            } else if matches!(self.peek(), Some(c) if c.is_ascii_alphabetic() || c == b'_') {
                // `name = value`, or a bare true/false/nil value.
                let save = (self.pos, self.line);
                let word = self.name().unwrap_or_default();
                self.skip_space()?;
                if self.peek() == Some(b'=') && self.peek_at(1) != Some(b'=') {
                    self.bump();
                    Some(Key::Str(word))
                } else {
                    (self.pos, self.line) = save;
                    None
                }
            } else {
                None
            };
            let value = self.value(depth)?;
            let key = key.unwrap_or_else(|| {
                next_index += 1;
                Key::Int(next_index - 1)
            });
            if value != Value::Nil {
                table.entries.push((key, value));
            }
            self.skip_space()?;
            if self.eat(b',') || self.eat(b';') {
                continue;
            }
            self.skip_space()?;
            if self.eat(b'}') {
                return Ok(table);
            }
            return Err(self.error("expected ',' or '}'"));
        }
    }

    fn expect_equals(&mut self) -> Result<(), ParseError> {
        self.skip_space()?;
        if self.eat(b'=') {
            Ok(())
        } else {
            Err(self.error("expected '='"))
        }
    }

    fn quoted(&mut self) -> Result<String, ParseError> {
        let quote = self.bump().unwrap_or(b'"');
        let mut out = Vec::new();
        loop {
            match self.bump() {
                None | Some(b'\n') => return Err(self.error("unfinished string")),
                Some(c) if c == quote => break,
                Some(b'\\') => {
                    let c = self.bump().ok_or_else(|| self.error("unfinished string"))?;
                    match c {
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'a' => out.push(7),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'v' => out.push(11),
                        b'\\' | b'"' | b'\'' => out.push(c),
                        b'\n' => out.push(b'\n'),
                        b'\r' => {
                            self.eat(b'\n');
                            out.push(b'\n');
                        }
                        b'x' => {
                            let hex = self.src.get(self.pos..self.pos + 2).unwrap_or_default();
                            let n = std::str::from_utf8(hex).ok().and_then(|h| u8::from_str_radix(h, 16).ok());
                            let n = n.ok_or_else(|| self.error("bad \\x escape"))?;
                            self.pos += 2;
                            out.push(n);
                        }
                        b'0'..=b'9' => {
                            let mut n = u32::from(c - b'0');
                            for _ in 0..2 {
                                match self.peek() {
                                    Some(d @ b'0'..=b'9') => {
                                        self.bump();
                                        n = n * 10 + u32::from(d - b'0');
                                    }
                                    _ => break,
                                }
                            }
                            let byte = u8::try_from(n).map_err(|_| self.error("escape out of range"))?;
                            out.push(byte);
                        }
                        _ => return Err(self.error(format!("bad escape '\\{}'", c as char))),
                    }
                }
                Some(c) => out.push(c),
            }
        }
        Ok(String::from_utf8_lossy(&out).into_owned())
    }

    fn number(&mut self) -> Result<f64, ParseError> {
        let negative = self.eat(b'-');
        self.skip_space()?;
        let start = self.pos;
        let n = if self.peek() == Some(b'0') && matches!(self.peek_at(1), Some(b'x' | b'X')) {
            self.pos += 2;
            let digits = self.pos;
            while matches!(self.peek(), Some(c) if c.is_ascii_hexdigit()) {
                self.pos += 1;
            }
            let text = std::str::from_utf8(&self.src[digits..self.pos]).unwrap_or("");
            u64::from_str_radix(text, 16).map(|n| n as f64).ok()
        } else {
            while matches!(self.peek(), Some(c) if c.is_ascii_digit() || c == b'.') {
                self.pos += 1;
            }
            if matches!(self.peek(), Some(b'e' | b'E')) {
                self.pos += 1;
                if matches!(self.peek(), Some(b'+' | b'-')) {
                    self.pos += 1;
                }
                while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                    self.pos += 1;
                }
            }
            std::str::from_utf8(&self.src[start..self.pos]).ok().and_then(|t| t.parse::<f64>().ok())
        };
        let n = n.ok_or_else(|| self.error("bad number"))?;
        Ok(if negative { -n } else { n })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one(src: &str) -> Value {
        parse(&format!("X = {src}")).unwrap().remove("X").unwrap()
    }

    #[test]
    fn scalars() {
        assert_eq!(one("nil"), Value::Nil);
        assert_eq!(one("true"), Value::Bool(true));
        assert_eq!(one("-2531.31201171875"), Value::Number(-2531.31201171875));
        assert_eq!(one("1e3"), Value::Number(1000.0));
        assert_eq!(one("0x1F"), Value::Number(31.0));
        assert_eq!(one(r#""a\"b\\c\nd\065""#), Value::Str("a\"b\\c\ndA".into()));
        assert_eq!(one("[[long\n]]"), Value::Str("long\n".into()));
    }

    #[test]
    fn utf8_text_survives() {
        assert_eq!(one("\"Praise the sun! ☀ café\""), Value::Str("Praise the sun! ☀ café".into()));
        // WoW sometimes writes non-ASCII bytes as decimal escapes.
        assert_eq!(one(r#""caf\195\169""#), Value::Str("café".into()));
    }

    #[test]
    fn tables_as_wow_writes_them() {
        let v = one(
            "{\n[\"stones\"] = {\n[\"Mad-Decent-1-1\"] = {\n[\"v\"] = 2,\n},\n},\n[1411] = true,\n\"first\", -- [1]\n\"second\", -- [2]\n}",
        );
        assert_eq!(v.path(&["stones", "Mad-Decent-1-1", "v"]), Some(&Value::Number(2.0)));
        let t = v.as_table().unwrap();
        assert_eq!(t.get_int(1411), Some(&Value::Bool(true)));
        assert_eq!(t.get_int(1), Some(&Value::Str("first".into())));
        assert_eq!(t.get_int(2), Some(&Value::Str("second".into())));
    }

    #[test]
    fn bare_keys_semicolons_and_nil_values() {
        let v = one("{ a = 1; b = nil, [\"c\"] = false, }");
        let t = v.as_table().unwrap();
        assert_eq!(t.get("a"), Some(&Value::Number(1.0)));
        assert_eq!(t.get("b"), None);
        assert_eq!(t.get("c"), Some(&Value::Bool(false)));
    }

    #[test]
    fn several_variables_and_comments() {
        let vars = parse("\u{feff}-- header\nA = 1\n--[[ block\ncomment ]]\nB = { }\n").unwrap();
        assert_eq!(vars["A"], Value::Number(1.0));
        assert_eq!(vars["B"], Value::Table(Table::default()));
    }

    #[test]
    fn refuses_code() {
        for bad in [
            "X = os.exit()",
            "X = print",
            "X = 1 + 1",
            "X = { f() }",
            "X = function() end",
            "X = \"unfinished",
            "X = { [{}] = 1 }",
            "X = { 1 2 }",
        ] {
            assert!(parse(bad).is_err(), "should refuse: {bad}");
        }
    }

    #[test]
    fn refuses_deep_nesting() {
        let deep = format!("X = {}{}", "{".repeat(500), "}".repeat(500));
        assert!(parse(&deep).is_err());
    }

    #[test]
    fn errors_name_the_line() {
        let err = parse("X = {\n[\"a\"] = 1,\n[\"b\"] = oops,\n}").unwrap_err();
        assert_eq!(err.line, 3);
    }
}
