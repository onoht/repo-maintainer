#!/bin/bash
# Manual trigger - Scan all configured repos for open issues and PRs
# Creates signal files for the main agent to process

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="/data/.clawdbot/repo-maintainer"
CONFIG_FILE="${REPO_MAINTAINER_CONFIG:-$HOME/.config/repo-maintainer/repos.yaml}"

mkdir -p "$STATE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get bot username
BOT_USERNAME=$(gh api user --jq '.login' 2>/dev/null)
if [ -z "$BOT_USERNAME" ]; then
    echo -e "${RED}ERROR: Not authenticated. Run 'gh auth login' first.${NC}"
    exit 1
fi

# Get repos from config
get_repos() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -oE '[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+:' "$CONFIG_FILE" | sed 's/:$//'
    else
        echo "ERROR: Config not found at $CONFIG_FILE" >&2
        echo "Run the daemon first to auto-generate config, or create manually." >&2
        exit 1
    fi
}

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Repo Maintainer - Manual Scan${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "User: ${GREEN}@$BOT_USERNAME${NC}"
echo -e "Config: ${YELLOW}$CONFIG_FILE${NC}"
echo ""

REPOS=$(get_repos)
if [ -z "$REPOS" ]; then
    echo -e "${RED}No repos configured.${NC}"
    exit 1
fi

TOTAL_ISSUES=0
TOTAL_PRS=0
YOUR_PRS=0

for REPO in $REPOS; do
    echo -e "\n${BLUE}▶ $REPO${NC}"
    echo "  Scanning..."
    
    # Fetch open issues
    ISSUES=$(gh issue list --repo "$REPO" --state open --json number,title,updatedAt,author,labels --jq '.[] | @base64' 2>/dev/null || true)
    
    ISSUE_COUNT=0
    while IFS= read -r issue_b64; do
        [ -z "$issue_b64" ] && continue
        
        ISSUE=$(echo "$issue_b64" | base64 -d)
        NUMBER=$(echo "$ISSUE" | jq -r '.number')
        TITLE=$(echo "$ISSUE" | jq -r '.title')
        AUTHOR=$(echo "$ISSUE" | jq -r '.author.login')
        LABELS=$(echo "$ISSUE" | jq '[.labels[].name]')
        UPDATED=$(echo "$ISSUE" | jq -r '.updatedAt')
        
        # Create signal file
        jq -n \
            --arg repo "$REPO" \
            --argjson number "$NUMBER" \
            --arg title "$TITLE" \
            --arg author "$AUTHOR" \
            --arg url "https://github.com/$REPO/issues/$NUMBER" \
            --argjson labels "$LABELS" \
            --arg updated "$UPDATED" \
            '{repo: $repo, number: $number, title: $title, author: $author, url: $url, labels: $labels, updated: $updated}' \
            > "$STATE_DIR/pending-issue-$NUMBER.json"
        
        echo -e "  ${YELLOW}Issue #$NUMBER${NC}: $TITLE ${YELLOW}[@$AUTHOR]${NC}"
        ((ISSUE_COUNT++))
        ((TOTAL_ISSUES++))
    done <<< "$ISSUES"
    
    # Fetch open PRs
    PRS=$(gh pr list --repo "$REPO" --state open --json number,title,author,headRefName --jq '.[] | @base64' 2>/dev/null || true)
    
    PR_COUNT=0
    while IFS= read -r pr_b64; do
        [ -z "$pr_b64" ] && continue
        
        PR=$(echo "$pr_b64" | base64 -d)
        NUMBER=$(echo "$PR" | jq -r '.number')
        TITLE=$(echo "$PR" | jq -r '.title')
        AUTHOR=$(echo "$PR" | jq -r '.author.login')
        BRANCH=$(echo "$PR" | jq -r '.headRefName')
        
        if [ "$AUTHOR" = "$BOT_USERNAME" ]; then
            # Create signal file for your PR
            jq -n \
                --arg repo "$REPO" \
                --argjson number "$NUMBER" \
                --arg title "$TITLE" \
                --arg url "https://github.com/$REPO/pull/$NUMBER" \
                --arg branch "$BRANCH" \
                '{repo: $repo, number: $number, title: $title, url: $url, branch: $branch}' \
                > "$STATE_DIR/pending-pr.json"
            
            echo -e "  ${GREEN}PR #$NUMBER${NC} (YOURS): $TITLE ${GREEN}[$BRANCH]${NC}"
            ((YOUR_PRS++))
        else
            echo -e "  ${BLUE}PR #$NUMBER${NC}: $TITLE ${BLUE}[@$AUTHOR]${NC}"
        fi
        
        ((PR_COUNT++))
        ((TOTAL_PRS++))
    done <<< "$PRS"
    
    if [ $ISSUE_COUNT -eq 0 ] && [ $PR_COUNT -eq 0 ]; then
        echo -e "  ${GREEN}✓ No open issues or PRs${NC}"
    fi
done

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Issues found:  ${YELLOW}$TOTAL_ISSUES${NC}"
echo -e "  PRs found:     ${YELLOW}$TOTAL_PRS${NC}"
echo -e "  Your PRs:      ${GREEN}$YOUR_PRS${NC}"
echo ""

if [ $TOTAL_ISSUES -gt 0 ] || [ $YOUR_PRS -gt 0 ]; then
    echo -e "${GREEN}Signal files created in: $STATE_DIR/${NC}"
    echo ""
    echo "Next steps:"
    echo "  - Main agent will process on next heartbeat"
    echo "  - Or manually: ls $STATE_DIR/pending-*.json"
else
    echo -e "${GREEN}Nothing to process.${NC}"
fi
