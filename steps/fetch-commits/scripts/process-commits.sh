#!/bin/bash
# Process and format commits

set -e

COMMITS_FILE="$1"
FULL_COMMIT_MESSAGE="$2"
OUTPUT_FILE="$3"
FILTER_AGENT_COMMITS="$4"
GROUP_BY_TYPE="$5"
SHOW_PR_LINKS="$6"
MAX_COMMITS="$7"
COMPARE_URL="$8"

# Constants
CONVENTIONAL_COMMIT_TYPES="build|chore|docs|feat|fix|refactor|revert|style|test|release|security|deps|api"
NL=$'\n'

# Helper function to format task links
format_task_links() {
  local message="$1"
  message=$(printf '%s\n' "$message" | sed -E "s/ctask \`([A-Za-z0-9\-]+)\`/[\1](https:\/\/app.clickup.com\/t\/${CLICKUP_WORKSPACE_ID}\/\1)/g")
  message=$(printf '%s\n' "$message" | sed -E "s/task \`([A-Za-z0-9\-]+)\`/[\1](https:\/\/app.clickup.com\/t\/\1)/g")
  printf '%s\n' "$message"
}

# Helper function to format conventional commits
format_conventional_commit() {
  local text="$1"
  local prefix rest type scope_and_breaking

  # Check if text matches conventional commit pattern (case-insensitive)
  if printf '%s\n' "$text" | grep -Eiq "^(${CONVENTIONAL_COMMIT_TYPES})(\([^)]+\))?(!)?:"; then
    prefix=$(printf '%s\n' "$text" | grep -oEi "^(${CONVENTIONAL_COMMIT_TYPES})(\([^)]+\))?(!)?:")
    rest="${text#"$prefix" }"

    # Convert the commit type to lowercase, then capitalize first letter
    type=$(printf '%s\n' "$prefix" | grep -oEi "^(${CONVENTIONAL_COMMIT_TYPES})" | tr '[:upper:]' '[:lower:]')

    # Keep scope and breaking marker exactly as written, e.g. "(auth)!:"
    scope_and_breaking="${prefix:${#type}}"
    type="$(tr '[:lower:]' '[:upper:]' <<< "${type:0:1}")${type:1}"

    printf '%s\n' "**${type}${scope_and_breaking}** ${rest}"
  else
    printf '%s\n' "$text"
  fi
}

# Helper function to convert text to Title Case
title_case() {
  printf '%s\n' "$1" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# Helper function to detect the Copilot coding agent bot author
is_copilot_agent() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" == *"copilot"*"agent"*"bot"* ]] || [[ "$lower" == *"copilot-swe-agent"* ]]
}

