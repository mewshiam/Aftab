//! Thin, timeout-aware HTTP client used by the provider and downloader.
//!
//! Wraps `ureq` 2.x (rustls — no system OpenSSL dependency, which matters on
//! Android and Windows) and maps every failure onto the [`AftabError`]
//! taxonomy so callers never see a foreign error type.

use std::time::Duration;

use crate::error::{AftabError, AftabResult};

/// Default timeout: upstream uses 30s connect / 30s read; we keep one
/// overall budget per request so failover rounds stay bounded.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

/// An HTTP client. Cheap to clone (the underlying agent is shared).
#[derive(Clone)]
pub struct HttpClient {
    agent: ureq::Agent,
    timeout: Duration,
}

impl Default for HttpClient {
    fn default() -> Self {
        HttpClient::new(DEFAULT_TIMEOUT)
    }
}

impl HttpClient {
    /// A client with a per-request overall timeout.
    pub fn new(timeout: Duration) -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout(timeout)
            .user_agent(concat!("Aftab/", env!("CARGO_PKG_VERSION")))
            .build();
        HttpClient { agent, timeout }
    }

    /// The configured per-request timeout.
    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    /// GET a URL, returning the body as text. Non-2xx statuses become
    /// [`AftabError::BadResponse`] — which is exactly the signal the
    /// provider's failover loop listens for.
    pub fn get_text(&self, url: &str) -> AftabResult<String> {
        let response = self.agent.get(url).call().map_err(map_ureq_error)?;
        read_body(response, url)
    }

    /// GET with a `Range: bytes=N-` header (plain GET when `from == 0`),
    /// for resumable downloads. Returns `(status, body, content_length)` so
    /// the downloader can distinguish 206 (resume ok) from 200 (full
    /// restart).
    pub fn get_range(&self, url: &str, from: u64) -> AftabResult<(u16, Vec<u8>, Option<u64>)> {
        let mut request = self.agent.get(url);
        if from > 0 {
            request = request.set("Range", &format!("bytes={from}-"));
        }
        let response = request.call().map_err(map_ureq_error)?;
        let status = response.status();
        let total = content_length(&response);
        let mut bytes = Vec::new();
        use std::io::Read;
        response
            .into_reader()
            .read_to_end(&mut bytes)
            .map_err(|e| AftabError::Network(format!("body read failed: {e}")))?;
        Ok((status, bytes, total))
    }

    /// GET a URL known to be small (metadata), bounded in size to keep a
    /// hostile server from exhausting memory.
    pub fn get_text_bounded(&self, url: &str, max_bytes: usize) -> AftabResult<String> {
        let response = self.agent.get(url).call().map_err(map_ureq_error)?;
        let status = response.status();
        if !(200..300).contains(&status) {
            return Err(AftabError::BadResponse {
                status,
                url: crate::urlsafe::redact_url_for_log(url),
            });
        }
        let total = content_length(&response);
        if let Some(t) = total {
            if t as usize > max_bytes {
                return Err(AftabError::BadResponse {
                    status: 413,
                    url: crate::urlsafe::redact_url_for_log(url),
                });
            }
        }
        read_body(response, url)
    }
}

fn map_ureq_error(e: ureq::Error) -> AftabError {
    match e {
        ureq::Error::Status(code, resp) => {
            let url = resp.get_url().to_string();
            AftabError::BadResponse {
                status: code,
                url: crate::urlsafe::redact_url_for_log(&url),
            }
        }
        ureq::Error::Transport(t) => AftabError::Network(t.to_string()),
    }
}

fn read_body(response: ureq::Response, url: &str) -> AftabResult<String> {
    let status = response.status();
    if !(200..300).contains(&status) {
        return Err(AftabError::BadResponse {
            status,
            url: crate::urlsafe::redact_url_for_log(url),
        });
    }
    response
        .into_string()
        .map_err(|e| AftabError::Network(format!("body read failed: {e}")))
}

fn content_length(response: &ureq::Response) -> Option<u64> {
    response
        .header("Content-Length")
        .and_then(|v| v.parse::<u64>().ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_timeout_is_30s() {
        assert_eq!(HttpClient::default().timeout(), Duration::from_secs(30));
    }

    #[test]
    fn custom_timeout_is_reported() {
        assert_eq!(
            HttpClient::new(Duration::from_secs(5)).timeout(),
            Duration::from_secs(5)
        );
    }

    // Network-level integration coverage lives in tests/provider_integration.rs,
    // which spins a real local HTTP server — see that file for the full story.
}
