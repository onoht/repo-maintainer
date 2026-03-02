# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                            │
│                                                                      │
│  • Issues        • Pull Requests        • Reviews        • Comments │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            │ Notifications API
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Daemon (daemon.sh)                           │
│                         Poll every 60 seconds                        │
│                                                                      │
│  1. Fetch notifications from GitHub API                              │
│  2. Filter for monitored repos                                       │
│  3. Create signal files                                              │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            │ Signal Files
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Signal Files Directory                            │
│                 /data/.clawdbot/repo-maintainer/                     │
│                                                                      │
│  • pending-issue-N.json    → New issue needs triage                  │
│  • pending-pr.json         → PR needs verification                   │
│  • pending-review          → Review needs response                   │
│  • new-activity            → Comments need checking                  │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            │ Read by OpenClaw
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          OpenClaw Main Agent                         │
│                                                                      │
│  1. Detect signal file                                               │
│  2. Decide action based on type                                      │
│  3. Execute or delegate                                              │
└──────────┬──────────────────────────────────────┬───────────────────┘
           │                                      │
           │ Direct Action                        │ Spawn Subagent
           ▼                                      ▼
┌──────────────────────┐              ┌──────────────────────┐
│  Simple Actions      │              │   Complex Actions    │
│                      │              │                      │
│  • Apply labels      │              │  • Fix issue         │
│  • Merge PR          │              │  • Run tests         │
│  • Add comment       │              │  • Create PR         │
└──────────────────────┘              └──────────────────────┘
```

## Component Details

### 1. Daemon (daemon.sh)

**Purpose**: Poll GitHub notifications and create signal files

**Flow**:
```
Start
  ↓
Check GH_TOKEN
  ↓
Get bot username (gh auth)
  ↓
Load/create config (repos.yaml)
  ↓
Get monitored repos
  ↓
┌─────────────┐
│  Main Loop  │◄───────────┐
└──────┬──────┘            │
       ↓                   │
Fetch notifications        │
(since 5 min ago)          │
       ↓                   │
For each notification:     │
  - Check if processed     │
  - Check if in our repos  │
  - Create signal file     │
  - Mark as processed      │
       ↓                   │
Sleep POLL_INTERVAL        │
       └───────────────────┘
```

**Signal File Creation**:

```python
# Issue opened
if subject_type == "Issue":
    create_file(f"pending-issue-{number}.json", {
        "repo": repo,
        "number": number,
        "title": title,
        "author": author,
        "labels": labels
    })

# PR by bot user
if subject_type == "PullRequest" and author == BOT_USERNAME:
    create_file("pending-pr.json", {
        "repo": repo,
        "number": number,
        "title": title
    })

# Review activity
if subject_type in ["PullRequestReview", "PullRequestReviewComment"]:
    create_file("pending-review")
```

### 2. Issue Triage (triage.py)

**Purpose**: Analyze and classify issues

**Flow**:
```
Read issue (title + body)
  ↓
Detect labels
  - Match against patterns
  - Calculate confidence
  ↓
Detect priority
  - Check for P0-P3 indicators
  - Default to P2
  ↓
Check if clarification needed
  - Too short?
  - Missing repro steps?
  - Missing version info?
  ↓
Output:
  - Suggested labels
  - Priority
  - Clarification questions
  ↓
Apply (if --apply flag)
  ↓
Comment (if --comment flag)
```

**Label Detection Algorithm**:

```python
def detect_labels(text):
    matches = {}
    for label, patterns in LABEL_PATTERNS.items():
        count = sum(1 for p in patterns if re.search(p, text.lower()))
        if count > 0:
            matches[label] = count
    
    # Return top 2 labels
    sorted_labels = sorted(matches.items(), key=lambda x: -x[1])
    return [l for l, _ in sorted_labels[:2]]
```

### 3. PR Verification (verify-pr.sh)

**Purpose**: Build and test PRs

**Flow**:
```
Clone/update repo
  ↓
Checkout PR branch
  ↓
Detect project type:
  - Cargo.toml      → Rust
  - package.json    → Node.js
  - pyproject.toml  → Python
  - Makefile        → Make
  - (none)          → Static
  ↓
Run verification:
  - Rust:   cargo build && cargo test
  - Node:   npm install && npm test
  - Python: pytest
  - Make:   make test
  - Static: (skip)
  ↓
Result:
  - Pass → Ready to merge
  - Fail → DO NOT MERGE
```

**Project Detection**:

```bash
if [ -f "Cargo.toml" ]; then
    # Rust project
    cargo build --quiet && cargo test --quiet
elif [ -f "package.json" ]; then
    # Node.js project
    npm install --quiet && npm test
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    # Python project
    pytest
elif [ -f "Makefile" ]; then
    # Makefile project
    make test
else
    # Static content
    echo "No verification required"
