#!/bin/bash
# Get GitHub user information

set -e

OUTPUT_FILE="$1"

TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
ACTOR="${TRIGGERING_ACTOR:-$GITHUB_ACTOR}"

# Get user name with fallback
TRIGGERING_USER_NAME=""
if [ -n "$TOKEN" ] && [ -n "$ACTOR" ]; then
  TRIGGERING_USER_NAME=$(curl -sf -H @<(printf 'Authorization: Bearer %s\n' "$TOKEN") \
    -H "Accept: application/vnd.github.v3+json" \
    "${GITHUB_API_URL:-https://api.github.com}/users/${ACTOR}" 2>/dev/null | jq -r '.name // ""' 2>/dev/null || echo "")
fi

if [ -z "$TRIGGERING_USER_NAME" ] || [ "$TRIGGERING_USER_NAME" = "null" ]; then
    TRIGGERING_USER_NAME="${ACTOR:-Unknown User}"
fi

# Ensure the user name is properly quoted and sanitized
TRIGGERING_USER_NAME=$(printf '%s' "$TRIGGERING_USER_NAME" | tr -c '[:alnum:] ' ' ' | tr -s ' ')

echo "TRIGGERING_USER_NAME=\"$TRIGGERING_USER_NAME\"" > "$OUTPUT_FILE"
