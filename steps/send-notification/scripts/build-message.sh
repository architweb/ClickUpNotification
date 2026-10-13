#!/bin/bash
# Build the notification message

set -e

USER_INFO_FILE="$1"
TITLE="$2"
DESCRIPTION="$3"
FORMATTED_DURATION="$4"
COMMIT_FILE="$5"
OUTPUT_FILE="$6"
WORKFLOW_STATUS="${7:-success}"

NL=$'\n'

# Load user info
if [ -f "$USER_INFO_FILE" ]; then
  # shellcheck source=/dev/null
  source "$USER_INFO_FILE"
fi

trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Determine environment emoji:
#   1. first matching "<branch glob>=<emoji>" line of ENVIRONMENT_EMOJIS (case-insensitive)
#   2. STAGING_EMOJI when the branch name contains "staging"
#   3. PRODUCTION_EMOJI otherwise
resolve_emoji() {
  local branch line pattern emoji
  branch=$(printf '%s' "$GITHUB_REF_NAME" | tr '[:upper:]' '[:lower:]')

  while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "${line%$'\r'}")
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    pattern=$(trim "${line%%=*}" | tr '[:upper:]' '[:lower:]')
    emoji=$(trim "${line#*=}")
    [ -z "$pattern" ] && continue
    # shellcheck disable=SC2053  # pattern is intentionally matched as a glob
    if [[ "$branch" == $pattern ]]; then
      printf '%s' "$emoji"
      return 0
    fi
  done <<< "$ENVIRONMENT_EMOJIS"

  if printf '%s' "$GITHUB_REF_NAME" | grep -qi "staging"; then
    printf '%s' "${STAGING_EMOJI:-🧪}"
  else
    printf '%s' "${PRODUCTION_EMOJI:-🚀}"
  fi
}

DEPLOY_EMOJI=$(resolve_emoji)
WORKFLOW_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

DEPLOY_INFO="_Triggered by: ${TRIGGERING_USER_NAME}"
[ "$FORMATTED_DURATION" != "unknown" ] && [ -n "$FORMATTED_DURATION" ] && DEPLOY_INFO="${DEPLOY_INFO}, Done in: ${FORMATTED_DURATION}min"
DEPLOY_INFO="${DEPLOY_INFO}_"

case "$WORKFLOW_STATUS" in
  failure)
    FINAL_MESSAGE="❌ ${DEPLOY_EMOJI} **${CLICKUP_PROJECT_NAME}** deployment to **${GITHUB_REF_NAME}** failed!${NL}${NL}${DEPLOY_INFO}${NL}${NL}⚠️ The workflow has failed. Check the logs for details.${NL}🔗 [View Workflow Run](${WORKFLOW_URL})"
    ;;
  cancelled)
    FINAL_MESSAGE="⚠️ ${DEPLOY_EMOJI} **${CLICKUP_PROJECT_NAME}** deployment to **${GITHUB_REF_NAME}** was cancelled.${NL}${NL}${DEPLOY_INFO}${NL}${NL}🔗 [View Workflow Run](${WORKFLOW_URL})"
    ;;
  *)
    # Build base message
    if [ -n "$TITLE" ]; then
      BASE_MESSAGE="${DEPLOY_EMOJI} **${GITHUB_REF_NAME}** | **${CLICKUP_PROJECT_NAME}** | $TITLE"
    else
      BASE_MESSAGE="${DEPLOY_EMOJI} **${CLICKUP_PROJECT_NAME}** deployed to **${GITHUB_REF_NAME}**"
    fi

    if [ -n "$DESCRIPTION" ]; then
      FINAL_MESSAGE="${BASE_MESSAGE}${NL}_${DESCRIPTION}_${NL}${NL}${DEPLOY_INFO}"
    else
      FINAL_MESSAGE="${BASE_MESSAGE}${NL}${NL}${DEPLOY_INFO}"
    fi

    # Add commit information if available
    if [ -f "$COMMIT_FILE" ] && [ -s "$COMMIT_FILE" ]; then
      COMMIT_LIST=$(cat "$COMMIT_FILE")
      if [ -n "$COMMIT_LIST" ]; then
        FINAL_MESSAGE="${FINAL_MESSAGE}${COMMIT_LIST}"
      fi
    fi
    ;;
esac

printf '%s\n' "$FINAL_MESSAGE" > "$OUTPUT_FILE"
