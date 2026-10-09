//! URL safety for untrusted media URLs.
//!
//! Every URL that arrives from the provider API is *untrusted input*: before
//! the player or the downloader is allowed to touch it, it must pass
//! [`is_safe_media_url`]. The checks:
//!
//! 1. Parses cleanly with the `url` crate (**parse first, sanitize later** —
//!    percent-encoding an already-built string before parsing was the source
//!    of a real double-encoding bug, hence the ordering test below).
//! 2. Scheme is exactly `http` or `https`.
//! 3. No userinfo (`https://evil@cdn/…` tricks).
//! 4. The host resolves to a **public** address — loopback, private ranges,
//!    link-local, multicast, unspecified, and broadcast addresses are all
//!    refused (SSRF guard). IPv6 literals are handled with their brackets
//!    stripped for resolution but preserved in the canonical URL.
//! 5. Port is explicit or scheme-default; non-default ports are allowed but
//!    the canonical form records them so logs can't "forget" them.
//!
//! Trusted, app-configured endpoints (the provider base and its helpers) are
//! exempt by design — see [`Policy::trusted`]. The provider itself applies
//! the untrusted policy only to URLs *inside* API responses (media sources),
//! never to its own configuration.

use std::net::{IpAddr, ToSocketAddrs};

use url::Url;

use crate::error::{AftabError, AftabResult};

/// Which URLs we are willing to talk to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Policy {
    /// Allow loopback/private/link-local hosts. Enabled **only** by tests
    /// that run against local fixture servers; production keeps this off.
    pub allow_private_hosts: bool,
}

impl Policy {
    /// The production policy: strict, private networks refused.
    pub const STRICT: Policy = Policy {
        allow_private_hosts: false,
    };

    /// The test policy: local fixture servers allowed.
    pub const TRUSTED: Policy = Policy {
        allow_private_hosts: true,
    };
}

impl Default for Policy {
    fn default() -> Self {
        Policy::STRICT
    }
}

/// Validate an untrusted URL under the strict production policy.
pub fn is_safe_media_url(input: &str) -> AftabResult<Url> {
    check_url(input, Policy::STRICT)
}

/// Validate an untrusted URL under an explicit policy.
pub fn check_url(input: &str, policy: Policy) -> AftabResult<Url> {
    // 1) Parse FIRST, on the raw input. Sanitizing before parsing causes
    //    double-encoding (`%2520`), which once made safe URLs look unsafe.
    let trimmed = input.trim();
    let url = Url::parse(trimmed).map_err(|e| AftabError::BadUrl(format!("{e}: {trimmed:?}")))?;

    // 2) Scheme allow-list.
    match url.scheme() {
        "http" | "https" => {}
        other => {
            return Err(AftabError::UnsupportedScheme(format!(
                "{other:?} — only http/https are supported for media"
            )))
        }
    }

    // 3) Userinfo must be absent.
    if url.username() != "" || url.password().is_some() {
        return Err(AftabError::UnsafeUrl("userinfo is not allowed".into()));
    }

    // 4) Host must be present.
    let host = url
        .host_str()
        .ok_or_else(|| AftabError::UnsafeUrl("URL has no host".into()))?;

    if !policy.allow_private_hosts {
        check_public_host(host, url.port_or_known_default())?;
    }

    Ok(url)
}

/// Resolve `host` (brackets already handled by `url`) and refuse
/// non-public addresses.
fn check_public_host(host: &str, port: Option<u16>) -> AftabResult<()> {
    // The `url` crate keeps IPv6 literals WITHOUT brackets in `host_str()`
    // and WITH brackets in serialization; resolve the bracket-free form.
    let dns_target = host.trim_matches(|c| c == '[' || c == ']');

    let ips: Vec<IpAddr> = if let Ok(ip) = dns_target.parse::<IpAddr>() {
        vec![ip]
    } else {
        // DNS resolution (blocking — the core is called off the UI thread).
        let port = port.unwrap_or(80);
        (dns_target, port)
            .to_socket_addrs()
            .map_err(|e| {
                AftabError::Network(format!("DNS resolution failed for {dns_target}: {e}"))
            })?
            .map(|sa| sa.ip())
            .collect()
    };

    if ips.is_empty() {
        return Err(AftabError::Network(format!(
            "host {dns_target} resolved to no addresses"
        )));
    }

    for ip in ips {
        if !is_public_ip(ip) {
            return Err(AftabError::UnsafeUrl(format!(
                "{host} resolves to non-public address {ip}"
            )));
        }
    }
    Ok(())
}

