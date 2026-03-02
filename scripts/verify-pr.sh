#!/bin/bash
# Verify a PR by checking it out, building, and running tests

set -euo pipefail

REPO="${1:-}"
PR_NUMBER="${2:-}"
WORK_DIR="${WORK_DIR:-/tmp/repo-maintainer-work}"

if [ -z "$REPO" ] || [ -z "$PR_NUMBER" ]; then
    echo "Usage: $0 <owner/repo> <pr-number>"
    exit 1
fi

REPO_NAME="${REPO#*/}"
WORK_DIR="$WORK_DIR/$REPO_NAME"

echo "=== Verifying PR #$PR_NUMBER in $REPO ==="

# Clone or update
if [ -d "$WORK_DIR" ]; then
    cd "$WORK_DIR"
    git fetch origin
else
    git clone "https://github.com/$REPO.git" "$WORK_DIR"
    cd "$WORK_DIR"
fi

# Checkout PR
echo "Checking out PR #$PR_NUMBER..."
gh pr checkout "$PR_NUMBER" --repo "$REPO"

# Get PR info
PR_TITLE=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title -q '.title')
PR_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Branch: $PR_BRANCH"
echo "Title: $PR_TITLE"

# Detect project type and verify
echo ""
echo "=== Detecting project type ==="

VERIFY_OK=true
VERIFY_MSG=""

if [ -f "Cargo.toml" ]; then
    echo "Rust project detected"
    echo ""
    echo "Running: cargo build"
    if cargo build --quiet 2>&1; then
        echo "✅ Build succeeded"
    else
        VERIFY_OK=false
        VERIFY_MSG="Build failed"
        echo "❌ Build failed"
    fi
    
    if [ "$VERIFY_OK" = true ]; then
        echo ""
        echo "Running: cargo test"
        if cargo test --quiet 2>&1; then
            echo "✅ Tests passed"
        else
            VERIFY_OK=false
            VERIFY_MSG="Tests failed"
            echo "❌ Tests failed"
        fi
    fi

elif [ -f "package.json" ]; then
    echo "Node.js project detected"
    echo ""
    echo "Running: npm install"
    if npm install --quiet 2>&1; then
        echo "✅ Dependencies installed"
    else
        VERIFY_OK=false
        VERIFY_MSG="npm install failed"
        echo "❌ Install failed"
    fi
    
    if [ "$VERIFY_OK" = true ]; then
        # Check if test script exists
        HAS_TEST=$(node -e "const p=require('./package.json'); console.log(p.scripts && p.scripts.test ? 'yes' : 'no')")
        
        if [ "$HAS_TEST" = "yes" ]; then
            echo ""
            echo "Running: npm test"
            if npm test 2>&1; then
                echo "✅ Tests passed"
            else
                VERIFY_OK=false
                VERIFY_MSG="Tests failed"
                echo "❌ Tests failed"
            fi
        else
            echo "⚠️  No test script found, skipping tests"
        fi
    fi

elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
    echo "Python project detected"
    
    # Try pytest
    if command -v pytest &>/dev/null; then
        echo ""
        echo "Running: pytest"
        if pytest 2>&1; then
            echo "✅ Tests passed"
        else
            VERIFY_OK=false
            VERIFY_MSG="Tests failed"
            echo "❌ Tests failed"
        fi
    else
        echo "⚠️  pytest not installed, skipping tests"
    fi

elif [ -f "Makefile" ]; then
    echo "Makefile project detected"
    
    # Check for test target
    if grep -q "^test:" Makefile; then
        echo ""
        echo "Running: make test"
        if make test 2>&1; then
            echo "✅ Tests passed"
        else
            VERIFY_OK=false
            VERIFY_MSG="Tests failed"
            echo "❌ Tests failed"
        fi
    else
        echo "⚠️  No test target in Makefile"
    fi

else
    echo "No build system detected (static content or unknown)"
    echo "✅ No verification required"
fi

# Output result
echo ""
echo "=== Verification Result ==="

if [ "$VERIFY_OK" = true ]; then
    echo "✅ PASSED - PR is ready to merge"
    echo ""
    echo "To merge:"
    echo "  gh pr merge $PR_NUMBER --repo $REPO --squash --delete-branch"
    exit 0
else
    echo "❌ FAILED - $VERIFY_MSG"
    echo ""
    echo "DO NOT MERGE - verification failed"
    exit 1
fi
