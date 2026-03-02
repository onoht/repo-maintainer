# Quick Start Guide

Get up and running with Repo Maintainer in 5 minutes.

## Prerequisites

- [OpenClaw](https://docs.openclaw.ai/start/getting-started) installed
- [GitHub CLI](https://cli.github.com/) installed
- Python 3.7+

## Installation

### Option 1: As OpenClaw Skill (Recommended)

```bash
# Navigate to skills directory
cd ~/.openclaw/workspace/skills

# Clone the repository
git clone https://github.com/onoht/repo-maintainer.git

# Done! The skill is now available to OpenClaw
```

### Option 2: Standalone

```bash
# Clone anywhere
git clone https://github.com/onoht/repo-maintainer.git
cd repo-maintainer
```

## Setup

### 1. Authenticate with GitHub

```bash
# Login to GitHub
gh auth login

# Verify authentication
gh auth status
```

Expected output:
```
✓ Logged in to github.com as yourname (~/.config/gh/hosts.yml)
✓ Git operations for github.com configured to use https protocol
✓ Token: gho_xxxxxxxxxxxx
```

### 2. Start the Daemon

```bash
# If installed as skill
~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh start

# If standalone
./scripts/daemon.sh start
```

Expected output:
```
Starting repo-maintainer daemon...
Started (PID: 12345)
Log: /data/.clawdbot/repo-maintainer/daemon.log
```

### 3. Check Status

```bash
./scripts/daemon.sh status
```

Expected output:
```
Running (PID: 12345)
Log: /data/.clawdbot/repo-maintainer/daemon.log

Pending signals:
  (none)
```

### 4. View Configuration

```bash
# Config auto-created on first run
cat ~/.config/repo-maintainer/repos.yaml
```

## What Happens Next

The daemon will now:

1. **Poll GitHub every 60 seconds** for new notifications
2. **Auto-detect your repos** (from GitHub API)
3. **Create signal files** when events occur
4. **OpenClaw processes signals** and takes action

## Testing It Out

### Test Issue Triage

1. **Open an issue** in one of your monitored repos:
   ```bash
   gh issue create --repo yourname/yourrepo \
     --title "Bug: Button not working" \
     --body "The submit button doesn't respond to clicks."
   ```

2. **Wait 60 seconds** for the daemon to detect it

3. **Check the signal file**:
   ```bash
   cat /data/.clawdbot/repo-maintainer/pending-issue-*.json
   ```

4. **View daemon log**:
   ```bash
   tail -f /data/.clawdbot/repo-maintainer/daemon.log
   ```

5. **Check the issue** - it should be labeled automatically:
   ```bash
   gh issue view 42 --repo yourname/yourrepo
   ```

### Test PR Verification

1. **Create a PR** (using your bot account):
   ```bash
   # Make a change
   echo "# Test" >> README.md
   git add README.md
   git commit -m "Test PR"
   git push origin test-branch
   
   # Create PR
   gh pr create --title "Test PR" --body "Testing auto-merge"
   ```

2. **Wait 60 seconds** for the daemon

3. **Check signal file**:
   ```bash
   cat /data/.clawdbot/repo-maintainer/pending-pr.json
   ```

4. **PR will be verified and merged** automatically (if tests pass)

## Manual Testing

### Test Issue Triage Script

```bash
# Analyze an issue (dry run)
python3 scripts/triage.py owner/repo --issue 42

# Analyze and apply labels
python3 scripts/triage.py owner/repo --issue 42 --apply

# Output as JSON
python3 scripts/triage.py owner/repo --issue 42 --json
```

### Test PR Verification Script

```bash
# Verify a PR
./scripts/verify-pr.sh owner/repo 55
```

## Configuration

### Customize Monitored Repos

Edit `~/.config/repo-maintainer/repos.yaml`:

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
      require_tests: false

daemon:
  poll_interval: 60
  log_level: info
```

### Custom Label Patterns

```yaml
labels:
  bug:
    - "error"
    - "crash"
    - "\\bbug\\b"
  enhancement:
    - "feature"
    - "add support"
```

### Priority Patterns

```yaml
priority:
  P0:  # Critical
    - "security"
    - "production down"
  P1:  # High
    - "regression"
  P3:  # Low
    - "nice to have"
```

## Common Tasks

### Stop the Daemon

```bash
./scripts/daemon.sh stop
```

### Restart the Daemon

```bash
./scripts/daemon.sh stop
./scripts/daemon.sh start
```

### View Logs

```bash
# Tail logs
tail -f /data/.clawdbot/repo-maintainer/daemon.log

# View recent activity
tail -n 50 /data/.clawdbot/repo-maintainer/daemon.log
```

### Check Pending Signals

```bash
ls -la /data/.clawdbot/repo-maintainer/*.json
```

### Clear Processed Notifications

```bash
# Be careful - this will reprocess old notifications
rm /data/.clawdbot/repo-maintainer/processed-notifications
```

## Troubleshooting

### Daemon Won't Start

```bash
# Check GitHub auth
gh auth status

# Check if already running
./scripts/daemon.sh status

# Check logs
cat /data/.clawdbot/repo-maintainer/daemon.log
```

### No Repos Detected

```bash
# Check if you have repos
gh repo list --limit 100

# Manually create config
mkdir -p ~/.config/repo-maintainer
nano ~/.config/repo-maintainer/repos.yaml
```

### Notifications Not Being Processed

```bash
# Check if daemon is running
./scripts/daemon.sh status

# Check recent logs
tail -n 100 /data/.clawdbot/repo-maintainer/daemon.log

# Check if repos are in config
cat ~/.config/repo-maintainer/repos.yaml | grep "  .*/.*:"
```

## Next Steps

- Read the [full README](README.md)
- Check the [architecture documentation](ARCHITECTURE.md)
- Explore [example configurations](assets/repos.yaml.example)
- Review [workflow diagrams](references/workflows.md)

## Support

- **Issues**: [github.com/onoht/repo-maintainer/issues](https://github.com/onoht/repo-maintainer/issues)
- **OpenClaw Docs**: [docs.openclaw.ai](https://docs.openclaw.ai)
- **Discord**: [discord.gg/clawd](https://discord.gg/clawd)

## Uninstall

```bash
# Stop daemon
./scripts/daemon.sh stop

# Remove skill
rm -rf ~/.openclaw/workspace/skills/repo-maintainer

# Remove config (optional)
rm -rf ~/.config/repo-maintainer

# Remove state (optional)
rm -rf /data/.clawdbot/repo-maintainer
```
