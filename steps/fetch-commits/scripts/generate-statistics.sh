#!/bin/bash
# Generate commit statistics

set -e

COMMITS_FILE="$1"
META_FILE="$2"
OUTPUT_FILE="$3"

NL=$'\n'

# Early exit if no commits file or empty
if [ ! -f "$COMMITS_FILE" ]; then
  : > "$OUTPUT_FILE"
  exit 0
fi

COMMITS_JSON=$(cat "$COMMITS_FILE")

# Early exit if no commits or no metadata
if [ "$COMMITS_JSON" = "[]" ] || [ -z "$COMMITS_JSON" ] || [ ! -f "$META_FILE" ]; then
  : > "$OUTPUT_FILE"
  exit 0
fi

# Read metadata (PREVIOUS_SHA, CURRENT_SHA, BASE_SOURCE, COMPARE_URL) - exit early if unreadable
# shellcheck source=/dev/null
if ! source "$META_FILE" 2>/dev/null; then
  : > "$OUTPUT_FILE"
  exit 0
fi

# Calculate statistics
TOTAL_COMMITS=$(printf '%s\n' "$COMMITS_JSON" | jq 'length')
UNIQUE_AUTHORS=$(printf '%s\n' "$COMMITS_JSON" | jq -r '.[].author' | sort -u | wc -l | tr -d ' ')

FILES_CHANGED="0"
LINES_ADDED="0"
LINES_REMOVED="0"
FILES_ADDED="0"
FILES_REMOVED="0"

