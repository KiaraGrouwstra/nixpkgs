//! Prometheus-format counters, hand-rolled to keep the dependency set small.
//!
//! The point of this endpoint's proof of concept is the server-side cost, so the
//! interesting series are `decompressed_bytes` (the CPU proxy) against
//! `response_bytes` (what the client wanted) and `nar_bytes` (what fetching the
//! whole archive would have cost the client).

use std::fmt::Write as _;
use std::sync::atomic::{AtomicU64, Ordering};

const DURATION_BUCKETS: [f64; 9] = [0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, f64::INFINITY];

#[derive(Debug, Clone, Copy)]
pub enum Outcome {
    Ok,
    Redirect,
    NotFound,
    BadRequest,
    Error,
}

impl Outcome {
    fn label(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::Redirect => "redirect",
            Self::NotFound => "not_found",
            Self::BadRequest => "bad_request",
            Self::Error => "error",
        }
    }
}

#[derive(Default)]
pub struct Metrics {
    requests: [AtomicU64; 5],
    in_flight: AtomicU64,
    upstream_bytes: AtomicU64,
    decompressed_bytes: AtomicU64,
    response_bytes: AtomicU64,
    nar_bytes: AtomicU64,
    duration_sum_micros: AtomicU64,
    duration_count: AtomicU64,
    duration_buckets: [AtomicU64; DURATION_BUCKETS.len()],
}

impl Metrics {
    pub fn request_started(&self) {
        self.in_flight.fetch_add(1, Ordering::Relaxed);
    }

    pub fn request_finished(&self, outcome: Outcome) {
        self.in_flight.fetch_sub(1, Ordering::Relaxed);
        self.requests[outcome as usize].fetch_add(1, Ordering::Relaxed);
    }

    pub fn add_upstream_bytes(&self, n: u64) {
        self.upstream_bytes.fetch_add(n, Ordering::Relaxed);
    }

    /// Record what one served request cost. `nar_size` is the whole-archive size
    /// the client would otherwise have downloaded.
    pub fn observe_served(
        &self,
        decompressed: u64,
        response: u64,
        nar_size: u64,
        elapsed: std::time::Duration,
    ) {
        self.decompressed_bytes
            .fetch_add(decompressed, Ordering::Relaxed);
        self.response_bytes.fetch_add(response, Ordering::Relaxed);
        self.nar_bytes.fetch_add(nar_size, Ordering::Relaxed);
        self.duration_sum_micros
            .fetch_add(elapsed.as_micros() as u64, Ordering::Relaxed);
        self.duration_count.fetch_add(1, Ordering::Relaxed);
        let seconds = elapsed.as_secs_f64();
        for (bucket, counter) in DURATION_BUCKETS.iter().zip(&self.duration_buckets) {
            if seconds <= *bucket {
                counter.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    pub fn render(&self) -> String {
        let mut out = String::new();
        let get = |v: &AtomicU64| v.load(Ordering::Relaxed);

        out.push_str("# HELP nix_cache_serve_requests_total Requests by outcome.\n");
        out.push_str("# TYPE nix_cache_serve_requests_total counter\n");
        for (index, counter) in self.requests.iter().enumerate() {
            let label = [
                Outcome::Ok,
                Outcome::Redirect,
                Outcome::NotFound,
                Outcome::BadRequest,
                Outcome::Error,
            ][index]
                .label();
            let _ = writeln!(
                out,
                "nix_cache_serve_requests_total{{outcome=\"{label}\"}} {}",
                get(counter)
            );
        }

        for (name, help, kind, value) in [
            (
                "nix_cache_serve_in_flight",
                "Requests currently being served.",
                "gauge",
                get(&self.in_flight),
            ),
            (
                "nix_cache_serve_upstream_bytes_total",
                "Compressed bytes read from the upstream cache.",
                "counter",
                get(&self.upstream_bytes),
            ),
            (
                "nix_cache_serve_decompressed_bytes_total",
                "Uncompressed NAR bytes the server had to decode.",
                "counter",
                get(&self.decompressed_bytes),
            ),
            (
                "nix_cache_serve_response_bytes_total",
                "File bytes returned to clients.",
                "counter",
                get(&self.response_bytes),
            ),
            (
                "nix_cache_serve_nar_bytes_total",
                "Uncompressed size of the NARs behind served requests.",
                "counter",
                get(&self.nar_bytes),
            ),
        ] {
            let _ = writeln!(
                out,
                "# HELP {name} {help}\n# TYPE {name} {kind}\n{name} {value}"
            );
        }

        out.push_str("# HELP nix_cache_serve_duration_seconds Time to serve a file.\n");
        out.push_str("# TYPE nix_cache_serve_duration_seconds histogram\n");
        for (bucket, counter) in DURATION_BUCKETS.iter().zip(&self.duration_buckets) {
            let le = if bucket.is_infinite() {
                "+Inf".to_owned()
            } else {
                bucket.to_string()
            };
            let _ = writeln!(
                out,
                "nix_cache_serve_duration_seconds_bucket{{le=\"{le}\"}} {}",
                get(counter)
            );
        }
        let _ = writeln!(
            out,
            "nix_cache_serve_duration_seconds_sum {:.6}",
            get(&self.duration_sum_micros) as f64 / 1e6
        );
        let _ = writeln!(
            out,
            "nix_cache_serve_duration_seconds_count {}",
            get(&self.duration_count)
        );

        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn served_requests_land_in_every_cumulative_bucket_above_them() {
        let metrics = Metrics::default();
        metrics.observe_served(1000, 10, 5000, std::time::Duration::from_millis(200));
        let text = metrics.render();
        assert!(text.contains("nix_cache_serve_decompressed_bytes_total 1000"));
        assert!(text.contains("nix_cache_serve_response_bytes_total 10"));
        assert!(text.contains("nix_cache_serve_nar_bytes_total 5000"));
        // 0.2s falls into the 0.25 bucket and every wider one, but not 0.1.
        assert!(text.contains("nix_cache_serve_duration_seconds_bucket{le=\"0.1\"} 0"));
        assert!(text.contains("nix_cache_serve_duration_seconds_bucket{le=\"0.25\"} 1"));
        assert!(text.contains("nix_cache_serve_duration_seconds_bucket{le=\"+Inf\"} 1"));
    }

    #[test]
    fn outcomes_are_counted_under_their_own_label() {
        let metrics = Metrics::default();
        metrics.request_started();
        metrics.request_finished(Outcome::NotFound);
        let text = metrics.render();
        assert!(text.contains("nix_cache_serve_requests_total{outcome=\"not_found\"} 1"));
        assert!(text.contains("nix_cache_serve_requests_total{outcome=\"ok\"} 0"));
        assert!(text.contains("nix_cache_serve_in_flight 0"));
    }
}
