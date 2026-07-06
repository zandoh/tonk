# Shared bats setup: extracts the embedded scripts and shims the network.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Extract an embedded run: script to $TMP/<out>.sh
extract() { # extract <out> <file> [step name]
  local out="$1"; shift
  "$REPO_ROOT/scripts/extract-step.sh" "$@" > "$TMP/$out.sh"
}

# A curl that never talks to the network: prints whatever payload was passed
# via -d, so tests can assert on the exact JSON the action builds.
shim_curl() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<'SHIM'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = "-d" ]; then printf '%s' "$2"; shift 2; else shift; fi
done
SHIM
  chmod +x "$TMP/bin/curl"
  PATH="$TMP/bin:$PATH"
}

# A curl that fails like a Discord outage would.
shim_curl_failing() {
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\nexit 22\n' > "$TMP/bin/curl"
  chmod +x "$TMP/bin/curl"
  PATH="$TMP/bin:$PATH"
}

# A gh that serves a canned run-history response from $TMP/runs.json.
shim_gh() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<SHIM
#!/usr/bin/env bash
cat "$TMP/runs.json"
SHIM
  chmod +x "$TMP/bin/gh"
  PATH="$TMP/bin:$PATH"
}
