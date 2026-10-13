#!/usr/bin/env bats
# Tests for steps/send-notification/scripts/build-message.sh

load test_helper

setup() {
  common_setup
  export CLICKUP_PROJECT_NAME="Proj"
  OUT="$TMP/msg.md"
  USER_INFO="$TMP/user.env"
  echo 'TRIGGERING_USER_NAME="Jane Doe"' > "$USER_INFO"
  printf '\n\n**Change Log:**\n_*Bob:*_\n* **Fix:** thing\n' > "$TMP/changelog.md"
}

# build [title] [description] [duration] [commit file] [status]
build() {
  run bash "$SEND_NOTIFICATION/build-message.sh" "$USER_INFO" "${1:-}" "${2:-}" "${3:-unknown}" "${4:-}" "$OUT" "${5:-success}"
  [ "$status" -eq 0 ]
}

@test "default header, triggered by and duration" {
  build "" "" "02:15" "$TMP/changelog.md"
  [ "$(sed -n '1p' "$OUT")" = "🚀 **Proj** deployed to **main**" ]
  grep -qxF '_Triggered by: Jane Doe, Done in: 02:15min_' "$OUT"
  grep -qF '**Change Log:**' "$OUT"
}

@test "custom title and description directly under the header" {
  build "My Title" "My desc"
  [ "$(sed -n '1p' "$OUT")" = "🚀 **main** | **Proj** | My Title" ]
  [ "$(sed -n '2p' "$OUT")" = "_My desc_" ]
  grep -qxF '_Triggered by: Jane Doe_' "$OUT"
}

@test "staging branches use the staging emoji" {
  export GITHUB_REF_NAME="release/Staging"
  build
  [[ "$(sed -n '1p' "$OUT")" == "🧪 "* ]]
}

@test "custom staging and production emojis" {
  export STAGING_EMOJI="🟡" PRODUCTION_EMOJI="🟢"
  build
  [[ "$(sed -n '1p' "$OUT")" == "🟢 "* ]]
  export GITHUB_REF_NAME="staging"
  build
  [[ "$(sed -n '1p' "$OUT")" == "🟡 "* ]]
}

@test "environment_emojis: first matching glob wins, case-insensitive" {
  export GITHUB_REF_NAME="Release/Beta"
  export ENVIRONMENT_EMOJIS=$'# comment\nrelease/beta = 🅱️\nrelease/* = 📦\n'
  build
  [[ "$(sed -n '1p' "$OUT")" == "🅱️ "* ]]
}

@test "environment_emojis: falls back to staging/production when nothing matches" {
  export GITHUB_REF_NAME="release/staging"
  export ENVIRONMENT_EMOJIS=$'hotfix/*=🔥'
  build
  [[ "$(sed -n '1p' "$OUT")" == "🧪 "* ]]
}

@test "failure message links to the workflow run" {
  build "Ignored title" "" "unknown" "$TMP/changelog.md" failure
  [ "$(sed -n '1p' "$OUT")" = "❌ 🚀 **Proj** deployment to **main** failed!" ]
  grep -qF '🔗 [View Workflow Run](https://github.com/org/repo/actions/runs/42)' "$OUT"
  refute_contains "$OUT" 'Change Log'
}

@test "cancelled message" {
  build "" "" "01:00" "" cancelled
  [ "$(sed -n '1p' "$OUT")" = "⚠️ 🚀 **Proj** deployment to **main** was cancelled." ]
  grep -qxF '_Triggered by: Jane Doe, Done in: 01:00min_' "$OUT"
  grep -qF '/actions/runs/42' "$OUT"
}

@test "backslashes in title and changelog are not interpreted" {
  printf '\n\n**Change Log:**\n* path C:\\temp\\new\n' > "$TMP/changelog.md"
  build 'Deploy \t done' "" "unknown" "$TMP/changelog.md"
  grep -qF 'Deploy \t done' "$OUT"
  grep -qF 'C:\temp\new' "$OUT"
}
