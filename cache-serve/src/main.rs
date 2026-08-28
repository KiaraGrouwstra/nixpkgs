//! A read-only per-file endpoint in front of a Nix binary cache.
//!
//! `GET /serve/<storehash>/<path-within-store-path>` returns one file's bytes.
//! Nothing is signed, no store semantics are involved and there is no write
//! path: this is the same trust level as the `.ls` listing it complements.
//!
//! It is a plain HTTP origin. Deployed in front of `cache.nixos.org` it is a
//! consumer of the existing public interface rather than a replacement for any
//! of it -- `/nar/`, `.narinfo` and `.ls` are untouched.

mod metrics;
mod nar;
mod narinfo;
mod serve;

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use axum::routing::get;
use axum::Router;
use clap::Parser;
use tokio::sync::Semaphore;

#[derive(Parser, Debug)]
#[command(about, version)]
struct Args {
    /// Address to listen on.
    #[arg(long, env = "NIX_CACHE_SERVE_LISTEN", default_value = "127.0.0.1:8088")]
    listen: SocketAddr,

    /// Binary cache to read from. Must serve `.narinfo` and `nar/` over HTTP.
    #[arg(
        long,
        env = "NIX_CACHE_SERVE_UPSTREAM",
        default_value = "https://cache.nixos.org"
    )]
    upstream: String,

    /// Maximum NARs decompressed concurrently. Decompression is the entire
    /// server-side cost of this endpoint, so this is the knob that bounds it.
    #[arg(long, env = "NIX_CACHE_SERVE_MAX_CONCURRENCY", default_value_t = default_concurrency())]
    max_concurrency: usize,
}

fn default_concurrency() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
}

pub struct AppState {
    pub client: reqwest::Client,
    pub upstream: String,
    pub permits: Arc<Semaphore>,
    pub metrics: Arc<metrics::Metrics>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nix_cache_serve=info,tower_http=warn".into()),
        )
        .init();

    let args = Args::parse();
    let upstream = args.upstream.trim_end_matches('/').to_owned();

    let state = Arc::new(AppState {
        client: reqwest::Client::builder()
            .user_agent(concat!("nix-cache-serve/", env!("CARGO_PKG_VERSION")))
            .build()
            .context("cannot build the http client")?,
        upstream,
        permits: Arc::new(Semaphore::new(args.max_concurrency)),
        metrics: Arc::new(metrics::Metrics::default()),
    });

    let app = Router::new()
        .route("/serve/{hash}/{*path}", get(serve::get_file))
        .route("/serve/{hash}", get(serve::get_root))
        .route("/serve/{hash}/", get(serve::get_root))
        .route("/metrics", get(render_metrics))
        .route("/health", get(|| async { "ok\n" }))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(args.listen)
        .await
        .with_context(|| format!("cannot bind {}", args.listen))?;
    tracing::info!(listen = %args.listen, "serving");

    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .context("server failed")
}

async fn render_metrics(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> impl axum::response::IntoResponse {
    (
        [(
            axum::http::header::CONTENT_TYPE,
            "text/plain; version=0.0.4",
        )],
        state.metrics.render(),
    )
}
