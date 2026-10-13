#!/bin/bash
# Handle test mode preview

set -e

MESSAGE_FILE="$1"
NAMES_FILE="$2"
WORKSPACE_ID="$3"

# Load resolved names
if [ -f "$NAMES_FILE" ]; then
  # shellcheck source=/dev/null
  source "$NAMES_FILE"
fi

# Set defaults if not loaded
WORKSPACE_NAME="${WORKSPACE_NAME:-$WORKSPACE_ID}"

echo "🧪 TEST MODE ENABLED - Message preview (NOT SENT to ClickUp)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📋 PREVIEW OF MESSAGE CONTENT:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
cat "$MESSAGE_FILE"
echo ""

MESSAGE_LENGTH=$(wc -c < "$MESSAGE_FILE" | tr -d " ")

echo "═══════════════════════════════════════════════════════════════"
echo "📝 MESSAGE DETAILS:"
echo "═══════════════════════════════════════════════════════════════"

# Build destination string intelligently
DESTINATION="ClickUp"
if [ -n "$WORKSPACE_NAME" ] && [ "$WORKSPACE_NAME" != "***" ]; then
  DESTINATION="$DESTINATION => $WORKSPACE_NAME"
fi
DESTINATION="$DESTINATION => Channels"

echo "• Destination: $DESTINATION"
echo "• Content Format: text/md"
echo "• Character Count: $MESSAGE_LENGTH characters"
echo "• API Token: Provided (hidden for security)"
echo ""
echo "⚠️  TEST MODE: No actual API call made to ClickUp"
echo "    Set test_mode to \"false\" to send this message"
echo "═══════════════════════════════════════════════════════════════"
