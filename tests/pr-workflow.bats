#!/usr/bin/env bats
# Exercises the config/embed-building script embedded in
# .github/workflows/pr.yml — verb, color, draft suppression, the activity
# toggle, and defensive title sanitisation. The step is extracted by name;
# renaming it means updating the setup below.

load helpers

setup() {
  TMP="$(mktemp -d)"
  extract cfg .github/workflows/pr.yml "Read config and build the embed"
  export GITHUB_OUTPUT="$TMP/out"
  : > "$GITHUB_OUTPUT"
}

teardown() { rm -rf "$TMP"; }

out() { grep "^$1=" "$GITHUB_OUTPUT" | head -1 | cut -d= -f2-; }

run_cfg() {
  export CONFIG_PATH="${CONFIG_PATH:-$TMP/discord.yml}"
  # ${VAR-default}: default only when unset, so tests can pass explicit ""
  export ACTION="${ACTION-opened}" MERGED="${MERGED-false}" DRAFT="${DRAFT-false}"
  export NUMBER="${NUMBER-42}" AUTHOR="${AUTHOR-octocat}"
  export PR_TITLE="${PR_TITLE-add a widget}"
  export PR_URL="${PR_URL-https://github.com/zandoh/x/pull/42}"
  export BASE="${BASE-main}" HEAD="${HEAD-feature}"
  bash "$TMP/cfg.sh"
}

@test "opened builds a green embed and posts" {
  run_cfg
  [ "$(out post)" = "true" ]
  [ "$(out color)" = "3066993" ]
  [ "$(out title)" = "🔀 PR #42 opened: add a widget" ]
  [ "$(out desc)" = 'opened by @octocat · `feature` → `main`' ]
  [ "$(out url)" = "https://github.com/zandoh/x/pull/42" ]
}

@test "reopened is blue" {
  ACTION=reopened run_cfg
  [ "$(out color)" = "3447003" ]
  [ "$(out title)" = "🔁 PR #42 reopened: add a widget" ]
}

@test "merged close is purple and reads 'merged'" {
  ACTION=closed MERGED=true run_cfg
  [ "$(out post)" = "true" ]
  [ "$(out color)" = "10181046" ]
  [ "$(out title)" = "🟣 PR #42 merged: add a widget" ]
  [ "$(out desc)" = 'merged by @octocat · `feature` → `main`' ]
}

@test "unmerged close is grey and reads 'closed'" {
  ACTION=closed MERGED=false run_cfg
  [ "$(out color)" = "10070709" ]
  [ "$(out title)" = "🚫 PR #42 closed: add a widget" ]
}

@test "draft opened is suppressed" {
  DRAFT=true run_cfg
  [ "$(out post)" = "false" ]
}

@test "draft reopened is suppressed" {
  ACTION=reopened DRAFT=true run_cfg
  [ "$(out post)" = "false" ]
}

@test "closing a draft still posts — it's a real end of life" {
  ACTION=closed MERGED=false DRAFT=true run_cfg
  [ "$(out post)" = "true" ]
  [ "$(out title)" = "🚫 PR #42 closed: add a widget" ]
}

@test "missing config file yields defaults and still posts" {
  CONFIG_PATH="$TMP/nope.yml" run_cfg
  [ "$(out post)" = "true" ]
  [ "$(out username)" = "" ]
  [ "$(out avatar)" = "" ]
}

@test "username and avatar flow through from config" {
  printf 'username: Hearth\navatar: https://example.invalid/h.png\n' > "$TMP/discord.yml"
  run_cfg
  [ "$(out username)" = "Hearth" ]
  [ "$(out avatar)" = "https://example.invalid/h.png" ]
}

@test "pull-request-activity: false turns the stream off" {
  printf 'notify:\n  pull-request-activity: false\n' > "$TMP/discord.yml"
  run_cfg
  [ "$(out post)" = "false" ]
}

@test "an unrelated action does not post" {
  ACTION=labeled run_cfg
  [ "$(out post)" = "false" ]
}

@test "missing base/head drops the branch suffix" {
  BASE="" HEAD="" run_cfg
  [ "$(out desc)" = "opened by @octocat" ]
}

@test "CR/LF in the title cannot inject extra output keys" {
  # A title carrying a newline + a forged key must not add that key.
  PR_TITLE=$'pwn\npost=false' run_cfg
  [ "$(out post)" = "true" ]
  [ "$(out title)" = "🔀 PR #42 opened: pwnpost=false" ]
}
