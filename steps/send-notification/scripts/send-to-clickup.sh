#!/bin/bash
# Send message to ClickUp API
# The API token is read from CLICKUP_API_TOKEN so it never appears in process arguments.
# Network errors, HTTP 429 and HTTP 5xx are retried with exponential backoff.

set -e

MESSAGE_FILE="$1"
WORKSPACE_ID="$2"
CHANNEL_ID="$3"
MESSAGE_ID_FILE="$4"

API_TOKEN="$CLICKUP_API_TOKEN"
MAX_ATTEMPTS="${CLICKUP_MAX_ATTEMPTS:-3}"
RETRY_BASE_DELAY="${CLICKUP_RETRY_BASE_DELAY:-2}"
MAX_RETRY_AFTER=60

PAYLOAD_FILE=$(mktemp)
RESPONSE_FILE=$(mktemp)
HEADERS_FILE=$(mktemp)
AUTH_HEADER_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE" "$HEADERS_FILE" "$AUTH_HEADER_FILE"' EXIT

chmod 600 "$AUTH_HEADER_FILE"
printf 'Authorization: %s\n' "$API_TOKEN" > "$AUTH_HEADER_FILE"

# Create JSON payload
jq -n --rawfile content "$MESSAGE_FILE" '{
  type: "message",
  content_format: "text/md",
  content: ($content | sub("\n+$"; ""))
}' > "$PAYLOAD_FILE"

ATTEMPT=1
while true; do
  HTTP_CODE=$(curl -s -o "$RESPONSE_FILE" -D "$HEADERS_FILE" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H @"$AUTH_HEADER_FILE" \
    -d @"$PAYLOAD_FILE" \
    "https://api.clickup.com/api/v3/workspaces/$WORKSPACE_ID/chat/channels/$CHANNEL_ID/messages") || HTTP_CODE="000"

  if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    echo "--- ClickUp notification sent successfully ---"
    if [ -n "$MESSAGE_ID_FILE" ]; then
      jq -r '.id // .data.id // empty' "$RESPONSE_FILE" 2>/dev/null > "$MESSAGE_ID_FILE" || true
    fi
    exit 0
  fi

  RETRYABLE=false
  if [ "$HTTP_CODE" = "000" ] || [ "$HTTP_CODE" = "429" ] || [[ "$HTTP_CODE" -ge 500 && "$HTTP_CODE" -lt 600 ]]; then
    RETRYABLE=true
  fi

  if $RETRYABLE && [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    DELAY=$((RETRY_BASE_DELAY * (1 << (ATTEMPT - 1))))
    RETRY_AFTER=$(grep -i '^retry-after:' "$HEADERS_FILE" 2>/dev/null | head -1 | tr -dc '0-9' || true)
    if [ -n "$RETRY_AFTER" ] && [ "$RETRY_AFTER" -le "$MAX_RETRY_AFTER" ]; then
      DELAY="$RETRY_AFTER"
    fi
    echo "::warning::ClickUp returned HTTP $HTTP_CODE (attempt $ATTEMPT/$MAX_ATTEMPTS). Retrying in ${DELAY}s..."
    sleep "$DELAY"
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi

  echo "::error::Failed to send notification to ClickUp. HTTP code: $HTTP_CODE"
  echo "ClickUp response: $(cat "$RESPONSE_FILE")"
  echo "Message length: $(jq -r '.content | length' "$PAYLOAD_FILE") characters"
  exit 1
done
