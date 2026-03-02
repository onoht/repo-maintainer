#!/bin/bash
# GitHub Notification Daemon for Repo Maintainer
# Polls GitHub notifications and creates signal files for main agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="/data/.clawdbot/repo-maintainer"
PID_FILE="$STATE_DIR/daemon.pid"
LOG_FILE="$STATE_DIR/daemon.log"
CONFIG_FILE="${REPO_MAINTAINER_CONFIG:-$HOME/.config/repo-maintainer/repos.yaml}"

# Defaults
POLL_INTERVAL=${POLL_INTERVAL:-60}

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

# API helper
gh_api() {
    curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
}

log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Get repos from config or auto-detect from GitHub
get_repos() {
    if [ -f "$CONFIG_FILE" ]; then
        # Extract repo names from config (lines with "owner/repo:" pattern)
        grep -oE '[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+:' "$CONFIG_FILE" | sed 's/:$//' | tr '\n' ' '
    else
        # Auto-detect: get repos owned by user
        log "Auto-detecting repos for @$BOT_USERNAME..."
        gh api "users/$BOT_USERNAME/repos?per_page=100&type=owner" \
            --jq '.[].full_name' 2>/dev/null | tr '\n' ' '
    fi
}

# Generate default config if missing
ensure_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        log "Creating default config at $CONFIG_FILE"
        
        # Get repos first
        local repos
        repos=$(get_repos)
        
        # Build config
        {
            echo "# Repo Maintainer Config"
            echo "# Auto-generated for @$BOT_USERNAME"
            echo ""
            echo "repos:"
            for repo in $repos; do
                [ -z "$repo" ] && continue
                cat << REPO
  $repo:
    issues:
      auto_label: true
      stale_days: 30
    prs:
      auto_merge: true
      require_tests: true
REPO
            done
            echo ""
            echo "daemon:"
            echo "  poll_interval: 60"
        } > "$CONFIG_FILE"
        
        local count=$(echo "$repos" | wc -w)
        log "Config created with $count repos"
    fi
}

REPOS=$(get_repos)

is_processed() {
    local id="$1"
    grep -q "^$id$" "$STATE_DIR/processed-notifications" 2>/dev/null
}

mark_processed() {
    local id="$1"
    echo "$id" >> "$STATE_DIR/processed-notifications"
    tail -1000 "$STATE_DIR/processed-notifications" > "$STATE_DIR/processed.tmp"
    mv "$STATE_DIR/processed.tmp" "$STATE_DIR/processed-notifications"
}

process_notification() {
    local notif="$1"
    local id=$(echo "$notif" | jq -r '.id')
    local reason=$(echo "$notif" | jq -r '.reason')
    local repo=$(echo "$notif" | jq -r '.repository.full_name')
    local subject_type=$(echo "$notif" | jq -r '.subject.type')
    local subject_url=$(echo "$notif" | jq -r '.subject.url')
    local subject_title=$(echo "$notif" | jq -r '.subject.title')
    
    # Skip if not in our repos
    local in_repos=false
    for r in $REPOS; do
        [ "$r" = "$repo" ] && in_repos=true && break
    done
    [ "$in_repos" = false ] && return 0
    
    log "[$subject_type] $subject_title in $repo"
    
    case "$subject_type" in
        "PullRequest")
            local pr_data=$(gh_api "$subject_url")
            local pr_number=$(echo "$pr_data" | jq -r '.number')
            local pr_user=$(echo "$pr_data" | jq -r '.user.login')
            local pr_state=$(echo "$pr_data" | jq -r '.state')
            local pr_url=$(echo "$pr_data" | jq -r '.html_url')
            
            if [ "$pr_user" = "$BOT_USERNAME" ] && [ "$pr_state" = "open" ]; then
                log "  → Pending PR #$pr_number"
                jq -n \
                    --arg repo "$repo" \
                    --argjson number "$pr_number" \
                    --arg title "$subject_title" \
                    --arg url "$pr_url" \
                    '{repo: $repo, number: $number, title: $title, url: $url}' \
                    > "$STATE_DIR/pending-pr.json"
            fi
            ;;
            
        "Issue")
            local issue_data=$(gh_api "$subject_url")
            local issue_number=$(echo "$issue_data" | jq -r '.number')
            local issue_user=$(echo "$issue_data" | jq -r '.user.login')
            local issue_url=$(echo "$issue_data" | jq -r '.html_url')
            local labels=$(echo "$issue_data" | jq '[.labels[].name]')
            
            log "  → Issue #$issue_number by $issue_user"
            jq -n \
                --arg repo "$repo" \
                --argjson number "$issue_number" \
                --arg title "$subject_title" \
                --arg author "$issue_user" \
                --arg url "$issue_url" \
                --argjson labels "$labels" \
                '{repo: $repo, number: $number, title: $title, author: $author, url: $url, labels: $labels}' \
                > "$STATE_DIR/pending-issue-$issue_number.json"
            ;;
            
        "PullRequestReview"|"PullRequestReviewComment")
            log "  → Review activity"
            touch "$STATE_DIR/pending-review"
            ;;
            
        "IssueComment")
            # Check if it's on an issue we're tracking
            log "  → Comment activity"
            touch "$STATE_DIR/new-activity"
            ;;
    esac
    
    mark_processed "$id"
}

run_daemon() {
    ensure_config
    REPOS=$(get_repos)
    
    log "=== Daemon Started ==="
    log "User: @$BOT_USERNAME"
    log "Poll interval: ${POLL_INTERVAL}s"
    log "Repos: $REPOS"
    
    while true; do
        local since=$(date -u -d '5 minutes ago' -Iseconds 2>/dev/null || date -u -v-5M -Iseconds)
        local notifications=$(gh_api "https://api.github.com/notifications?since=$since&per_page=50" | jq -r '.[] | @base64')
        
        local count=0
        while read -r notif_b64; do
            [ -z "$notif_b64" ] && continue
            
            local notif=$(echo "$notif_b64" | base64 -d)
            local id=$(echo "$notif" | jq -r '.id')
            
            is_processed "$id" && continue
            
            process_notification "$notif"
            ((count++))
        done <<< "$notifications"
        
        [ $count -gt 0 ] && log "Processed $count notifications"
        
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
            echo "Pending signals:"
            ls -la "$STATE_DIR"/*.json 2>/dev/null || echo "  (none)"
        else
            echo "Not running"
        fi
        ;;
        
    _run)
        run_daemon
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
