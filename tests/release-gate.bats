#!/usr/bin/env bats
# Exercises the CI-gate and tag-move scripts. The gate now lives in one
# reusable workflow (verify-ci.yml) that release.yml and pages.yml both call;
# the tag-move stays in release.yml. Steps are extracted by name; renaming a
# step means updating this.
#
# Not covered on purpose: the pending/missing retry loop and the 20-minute
# timeout branch depend on wall-clock SECONDS and a real `sleep 30`, so they
# are out of unit scope. Every test here feeds the gate a fully-concluded set
# of checks so it exits before the sleep.

load helpers

setup() {
  TMP="$(mktemp -d)"
  extract gate    .github/workflows/verify-ci.yml "Wait for green CI on this commit"
  extract movetag .github/workflows/release.yml   "Point the major tag at this release"
  export GH_TOKEN=t GITHUB_REPOSITORY="zandoh/tonk" GITHUB_SHA="deadbeefcafe"
}

teardown() { rm -rf "$TMP"; }

green_checks() {
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"test","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"smoke","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"}]
JSON
}

@test "gate passes when all required checks are green" {
  shim_gh_checks; green_checks
  run bash "$TMP/gate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required checks are green"* ]]
}

@test "release gate fails fast when a required check failed" {
  shim_gh_checks
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"test","status":"completed","conclusion":"failure","started_at":"2026-07-07T10:00:00Z"},
 {"name":"smoke","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"}]
JSON
  run bash "$TMP/gate.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
  [[ "$output" == *"test"* ]]
}

@test "release gate treats a non-success conclusion as not green" {
  shim_gh_checks
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"test","status":"completed","conclusion":"cancelled","started_at":"2026-07-07T10:00:00Z"},
 {"name":"smoke","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"}]
JSON
  run bash "$TMP/gate.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
}

@test "release gate honors the newest run when a check was re-run" {
  shim_gh_checks
  # Newest entry (failure@10:30) is FIRST, not last in array order, so the old
  # `| last` code would pick the stale success and this test would not fail.
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"failure","started_at":"2026-07-07T10:30:00Z"},
 {"name":"lint","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"test","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"smoke","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"}]
JSON
  run bash "$TMP/gate.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
  [[ "$output" == *"lint"* ]]
}

@test "release gate honors a newer success over an older failure" {
  shim_gh_checks
  # Newest entry (success@10:30) is FIRST, not last, so the direction of the
  # sort is what makes this pass — old `| last` would pick the stale failure.
  cat > "$TMP/checks.json" <<'JSON'
[{"name":"lint","status":"completed","conclusion":"success","started_at":"2026-07-07T10:30:00Z"},
 {"name":"lint","status":"completed","conclusion":"failure","started_at":"2026-07-07T10:00:00Z"},
 {"name":"test","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"},
 {"name":"smoke","status":"completed","conclusion":"success","started_at":"2026-07-07T10:00:00Z"}]
JSON
  run bash "$TMP/gate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required checks are green"* ]]
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