/// Is this IP acceptable for an untrusted outbound connection?
pub fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            !(v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_multicast()
                || v4.is_broadcast()
                || v4.is_unspecified()
                // Carrier-grade NAT 100.64.0.0/10 and documentation ranges.
                || v4.octets()[0] == 100 && (v4.octets()[1] & 0xC0) == 64
                || matches!(v4.octets()[0], 192) && v4.octets()[1] == 0 && v4.octets()[2] == 2
                || v4.octets()[0] == 198 && (v4.octets()[1] == 18 || v4.octets()[1] == 19))
        }
        IpAddr::V6(v6) => {
            !(v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || (v6.segments()[0] & 0xfe00) == 0xfc00 // unique-local fc00::/7
                || (v6.segments()[0] & 0xffc0) == 0xfe80) // link-local fe80::/10
        }
    }
}

/// Redact a URL for logging: keep scheme, host, and **port**; drop path,
/// query, and fragment. (An earlier version dropped the port too, which made
/// failover diagnostics useless — the test below pins the fix.)
pub fn redact_url_for_log(url: &str) -> String {
    match Url::parse(url.trim()) {
        Ok(u) => {
            let mut out = format!("{}://{}", u.scheme(), u.host_str().unwrap_or("?"));
            if let Some(p) = u.port() {
                out.push_str(&format!(":{p}"));
            }
            out
        }
        Err(_) => "<unparseable url>".to_string(),
    }
}

