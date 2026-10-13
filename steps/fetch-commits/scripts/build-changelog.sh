#!/bin/bash
# Build final changelog combining all sections

set -e

COMMITS_OUTPUT="$1"
STATS_OUTPUT="$2"
SHOW_STATS="$3"
FINAL_OUTPUT="$4"
SHOW_COMPARE_LINK="$5"
COMPARE_URL="$6"

NL=$'\n'
FINAL_MESSAGE=""

# Add commits section
if [ -f "$COMMITS_OUTPUT" ] && [ -s "$COMMITS_OUTPUT" ]; then
  COMMITS_CONTENT=$(cat "$COMMITS_OUTPUT")
  if [ -n "$COMMITS_CONTENT" ]; then
    FINAL_MESSAGE="${NL}${NL}**Change Log:**${COMMITS_CONTENT}"

    # Add link to the full diff on GitHub
    if [[ "$SHOW_COMPARE_LINK" == "true" ]] && [ -n "$COMPARE_URL" ]; then
      FINAL_MESSAGE="${FINAL_MESSAGE}${NL}${NL}🔗 [View full diff](${COMPARE_URL})"
    fi
  fi
fi

# Add statistics section if enabled
if [[ "$SHOW_STATS" == "true" ]] && [ -f "$STATS_OUTPUT" ] && [ -s "$STATS_OUTPUT" ]; then
  STATS_CONTENT=$(cat "$STATS_OUTPUT")
  if [ -n "$STATS_CONTENT" ]; then
    FINAL_MESSAGE="$FINAL_MESSAGE$STATS_CONTENT"
  fi
fi

printf '%s\n' "$FINAL_MESSAGE" > "$FINAL_OUTPUT"
