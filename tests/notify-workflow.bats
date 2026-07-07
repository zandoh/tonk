#!/usr/bin/env bats
# Exercises the scripts embedded in .github/workflows/notify.yml — config
# parsing (including the yq explicit-false trap) and recovery detection.
# Steps are extracted by name; renaming a step means updating these.

load helpers

setup() {
  TMP="$(mktemp -d)"
  extract cfg .github/workflows/notify.yml "Read config and build messages"
  extract prev .github/workflows/notify.yml "Check whether this green run ended a failure streak"
  export GITHUB_OUTPUT="$TMP/out"
  : > "$GITHUB_OUTPUT"
}

teardown() { rm -rf "$TMP"; }

out() { grep "^$1=" "$GITHUB_OUTPUT" | head -1 | cut -d= -f2-; }

run_cfg() {
  export CONFIG_PATH="${CONFIG_PATH:-$TMP/discord.yml}"
  # ${VAR-default}: default only when unset, so tests can pass explicit ""
  export EVENT="${EVENT-push}" WF_NAME="${WF_NAME-CI}" BRANCH="${BRANCH-main}"
  export COMMIT_MSG=$'feat: subject\nbody' SHA="0123456789abcdef"
  bash "$TMP/cfg.sh"
}

@test "missing config file yields defaults" {
  CONFIG_PATH="$TMP/nope.yml" run_cfg
  [ "$(out username)" = "" ]
  [ "$(out avatar)" = "" ]
  [ "$(out failure)" = "true" ]
  [ "$(out recovery)" = "true" ]
}

@test "username, avatar, and titles are built from config and event" {
  printf 'username: Hearth CI\navatar: https://example.invalid/hearth.png\n' > "$TMP/discord.yml"
  run_cfg
  [ "$(out username)" = "Hearth CI" ]
  [ "$(out avatar)" = "https://example.invalid/hearth.png" ]
  [ "$(out fail_title)" = "CI failed on main" ]
  [ "$(out ok_title)" = "CI back to green on main" ]
  [ "$(out desc)" = 'feat: subject (`0123456`)' ]
}

@test "explicit false toggles are honored despite yq's // operator" {
  printf 'notify:\n  failure: false\n  recovery: false\n' > "$TMP/discord.yml"
  run_cfg
  [ "$(out failure)" = "false" ]
  [ "$(out recovery)" = "false" ]
}

@test "pull_request runs are suppressed by default" {
  printf 'username: x\n' > "$TMP/discord.yml"
  EVENT=pull_request run_cfg
  [ "$(out failure)" = "false" ]
  [ "$(out recovery)" = "false" ]
}

@test "pull-requests: true opts PR runs in" {
  printf 'notify:\n  pull-requests: true\n' > "$TMP/discord.yml"
  EVENT=pull_request run_cfg
  [ "$(out failure)" = "true" ]
  [ "$(out recovery)" = "true" ]
}

@test "empty branch (tag run) drops the location suffix" {
  BRANCH="" run_cfg
  [ "$(out fail_title)" = "CI failed" ]
}

run_prev() {
  export GH_TOKEN=t REPO=zandoh/x WF_ID=1 RUN_NUMBER=10 BRANCH="${BRANCH-main}"
  bash "$TMP/prev.sh"
}

@test "previous failure means recovery" {
  shim_gh
  printf '{"workflow_runs":[{"run_number":9,"conclusion":"failure"}]}' > "$TMP/runs.json"
  run_prev
  [ "$(out recovered)" = "true" ]
}

@test "previous success is not a recovery" {
  shim_gh
  printf '{"workflow_runs":[{"run_number":9,"conclusion":"success"}]}' > "$TMP/runs.json"
  run_prev
  [ "$(out recovered)" = "false" ]
}

@test "only runs older than the current one count" {
  shim_gh
  # run 11 (newer, failed) must be ignored; run 8 (older, success) decides
  printf '{"workflow_runs":[{"run_number":11,"conclusion":"failure"},{"run_number":8,"conclusion":"success"}]}' > "$TMP/runs.json"
  run_prev
  [ "$(out recovered)" = "false" ]
}

@test "first run ever is not a recovery" {
  shim_gh
  printf '{"workflow_runs":[]}' > "$TMP/runs.json"
  run_prev
  [ "$(out recovered)" = "false" ]
}

@test "missing branch skips the API entirely" {
  # no gh shim on purpose: reaching for the network would fail the test
  BRANCH="" run_prev
  [ "$(out recovered)" = "false" ]
}
