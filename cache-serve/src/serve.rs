//! The `/serve/<storehash>/<path>` handler.
//!
//! One request is: fetch the `.narinfo`, open the NAR, decompress it forward
//! until the wanted file's contents begin, then stream those bytes out and drop
//! the upstream connection. Nothing is written to disk and no store semantics
//! are involved -- this is the same trust level as the `.ls` listing, which is
//! already public.

use std::sync::Arc;
use std::time::Instant;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use futures_util::TryStreamExt;
use tokio::io::AsyncRead;
use tokio::sync::mpsc;
use tokio_util::io::StreamReader;

use crate::metrics::Outcome;
use crate::nar::{split_path, Located, NarReader};
use crate::narinfo::{self, Compression};
use crate::AppState;

const CHUNK: usize = 64 * 1024;

/// Store paths are immutable, so a hit can be cached indefinitely.
const IMMUTABLE: &str = "public, max-age=31536000, immutable";

/// Misses are cheap to recompute and a path can appear later, so cache them
/// briefly rather than indefinitely.
const NEGATIVE: &str = "public, max-age=60";

enum Failure {
    BadRequest(String),
    NotFound(String),
    Upstream(String),
}

impl Failure {
    fn outcome(&self) -> Outcome {
        match self {
            Self::BadRequest(_) => Outcome::BadRequest,
            Self::NotFound(_) => Outcome::NotFound,
            Self::Upstream(_) => Outcome::Error,
        }
    }

    fn into_response(self) -> Response {
        let (status, body, cache) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg, NEGATIVE),
            Self::NotFound(msg) => (StatusCode::NOT_FOUND, msg, NEGATIVE),
            Self::Upstream(msg) => (StatusCode::BAD_GATEWAY, msg, "no-store"),
        };
        (
            status,
            [
                (header::CACHE_CONTROL, cache),
                (header::CONTENT_TYPE, "text/plain; charset=utf-8"),
            ],
            format!("{body}\n"),
        )
            .into_response()
    }
}

pub async fn get_file(
    State(state): State<Arc<AppState>>,
    Path((hash, path)): Path<(String, String)>,
) -> Response {
    state.metrics.request_started();
    let started = Instant::now();
    let (response, outcome) = match serve(&state, &hash, &path, started).await {
        Ok(pair) => pair,
        Err(failure) => {
            let outcome = failure.outcome();
            (failure.into_response(), outcome)
        }
    };
    state.metrics.request_finished(outcome);
    response
}

/// A request for the store path itself rather than a file inside it.
pub async fn get_root(State(state): State<Arc<AppState>>) -> Response {
    state.metrics.request_started();
    let response = Failure::NotFound(
        "this endpoint serves individual files; use the .ls listing to discover paths".to_owned(),
    )
    .into_response();
    state.metrics.request_finished(Outcome::NotFound);
    response
}

