#!/usr/bin/env bats
# Exercises the CI-gate and tag-move scripts embedded in release.yml and
# pages.yml. Steps are extracted by name; renaming a step means updating this.
#
# Not covered on purpose: the pending/missing retry loop and the 20-minute
# timeout branch depend on wall-clock SECONDS and a real `sleep 30`, so they
# are out of unit scope. Every test here feeds the gate a fully-concluded set
# of checks so it exits before the sleep.

load helpers

setup() {
  TMP="$(mktemp -d)"
  extract rel_gate  .github/workflows/release.yml "Wait for green CI on the tagged commit"
  extract pages_gate .github/workflows/pages.yml  "Wait for green CI on this commit"
  extract movetag   .github/workflows/release.yml "Point the major tag at this release"
  export GH_TOKEN=t GITHUB_REPOSITORY="zandoh/tonk" GITHUB_SHA="deadbeefcafe"
}

teardown() { rm -rf "$TMP"; }

green_checks() {
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success"},
 {"name":"test","status":"completed","conclusion":"success"},
 {"name":"smoke","status":"completed","conclusion":"success"}]
JSON
}

@test "release gate passes when all required checks are green" {
  shim_gh_checks; green_checks
  run bash "$TMP/rel_gate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required checks are green"* ]]
}

@test "pages gate passes when all required checks are green" {
  shim_gh_checks; green_checks
  run bash "$TMP/pages_gate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required checks are green"* ]]
}

@test "release gate fails fast when a required check failed" {
  shim_gh_checks
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success"},
 {"name":"test","status":"completed","conclusion":"failure"},
 {"name":"smoke","status":"completed","conclusion":"success"}]
JSON
  run bash "$TMP/rel_gate.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
  [[ "$output" == *"test"* ]]
}

@test "release gate treats a non-success conclusion as not green" {
  shim_gh_checks
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success"},
 {"name":"test","status":"completed","conclusion":"cancelled"},
 {"name":"smoke","status":"completed","conclusion":"success"}]
JSON
  run bash "$TMP/rel_gate.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
}

@test "existing major tag is force-updated via PATCH" {
  shim_gh_tag
  : > "$TMP/tag-exists"
  export GITHUB_REF_NAME="v2.1.0"
  run bash "$TMP/movetag.sh"
  [ "$status" -eq 0 ]
  grep -q -- "-X PATCH" "$TMP/gh.log"
  grep -q "refs/tags/v2" "$TMP/gh.log"
  grep -q "force=true" "$TMP/gh.log"
  ! grep -q -- "-X POST" "$TMP/gh.log"
}

@test "absent major tag is created via POST" {
  shim_gh_tag   # no $TMP/tag-exists -> GET exits 1
  export GITHUB_REF_NAME="v2.1.0"
  run bash "$TMP/movetag.sh"
  [ "$status" -eq 0 ]
  grep -q -- "-X POST" "$TMP/gh.log"
  grep -q "refs/tags/v2" "$TMP/gh.log"
  ! grep -q -- "-X PATCH" "$TMP/gh.log"
}
