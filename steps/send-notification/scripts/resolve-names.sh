#!/bin/bash
# Resolve workspace and channel names from IDs
# The API token is read from CLICKUP_API_TOKEN so it never appears in process arguments.

set -e

WORKSPACE_ID="$1"
OUTPUT_FILE="$2"

API_TOKEN="$CLICKUP_API_TOKEN"

# Default to IDs, but handle masked values
WORKSPACE_NAME="$WORKSPACE_ID"

# Don't try to resolve if token or IDs are missing or masked
if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "***" ] || [ "$WORKSPACE_ID" = "***" ]; then
  echo "WORKSPACE_NAME=\"$WORKSPACE_NAME\"" >"$OUTPUT_FILE"
  exit 0
fi

# Try to resolve workspace name from teams API
TEAMS_RESPONSE=$(curl -s -H @<(printf 'Authorization: %s\n' "$API_TOKEN") \
  "https://api.clickup.com/api/v2/team" 2>/dev/null || echo "")

if [ -n "$TEAMS_RESPONSE" ]; then
  RESOLVED_NAME=$(printf '%s\n' "$TEAMS_RESPONSE" | jq -r --arg id "$WORKSPACE_ID" '.teams[]? | select(.id == $id) | .name' 2>/dev/null || echo "")

  if [ -n "$RESOLVED_NAME" ] && [ "$RESOLVED_NAME" != "null" ]; then
    WORKSPACE_NAME="$RESOLVED_NAME"
  fi
fi

# Sanitize before writing a file that is loaded with `source`
WORKSPACE_NAME=$(printf '%s' "$WORKSPACE_NAME" | tr -c '[:alnum:] ._-' ' ' | tr -s ' ')

# Output results
echo "WORKSPACE_NAME=\"$WORKSPACE_NAME\"" >"$OUTPUT_FILE"
