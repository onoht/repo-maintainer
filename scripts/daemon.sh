#!/bin/bash
# Repo Maintainer Daemon - Direct Polling
# Polls repos for issues/PRs directly instead of using GitHub notifications API

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="/data/.clawdbot/repo-maintainer"
STATE_FILE="$STATE_DIR/state.json"
PID_FILE="$STATE_DIR/daemon.pid"
LOG_FILE="$STATE_DIR/daemon.log"
CONFIG_FILE="${REPO_MAINTAINER_CONFIG:-$HOME/.config/repo-maintainer/repos.yaml}"

# Default poll interval: 5 minutes (300 seconds)
POLL_INTERVAL=${POLL_INTERVAL:-300}

mkdir -p "$STATE_DIR"

# Load GH_TOKEN
GITHUB_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null)}"
if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GH_TOKEN not found. Run 'gh auth login' first." >&2
    exit 1
fi

# Get bot username from gh auth
BOT_USERNAME=$(gh api user --jq '.login' 2>/dev/null)
if [ -z "$BOT_USERNAME" ]; then
    echo "ERROR: Could not get GitHub username. Run 'gh auth login' first." >&2
    exit 1
fi

log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Get repos from config
get_repos() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -oE '[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+:' "$CONFIG_FILE" | sed 's/:$//'
    else
        log "ERROR: Config not found at $CONFIG_FILE"
        return 1
    fi
}

# Initialize state file if missing
init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo '{}' > "$STATE_FILE"
    fi
}

# Get current state
get_state() {
    cat "$STATE_FILE" 2>/dev/null || echo '{}'
}

