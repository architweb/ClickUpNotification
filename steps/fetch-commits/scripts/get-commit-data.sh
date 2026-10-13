#!/bin/bash
# Get commit data from GitHub API
#
# The changelog base is, in order of preference:
#   1. head SHA of the last successful run of this workflow on this branch
#   2. since_ref (tag, branch or SHA), when there is no previous successful run
#   3. the last FALLBACK_DAYS days of history on this branch

set -e

OUTPUT_FILE="$1"
SINCE_REF="$2"

FALLBACK_DAYS=30
REPO="${GITHUB_REPOSITORY}"
COMMIT_FIELDS='{sha: .sha, message: .commit.message, author: .commit.author.name}'

echo "[]" > "$OUTPUT_FILE"
: > "${OUTPUT_FILE}.meta"

if ! command -v gh &> /dev/null; then
  echo "::warning::GitHub CLI (gh) not found - skipping changelog."
  exit 0
fi

BASE_SHA=""
BASE_SOURCE=""
COMMITS_JSON="[]"

# 1. Last successful run of this workflow on this branch
WORKFLOW_ID=$(gh api "repos/${REPO}/actions/runs/${GITHUB_RUN_ID}" --jq '.workflow_id' 2>/dev/null || echo "")
if [ -n "$WORKFLOW_ID" ]; then
  BASE_SHA=$(gh api "repos/${REPO}/actions/workflows/${WORKFLOW_ID}/runs?branch=${GITHUB_REF_NAME}&status=success&per_page=1" \
    --jq '.workflow_runs[0].head_sha // empty' 2>/dev/null || echo "")
  [ -n "$BASE_SHA" ] && BASE_SOURCE="previous_run"
fi

# 2. No previous successful run: use since_ref
if [ -z "$BASE_SHA" ] && [ -n "$SINCE_REF" ]; then
  BASE_SHA=$(gh api "repos/${REPO}/commits/${SINCE_REF}" --jq '.sha' 2>/dev/null || echo "")
  if [ -n "$BASE_SHA" ]; then
    BASE_SOURCE="since_ref"
  else
    echo "::warning::since_ref '${SINCE_REF}' could not be resolved - falling back to the last ${FALLBACK_DAYS} days."
  fi
fi

# 3. Still no base: last commit before the fallback window
if [ -z "$BASE_SHA" ]; then
  SINCE_DATE=$(jq -nr --argjson days "$FALLBACK_DAYS" '(now - ($days * 86400)) | floor | todate')
  BASE_SOURCE="last_${FALLBACK_DAYS}_days"
  BASE_SHA=$(gh api "repos/${REPO}/commits?sha=${GITHUB_SHA}&until=${SINCE_DATE}&per_page=1" \
    --jq '.[0].sha // empty' 2>/dev/null || echo "")

  # Repository history is shorter than the window: list everything since that date
  if [ -z "$BASE_SHA" ]; then
    COMMITS_JSON=$(gh api "repos/${REPO}/commits?sha=${GITHUB_SHA}&since=${SINCE_DATE}&per_page=100" \
      --jq "[.[] | ${COMMIT_FIELDS}] | reverse" 2>/dev/null || echo "[]")
  fi
fi

if [ -n "$BASE_SHA" ] && [ "$BASE_SHA" != "$GITHUB_SHA" ]; then
  COMMITS_JSON=$(gh api "repos/${REPO}/compare/${BASE_SHA}...${GITHUB_SHA}" \
    --jq "[.commits[] | ${COMMIT_FIELDS}]" 2>/dev/null || echo "[]")
fi

if [ "$COMMITS_JSON" != "[]" ] && [ -n "$COMMITS_JSON" ]; then
  echo "$COMMITS_JSON" > "$OUTPUT_FILE"
  {
    echo "CURRENT_SHA=$GITHUB_SHA"
    echo "BASE_SOURCE=$BASE_SOURCE"
    if [ -n "$BASE_SHA" ]; then
      echo "PREVIOUS_SHA=$BASE_SHA"
      echo "COMPARE_URL=${GITHUB_SERVER_URL:-https://github.com}/${REPO}/compare/${BASE_SHA}...${GITHUB_SHA}"
    fi
  } > "${OUTPUT_FILE}.meta"

  if [ "$BASE_SOURCE" != "previous_run" ]; then
    echo "No previous successful run found - changelog based on: ${BASE_SOURCE}"
  fi
fi
