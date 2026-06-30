#!/usr/bin/env bash
#
# github-activity-cli
# --------------------
# Fetches a GitHub user's public event timeline via the REST API,
# paginates through all available pages, caches each page on disk
# with ETag-based conditional requests, and renders the combined
# result as a grouped, icon-annotated activity feed.
#
# Usage:
#   ./github-activity.sh <username> [per_page] [page]
#
# Arguments:
#   username   GitHub login to fetch events for (required)
#   per_page   Results per page, 1-100 (default: 30)
#   page       Starting page number, >= 1 (default: 1)
#
# Requires: bash >= 4 (array refs / arithmetic assume bash, not POSIX sh),
#           curl >= 7.95 (for the %output{} write-out variable),
#           jq
#
# Cache layout:
#   ~/.cache/github-activity-cli/<username>/.page-<N>   raw JSON response
#   ~/.cache/github-activity-cli/<username>/.etag-<N>   ETag for page N
#
# Exit codes:
#   0  success
#   1  missing dependency, invalid argument, or failed request
 
set -o pipefail

readonly CACHE_ROOT="${HOME}/.cache/github-activity-cli"

# ---------------------------------------------------------------------------
# require_command <command_name>
#
# Verifies that the given command exists on PATH.
#
# Arguments:
#   $1  Name of the command to check (e.g. "curl")
#
# Returns:
#   0 if the command is available; 1 otherwise (with a message on stderr)
# ---------------------------------------------------------------------------
function require_command {
 
    [ -z "$1" ] && { >&2 echo "Usage: require_command <command_name>"; return 1; };
    
    &>/dev/null command -v "$1" || { >&2 echo "Error: Required command '$1' is not installed."; return 1; }
 
}

# ---------------------------------------------------------------------------
# github_user_activity <username> <per_page> <page>
#
# Fetches a single page of a GitHub user's public events, using a cached
# ETag (if present) to issue a conditional GET. On success (HTTP 200 or
# 304) prints the path to the cached JSON file on stdout. The caller is
# responsible for reading and parsing that file.
#
# Arguments:
#   $1  GitHub username
#   $2  Results per page (1-100)
#   $3  Page number (>= 1)
#
# Outputs:
#   stdout  Absolute path to the cached events JSON file for this page
#   stderr  Error message on failure
#
# Returns:
#   0 on HTTP 200/304; 1 on any other response code or local failure
# ---------------------------------------------------------------------------
function github_user_activity {
    
    [ -z "$1" ] && { >&2 echo "Error: GitHub username is required."; return 1; }
    
    local username="$1"
    local per_page="$2"
    local page="$3"
 
    local cache_dir="${CACHE_ROOT}/${username}"
    [ -d "$cache_dir" ] || mkdir -p "${cache_dir}" || { >&2 echo "Error: Failed to create cache directory '${cache_dir}'."; return 1; }
 
    local events_page_file="${cache_dir}/.page-${page}"
    local etag_file="${cache_dir}/.etag-${page}"

    local args=(
        --get
        --data-urlencode "per_page=${per_page}"
        --data-urlencode "page=${page}"
        --silent
        --show-error
        --location
        --compressed
        --output "${events_page_file}"
        --write-out "%{stdout}%{response_code}%output{${etag_file}}%header{etag}"
        --header "Accept: application/vnd.github+json"
        --header "X-GitHub-Api-Version: 2026-03-10"
    )
 
    [ -s "$etag_file" ] && args+=(--header "If-None-Match: $(<"$etag_file")")
    #   [ -n "${GITHUB_TOKEN:-}" ] && args+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
    
    local response_code
    response_code=$(curl "${args[@]}" "https://api.github.com/users/${username}/events")

    case "$response_code" in
        200|304)
            >&1 echo "${events_page_file}"
            ;;
        *)
            >&2 echo "Error: Failed to fetch GitHub user activity. HTTP response code: ${response_code}"
            return 1
            ;;
    esac

}

# ---------------------------------------------------------------------------
# main <username> [per_page] [page]
#
# Entry point. Validates dependencies and arguments, paginates through
# all event pages for the given user (stopping once a short page
# signals the last page), merges the cached JSON files, and prints a
# grouped, icon-annotated summary to stdout.
#
# Arguments:
#   $1  GitHub username (required)
#   $2  Results per page, 1-100 (optional, default 30)
#   $3  Starting page number, >= 1 (optional, default 1)
#
# Returns:
#   0 on success; 1 on missing dependency, invalid argument, or
#   request failure
# ---------------------------------------------------------------------------
function main {

    for cmd in curl jq; do require_command "${cmd}" || return 1; done

    local username="$1"
    local per_page="${2:-30}"
    local page="${3:-1}"

    [ -z "$username"            ] && { >&2 echo "Error: username is required."       ; return 1; }
    [[ "$per_page" =~ ^[0-9]+$ ]] || { >&2 echo "Error: per_page must be an integer."; return 1; }
    [[ "$page"     =~ ^[0-9]+$ ]] || { >&2 echo "Error: page must be an integer."    ; return 1; }

    [ "$per_page" -gt 100 ] && { >&2 echo "Error: per_page must not exceed 100."       ; return 1; }
    [ "$per_page" -le   0 ] && { >&2 echo "Error: per_page must be a positive integer."; return 1; }
    [ "$page"     -le   0 ] && { >&2 echo "Error: page must be a positive integer."    ; return 1; }

    local -a events_page_files=()
    
    while true; do

        local events_page_file

        events_page_file=$(github_user_activity "$username" "$per_page" "$page") || return 1

        events_page_files+=("$events_page_file")

        [ "$(jq length "$events_page_file")" -lt "$per_page" ] && { break; }

        ((page++))

    done

    [ "${#events_page_files[@]}" -eq 0 ] && { echo "[]"; } ||  { jq -s add "${events_page_files[@]}"; } \
    | jq -r '.[] | [ .type, .actor.login, .repo.name, .created_at, (.payload.action // "") ] | @tsv' \
    | sort -k3,3 -k4,4r \
    | awk '
    function icon(t, action) {
 
        if (t == "PushEvent") return "📌 Push"
 
        if (t == "PullRequestEvent") return "🔀 PR"
        if (t == "PullRequestReviewEvent") return "🧐 Review"
        if (t == "PullRequestReviewCommentEvent") return "💬 Review Comment"
 
        if (t == "IssuesEvent") {
            if (action == "opened") return "🐞 Issue Opened"
            if (action == "closed") return "🐞 Issue Closed"
            return "🐞 Issue"
        }
 
        if (t == "IssueCommentEvent") return "💬 Issue Comment"
 
        if (t == "ForkEvent") return "🍴 Fork"
        if (t == "WatchEvent") return "⭐ Star"
        if (t == "CreateEvent") return "🆕 Create"
        if (t == "DeleteEvent") return "❌ Delete"
        if (t == "ReleaseEvent") return "🚀 Release"
        if (t == "MemberEvent") return "👤 Member"
        if (t == "PublicEvent") return "🌍 Public"
        if (t == "GollumEvent") return "📄 Wiki"
 
        return "📦 " t
    }
 
    BEGIN { current_repo = "" }
 
    {
        type = $1
        actor = $2
        repo = $3
        time = $4
        action = $5
 
        label = icon(type, action)
 
        if (repo != current_repo) {
            print ""
            print "📦 " repo
            print "----------------------"
            current_repo = repo
        }
 
        printf "  %-18s %s\n", label, time
    }
    '
}
 
main "$@"
