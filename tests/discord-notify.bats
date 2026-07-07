#!/usr/bin/env bats
# Exercises the script embedded in action.yml —
# the payload builder and its guard rails.

load helpers

setup() {
  TMP="$(mktemp -d)"
  extract send action.yml
  shim_curl

  # Baseline env as the runner would provide it.
  export WEBHOOK_URL="https://example.invalid/hook"
  export STATUS="" TITLE="a title" DESCRIPTION="" URL="" COLOR="" BOT_USERNAME="" FOOTER=""
  export RUN_URL="https://github.com/zandoh/x/actions/runs/1"
  export REPO="zandoh/x" REF_NAME="main" SHA="0123456789abcdef" WORKFLOW="CI"
  export COMMIT_MSG=$'feat: subject line\nbody that must not appear'
}

teardown() { rm -rf "$TMP"; }

@test "unset webhook skips silently with exit 0" {
  export WEBHOOK_URL=""
  run bash "$TMP/send.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping Discord notification"* ]]
}

@test "failure status prefixes ❌ and defaults to red" {
  export STATUS=failure TITLE="CI failed"
  run bash "$TMP/send.sh"
  [ "$status" -eq 0 ]
  jq -e '.embeds[0] | (.title == "❌ CI failed") and (.color == 15548997)' <<<"$output"
}

@test "success status prefixes ✅ and defaults to green" {
  export STATUS=success
  run bash "$TMP/send.sh"
  jq -e '.embeds[0] | (.title == "✅ a title") and (.color == 5763719)' <<<"$output"
}

@test "no status means no emoji and neutral blue" {
  run bash "$TMP/send.sh"
  jq -e '.embeds[0] | (.title == "a title") and (.color == 3447003)' <<<"$output"
}

@test "explicit color beats the status default" {
  export STATUS=success COLOR=15269692
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].color == 15269692' <<<"$output"
}

@test "non-numeric color falls back to the status default" {
  export STATUS=failure COLOR="volt"
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].color == 15548997' <<<"$output"
}

@test "username is included when set and omitted when empty" {
  export BOT_USERNAME="Hearth CI"
  run bash "$TMP/send.sh"
  jq -e '.username == "Hearth CI"' <<<"$output"

  export BOT_USERNAME=""
  run bash "$TMP/send.sh"
  jq -e 'has("username") | not' <<<"$output"
}

@test "default description is repo · branch · short sha + commit subject" {
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].description == "zandoh/x · `main` · `0123456`\nfeat: subject line"' <<<"$output"
}

@test "explicit description passes through untouched" {
  export DESCRIPTION=$'line one\nline two'
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].description == "line one\nline two"' <<<"$output"
}

@test "description over 4096 chars is truncated with ellipsis" {
  DESCRIPTION="$(printf 'x%.0s' $(seq 1 5000))"
  export DESCRIPTION
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].description | (length == 4096) and endswith("...")' <<<"$output"
}

@test "title over 256 chars is truncated" {
  TITLE="$(printf 't%.0s' $(seq 1 300))"
  export TITLE
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].title | length == 256' <<<"$output"
}

@test "footer defaults to the workflow name and honors an override" {
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].footer.text == "CI"' <<<"$output"

  export FOOTER="by someone"
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].footer.text == "by someone"' <<<"$output"
}

@test "url defaults to the run URL and honors an override" {
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].url == "https://github.com/zandoh/x/actions/runs/1"' <<<"$output"

  export URL="https://example.com/release"
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].url == "https://example.com/release"' <<<"$output"
}

@test "embeds always carry a timestamp" {
  run bash "$TMP/send.sh"
  jq -e '.embeds[0].timestamp | length > 0' <<<"$output"
}

@test "a Discord outage warns instead of failing the run" {
  shim_curl_failing
  run bash "$TMP/send.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Discord notification failed"* ]]
}

@test "hostile commit message cannot break the JSON" {
  export COMMIT_MSG=$'fix: "quotes" `ticks` \\slashes $(rm -rf /) \n second line'
  run bash "$TMP/send.sh"
  [ "$status" -eq 0 ]
  jq -e '.embeds[0].description | contains("$(rm -rf /)")' <<<"$output"
}