# Helper function to extract name from the first Co-authored-by line of a message
extract_coauthor_name() {
  local line name
  line=$(printf '%s\n' "$1" | grep -i "^[[:space:]]*Co-authored-by:" | head -1 || true)
  [ -z "$line" ] && return 0
  name=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*[Cc]o-authored-by:[[:space:]]*//')
  name=$(printf '%s\n' "$name" | sed -E 's/[[:space:]]*<[^>]+>[[:space:]]*$//')
  name=$(printf '%s\n' "$name" | sed -E 's/[[:space:]]+[0-9]+\+[^ ]+$//')
  name=$(printf '%s\n' "$name" | sed -E 's/[[:space:]]+[^ ]+@[^ ]+$//')
  printf '%s\n' "$name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Helper function to linkify PR references
linkify_pr_refs() {
  local message="$1"
  if [[ "$SHOW_PR_LINKS" == "true" ]]; then
    local repo_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
    message=$(printf '%s\n' "$message" | sed -E "s|#([0-9]{1,7})|[#\\1](${repo_url}/pull/\\1)|g")
  fi
  printf '%s\n' "$message"
}

COMMITS_JSON=$(cat "$COMMITS_FILE")

if [ "$COMMITS_JSON" = "[]" ] || [ -z "$COMMITS_JSON" ]; then
  : > "$OUTPUT_FILE"
  exit 0
fi

COMMIT_COUNT=$(printf '%s\n' "$COMMITS_JSON" | jq 'length')

if [ "$COMMIT_COUNT" -eq 0 ]; then
  : > "$OUTPUT_FILE"
  exit 0
fi

# Pre-scan: co-author of the first Copilot agent commit that has one.
# Used for Copilot agent commits that carry no Co-authored-by line themselves.
COPILOT_FALLBACK_COAUTHOR=""
for ((i=0; i<COMMIT_COUNT; i++)); do
  if is_copilot_agent "$(printf '%s\n' "$COMMITS_JSON" | jq -r ".[$i].author")"; then
    COPILOT_FALLBACK_COAUTHOR=$(extract_coauthor_name "$(printf '%s\n' "$COMMITS_JSON" | jq -r ".[$i].message")")
    [ -n "$COPILOT_FALLBACK_COAUTHOR" ] && break
  fi
done

# Accepted entries in chronological order: formatted block + group label
ENTRY_BLOCKS=()
ENTRY_GROUPS=()
UNIQUE_KEYS=()

for ((i=0; i<COMMIT_COUNT; i++)); do
  RAW_AUTHOR=$(printf '%s\n' "$COMMITS_JSON" | jq -r ".[$i].author")
  AUTHOR=$(printf '%s' "$RAW_AUTHOR" | tr -c '[:alnum:] ' ' ' | tr -s ' ')
  AUTHOR=$(printf '%s\n' "$AUTHOR" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -z "$AUTHOR" ] && AUTHOR="Unknown Contributor"

  RAW_MESSAGE=$(printf '%s\n' "$COMMITS_JSON" | jq -r ".[$i].message")
  FIRST_LINE=$(printf '%s\n' "$RAW_MESSAGE" | sed -n '1p')

  # Filter agent commits
  if [[ "$FILTER_AGENT_COMMITS" == "true" ]]; then
    if printf '%s\n' "$FIRST_LINE" | grep -qi "^Initial plan$"; then
      continue
    fi
    if printf '%s\n' "$FIRST_LINE" | grep -qi "^Agent-Logs-Url:"; then
      continue
    fi
    if printf '%s\n' "$FIRST_LINE" | grep -qi "^Co-authored-by:"; then
      continue
    fi
  fi

  # Capitalize author name (Title Case)
  AUTHOR=$(title_case "$AUTHOR")

  # Handle copilot agent bot author: prefer this commit's own co-author
  if is_copilot_agent "$RAW_AUTHOR"; then
    COAUTHOR=$(extract_coauthor_name "$RAW_MESSAGE")
    [ -z "$COAUTHOR" ] && COAUTHOR="$COPILOT_FALLBACK_COAUTHOR"
    if [ -n "$COAUTHOR" ]; then
      AUTHOR="$(title_case "$COAUTHOR") (Copilot Agent)"
    else
      AUTHOR="Copilot Agent"
    fi
  fi

  if [[ "$FULL_COMMIT_MESSAGE" == "true" ]]; then
    FORMATTED_MESSAGE=$(format_task_links "$RAW_MESSAGE")

    HEADER_LINE=$(printf '%s\n' "$FORMATTED_MESSAGE" | sed -n '1p')
    BODY_LINES=$(printf '%s\n' "$FORMATTED_MESSAGE" | sed '1d')

    # Strip Co-authored-by lines from body when filtering
    if [[ "$FILTER_AGENT_COMMITS" == "true" ]]; then
      BODY_LINES=$(printf '%s\n' "$BODY_LINES" | grep -vi "^[[:space:]]*Co-authored-by:" || true)
    fi

    HEADER_LINE=$(format_conventional_commit "$HEADER_LINE")
    HEADER_LINE=$(linkify_pr_refs "$HEADER_LINE")

    # Consistent formatting: always use single space after bullet
    FINAL_COMMIT_BLOCK="* ${HEADER_LINE}"

    # Only add body if it exists and has non-whitespace content
    if [ -n "$BODY_LINES" ] && [ -n "$(printf '%s' "$BODY_LINES" | tr -d '[:space:]')" ]; then
      if printf '%s\n' "$BODY_LINES" | grep -qE '^\s*[\*\-\+]'; then
        INDENTED_BODY=$(printf '%s\n' "$BODY_LINES" | sed -E 's/^\s*([\*\-\+])/  \1 /')
      else
        INDENTED_BODY=$(printf '%s\n' "$BODY_LINES" | sed 's/^/  /')
      fi
      INDENTED_BODY=$(linkify_pr_refs "$INDENTED_BODY")
      FINAL_COMMIT_BLOCK="${FINAL_COMMIT_BLOCK}${NL}${NL}${INDENTED_BODY}"
    fi

  else
    MESSAGE=$(format_task_links "$FIRST_LINE")
    MESSAGE=$(format_conventional_commit "$MESSAGE")
    MESSAGE=$(linkify_pr_refs "$MESSAGE")

    FINAL_COMMIT_BLOCK="* ${MESSAGE}"
  fi

  # Skip merge commits (both "Merge branch" and "Merge pull request")
  if [[ "$FINAL_COMMIT_BLOCK" =~ ^\*[[:space:]]+[Mm]erge[[:space:]]+(branch|pull[[:space:]]+request) ]]; then
    continue
  fi

  # Use only the commit message for uniqueness, not author+message
  COMMIT_SIGNATURE="${FINAL_COMMIT_BLOCK#\* }"
  IS_UNIQUE=true
  for existing_key in "${UNIQUE_KEYS[@]}"; do
    if [[ "$existing_key" == "$COMMIT_SIGNATURE" ]]; then
      IS_UNIQUE=false
      break
    fi
  done
  $IS_UNIQUE || continue
  UNIQUE_KEYS+=("$COMMIT_SIGNATURE")

  if [[ "$GROUP_BY_TYPE" == "true" ]]; then
    # Determine conventional commit type
    COMMIT_TYPE="Other"
    if printf '%s\n' "$FIRST_LINE" | grep -Eiq "^(${CONVENTIONAL_COMMIT_TYPES})(\([^)]+\))?(!)?:"; then
      COMMIT_TYPE=$(printf '%s\n' "$FIRST_LINE" | grep -oEi "^(${CONVENTIONAL_COMMIT_TYPES})" | tr '[:upper:]' '[:lower:]')
      COMMIT_TYPE="$(tr '[:lower:]' '[:upper:]' <<< "${COMMIT_TYPE:0:1}")${COMMIT_TYPE:1}"
    fi

    # Map types to display labels with emojis
    case "$COMMIT_TYPE" in
      Feat) GROUP_LABEL="🎯 Features" ;;
      Fix) GROUP_LABEL="🔧 Fixes" ;;
      Refactor) GROUP_LABEL="🔄 Refactors" ;;
      Docs) GROUP_LABEL="📝 Documentation" ;;
      Style) GROUP_LABEL="🎨 Styles" ;;
      Test) GROUP_LABEL="🧪 Tests" ;;
      Build) GROUP_LABEL="🏗️ Build" ;;
      Chore) GROUP_LABEL="🧹 Chores" ;;
      Revert) GROUP_LABEL="⏪ Reverts" ;;
      Security) GROUP_LABEL="🔒 Security" ;;
      Deps) GROUP_LABEL="📦 Dependencies" ;;
      Api) GROUP_LABEL="🔌 API" ;;
      Release) GROUP_LABEL="🚀 Releases" ;;
      *) GROUP_LABEL="📋 Other" ;;
    esac

    # Strip conventional commit prefix for cleaner display under type headers
    if [[ "$COMMIT_TYPE" != "Other" ]]; then
      FINAL_COMMIT_BLOCK=$(printf '%s\n' "$FINAL_COMMIT_BLOCK" | sed -E "1s/^\* \*\*[^*]+\*\* /\* /")
    fi
  else
    # Group by author (default)
    GROUP_LABEL="$AUTHOR"
  fi

  ENTRY_BLOCKS+=("$FINAL_COMMIT_BLOCK")
  ENTRY_GROUPS+=("$GROUP_LABEL")
