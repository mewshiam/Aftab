//! Error taxonomy for the Aftab core.
//!
//! Every failure path in the core maps to one [`AftabError`] with a stable
//! numeric [`code`](AftabError::code) that crosses the FFI boundary unchanged.
//! The Dart side never parses error strings; it switches on the code.

use std::fmt;

/// Stable error codes shared with the FFI layer (`core/include/aftab.h`).
///
/// Codes are non-zero, monotonically assigned, and must never be renumbered
/// once published — the C header and Dart bindings depend on them.
pub mod codes {
    pub const NETWORK: i32 = 1;
    pub const BAD_RESPONSE: i32 = 2;
    pub const PARSE: i32 = 3;
    pub const BAD_URL: i32 = 4;
    pub const UNSAFE_URL: i32 = 5;
    pub const UNSUPPORTED_SCHEME: i32 = 6;
    pub const IO: i32 = 7;
    pub const INVALID_ARGUMENT: i32 = 8;
    pub const STORAGE: i32 = 9;
    pub const NOT_FOUND: i32 = 10;
    pub const OUT_OF_MEMORY: i32 = 11;
    pub const UNKNOWN: i32 = 99;
}

/// The single error type used across the core.
#[derive(Debug)]
pub enum AftabError {
    /// Transport-level failure (DNS, connect, read, timeout).
    Network(String),
    /// Server answered, but with a non-success HTTP status.
    BadResponse { status: u16, url: String },
    /// Payload arrived but could not be parsed as the expected shape.
    Parse(String),
    /// A URL could not be parsed at all.
    BadUrl(String),
    /// A URL parses but points somewhere we refuse to talk to
    /// (SSRF guard: private / loopback / link-local hosts, userinfo, …).
    UnsafeUrl(String),
    /// A URL uses a scheme we do not support for media transport.
    UnsupportedScheme(String),
    /// Local filesystem failure.
    Io(String),
    /// Caller passed an invalid argument (empty API key, bad page number…).
    InvalidArgument(String),
    /// Persistent store failure (corrupt file, unwritable directory…).
    Storage(String),
    /// Requested entity does not exist.
    NotFound(String),
    /// FFI-level allocation failure.
    OutOfMemory,
    /// Anything else.
    Unknown(String),
}

impl AftabError {
    /// Stable numeric code, mirrored in `core/include/aftab.h`.
    pub fn code(&self) -> i32 {
        match self {
            AftabError::Network(_) => codes::NETWORK,
            AftabError::BadResponse { .. } => codes::BAD_RESPONSE,
            AftabError::Parse(_) => codes::PARSE,
            AftabError::BadUrl(_) => codes::BAD_URL,
            AftabError::UnsafeUrl(_) => codes::UNSAFE_URL,
            AftabError::UnsupportedScheme(_) => codes::UNSUPPORTED_SCHEME,
            AftabError::Io(_) => codes::IO,
            AftabError::InvalidArgument(_) => codes::INVALID_ARGUMENT,
            AftabError::Storage(_) => codes::STORAGE,
            AftabError::NotFound(_) => codes::NOT_FOUND,
            AftabError::OutOfMemory => codes::OUT_OF_MEMORY,
            AftabError::Unknown(_) => codes::UNKNOWN,
        }
    }

    /// Human-readable message. Persian strings are user-facing; English
    /// strings are developer-facing diagnostics.
    pub fn message(&self) -> String {
        match self {
            AftabError::Network(m) => format!("network error: {m}"),
            AftabError::BadResponse { status, url } => {
                format!("server returned HTTP {status} for {url}")
            }
            AftabError::Parse(m) => format!("could not parse response: {m}"),
            AftabError::BadUrl(m) => format!("invalid URL: {m}"),
            AftabError::UnsafeUrl(m) => format!("unsafe URL rejected: {m}"),
            AftabError::UnsupportedScheme(m) => format!("unsupported URL scheme: {m}"),
            AftabError::Io(m) => format!("I/O error: {m}"),
            AftabError::InvalidArgument(m) => format!("invalid argument: {m}"),
            AftabError::Storage(m) => format!("storage error: {m}"),
            AftabError::NotFound(m) => format!("not found: {m}"),
            AftabError::OutOfMemory => "out of memory".to_string(),
            AftabError::Unknown(m) => format!("unknown error: {m}"),
        }
    }
}

impl fmt::Display for AftabError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}] {}", self.code(), self.message())
    }
}

impl std::error::Error for AftabError {}

impl From<std::io::Error> for AftabError {
    fn from(e: std::io::Error) -> Self {
        AftabError::Io(e.to_string())
    }
}

impl From<serde_json::Error> for AftabError {
    fn from(e: serde_json::Error) -> Self {
        AftabError::Parse(e.to_string())
    }
}

impl From<url::ParseError> for AftabError {
    fn from(e: url::ParseError) -> Self {
        AftabError::BadUrl(e.to_string())
    }
}

/// Convenient result alias used throughout the core.
pub type AftabResult<T> = Result<T, AftabError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_stable_and_distinct() {
        let all = [
            codes::NETWORK,
            codes::BAD_RESPONSE,
            codes::PARSE,
            codes::BAD_URL,
            codes::UNSAFE_URL,
            codes::UNSUPPORTED_SCHEME,
            codes::IO,
            codes::INVALID_ARGUMENT,
            codes::STORAGE,
            codes::NOT_FOUND,
            codes::OUT_OF_MEMORY,
            codes::UNKNOWN,
        ];
        let mut sorted = all.to_vec();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), all.len(), "error codes must be unique");
        assert!(all.iter().all(|c| *c != 0), "zero is reserved for OK");
    }

    #[test]
    fn network_error_display_includes_code() {
        let e = AftabError::Network("timeout".into());
        assert_eq!(e.code(), codes::NETWORK);
        let text = e.to_string();
        assert!(
            text.starts_with("[1]"),
            "display embeds the stable code: {text}"
        );
    }

    #[test]
    fn io_conversion() {
        let e: AftabError = std::io::Error::new(std::io::ErrorKind::NotFound, "gone").into();
        assert_eq!(e.code(), codes::IO);
    }

    #[test]
    fn serde_error_maps_to_parse() {
        let bad: serde_json::Result<()> = serde_json::from_str("{definitely not json");
        let e: AftabError = bad.err().unwrap().into();
        assert_eq!(e.code(), codes::PARSE);
    }

    #[test]
    fn url_parse_error_maps_to_bad_url() {
        let e: AftabError = url::Url::parse("not a url at all").unwrap_err().into();
        assert_eq!(e.code(), codes::BAD_URL);
    }
}