# Get file and line statistics from local history
if [ -n "$PREVIOUS_SHA" ] && [ "$PREVIOUS_SHA" != "$CURRENT_SHA" ]; then
  # Get diff stats and name status separately for reliability
  DIFF_STATS=$(git diff --stat "$PREVIOUS_SHA...$CURRENT_SHA" 2>/dev/null || echo "")
  NAME_STATUS=$(git diff --name-status "$PREVIOUS_SHA...$CURRENT_SHA" 2>/dev/null || echo "")

  if [ -n "$DIFF_STATS" ]; then
    SUMMARY_LINE=$(printf '%s\n' "$DIFF_STATS" | tail -1)
    FILES_CHANGED=$(printf '%s\n' "$SUMMARY_LINE" | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+' || true)
    LINES_ADDED=$(printf '%s\n' "$SUMMARY_LINE" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+' || true)
    LINES_REMOVED=$(printf '%s\n' "$SUMMARY_LINE" | grep -oE '[0-9]+ deletions?' | grep -oE '[0-9]+' || true)
  fi

  if [ -n "$NAME_STATUS" ]; then
    FILES_ADDED=$(printf '%s\n' "$NAME_STATUS" | grep -c '^A' || true)
    FILES_REMOVED=$(printf '%s\n' "$NAME_STATUS" | grep -c '^D' || true)
  fi
fi

FILES_CHANGED="${FILES_CHANGED:-0}"
LINES_ADDED="${LINES_ADDED:-0}"
LINES_REMOVED="${LINES_REMOVED:-0}"
FILES_ADDED="${FILES_ADDED:-0}"
FILES_REMOVED="${FILES_REMOVED:-0}"

# Calculate commit type statistics
COMMIT_MESSAGES=$(printf '%s\n' "$COMMITS_JSON" | jq -r '.[].message')
REFACTOR_COMMITS=$(printf '%s\n' "$COMMIT_MESSAGES" | grep -iEc '^(refactor|refact)(\([^)]*\))?!?:' || true)
FIX_COMMITS=$(printf '%s\n' "$COMMIT_MESSAGES" | grep -iEc '^fix(\([^)]*\))?!?:' || true)

# Determine release type based on commit messages
FEAT_COMMITS=$(printf '%s\n' "$COMMIT_MESSAGES" | grep -iEc '^feat(\([^)]*\))?!?:' || true)
BREAKING_COMMITS=$(printf '%s\n' "$COMMIT_MESSAGES" | grep -iEc '^[^:]+(\([^)]*\))?!:' || true)

if [ "${BREAKING_COMMITS:-0}" -gt 0 ]; then
  RELEASE_TYPE="🚨 Major"
elif [ "${FEAT_COMMITS:-0}" -gt 0 ]; then
  RELEASE_TYPE="🎯 Minor"
elif [ "${FIX_COMMITS:-0}" -gt 0 ]; then
  RELEASE_TYPE="🔧 Patch"
else
  RELEASE_TYPE=""  # Hide "Other" type
fi

# Find top contributor
TOP_CONTRIBUTOR=$(printf '%s\n' "$COMMITS_JSON" | jq -r '.[].author' | sort | uniq -c | sort -nr | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' || echo "Unknown")

# Capitalize top contributor name (Title Case)
TOP_CONTRIBUTOR=$(printf '%s\n' "$TOP_CONTRIBUTOR" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

# Handle copilot agent bot display name
TOP_CONTRIBUTOR_LOWER=$(printf '%s' "$TOP_CONTRIBUTOR" | tr '[:upper:]' '[:lower:]')
if [[ "$TOP_CONTRIBUTOR_LOWER" == *"copilot"*"agent"*"bot"* ]] || [[ "$TOP_CONTRIBUTOR_LOWER" == *"copilot-swe-agent"* ]]; then
  TOP_CONTRIBUTOR="Copilot Agent"
fi

# Calculate time since last deployment (only meaningful when the base is a previous run)
TIME_SINCE=""
if [ -n "$PREVIOUS_SHA" ] && { [ -z "$BASE_SOURCE" ] || [ "$BASE_SOURCE" = "previous_run" ]; }; then
  PREVIOUS_COMMIT_DATE=$(git show -s --format=%ct "$PREVIOUS_SHA" 2>/dev/null || echo "")
  CURRENT_COMMIT_DATE=$(git show -s --format=%ct "$CURRENT_SHA" 2>/dev/null || echo "")

  if [ -n "$PREVIOUS_COMMIT_DATE" ] && [ -n "$CURRENT_COMMIT_DATE" ]; then
    TIME_DIFF=$((CURRENT_COMMIT_DATE - PREVIOUS_COMMIT_DATE))
    DAYS=$((TIME_DIFF / 86400))
    HOURS=$(((TIME_DIFF % 86400) / 3600))
    MINUTES=$(((TIME_DIFF % 3600) / 60))

    # Hide if less than 30 minutes
    if [ "$TIME_DIFF" -ge 1800 ]; then
      TIME_SINCE="${DAYS} day(s), ${HOURS} hour(s), ${MINUTES} minute(s)"
    fi
  fi
fi

# Build statistics
STATS_TABLE="${NL}${NL}${NL}📊 **Stats:**${NL}"
STATS_TABLE+="📝 **Count**: ${TOTAL_COMMITS} Commit(s)${NL}"

# Only show release type if it's not "Other"
if [ -n "$RELEASE_TYPE" ]; then
  STATS_TABLE+="🎯 **Release Type**: ${RELEASE_TYPE}${NL}"
fi

# Only show if files were changed
if [ "$FILES_CHANGED" -gt 0 ]; then
  STATS_TABLE+="📁 **Changed**: ${FILES_CHANGED} file(s)${NL}"
fi

# Build Added line dynamically
if [ "$FILES_ADDED" -gt 0 ] || [ "$LINES_ADDED" -gt 0 ]; then
  ADDED_PARTS=""
  if [ "$FILES_ADDED" -gt 0 ]; then
    ADDED_PARTS="+${FILES_ADDED} file(s)"
  fi
  if [ "$LINES_ADDED" -gt 0 ]; then
    if [ -n "$ADDED_PARTS" ]; then
      ADDED_PARTS="${ADDED_PARTS}, +${LINES_ADDED} line(s)"
    else
      ADDED_PARTS="+${LINES_ADDED} line(s)"
    fi
  fi
  STATS_TABLE+="➕ **Added**: ${ADDED_PARTS}${NL}"
fi

# Build Removed line dynamically
if [ "$FILES_REMOVED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
  REMOVED_PARTS=""
  if [ "$FILES_REMOVED" -gt 0 ]; then
    REMOVED_PARTS="-${FILES_REMOVED} file(s)"
  fi
  if [ "$LINES_REMOVED" -gt 0 ]; then
    if [ -n "$REMOVED_PARTS" ]; then
      REMOVED_PARTS="${REMOVED_PARTS}, -${LINES_REMOVED} line(s)"
    else
      REMOVED_PARTS="-${LINES_REMOVED} line(s)"
    fi
  fi
  STATS_TABLE+="➖ **Removed**: ${REMOVED_PARTS}${NL}"
fi

# Only show if fixes exist
if [ "${FIX_COMMITS:-0}" -gt 0 ]; then
  STATS_TABLE+="🔧 **Fixes**: ${FIX_COMMITS} commit(s)${NL}"
fi

# Only show if refactors exist
if [ "${REFACTOR_COMMITS:-0}" -gt 0 ]; then
  STATS_TABLE+="🔄 **Refactor**: ${REFACTOR_COMMITS} commit(s)${NL}"
fi

# Only show if time diff is >= 30 minutes
if [ -n "$TIME_SINCE" ]; then
  STATS_TABLE+="⏰ **Last Deploy**: ${TIME_SINCE}${NL}"
fi

# Only show contributors if 2 or more
if [ "$UNIQUE_AUTHORS" -ge 2 ]; then
  STATS_TABLE+="👥 **Contributor(s)**: ${UNIQUE_AUTHORS}${NL}"
fi

# Only show top contributor if 3 or more contributors
if [ "$UNIQUE_AUTHORS" -ge 3 ]; then
  STATS_TABLE+="🏆 **Top Contributor**: ${TOP_CONTRIBUTOR}"
else
  # Remove trailing newline if top contributor is not shown
  STATS_TABLE="${STATS_TABLE%"$NL"}"
fi

printf '%s\n' "$STATS_TABLE" > "$OUTPUT_FILE"
