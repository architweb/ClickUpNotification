#!/usr/bin/env bats
# Tests for steps/fetch-commits/scripts/process-commits.sh

load test_helper

setup() {
  common_setup
  OUT="$TMP/out.md"
}

# run_process <commits file> [full] [filter] [group] [pr_links] [max] [compare_url]
run_process() {
  run bash "$FETCH_COMMITS/process-commits.sh" "$1" "${2:-true}" "$OUT" "${3:-true}" "${4:-false}" "${5:-false}" "${6:-}" "${7:-}"
}

@test "groups commits by author with title-cased, sanitized names" {
  run_process "$FIXTURES/commits.json"
  [ "$status" -eq 0 ]
  grep -qF '_*Jane Doe:*_' "$OUT"
  grep -qF '_*John Smith:*_' "$OUT"
  grep -qF '_*Bob:*_' "$OUT"
}

@test "converts task and ctask references into ClickUp links" {
  run_process "$FIXTURES/commits.json"
  grep -qF '[86ddd0y92](https://app.clickup.com/t/86ddd0y92)' "$OUT"
  grep -qF '[TST-747](https://app.clickup.com/t/999/TST-747)' "$OUT"
}

@test "normalizes conventional commit types and keeps scope and breaking marker" {
  run_process "$FIXTURES/commits.json"
  grep -qF '* **Feat(auth):** add login' "$OUT"
  grep -qF '* **Fix:** crash on save' "$OUT"
  grep -qF '* **Refactor!:** drop old api' "$OUT"
}

@test "skips merge commits and duplicate messages" {
  run_process "$FIXTURES/commits.json"
  refute_contains_i "$OUT" 'merge pull request'
  [ "$(grep -c 'add login' "$OUT")" -eq 1 ]
}

@test "filters agent commits and Co-authored-by trailers when enabled" {
  run_process "$FIXTURES/commits.json" true true
  refute_contains "$OUT" 'Initial plan'
  refute_contains_i "$OUT" 'Co-authored-by'
}

@test "keeps agent commits when filtering is disabled" {
  run_process "$FIXTURES/commits.json" true false
  grep -qF 'Initial plan' "$OUT"
  grep -qi 'Co-authored-by' "$OUT"
}

@test "attributes Copilot agent commits to their own co-author" {
  commits_json "$TMP/c.json" '[
    {sha:"1", author:"bob", message:"chore: a\n\nCo-authored-by: Carol Pair <carol@example.com>"},
    {sha:"2", author:"copilot-swe-agent[bot]", message:"docs: b\n\nCo-authored-by: Alice Writer <1+alice@users.noreply.github.com>"}
  ]'
  run_process "$TMP/c.json"
  grep -qF '_*Alice Writer (Copilot Agent):*_' "$OUT"
  refute_contains "$OUT" 'Carol Pair (Copilot Agent)'
}

@test "Copilot agent commits without a co-author fall back to another Copilot commit's co-author" {
  commits_json "$TMP/c.json" '[
    {sha:"1", author:"Copilot SWE Agent Bot", message:"feat: first"},
    {sha:"2", author:"Copilot SWE Agent Bot", message:"feat: second\n\nCo-authored-by: Dana Dev <dana@example.com>"}
  ]'
  run_process "$TMP/c.json"
  [ "$(grep -c '_\*Dana Dev (Copilot Agent):\*_' "$OUT")" -eq 1 ]
  grep -qF 'first' "$OUT"
  grep -qF 'second' "$OUT"
}

@test "co-author names with apostrophes do not break processing" {
  commits_json "$TMP/c.json" '[{sha:"1", author:"copilot-swe-agent[bot]", message:"fix: x\n\nCo-authored-by: Sean O'"'"'Brien <s@example.com>"}]'
  run_process "$TMP/c.json"
  [ "$status" -eq 0 ]
  grep -qF "O'brien (Copilot Agent)" "$OUT"
}

@test "groups by conventional type and strips the prefix" {
  run_process "$FIXTURES/commits.json" true true true
  grep -qF '_*🎯 Features:*_' "$OUT"
  grep -qF '_*🔧 Fixes:*_' "$OUT"
  grep -qF '_*📋 Other:*_' "$OUT"
  grep -qF '* add login' "$OUT"
  refute_contains "$OUT" '**Feat(auth):**'
}

@test "links PR references only when enabled" {
  run_process "$FIXTURES/commits.json" true true false true
  grep -qF '[#12](https://github.com/org/repo/pull/12)' "$OUT"

  run_process "$FIXTURES/commits.json" true true false false
  refute_contains "$OUT" '/pull/12'
}

@test "single-line mode keeps only the first line" {
  run_process "$FIXTURES/commits.json" false
  refute_contains "$OUT" 'first point'
  grep -qF '* **Feat(auth):** add login' "$OUT"
}

@test "preserves backslashes in commit messages" {
  commits_json "$TMP/c.json" '[{sha:"1", author:"bob", message:"fix: handle C:\\temp\\new path"}]'
  run_process "$TMP/c.json"
  grep -qF 'C:\temp\new path' "$OUT"
}

@test "max_commits keeps the most recent commits and summarizes the rest" {
  commits_json "$TMP/c.json" '[range(1;6) | {sha: "s\(.)", author: "bob", message: "feat: change \(.)"}]'
  run_process "$TMP/c.json" true true false false 2 "https://github.com/org/repo/compare/a...b"
  refute_contains "$OUT" 'change 3'
  grep -qF 'change 4' "$OUT"
  grep -qF 'change 5' "$OUT"
  grep -qF '_…and 3 more commit(s)_ [View all](https://github.com/org/repo/compare/a...b)' "$OUT"
}

@test "max_commits empty, 0 or larger than the list shows everything" {
  commits_json "$TMP/c.json" '[range(1;4) | {sha: "s\(.)", author: "bob", message: "feat: change \(.)"}]'
  for max in "" 0 10; do
    run_process "$TMP/c.json" true true false false "$max"
    [ "$(grep -c 'change' "$OUT")" -eq 3 ]
    refute_contains "$OUT" 'more commit'
  done
}

@test "invalid max_commits warns and shows everything" {
  commits_json "$TMP/c.json" '[range(1;4) | {sha: "s\(.)", author: "bob", message: "feat: change \(.)"}]'
  run_process "$TMP/c.json" true true false false abc
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::max_commits"* ]]
  [ "$(grep -c 'change' "$OUT")" -eq 3 ]
}

@test "empty commit list produces an empty file" {
  echo '[]' > "$TMP/c.json"
  run_process "$TMP/c.json"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
}
