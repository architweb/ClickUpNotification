#!/usr/bin/env bats
# Tests for steps/fetch-commits/scripts/build-changelog.sh

load test_helper

setup() {
  common_setup
  OUT="$TMP/changelog.md"
  printf '\n_*Bob:*_\n* **Fix:** thing\n\n' > "$TMP/commits.md"
  printf '\n\n\n📊 **Stats:**\n📝 **Count**: 1 Commit(s)\n' > "$TMP/stats.md"
  URL="https://github.com/org/repo/compare/a...b"
}

@test "adds the Change Log header" {
  run bash "$FETCH_COMMITS/build-changelog.sh" "$TMP/commits.md" "" false "$OUT" false ""
  [ "$status" -eq 0 ]
  grep -qF '**Change Log:**' "$OUT"
  refute_contains "$OUT" 'View full diff'
}

@test "adds the compare link when enabled" {
  run bash "$FETCH_COMMITS/build-changelog.sh" "$TMP/commits.md" "" false "$OUT" true "$URL"
  grep -qxF "🔗 [View full diff]($URL)" "$OUT"
}

@test "no compare link without commits" {
  : > "$TMP/empty.md"
  run bash "$FETCH_COMMITS/build-changelog.sh" "$TMP/empty.md" "" false "$OUT" true "$URL"
  refute_contains "$OUT" 'View full diff'
  refute_contains "$OUT" 'Change Log'
}

@test "appends statistics after the compare link" {
  run bash "$FETCH_COMMITS/build-changelog.sh" "$TMP/commits.md" "$TMP/stats.md" true "$OUT" true "$URL"
  link_line=$(grep -n 'View full diff' "$OUT" | cut -d: -f1)
  stats_line=$(grep -n 'Stats' "$OUT" | cut -d: -f1)
  [ "$link_line" -lt "$stats_line" ]
}

@test "statistics are skipped when disabled" {
  run bash "$FETCH_COMMITS/build-changelog.sh" "$TMP/commits.md" "$TMP/stats.md" false "$OUT" false ""
  refute_contains "$OUT" 'Stats'
}
