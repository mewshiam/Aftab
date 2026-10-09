//! A tiny, real HTTP/1.1 server for integration tests.
//!
//! The brief's rule: **no mocks of our own code.** The provider and the
//! downloader are exercised against a genuine TCP socket, a genuine HTTP
//! request parse, and genuine response bytes — only the *remote server* is
//! synthesized, which is exactly what a fixture server is for.

#![allow(dead_code)]

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

/// One parsed incoming request.
#[derive(Debug, Clone)]
pub struct Request {
    pub method: String,
    pub path: String,
    /// Parsed `Range: bytes=N-` header, if present.
    pub range_from: Option<u64>,
}

/// One canned response.
#[derive(Debug, Clone)]
pub struct Resp {
    pub status: u16,
    pub body: Vec<u8>,
    pub content_range: Option<String>,
}

impl Resp {
    /// 200 with a JSON body.
    pub fn json(body: impl Into<String>) -> Resp {
        Resp {
            status: 200,
            body: body.into().into_bytes(),
            content_range: None,
        }
    }

    /// 500 with a stub body.
    pub fn error() -> Resp {
        Resp {
            status: 500,
            body: b"upstream exploded".to_vec(),
            content_range: None,
        }
    }
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        206 => "Partial Content",
        416 => "Range Not Satisfiable",
        500 => "Internal Server Error",
        _ => "Status",
    }
}

/// A live fixture server. Records every request it served.
pub struct TestServer {
    /// Host:port the server is listening on.
    pub addr: String,
    /// Base URL, e.g. `http://127.0.0.1:39127`.
    pub base: String,
    /// Every request path (plus its Range, when present), in order.
    pub hits: Arc<Mutex<Vec<String>>>,
}

impl TestServer {
    /// URL for a path.
    pub fn url(&self, path: &str) -> String {
        format!("{}{}", self.base, path)
    }

    /// Number of recorded requests whose path contains `needle`.
    pub fn hits_containing(&self, needle: &str) -> usize {
        self.hits
            .lock()
            .map(|h| h.iter().filter(|p| p.contains(needle)).count())
            .unwrap_or(0)
    }

    /// Snapshot of all recorded requests.
    pub fn recorded(&self) -> Vec<String> {
        self.hits.lock().map(|h| h.clone()).unwrap_or_default()
    }
}

/// Spawn a fixture server. `handler` decides the response for each request.
pub fn spawn_server<F>(handler: F) -> TestServer
where
    F: Fn(&Request) -> Resp + Send + Sync + 'static,
{
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind fixture server");
    let addr = listener.local_addr().expect("local addr");
    let base = format!("http://{addr}");
    let hits: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
    let hits_clone = Arc::clone(&hits);

    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { break };
            let handler = &handler;
            let hits = &hits_clone;
            if serve_one(stream, handler, hits).is_err() {
                // A malformed request kills only that connection.
                continue;
            }
        }
    });

    // Give the accept loop a moment to be ready.
    thread::sleep(Duration::from_millis(20));

    TestServer {
        addr: addr.to_string(),
        base,
        hits,
    }
}

/// Spawn a "server down": accepts connections, then closes them without
/// answering. Deterministic on every platform — unlike bind-then-drop port
/// games, which Windows can immediately re-assign to the next listener.
pub fn spawn_refusing_server() -> TestServer {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind refusing server");
    let addr = listener.local_addr().expect("local addr");
    let base = format!("http://{addr}");
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { break };
            // Answer nothing; kill the socket immediately.
            let _ = stream.shutdown(std::net::Shutdown::Both);
        }
    });
    thread::sleep(Duration::from_millis(20));
    TestServer {
        addr: addr.to_string(),
        base,
        hits: Arc::new(Mutex::new(Vec::new())),
    }
}

fn serve_one<F>(stream: TcpStream, handler: F, hits: &Mutex<Vec<String>>) -> std::io::Result<()>
where
    F: Fn(&Request) -> Resp,
{
    stream.set_read_timeout(Some(Duration::from_secs(10)))?;
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    let mut reader = BufReader::new(stream.try_clone()?);

    let mut request_line = String::new();
    reader.read_line(&mut request_line)?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("GET").to_string();
    let path = parts.next().unwrap_or("/").to_string();

    // Headers until the blank line.
    let mut range_from: Option<u64> = None;
    loop {
        let mut line = String::new();
        reader.read_line(&mut line)?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            break;
        }
        if let Some((name, value)) = trimmed.split_once(':') {
            if name.trim().eq_ignore_ascii_case("range") {
                let spec = value.trim();
                if let Some(num) = spec
                    .strip_prefix("bytes=")
                    .and_then(|r| r.split('-').next())
                {
                    range_from = num.parse().ok();
                }
            }
        }
    }

    if let Ok(mut h) = hits.lock() {
        h.push(match range_from {
            Some(r) => format!("{path} [range {r}]"),
            None => path.clone(),
        });
    }

    let resp = handler(&Request {
        method,
        path,
        range_from,
    });

    let mut stream = stream;
    let mut head = format!(
        "HTTP/1.1 {} {}\r\nContent-Length: {}\r\nConnection: close\r\n",
        resp.status,
        reason(resp.status),
        resp.body.len()
    );
    if let Some(cr) = &resp.content_range {
        head.push_str(&format!("Content-Range: {cr}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes())?;
    stream.write_all(&resp.body)?;
    stream.flush()?;
    stream.shutdown(std::net::Shutdown::Both)?;
    Ok(())
}

/// A handler that serves `data` with real HTTP `Range` support —
/// the semantics a media CDN implements.
pub fn range_aware(data: &'static [u8]) -> impl Fn(&Request) -> Resp {
    move |req: &Request| match req.range_from {
        Some(from) if (from as usize) < data.len() => Resp {
            status: 206,
            body: data[from as usize..].to_vec(),
            content_range: Some(format!("bytes {}-{}/{}", from, data.len() - 1, data.len())),
        },
        Some(_) => Resp {
            status: 416,
            body: Vec::new(),
            content_range: None,
        },
        None => Resp {
            status: 200,
            body: data.to_vec(),
            content_range: None,
        },
    }
}

/// A handler that always ignores `Range` and returns the full body with 200
/// — the "dumb CDN" case the downloader must survive.
pub fn range_blind(data: &'static [u8]) -> impl Fn(&Request) -> Resp {
    move |_req: &Request| Resp {
        status: 200,
        body: data.to_vec(),
        content_range: None,
    }
}
