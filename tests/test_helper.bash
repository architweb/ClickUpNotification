# Shared setup for bats tests. Load with: load test_helper
# shellcheck disable=SC2034  # variables are used by the .bats files that load this helper

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FETCH_COMMITS="$ROOT/steps/fetch-commits/scripts"
SEND_NOTIFICATION="$ROOT/steps/send-notification/scripts"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

common_setup() {
  TMP="$BATS_TEST_TMPDIR"
  STUB_BIN="$TMP/stub-bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"

  export GITHUB_REPOSITORY="org/repo"
  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_RUN_ID="42"
  export GITHUB_REF_NAME="main"
  export GITHUB_SHA="headsha"
  export CLICKUP_WORKSPACE_ID="999"
  unset ENVIRONMENT_EMOJIS STAGING_EMOJI PRODUCTION_EMOJI
}

# Write a JSON array of commits to a file: commits_json <file> <jq expression>
commits_json() {
  jq -n "$2" > "$1"
}

# Stub `gh api <endpoint> --jq <filter>` with canned responses from $GH_RESP/*.json
stub_gh() {
  export GH_RESP="$TMP/gh-responses"
  export GH_CALLS="$TMP/gh-calls.log"
  mkdir -p "$GH_RESP"
  : > "$GH_CALLS"
  cat > "$STUB_BIN/gh" <<'EOF'
#!/bin/bash
endpoint="$2"
filter="$4"
echo "$endpoint" >> "$GH_CALLS"
case "$endpoint" in
  */actions/workflows/*/runs*) file="run-history.json" ;;
  */actions/runs/*) file="run.json" ;;
  */compare/*) file="compare.json" ;;
  *"/commits?"*"until="*) file="commits-until.json" ;;
  *"/commits?"*"since="*) file="commits-since.json" ;;
  */commits/*) file="ref.json" ;;
  *) exit 1 ;;
esac
[ -f "$GH_RESP/$file" ] || exit 1
jq -r "$filter" "$GH_RESP/$file"
EOF
  chmod +x "$STUB_BIN/gh"
}

# Stub curl: returns HTTP codes listed in $CURL_CODES (one per call) and body $CURL_BODY.
# Records arguments in $CURL_ARGS and the last payload in $CURL_PAYLOAD.
stub_curl() {
  export CURL_CODES="$TMP/curl-codes"
  export CURL_BODY="$TMP/curl-body"
  export CURL_ARGS="$TMP/curl-args.log"
  export CURL_PAYLOAD="$TMP/curl-payload.json"
  : > "$CURL_ARGS"
  printf '%s\n' "$@" > "$CURL_CODES"
  echo '{}' > "$CURL_BODY"
  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/bash
echo "$*" >> "$CURL_ARGS"
out=""; headers=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -D) headers="$2"; shift ;;
    -d) [[ "$2" == @* ]] && cp "${2#@}" "$CURL_PAYLOAD"; shift ;;
  esac
  shift
done
code=$(head -1 "$CURL_CODES")
sed -i '1d' "$CURL_CODES"
[ -n "$headers" ] && printf 'HTTP/1.1 %s\r\n\r\n' "$code" > "$headers"
if [ -n "$out" ]; then
  cp "$CURL_BODY" "$out"
  printf '%s' "$code"
else
  cat "$CURL_BODY"
fi
EOF
  chmod +x "$STUB_BIN/curl"
}

# Fail when a file contains a string. (A bare `! grep` does not fail a bats test.)
refute_contains() {
  if grep -qF -- "$2" "$1"; then
    echo "unexpected '$2' in $1:"
    cat "$1"
    return 1
  fi
}

refute_contains_i() {
  if grep -qiF -- "$2" "$1"; then
    echo "unexpected '$2' (case-insensitive) in $1:"
    cat "$1"
    return 1
  fi
}