async fn serve(
    state: &Arc<AppState>,
    hash: &str,
    path: &str,
    started: Instant,
) -> Result<(Response, Outcome), Failure> {
    if !narinfo::is_store_hash(hash) {
        return Err(Failure::BadRequest("not a store path hash".to_owned()));
    }
    let Some(components) = split_path(path) else {
        return Err(Failure::BadRequest("invalid path".to_owned()));
    };

    let info = fetch_narinfo(state, hash).await?;

    // Bound how many archives are decompressed at once. Decompression is the
    // whole server-side cost of this endpoint, so it is the thing to cap.
    let permit = state
        .permits
        .clone()
        .acquire_owned()
        .await
        .map_err(|_| Failure::Upstream("server is shutting down".to_owned()))?;

    let nar_url = format!("{}/{}", state.upstream, info.url);
    let response = state
        .client
        .get(&nar_url)
        .send()
        .await
        .map_err(|e| Failure::Upstream(format!("cannot fetch nar: {e}")))?;
    if !response.status().is_success() {
        return Err(Failure::Upstream(format!(
            "nar fetch returned {}",
            response.status()
        )));
    }

    let metrics = state.metrics.clone();
    let counted = response.bytes_stream().map_ok(move |chunk| {
        metrics.add_upstream_bytes(chunk.len() as u64);
        chunk
    });
    let reader = StreamReader::new(counted.map_err(std::io::Error::other));
    let decoded = decode(info.compression, reader);

    let mut nar = NarReader::new(decoded);
    nar.read_magic()
        .await
        .map_err(|e| Failure::Upstream(format!("cannot read nar: {e}")))?;
    let located = nar
        .locate(&components)
        .await
        .map_err(|e| Failure::Upstream(format!("cannot read nar: {e}")))?;

    match located {
        Located::File { size, executable } => {
            let body = stream_contents(state.clone(), nar, size, info.nar_size, started, permit);
            let mut response = Response::new(body);
            let headers = response.headers_mut();
            headers.insert(header::CONTENT_LENGTH, size.into());
            headers.insert(header::CONTENT_TYPE, content_type(path));
            headers.insert(header::CACHE_CONTROL, HeaderValue::from_static(IMMUTABLE));
            headers.insert(
                header::HeaderName::from_static("x-nar-executable"),
                HeaderValue::from_static(if executable { "true" } else { "false" }),
            );
            Ok((response, Outcome::Ok))
        }
        Located::Symlink { target } => match redirect_target(hash, &components, &target) {
            // Following a symlink would mean a second pass over the archive, and
            // possibly a different one; a redirect lets the client (and the CDN
            // in front) do that as an ordinary cacheable request.
            Some(location) => Ok((
                (
                    StatusCode::SEE_OTHER,
                    [
                        (header::LOCATION, location),
                        (header::CACHE_CONTROL, IMMUTABLE.to_owned()),
                    ],
                )
                    .into_response(),
                Outcome::Redirect,
            )),
            None => Err(Failure::NotFound(format!(
                "symlink to {target:?}, which is outside this store path"
            ))),
        },
        Located::Directory => Err(Failure::NotFound(
            "that path is a directory; use the .ls listing to enumerate it".to_owned(),
        )),
        Located::NotFound => Err(Failure::NotFound(
            "no such file in this store path".to_owned(),
        )),
    }
}

async fn fetch_narinfo(state: &Arc<AppState>, hash: &str) -> Result<narinfo::NarInfo, Failure> {
    let url = format!("{}/{hash}.narinfo", state.upstream);
    let response = state
        .client
        .get(&url)
        .send()
        .await
        .map_err(|e| Failure::Upstream(format!("cannot fetch narinfo: {e}")))?;
    if response.status() == StatusCode::NOT_FOUND {
        return Err(Failure::NotFound("no such store path".to_owned()));
    }
    if !response.status().is_success() {
        return Err(Failure::Upstream(format!(
            "narinfo fetch returned {}",
            response.status()
        )));
    }
    let body = response
        .text()
        .await
        .map_err(|e| Failure::Upstream(format!("cannot read narinfo: {e}")))?;
    narinfo::parse(&body).map_err(|e| Failure::Upstream(e.to_string()))
}

fn decode<R>(compression: Compression, reader: R) -> Box<dyn AsyncRead + Unpin + Send>
where
    R: AsyncRead + Unpin + Send + 'static,
{
    use async_compression::tokio::bufread as codec;
    let reader = tokio::io::BufReader::new(reader);
    match compression {
        Compression::None => Box::new(reader),
        Compression::Zstd => Box::new(codec::ZstdDecoder::new(reader)),
        Compression::Xz => Box::new(codec::XzDecoder::new(reader)),
        Compression::Bzip2 => Box::new(codec::BzDecoder::new(reader)),
        Compression::Brotli => Box::new(codec::BrotliDecoder::new(reader)),
    }
}