done

# Limit to the most recent MAX_COMMITS entries (empty or 0 = show all)
TOTAL_ENTRIES=${#ENTRY_BLOCKS[@]}
START_INDEX=0
if [ -n "$MAX_COMMITS" ] && [ "$MAX_COMMITS" != "0" ]; then
  if [[ "$MAX_COMMITS" =~ ^[0-9]+$ ]]; then
    if [ "$TOTAL_ENTRIES" -gt "$MAX_COMMITS" ]; then
      START_INDEX=$((TOTAL_ENTRIES - MAX_COMMITS))
    fi
  else
    echo "::warning::max_commits must be a positive number, got '$MAX_COMMITS'. Showing all commits."
  fi
fi

# Group entries, keeping groups in order of first appearance
GROUP_LIST=()
GROUP_COMMITS_LIST=()
for ((k=START_INDEX; k<TOTAL_ENTRIES; k++)); do
  FOUND=false
  for j in "${!GROUP_LIST[@]}"; do
    if [[ "${GROUP_LIST[$j]}" == "${ENTRY_GROUPS[$k]}" ]]; then
      GROUP_COMMITS_LIST[j]+="${ENTRY_BLOCKS[$k]}${NL}${NL}"
      FOUND=true
      break
    fi
  done

  if ! $FOUND; then
    GROUP_LIST+=("${ENTRY_GROUPS[$k]}")
    GROUP_COMMITS_LIST+=("${ENTRY_BLOCKS[$k]}${NL}${NL}")
  fi
done

# Build changelog
COMMIT_LIST_MD=""
for k in "${!GROUP_LIST[@]}"; do
  COMMIT_LIST_MD+="${NL}_*${GROUP_LIST[$k]}:*_${NL}${GROUP_COMMITS_LIST[$k]}"
done

if [ "$START_INDEX" -gt 0 ]; then
  MORE_LINE="_…and ${START_INDEX} more commit(s)_"
  if [ -n "$COMPARE_URL" ]; then
    MORE_LINE="${MORE_LINE} [View all](${COMPARE_URL})"
  fi
  COMMIT_LIST_MD+="${MORE_LINE}"
fi

printf '%s\n' "$COMMIT_LIST_MD" > "$OUTPUT_FILE"