fi
```

## Data Flow

### Issue → Triage → Fix

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User opens issue                                              │
│    "App crashes when clicking button"                            │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Daemon detects notification                                   │
│    Creates: pending-issue-42.json                                │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Main agent reads signal file                                  │
│    Calls: triage.py --repo owner/repo --issue 42 --apply         │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. triage.py analyzes issue                                      │
│    - Detected labels: ["bug"]                                    │
│    - Priority: P1                                                │
│    - Needs clarification: Yes                                    │
│      - "What are the steps to reproduce?"                        │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Main agent adds comment                                       │
│    "Thanks for opening this issue! Could you provide..."         │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. User responds with details                                    │
│    Main agent spawns subagent to fix                             │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. Subagent fixes issue, opens PR                                │
│    PR #43: "Fix button crash"                                    │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. Daemon detects PR by bot                                      │
│    Creates: pending-pr.json                                      │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 9. Main agent verifies PR                                        │
│    Calls: verify-pr.sh owner/repo 43                             │
│    Result: ✅ PASSED                                             │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ 10. Main agent merges PR                                         │
│     gh pr merge 43 --squash --delete-branch                      │
└─────────────────────────────────────────────────────────────────┘
```

## State Management

### File Locations

| Path | Purpose |
|------|---------|
| `~/.config/repo-maintainer/repos.yaml` | Configuration |
| `/data/.clawdbot/repo-maintainer/daemon.pid` | Daemon PID |
| `/data/.clawdbot/repo-maintainer/daemon.log` | Daemon log |
| `/data/.clawdbot/repo-maintainer/pending-*.json` | Signal files |
| `/data/.clawdbot/repo-maintainer/processed-notifications` | Processed IDs |
| `/tmp/repo-maintainer-work/` | PR checkout directory |

### Signal File Lifecycle

```
1. Created by daemon when notification received
   ↓
2. Read by main agent
   ↓
3. Processed by main agent or subagent
   ↓
4. Deleted after processing (or left for audit)
```

### Configuration Auto-Generation

```
First run
  ↓
Check if config exists
  ↓ (No)
Get repos from GitHub API
  ↓
Generate default config
  ↓
Write to ~/.config/repo-maintainer/repos.yaml
  ↓
Use generated config
```

## Error Handling

### Daemon Errors

```bash
# GH_TOKEN missing
if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GH_TOKEN not found. Run 'gh auth login' first." >&2
    exit 1
fi

# API errors
gh_api() {
    curl -s -H "Authorization: Bearer $GITHUB_TOKEN" ...
}

# Log all errors
log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}
```

### Triage Errors

```python
# Issue fetch failed
if result.returncode != 0:
    print(f"Error fetching issue: {result.stderr}", file=sys.stderr)
    return None

# JSON parse failed
try:
    data = json.loads(result.stdout)
except json.JSONDecodeError:
    print("Error parsing issue data", file=sys.stderr)
    return None
```

### Verification Errors

```bash
# Build failed
if ! cargo build --quiet 2>&1; then
    VERIFY_OK=false
    VERIFY_MSG="Build failed"
    echo "❌ Build failed"
fi

# Tests failed
if ! npm test 2>&1; then
    VERIFY_OK=false
    VERIFY_MSG="Tests failed"
    echo "❌ Tests failed"
fi
```

## Performance Considerations

### Polling Interval

- Default: 60 seconds
- Configurable: `POLL_INTERVAL` env var or `daemon.poll_interval` in config
- Balance between responsiveness and API rate limits

### Notification Processing

- Only fetch notifications from last 5 minutes
- Keep processed notification IDs (last 1000)
- Skip already-processed notifications

### PR Verification

- Clone repos once, reuse for multiple PRs
- Work directory: `/tmp/repo-maintainer-work/`
- Clean checkout per PR

## Security

### Authentication

- Uses `gh auth login` for GitHub authentication
- Token stored in `GH_TOKEN` env var or retrieved via `gh auth token`
- Never hardcode tokens

### API Rate Limits

- GitHub API: 5000 requests/hour (authenticated)
- Daemon: ~60 requests/hour (1 per poll)
- Well within limits

### File Permissions

- State directory: `/data/.clawdbot/repo-maintainer/`
- Config: `~/.config/repo-maintainer/repos.yaml`
- Standard user permissions (no elevated access needed)

## Scalability

### Single User

- One daemon per user
- Monitors user's repos
- Single GitHub account

### Multi-Repo

- No hard limit on monitored repos
- Config file lists all repos
- Process one notification at a time

### Performance

- Lightweight: ~2-5 MB RAM
- Minimal CPU: Only when processing notifications
- I/O: Only when writing signal files

## Extensibility

### Adding New Project Types

Edit `verify-pr.sh`:

```bash
elif [ -f "go.mod" ]; then
    echo "Go project detected"
    go test ./...
```

### Adding New Label Patterns

Edit `triage.py`:

```python
LABEL_PATTERNS = {
    "bug": [...],
    "enhancement": [...],
    "ui": [
        r"\bui\b", r"\binterface\b", r"\bdesign\b"
    ]
}
```

### Adding New Workflows

1. Add detection logic to `daemon.sh`
2. Create new signal file type
3. Add handling in main agent
4. Document in `workflows.md`
