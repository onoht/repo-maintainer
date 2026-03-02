# Repo Maintainer

Fully autonomous GitHub repository maintenance for OpenClaw.

**Status**: Production-ready ✅  
**Type**: OpenClaw Skill  
**License**: MIT

---

## Overview

Repo Maintainer is an autonomous GitHub repository maintenance system that runs as a daemon and handles:

- **Issue Triage**: Auto-labels issues, detects priority, and asks clarifying questions
- **PR Verification**: Checks out, builds, and tests your PRs before auto-merging
- **Review Response**: Automatically addresses PR review comments
- **Stale Management**: Labels and closes stale issues

**Fully autonomous** — no human approval needed. The daemon monitors your GitHub notifications and takes action automatically.

---

## Features

✅ **Multi-tenant**: Works for any GitHub user  
✅ **Auto-labeling**: Smart issue classification with configurable patterns  
✅ **Priority Detection**: P0-P3 classification based on issue content  
✅ **Test Verification**: Supports Rust, Node.js, Python, and Makefile projects  
✅ **Subagent Delegation**: Spawns subagents to fix issues automatically  
✅ **Signal-based Architecture**: Lightweight daemon that creates signal files for the main agent

---

## Quick Start

### Prerequisites

- OpenClaw installed ([docs.openclaw.ai](https://docs.openclaw.ai))
- GitHub CLI (`gh`) installed and authenticated
- Python 3.7+ (for triage script)

### Installation

#### Option 1: Install as OpenClaw Skill

```bash
# Clone to your workspace skills directory
cd ~/.openclaw/workspace/skills
git clone https://github.com/onoht/repo-maintainer.git

# The skill will be automatically loaded by OpenClaw
```

#### Option 2: Standalone Clone

```bash
git clone https://github.com/onoht/repo-maintainer.git
cd repo-maintainer
```

### Setup

1. **Authenticate with GitHub**:
   ```bash
   gh auth login
   gh auth status  # Verify
   ```

2. **Start the daemon**:
   ```bash
   ~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh start
   ```

3. **Check status**:
   ```bash
   ~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh status
   ```

4. **View logs**:
   ```bash
   tail -f /data/.clawdbot/repo-maintainer/daemon.log
   ```

**That's it!** The daemon will:
- Auto-detect your GitHub repos on first run
- Create a default config at `~/.config/repo-maintainer/repos.yaml`
- Start monitoring for notifications every 60 seconds

---

## How It Works

### Architecture

```
GitHub Notifications → Daemon (60s) → Signal Files → Main Agent → Subagents
```

1. **Daemon** polls GitHub notifications every 60 seconds
2. **Signal files** are created in `/data/.clawdbot/repo-maintainer/`
3. **Main agent** reads signal files and decides what to do
4. **Subagents** are spawned to handle complex tasks (like fixing issues)

### Signal Files

| File | Meaning | Auto-Action |
|------|---------|-------------|
| `pending-pr.json` | New PR by you | Verify + merge |
| `pending-issue-*.json` | New issue | Triage + fix |
| `pending-review` | PR review | Address comments |
| `new-activity` | Comments | Respond if needed |

### Workflows

#### Issue → Triage → Fix

```
New Issue Detected
       ↓
Auto-label (bug/enhancement/docs)
       ↓
Assess Priority (P0-P3)
       ↓
Check for clarification needed
       ↓
If actionable: Spawn subagent to fix
       ↓
Subagent opens PR
```

#### PR → Verify → Merge

```
Your PR Detected
       ↓
Checkout locally
       ↓
Detect project type
       ↓
Run tests (Rust/Node/Python/Make)
       ↓
If passing: Merge (squash)
If failing: Comment, don't merge
```

---

## Configuration

Config file: `~/.config/repo-maintainer/repos.yaml`

### Basic Example

```yaml
repos:
  yourname/project-a:
    issues:
      auto_label: true
      stale_days: 30
    prs:
      auto_merge: true
      require_tests: true

  yourname/project-b:
    issues:
      auto_label: true
    prs:
      auto_merge: true
      require_tests: false  # Static site, no tests

daemon:
  poll_interval: 60
  log_level: info
```

### Advanced Example

See [assets/repos.yaml.example](assets/repos.yaml.example) for a complete example with:
- Multiple repos
- Custom label patterns
- Priority patterns
- Notification settings

### Key Settings

#### Repo Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `issues.enabled` | boolean | true | Process issues for this repo |
| `issues.auto_label` | boolean | true | Auto-label new issues |
| `issues.stale_days` | integer | 30 | Days before issue is stale |
| `prs.auto_merge_owner` | boolean | true | Auto-merge your own PRs |
| `prs.require_tests` | boolean | true | Require tests to pass |

#### Daemon Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `daemon.poll_interval` | integer | 60 | Seconds between polls |
| `daemon.log_level` | string | info | Log level (debug/info/warn/error) |

#### Custom Labels

```yaml
labels:
  bug:
    - "error"
    - "crash"
    - "doesn't work"
    - "\\bbug\\b"
  enhancement:
    - "feature"
    - "add support"
    - "would be nice"
```

Patterns are regex-compatible.

#### Custom Priorities

```yaml
priority:
  P0:  # Critical
    - "security"
    - "data loss"
    - "production down"
  P1:  # High
    - "regression"
    - "breaking change"
  P3:  # Low
    - "nice to have"
    - "minor"
```

---

## Scripts

### daemon.sh

Main notification polling daemon.

```bash
# Start daemon
./scripts/daemon.sh start

# Check status
./scripts/daemon.sh status

# Stop daemon
./scripts/daemon.sh stop
```

### verify-pr.sh

Verify a PR by building and testing.

```bash
./scripts/verify-pr.sh owner/repo 42
```

Supports:
- **Rust**: `cargo build && cargo test`
- **Node.js**: `npm install && npm test`
- **Python**: `pytest`
- **Makefile**: `make test`
- **Static**: No verification

### triage.py

Analyze and classify issues.

```bash
# Analyze issue
python3 scripts/triage.py owner/repo --issue 42

# Analyze and apply labels
python3 scripts/triage.py owner/repo --issue 42 --apply

# Output as JSON
python3 scripts/triage.py owner/repo --issue 42 --json
```

---

## Examples

### Example 1: Monitor Multiple Repos

```yaml
repos:
  yourname/api:
    issues:
      auto_label: true
      triage: true
    prs:
      auto_merge: true
      require_tests: true

  yourname/web:
    issues:
      auto_label: true
    prs:
      auto_merge: true
      require_tests: true

  yourname/docs:
    issues:
      enabled: false  # Docs don't use issues
    prs:
      auto_merge: true
      require_tests: false
```

### Example 2: Custom Label Detection

```yaml
repos:
  yourname/project:
    issues:
      auto_label: true

# Override default patterns
labels:
  bug:
    - "\\bbug\\b"
    - "\\berror\\b"
    - "\\bcrash\\b"
    - "\\bexception\\b"
  enhancement:
    - "\\bfeature\\b"
    - "\\badd\\b"
    - "\\brequest\\b"
  documentation:
    - "\\bdocs?\\b"
    - "\\breadme\\b"
    - "\\bexample\\b"
```

### Example 3: Priority-Based Triage

```yaml
repos:
  yourname/critical-app:
    issues:
      auto_label: true
      triage: true

priority:
  P0:  # Immediate attention
    - "security"
    - "outage"
    - "data loss"
    - "production down"
  P1:  # Fix within 24h
    - "regression"
    - "breaking change"
```

---

## Project Structure

```
repo-maintainer/
├── SKILL.md                  # OpenClaw skill definition
├── README.md                 # This file
├── LICENSE                   # MIT License
├── scripts/
│   ├── daemon.sh            # Notification polling daemon
│   ├── verify-pr.sh         # PR verification script
│   └── triage.py            # Issue triage script
├── references/
│   ├── workflows.md         # Detailed workflow diagrams
│   └── config-schema.md     # Full config documentation
└── assets/
    └── repos.yaml.example   # Example configuration
```

---

## Integration with OpenClaw

### As a Skill

When installed in `~/.openclaw/workspace/skills/repo-maintainer/`, the skill provides:

1. **Automatic trigger**: Polling daemon creates signal files
2. **Main agent integration**: Agent reads signals and takes action
3. **Subagent spawning**: Complex tasks delegated to subagents
4. **Seamless workflow**: Issues → Triage → Fix → PR → Merge

### Manual Usage

You can also use the scripts standalone:

```bash
# Triage a specific issue
python3 scripts/triage.py owner/repo --issue 42 --apply

# Verify a specific PR
./scripts/verify-pr.sh owner/repo 55
```

---

## Troubleshooting

### Daemon not starting

```bash
# Check GitHub auth
gh auth status

# Check logs
tail -f /data/.clawdbot/repo-maintainer/daemon.log
```

### No repos detected

```bash
# Manually create config
mkdir -p ~/.config/repo-maintainer
cat > ~/.config/repo-maintainer/repos.yaml << EOF
repos:
  yourname/repo:
    issues:
      auto_label: true
    prs:
      auto_merge: true
EOF
```

### Tests failing on PR verification

Check the verification output:

```bash
# Run verification manually
./scripts/verify-pr.sh owner/repo 42
```

---

## Limitations

- **GitHub only**: Works with GitHub repositories only (not GitLab, Bitbucket, etc.)
- **Poll-based**: Uses polling (60s default), not webhooks
- **Single user**: Each user runs their own daemon
- **No bulk operations**: One event at a time, sequential processing

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

All PRs are automatically verified and merged if tests pass.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Credits

Built for [OpenClaw](https://openclaw.ai) - your personal AI assistant.

Inspired by the need for fully autonomous repository maintenance without human approval gates.

---

## Links

- **Repository**: [github.com/onoht/repo-maintainer](https://github.com/onoht/repo-maintainer)
- **OpenClaw**: [openclaw.ai](https://openclaw.ai)
- **Documentation**: [docs.openclaw.ai](https://docs.openclaw.ai)
- **Issues**: [github.com/onoht/repo-maintainer/issues](https://github.com/onoht/repo-maintainer/issues)

---

## Changelog

### v1.0.0 (2026-03-02)

- Initial release
- Auto-issue triage with labeling
- PR verification and auto-merge
- Review response automation
- Stale issue management
- Multi-tenant support
- Subagent delegation
