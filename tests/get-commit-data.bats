#!/usr/bin/env bats
# Tests for steps/fetch-commits/scripts/get-commit-data.sh (gh is stubbed)

load test_helper

setup() {
  common_setup
  stub_gh
  OUT="$TMP/commits.json"
  echo '{"workflow_id": 7}' > "$GH_RESP/run.json"
  echo '{"commits": [{"sha": "c1", "commit": {"message": "feat: x", "author": {"name": "Alice"}}}]}' > "$GH_RESP/compare.json"
}

@test "uses the last successful run as the base" {
  echo '{"workflow_runs": [{"head_sha": "base1"}]}' > "$GH_RESP/run-history.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" ""
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].author' "$OUT")" = "Alice" ]
  grep -qxF 'BASE_SOURCE=previous_run' "$OUT.meta"
  grep -qxF 'PREVIOUS_SHA=base1' "$OUT.meta"
  grep -qxF 'COMPARE_URL=https://github.com/org/repo/compare/base1...headsha' "$OUT.meta"
  grep -qF 'compare/base1...headsha' "$GH_CALLS"
}

@test "previous run wins over since_ref" {
  echo '{"workflow_runs": [{"head_sha": "base1"}]}' > "$GH_RESP/run-history.json"
  echo '{"sha": "tagsha"}' > "$GH_RESP/ref.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" "v1.0.0"
  grep -qxF 'PREVIOUS_SHA=base1' "$OUT.meta"
}

@test "falls back to since_ref when there is no previous run" {
  echo '{"workflow_runs": []}' > "$GH_RESP/run-history.json"
  echo '{"sha": "tagsha"}' > "$GH_RESP/ref.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" "v1.0.0"
  [ "$status" -eq 0 ]
  grep -qxF 'BASE_SOURCE=since_ref' "$OUT.meta"
  grep -qxF 'PREVIOUS_SHA=tagsha' "$OUT.meta"
  grep -qF 'commits/v1.0.0' "$GH_CALLS"
}

@test "falls back to the last 30 days without previous run or since_ref" {
  echo '{"workflow_runs": []}' > "$GH_RESP/run-history.json"
  echo '[{"sha": "monthold"}]' > "$GH_RESP/commits-until.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" ""
  [ "$status" -eq 0 ]
  grep -qxF 'BASE_SOURCE=last_30_days' "$OUT.meta"
  grep -qxF 'PREVIOUS_SHA=monthold' "$OUT.meta"
  grep -qE 'commits\?sha=headsha&until=[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$GH_CALLS"
}

@test "unresolvable since_ref warns and falls back to the last 30 days" {
  echo '{"workflow_runs": []}' > "$GH_RESP/run-history.json"
  echo '[{"sha": "monthold"}]' > "$GH_RESP/commits-until.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" "does-not-exist"
  [[ "$output" == *"::warning::since_ref 'does-not-exist'"* ]]
  grep -qxF 'BASE_SOURCE=last_30_days' "$OUT.meta"
}

@test "young repository: lists all commits of the window, oldest first" {
  echo '{"workflow_runs": []}' > "$GH_RESP/run-history.json"
  echo '[]' > "$GH_RESP/commits-until.json"
  echo '[
    {"sha": "new", "commit": {"message": "feat: newer", "author": {"name": "B"}}},
    {"sha": "old", "commit": {"message": "feat: older", "author": {"name": "A"}}}
  ]' > "$GH_RESP/commits-since.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" ""
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].sha' "$OUT")" = "old" ]
  [ "$(jq 'length' "$OUT")" -eq 2 ]
  refute_contains "$OUT.meta" 'PREVIOUS_SHA'
}

@test "no commits when the previous run is the current commit" {
  echo '{"workflow_runs": [{"head_sha": "headsha"}]}' > "$GH_RESP/run-history.json"
  run bash "$FETCH_COMMITS/get-commit-data.sh" "$OUT" ""
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT")" = "[]" ]
  [ ! -s "$OUT.meta" ]
}