/// Pump `size` bytes of file contents into the response body, then drop the
/// upstream connection without reading the rest of the archive.
fn stream_contents<R>(
    state: Arc<AppState>,
    mut nar: NarReader<R>,
    size: u64,
    nar_size: u64,
    started: Instant,
    permit: tokio::sync::OwnedSemaphorePermit,
) -> Body
where
    R: AsyncRead + Unpin + Send + 'static,
{
    let (tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(2);
    tokio::spawn(async move {
        let mut remaining = size;
        let mut buf = vec![0u8; CHUNK];
        while remaining > 0 {
            let take = remaining.min(CHUNK as u64) as usize;
            if let Err(e) = nar.read_exact_counted(&mut buf[..take]).await {
                let _ = tx.send(Err(e)).await;
                return;
            }
            if tx
                .send(Ok(Bytes::copy_from_slice(&buf[..take])))
                .await
                .is_err()
            {
                // The client went away; stop decompressing.
                return;
            }
            remaining -= take as u64;
        }
        state
            .metrics
            .observe_served(nar.position(), size, nar_size, started.elapsed());
        drop(permit);
    });
    Body::from_stream(tokio_stream_wrapper(rx))
}

fn tokio_stream_wrapper(
    rx: mpsc::Receiver<Result<Bytes, std::io::Error>>,
) -> impl futures_util::Stream<Item = Result<Bytes, std::io::Error>> {
    futures_util::stream::unfold(rx, |mut rx| async move {
        rx.recv().await.map(|item| (item, rx))
    })
}

fn content_type(path: &str) -> HeaderValue {
    // `mime_guess` does not know about desktop entries, which are the motivating
    // case for this endpoint.
    if path.ends_with(".desktop") {
        return HeaderValue::from_static("application/x-desktop");
    }
    mime_guess::from_path(path)
        .first_raw()
        .and_then(|value| HeaderValue::from_str(value).ok())
        .unwrap_or(HeaderValue::from_static("application/octet-stream"))
}

/// Resolve a symlink to another `/serve/` URL, or `None` if it leaves the store.
fn redirect_target(hash: &str, components: &[String], target: &str) -> Option<String> {
    match target.strip_prefix("/nix/store/") {
        // An absolute target names another store path, which has its own NAR.
        Some(rest) => {
            let (store_path_name, remainder) = rest.split_once('/')?;
            // Store path names are `<hash>-<name>`.
            let other_hash = store_path_name.get(..32)?;
            if !narinfo::is_store_hash(other_hash) {
                return None;
            }
            let cleaned = split_path(remainder)?;
            Some(format!("/serve/{other_hash}/{}", cleaned.join("/")))
        }
        None => relative_target(hash, components, target),
    }
}

fn relative_target(hash: &str, components: &[String], target: &str) -> Option<String> {
    let mut resolved: Vec<&str> = components[..components.len() - 1]
        .iter()
        .map(String::as_str)
        .collect();
    for component in target.split('/') {
        match component {
            "" | "." => {}
            ".." => {
                resolved.pop()?;
            }
            other => resolved.push(other),
        }
    }
    if resolved.is_empty() {
        return None;
    }
    Some(format!("/serve/{hash}/{}", resolved.join("/")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parts(path: &str) -> Vec<String> {
        split_path(path).unwrap()
    }

    #[test]
    fn relative_symlinks_resolve_against_the_containing_directory() {
        assert_eq!(
            relative_target("h", &parts("share/applications/a.desktop"), "b.desktop").as_deref(),
            Some("/serve/h/share/applications/b.desktop")
        );
        assert_eq!(
            relative_target(
                "h",
                &parts("share/applications/a.desktop"),
                "../icons/x.png"
            )
            .as_deref(),
            Some("/serve/h/share/icons/x.png")
        );
    }

    #[test]
    fn symlinks_escaping_the_store_path_are_not_redirected() {
        assert_eq!(
            relative_target("h", &parts("bin/x"), "../../../etc/passwd"),
            None
        );
    }

    #[test]
    fn desktop_entries_get_their_own_content_type() {
        assert_eq!(
            content_type("share/applications/a.desktop"),
            "application/x-desktop"
        );
        assert_eq!(content_type("share/icons/x.png"), "image/png");
        assert_eq!(content_type("bin/hello"), "application/octet-stream");
    }
}
