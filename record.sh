#!/usr/bin/env bash
# Asks Haxa to run on a pull request, proving which repository and pull request this workflow
# is with the token GitHub signs for it, then says what started and, if asked, waits for it.
#
# Everything comes in as variables (see action.yml): HAXA_PIPELINE, HAXA_WAIT, HAXA_DRY_RUN,
# HAXA_PULL_REQUEST and HAXA_SERVER, with GitHub's own ACTIONS_ID_TOKEN_REQUEST_URL and
# ACTIONS_ID_TOKEN_REQUEST_TOKEN, GITHUB_OUTPUT and GITHUB_STEP_SUMMARY.
set -euo pipefail

server="${HAXA_SERVER%/}"
pipeline="${HAXA_PIPELINE:-both}"
pull_request="${HAXA_PULL_REQUEST:-}"
dry_run="${HAXA_DRY_RUN:-false}"
wait="${HAXA_WAIT:-false}"
poll_seconds="${HAXA_POLL_SECONDS:-20}"
answer="$(mktemp)"
trap 'rm -f "$answer"' EXIT

fail() {
  echo "::error::$1"
  exit 1
}

case "$pipeline" in demo | qa | both) ;; *) fail "pipeline is demo, qa or both, not \"$pipeline\"" ;; esac
case "$dry_run" in true | false) ;; *) fail "dry-run is true or false, not \"$dry_run\"" ;; esac
case "$wait" in true | false) ;; *) fail "wait is true or false, not \"$wait\"" ;; esac

# A token GitHub signs for this run, for the Haxa it's asking and no other.
token() {
  [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || return 1
  local audience
  audience="$(jq -rn --arg server "$server" '$server | @uri')"
  curl --silent --show-error --fail --retry 3 \
    --header "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$audience" | jq -er .value
}

# Calls Haxa, leaving its answer in $answer, and fails with what it said unless it's a 200.
call() { # method, path, [body]
  local signed status
  [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] ||
    fail "GitHub gives this workflow no token: add \`permissions: id-token: write\` to it."
  signed="$(token)" || fail "GitHub didn't give this workflow a token"
  # Patient, as a run may be waited on for an hour, across a restart of Haxa's.
  status="$(curl --silent --show-error --retry 10 --retry-connrefused --retry-max-time 300 \
    --output "$answer" --write-out '%{http_code}' \
    --request "$1" --header "Authorization: Bearer $signed" \
    --header "Content-Type: application/json" ${3:+--data "$3"} "$server$2")" ||
    fail "Haxa at $server couldn't be reached"
  [ "$status" = 200 ] ||
    fail "Haxa said no ($status): $(jq -r '.error // "no reason given"' "$answer" 2>/dev/null || echo "no reason given")"
}

ask="$(jq -n --arg pipeline "$pipeline" --arg pr "$pull_request" --argjson dry "$dry_run" \
  '{pipeline: $pipeline, dryRun: $dry} + (if $pr == "" then {} else {pullRequest: $pr} end)')"
call POST /api/actions/v1/runs "$ask"

jq -r '.warnings[] | "::warning::" + .' "$answer"
jq -r '.declined[] | "::warning::\(.pipeline) was not started: \(.reason)"' "$answer"

if [ "$dry_run" = true ]; then
  echo "This would start: $(jq -r '.wouldStart | if length == 0 then "nothing" else join(", ") end' "$answer")"
  exit 0
fi

runs="$(jq -c '.runs' "$answer")"
jq -r '.runs[] | "Haxa \(.pipeline): \(.status), \(.url)"' "$answer"
echo "run-urls=$(jq -c 'map(.url)' <<<"$runs")" >>"${GITHUB_OUTPUT:-/dev/null}"
{
  echo "### Haxa"
  echo
  echo "| Run | Status |"
  echo "| --- | --- |"
  jq -r '.[] | "| [\(.pipeline)](\(.url)) | \(.status) |"' <<<"$runs"
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

[ "$wait" = true ] || exit 0

# Each run's state, as its check on the pull request says, until each has ended.
query="${pull_request:+?pullRequest=$pull_request}"
for id in $(jq -r '.[].id' <<<"$runs"); do
  said=""
  while :; do
    call GET "/api/actions/v1/runs/$id$query"
    now="$(jq -r '"Haxa \(.pipeline): \(.title)"' "$answer")"
    [ "$now" = "$said" ] || echo "$now"
    said="$now"
    case "$(jq -r .state "$answer")" in success | neutral) break ;; esac
    sleep "$poll_seconds"
  done
done