# Update state for a repo
update_repo_state() {
    local repo="$1"
    local type="$2"  # issues or prs
    local number="$3"
    local updated_at="$4"
    local status="$5"

    local state=$(get_state)

    # Use jq to update the state
    echo "$state" | jq --arg repo "$repo" --arg type "$type" --arg num "$number" \
        --arg updated "$updated_at" --arg status "$status" '
        (.[$repo] // {}) as $repo_state |
        ($repo_state[$type] // {}) as $items |
        $items[$num] = {updated_at: $updated, status: $status} |
        $repo_state[$type] = $items |
        .[$repo] = $repo_state
    ' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Update last scan time for a repo
update_last_scan() {
    local repo="$1"
    local state=$(get_state)

    echo "$state" | jq --arg repo "$repo" --arg time "$(date -u -Iseconds)" '
        (.[$repo] // {}) as $repo_state |
        $repo_state.last_scan = $time |
        .[$repo] = $repo_state
    ' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Check if item needs processing (new or updated since last check)
needs_processing() {
    local repo="$1"
    local type="$2"  # issues or prs
    local number="$3"
    local updated_at="$4"

    local state=$(get_state)
    local last_updated=$(echo "$state" | jq -r --arg repo "$repo" --arg type "$type" --arg num "$number" \
        '.[$repo][$type][$num].updated_at // empty')

    # If never seen, or updated_at is newer
    [ -z "$last_updated" ] || [ "$updated_at" ">" "$last_updated" ]
}

# Process a single repo
process_repo() {
    local repo="$1"
    log "Scanning $repo"

    # Fetch open issues
    local issues
    issues=$(gh issue list --repo "$repo" --state open --json number,title,updatedAt,author,labels 2>/dev/null || echo '[]')

    echo "$issues" | jq -r '.[] | @base64' | while read -r issue_b64; do
        local issue=$(echo "$issue_b64" | base64 -d)
        local number=$(echo "$issue" | jq -r '.number')
        local title=$(echo "$issue" | jq -r '.title')
        local author=$(echo "$issue" | jq -r '.author.login')
        local labels=$(echo "$issue" | jq '[.labels[].name]')
        local updated_at=$(echo "$issue" | jq -r '.updatedAt')

        if needs_processing "$repo" "issues" "$number" "$updated_at"; then
            log "  New/updated issue #$number: $title"

            # Create signal file
            jq -n \
                --arg repo "$repo" \
                --argjson number "$number" \
                --arg title "$title" \
                --arg author "$author" \
                --arg url "https://github.com/$repo/issues/$number" \
                --argjson labels "$labels" \
                --arg updated "$updated_at" \
                '{repo: $repo, number: $number, title: $title, author: $author, url: $url, labels: $labels, updated: $updated}' \
                > "$STATE_DIR/pending-issue-$number.json"

            # Update state
            update_repo_state "$repo" "issues" "$number" "$updated_at" "pending"
        fi
    done

    # Fetch open PRs
    local prs
    prs=$(gh pr list --repo "$repo" --state open --json number,title,updatedAt,author,headRefName 2>/dev/null || echo '[]')

    echo "$prs" | jq -r '.[] | @base64' | while read -r pr_b64; do
        local pr=$(echo "$pr_b64" | base64 -d)
        local number=$(echo "$pr" | jq -r '.number')
        local title=$(echo "$pr" | jq -r '.title')
        local author=$(echo "$pr" | jq -r '.author.login')
        local branch=$(echo "$pr" | jq -r '.headRefName')
        local updated_at=$(echo "$pr" | jq -r '.updatedAt')

        # Only process PRs by bot user
        if [ "$author" = "$BOT_USERNAME" ]; then
            if needs_processing "$repo" "prs" "$number" "$updated_at"; then
                log "  New/updated PR #$number (yours): $title"

                # Create signal file
                jq -n \
                    --arg repo "$repo" \
                    --argjson number "$number" \
                    --arg title "$title" \
                    --arg url "https://github.com/$repo/pull/$number" \
                    --arg branch "$branch" \
                    '{repo: $repo, number: $number, title: $title, url: $url, branch: $branch}' \
                    > "$STATE_DIR/pending-pr.json"

                # Update state
                update_repo_state "$repo" "prs" "$number" "$updated_at" "pending"
            fi
        fi
    done

    update_last_scan "$repo"
}

# Run a single scan (for manual trigger)
run_scan() {
    init_state

    log "=== Starting Scan ==="
    local repos=$(get_repos)

    if [ -z "$repos" ]; then
        log "ERROR: No repos configured"
        return 1
    fi

    for repo in $repos; do
        process_repo "$repo"
    done

    log "=== Scan Complete ==="
}

# Main daemon loop
run_daemon() {
    init_state

    local repos=$(get_repos)

    if [ -z "$repos" ]; then
        log "ERROR: No repos configured"
        return 1
    fi

    log "=== Daemon Started ==="
    log "User: @$BOT_USERNAME"
    log "Poll interval: ${POLL_INTERVAL}s"
    log "Repos: $repos"

    while true; do
        for repo in $repos; do
            process_repo "$repo"
        done

        sleep "$POLL_INTERVAL"
    done
}

case "${1:-}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "Daemon already running (PID: $(cat $PID_FILE))"
            exit 0
        fi
        echo "Starting repo-maintainer daemon..."
        nohup "$0" _run >> "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo "Started (PID: $(cat $PID_FILE))"
        echo "Log: $LOG_FILE"
        ;;

    stop)
        if [ -f "$PID_FILE" ]; then
            kill $(cat "$PID_FILE") 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "Daemon stopped"
        else
            echo "Daemon not running"
        fi
        ;;

    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "Running (PID: $(cat $PID_FILE))"
            echo "Log: $LOG_FILE"
            echo ""
            echo "State:"
            cat "$STATE_FILE" 2>/dev/null | jq '.' || echo "  (no state yet)"
            echo ""
            echo "Pending signals:"
            ls -la "$STATE_DIR"/*.json 2>/dev/null | grep -v state.json || echo "  (none)"
        else
            echo "Not running"
        fi
        ;;

    scan)
        # Manual single scan
        run_scan
        echo "Scan complete. Check $STATE_DIR for signal files."
        ;;

    _run)
        run_daemon
        ;;

    *)
        echo "Usage: $0 {start|stop|status|scan}"
        exit 1
        ;;
esac