/// Percent-encode a single URL path segment (used to build provider URLs
/// from raw user queries — `URLEncoder.encode` upstream encodes spaces as
/// `+`, which the API rejects; we emit `%20`).
pub fn encode_path_segment(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.as_bytes() {
        match *b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(*b as char)
            }
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

/// Map a safety failure to its stable error code (used by tests; handy for
/// FFI callers too). `None` means the URL is safe.
pub fn unsafe_reason(input: &str) -> Option<i32> {
    is_safe_media_url(input).err().map(|e| e.code())
}

/// Convenience used by tests and the FFI: does the URL pass the strict policy?
pub fn strict_ok(input: &str) -> bool {
    is_safe_media_url(input).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::codes;

    #[test]
    fn https_and_http_are_supported() {
        // Public IP literals — no live DNS needed in unit tests.
        assert!(strict_ok("https://93.184.216.34/video.mp4"));
        assert!(strict_ok("http://8.8.8.8:8080/v.mp4"));
    }

    #[test]
    fn non_http_schemes_are_refused() {
        assert_eq!(
            unsafe_reason("ftp://example.com/v.mp4"),
            Some(codes::UNSUPPORTED_SCHEME)
        );
        assert_eq!(
            unsafe_reason("file:///etc/passwd"),
            Some(codes::UNSUPPORTED_SCHEME)
        );
        assert_eq!(
            unsafe_reason("javascript:alert(1)"),
            Some(codes::UNSUPPORTED_SCHEME)
        );
    }

    #[test]
    fn garbage_is_bad_url() {
        assert_eq!(unsafe_reason("not a url"), Some(codes::BAD_URL));
        assert_eq!(unsafe_reason(""), Some(codes::BAD_URL));
    }

    #[test]
    fn user_info_is_refused() {
        assert_eq!(
            unsafe_reason("https://user:pass@cdn.example.com/v.mp4"),
            Some(codes::UNSAFE_URL)
        );
        assert_eq!(
            unsafe_reason("http://token@localhost/x"),
            Some(codes::UNSAFE_URL) // userinfo fails before the IP check
        );
    }

    #[test]
    fn loopback_ipv4_is_refused() {
        assert_eq!(
            unsafe_reason("http://127.0.0.1/video.mp4"),
            Some(codes::UNSAFE_URL)
        );
        assert_eq!(
            unsafe_reason("http://127.255.255.254/x"),
            Some(codes::UNSAFE_URL)
        );
    }

    #[test]
    fn private_ipv4_ranges_are_refused() {
        for url in [
            "http://10.0.0.1/v.mp4",
            "http://172.16.5.4/v.mp4",
            "http://192.168.1.1/v.mp4",
            "http://169.254.169.254/latest/meta-data", // cloud metadata
            "http://0.0.0.0/x",
            "http://255.255.255.255/x",
        ] {
            assert_eq!(unsafe_reason(url), Some(codes::UNSAFE_URL), "{url}");
        }
    }

    #[test]
    fn ipv6_loopback_is_refused_with_or_without_brackets() {
        assert_eq!(unsafe_reason("http://[::1]/v.mp4"), Some(codes::UNSAFE_URL));
        assert_eq!(
            unsafe_reason("http://[::1]:8080/v.mp4"),
            Some(codes::UNSAFE_URL),
            "bracketed IPv6 with a port must resolve, not fail to parse"
        );
        assert_eq!(
            unsafe_reason("http://[fe80::1]/v.mp4"),
            Some(codes::UNSAFE_URL),
            "IPv6 link-local must be refused"
        );
        assert_eq!(
            unsafe_reason("http://[fd00::1]/v.mp4"),
            Some(codes::UNSAFE_URL),
            "IPv6 unique-local must be refused"
        );
    }

    #[test]
    fn trusted_policy_allows_local_fixture_servers() {
        let u = check_url("http://127.0.0.1:9/v.mp4", Policy::TRUSTED).unwrap();
        assert_eq!(u.host_str(), Some("127.0.0.1"));
        // Non-default port survives round-trip:
        assert_eq!(u.port(), Some(9));
    }

    #[test]
    fn parse_before_sanitize_no_double_encoding() {
        // A URL that already contains a percent-escape must not be re-encoded.
        let url = "http://example.com/a%20b.mp4";
        let u = check_url(url, Policy::TRUSTED).unwrap();
        assert_eq!(u.path(), "/a%20b.mp4", "the existing escape is untouched");
    }

    #[test]
    fn whitespace_is_trimmed_before_parsing() {
        assert!(check_url("  http://example.com/v.mp4  ", Policy::TRUSTED).is_ok());
    }

    #[test]
    fn redaction_keeps_port_and_drops_path() {
        let r = redact_url_for_log("https://cdn.example.com:8443/secret/path?token=x#frag");
        assert_eq!(r, "https://cdn.example.com:8443", "the port MUST survive");
        let no_port = redact_url_for_log("https://cdn.example.com/secret/path");
        assert_eq!(no_port, "https://cdn.example.com");
        assert_eq!(redact_url_for_log("garbage"), "<unparseable url>");
    }

    #[test]
    fn redaction_never_leaks_query_secrets() {
        let r = redact_url_for_log("https://h.com/p?apikey=4F5A9C3D9A86FA54EACEDDD635185");
        assert!(!r.contains("4F5A9C"), "api keys must not reach logs: {r}");
    }

    #[test]
    fn path_segment_encoding_matches_upstream_needs() {
        // Upstream URLEncoder produces '+' for spaces, which breaks these
        // path-style APIs; we require '%20'.
        assert_eq!(
            encode_path_segment("سلطان محمود"),
            "%D8%B3%D9%84%D8%B7%D8%A7%D9%86%20%D9%85%D8%AD%D9%85%D9%88%D8%AF"
        );
        assert_eq!(encode_path_segment("safe"), "safe");
        assert_eq!(
            encode_path_segment("a/b"),
            "a%2Fb",
            "path separators are escaped"
        );
    }

    #[test]
    fn public_ipv6_literal_is_accepted() {
        // 2606:4700::6810:84e5 is a real public address (Cloudflare-ish range).
        let u = check_url("http://[2606:4700::6810:84e5]/v.mp4", Policy::STRICT).unwrap();
        assert_eq!(u.host_str(), Some("[2606:4700::6810:84e5]"));
    }
}
