//! Talking to the Soapstone server (`server/`). The request and response
//! shapes are documented in `server/src/push.ts` and `server/src/pull.ts`.

use std::fmt;
use std::time::Duration;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug)]
pub enum ApiError {
    /// No answer at all: offline, or the server is down.
    Unreachable(String),
    /// `429`: wait this many seconds.
    Busy(u64),
    /// Any other error the server answered with (`{ error, message }`).
    Server { status: u16, code: String, message: String },
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::Unreachable(e) => write!(f, "can't reach the server ({e})"),
            ApiError::Busy(s) => write!(f, "server busy, retrying in {s} s"),
            ApiError::Server { status, message, .. } => write!(f, "server said {status}: {message}"),
        }
    }
}

impl std::error::Error for ApiError {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Registration {
    pub install_id: String,
    pub token: String,
}

#[derive(Deserialize)]
struct Challenge {
    challenge: String,
    bits: u32,
}

#[derive(Deserialize)]
struct ErrorBody {
    error: Option<String>,
    message: Option<String>,
}

pub struct Client {
    base: String,
    http: reqwest::blocking::Client,
    auth: Option<String>,
}

impl Client {
    pub fn new(base: &str, registration: Option<&Registration>) -> Client {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent(concat!("SoapstoneCompanion/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("HTTP client");
        Client {
            base: base.trim_end_matches('/').to_owned(),
            http,
            auth: registration.map(|r| format!("Bearer {}.{}", r.install_id, r.token)),
        }
    }

    /// Registers this install: fetch a puzzle, solve it, trade it for a token.
    pub fn register(&self) -> Result<Registration, ApiError> {
        let c: Challenge = self.send(self.http.get(format!("{}/v1/challenge", self.base)))?;
        let nonce = solve(&c.challenge, c.bits);
        let body = serde_json::json!({ "challenge": c.challenge, "nonce": nonce.to_string() });
        self.send(self.http.post(format!("{}/v1/register", self.base)).json(&body))
    }

    pub fn get<T: DeserializeOwned>(&self, path_and_query: &str) -> Result<T, ApiError> {
        self.send(self.authed(self.http.get(format!("{}{path_and_query}", self.base))))
    }

    pub fn post<T: DeserializeOwned>(&self, path: &str, body: &impl Serialize) -> Result<T, ApiError> {
        self.send(self.authed(self.http.post(format!("{}{path}", self.base))).json(body))
    }

    fn authed(&self, req: reqwest::blocking::RequestBuilder) -> reqwest::blocking::RequestBuilder {
        match &self.auth {
            Some(a) => req.header(reqwest::header::AUTHORIZATION, a),
            None => req,
        }
    }

    fn send<T: DeserializeOwned>(&self, req: reqwest::blocking::RequestBuilder) -> Result<T, ApiError> {
        let res = req.send().map_err(|e| ApiError::Unreachable(e.without_url().to_string()))?;
        let status = res.status();
        if status.as_u16() == 429 {
            let wait = res
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse().ok())
                .unwrap_or(60);
            return Err(ApiError::Busy(wait));
        }
        let text = res.text().map_err(|e| ApiError::Unreachable(e.without_url().to_string()))?;
        if !status.is_success() {
            let body: Option<ErrorBody> = serde_json::from_str(&text).ok();
            return Err(ApiError::Server {
                status: status.as_u16(),
                code: body.as_ref().and_then(|b| b.error.clone()).unwrap_or_default(),
                message: body.and_then(|b| b.message).unwrap_or_else(|| status.to_string()),
            });
        }
        serde_json::from_str(&text).map_err(|e| ApiError::Server {
            status: status.as_u16(),
            code: "bad_response".into(),
            message: e.to_string(),
        })
    }
}

/// The proof of work (`server/src/auth.ts`): a nonce such that
/// SHA-256("<challenge>:<nonce>") starts with `bits` zero bits.
pub fn solve(challenge: &str, bits: u32) -> u64 {
    (0u64..).find(|nonce| leading_zero_bits(&Sha256::digest(format!("{challenge}:{nonce}"))) >= bits).unwrap_or(0)
}

fn leading_zero_bits(digest: &[u8]) -> u32 {
    let mut bits = 0;
    for byte in digest {
        if *byte == 0 {
            bits += 8;
        } else {
            return bits + byte.leading_zeros();
        }
    }
    bits
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_leading_zero_bits() {
        assert_eq!(leading_zero_bits(&[0x00, 0x0f, 0xff]), 12);
        assert_eq!(leading_zero_bits(&[0x80]), 0);
        assert_eq!(leading_zero_bits(&[0x00, 0x00]), 16);
    }

    #[test]
    fn solves_a_puzzle() {
        let nonce = solve("1791234567.abc.def", 12);
        let digest = Sha256::digest(format!("1791234567.abc.def:{nonce}"));
        assert!(leading_zero_bits(&digest) >= 12);
    }

    #[test]
    fn unreachable_server() {
        let err = Client::new("http://127.0.0.1:9", None).register().unwrap_err();
        assert!(matches!(err, ApiError::Unreachable(_)), "{err}");
    }
}
