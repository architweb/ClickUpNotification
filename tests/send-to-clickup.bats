#!/usr/bin/env bats
# Tests for steps/send-notification/scripts/send-to-clickup.sh and resolve-names.sh (curl is stubbed)

load test_helper

setup() {
  common_setup
  export CLICKUP_API_TOKEN="pk_secret_token"
  export CLICKUP_RETRY_BASE_DELAY=0
  MESSAGE="$TMP/message.md"
  ID_FILE="$TMP/message-id"
  printf '🚀 **Proj** deployed\n\n* line with C:\\temp\n\n' > "$MESSAGE"
}

send() {
  run bash "$SEND_NOTIFICATION/send-to-clickup.sh" "$MESSAGE" "111" "222" "$ID_FILE"
}

@test "sends once and writes the message id" {
  stub_curl 200
  echo '{"id": "msg123"}' > "$CURL_BODY"
  send
  [ "$status" -eq 0 ]
  [ "$(cat "$ID_FILE")" = "msg123" ]
  [ "$(wc -l < "$CURL_ARGS")" -eq 1 ]
  grep -qF 'workspaces/111/chat/channels/222/messages' "$CURL_ARGS"
}

@test "payload keeps message content verbatim without trailing newlines" {
  stub_curl 201
  send
  [ "$(jq -r '.content' "$CURL_PAYLOAD")" = "$(printf '🚀 **Proj** deployed\n\n* line with C:\\temp')" ]
  [ "$(jq -r '.content_format' "$CURL_PAYLOAD")" = "text/md" ]
}

@test "the API token never appears in curl arguments" {
  stub_curl 200
  send
  refute_contains "$CURL_ARGS" 'pk_secret_token'
}

@test "retries on 5xx and network errors, then succeeds" {
  stub_curl 503 000 200
  send
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_ARGS")" -eq 3 ]
  [[ "$output" == *"HTTP 503 (attempt 1/3)"* ]]
}

@test "gives up after the maximum attempts on 429" {
  stub_curl 429 429 429 200
  send
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CURL_ARGS")" -eq 3 ]
  [[ "$output" == *"::error::Failed to send notification to ClickUp. HTTP code: 429"* ]]
}

@test "does not retry client errors" {
  stub_curl 401 200
  send
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CURL_ARGS")" -eq 1 ]
}

@test "resolve-names sanitizes the workspace name before it is sourced" {
  stub_curl
  printf '%s' '{"teams": [{"id": "111", "name": "Team $(touch pwned) \"x\""}]}' > "$CURL_BODY"
  cd "$TMP"
  run bash "$SEND_NOTIFICATION/resolve-names.sh" "111" "$TMP/names.env"
  [ "$status" -eq 0 ]
  # shellcheck source=/dev/null
  source "$TMP/names.env"
  [ ! -e "$TMP/pwned" ]
  [[ "$WORKSPACE_NAME" == "Team "* ]]
  refute_contains "$CURL_ARGS" 'pk_secret_token'
}
