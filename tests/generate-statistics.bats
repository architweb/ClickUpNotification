#!/usr/bin/env bats
# Tests for steps/fetch-commits/scripts/generate-statistics.sh

load test_helper

setup() {
  common_setup
  OUT="$TMP/stats.md"

  # Small repository: base commit, then two commits two hours later
  REPO_DIR="$TMP/repo"
  git init -q "$REPO_DIR"
  cd "$REPO_DIR"
  git config user.email t@example.com
  git config user.name Tester
  echo one > a.txt
  git add a.txt
  GIT_COMMITTER_DATE="2026-01-01T10:00:00Z" git commit -qm "chore: base"
  BASE=$(git rev-parse HEAD)
  printf 'one\ntwo\n' > a.txt
  echo new > b.txt
  git add a.txt b.txt
  GIT_COMMITTER_DATE="2026-01-01T12:00:00Z" git commit -qm "feat: add b"
  HEAD_SHA=$(git rev-parse HEAD)

  commits_json "$TMP/commits.json" '[
    {sha:"1", author:"alice", message:"feat: add b"},
    {sha:"2", author:"bob", message:"fix(core)!: breaking fix"},
    {sha:"3", author:"carol", message:"refactor: tidy"},
    {sha:"4", author:"alice", message:"docs: notes"}
  ]'
}

write_meta() {
  {
    echo "PREVIOUS_SHA=$BASE"
    echo "CURRENT_SHA=$HEAD_SHA"
    echo "BASE_SOURCE=$1"
  } > "$TMP/meta"
}

@test "builds the statistics block from git history" {
  write_meta previous_run
  run bash "$FETCH_COMMITS/generate-statistics.sh" "$TMP/commits.json" "$TMP/meta" "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"integer expression"* ]]
  grep -qF '📝 **Count**: 4 Commit(s)' "$OUT"
  grep -qF '🎯 **Release Type**: 🚨 Major' "$OUT"
  grep -qF '📁 **Changed**: 2 file(s)' "$OUT"
  grep -qF '➕ **Added**: +1 file(s), +2 line(s)' "$OUT"
  grep -qF '🔧 **Fixes**: 1 commit(s)' "$OUT"
  grep -qF '🔄 **Refactor**: 1 commit(s)' "$OUT"
  grep -qF '⏰ **Last Deploy**: 0 day(s), 2 hour(s), 0 minute(s)' "$OUT"
  grep -qF '👥 **Contributor(s)**: 3' "$OUT"
  grep -qF '🏆 **Top Contributor**: Alice' "$OUT"
}

@test "hides Last Deploy when the base is not a previous run" {
  write_meta last_30_days
  run bash "$FETCH_COMMITS/generate-statistics.sh" "$TMP/commits.json" "$TMP/meta" "$OUT"
  refute_contains "$OUT" 'Last Deploy'
  grep -qF '📝 **Count**: 4 Commit(s)' "$OUT"
}

@test "hides zero-value lines without errors" {
  write_meta previous_run
  commits_json "$TMP/one.json" '[{sha:"1", author:"alice", message:"chore: x"}]'
  run bash "$FETCH_COMMITS/generate-statistics.sh" "$TMP/one.json" "$TMP/meta" "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"integer expression"* ]]
  refute_contains "$OUT" 'Release Type'
  refute_contains "$OUT" 'Fixes'
  refute_contains "$OUT" 'Contributor'
}

@test "empty output without metadata" {
  run bash "$FETCH_COMMITS/generate-statistics.sh" "$TMP/commits.json" "$TMP/missing" "$OUT"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
}
