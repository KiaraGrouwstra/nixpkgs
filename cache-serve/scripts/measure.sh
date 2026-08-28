#!/usr/bin/env bash
#
# Measure what one `/serve/` request costs the server.
#
# The open question in the proposal is not client bytes-on-wire -- that is
# arithmetic on the narinfo -- but what moving decompression to the serving side
# costs. This drives a running instance and reports, per request, how much of the
# archive had to be fetched and decoded to answer it.
#
# Usage: measure.sh <paths-file> [base-url]
#
# `paths-file` holds one `<storehash> <path-within-store-path>` pair per line.
# Output is TSV on stdout and a summary on stderr.

set -uo pipefail

paths_file=${1:?usage: measure.sh <paths-file> [base-url]}
base=${2:-http://127.0.0.1:18088}

metric() {
  # $1: metric name, $2: scraped body
  awk -v name="$1" '$1 == name { print $2; exit }' <<<"$2"
}

printf 'hash\tpath\tstatus\tresponse_bytes\tupstream_bytes\tdecompressed_bytes\tnar_bytes\tseconds\n'

total_response=0
total_upstream=0
total_decompressed=0
total_nar=0
total_file=0
count=0

while read -r hash path; do
  [ -n "${hash:-}" ] || continue
  case $hash in \#*) continue ;; esac

  before=$(curl -sf "$base/metrics" | grep -Ev '^#')
  narinfo=$(curl -sf "https://cache.nixos.org/$hash.narinfo")
  file_size=$(awk -F': ' '/^FileSize/ { print $2 }' <<<"$narinfo")

  read -r status seconds < <(
    curl -s -o /dev/null -w '%{http_code} %{time_total}' "$base/serve/$hash/$path"
    echo
  )
  after=$(curl -sf "$base/metrics" | grep -Ev '^#')

  response=$(($(metric nix_cache_serve_response_bytes_total "$after") - $(metric nix_cache_serve_response_bytes_total "$before")))
  upstream=$(($(metric nix_cache_serve_upstream_bytes_total "$after") - $(metric nix_cache_serve_upstream_bytes_total "$before")))
  decompressed=$(($(metric nix_cache_serve_decompressed_bytes_total "$after") - $(metric nix_cache_serve_decompressed_bytes_total "$before")))
  nar=$(($(metric nix_cache_serve_nar_bytes_total "$after") - $(metric nix_cache_serve_nar_bytes_total "$before")))

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$hash" "$path" "$status" "$response" "$upstream" "$decompressed" "$nar" "$seconds"

  if [ "$status" = 200 ]; then
    total_response=$((total_response + response))
    total_upstream=$((total_upstream + upstream))
    total_decompressed=$((total_decompressed + decompressed))
    total_nar=$((total_nar + nar))
    total_file=$((total_file + ${file_size:-0}))
    count=$((count + 1))
  fi
done <"$paths_file"

{
  echo
  echo "served:                  $count"
  echo "bytes delivered:         $total_response"
  echo "compressed bytes read:   $total_upstream of $total_file whole-nar ($((total_file ? 100 * total_upstream / total_file : 0))%)"
  echo "bytes decompressed:      $total_decompressed of $total_nar whole-nar ($((total_nar ? 100 * total_decompressed / total_nar : 0))%)"
  echo "client-side saving:      $((total_response ? total_file / total_response : 0))x fewer bytes than fetching the nars"
} >&2
