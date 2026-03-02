# Installation Guide

Complete installation instructions for Repo Maintainer.

## Table of Contents

- [Requirements](#requirements)
- [Option 1: OpenClaw Skill (Recommended)](#option-1-openclaw-skill-recommended)
- [Option 2: Standalone Installation](#option-2-standalone-installation)
- [Post-Installation Setup](#post-installation-setup)
- [Verification](#verification)
- [Upgrading](#upgrading)
- [Uninstallation](#uninstallation)

## Requirements

### System Requirements

- **Operating System**: Linux, macOS, or Windows (via WSL2)
- **Memory**: 10 MB RAM (daemon only)
- **Disk Space**: 50 MB (including work directory)
- **Python**: 3.7 or higher
- **Git**: 2.x or higher

### Software Dependencies

- **GitHub CLI (`gh`)**: For GitHub API access
  - Install: [cli.github.com](https://cli.github.com/)
  - Verify: `gh --version`

- **OpenClaw** (optional, for skill mode):
  - Install: [docs.openclaw.ai/start/getting-started](https://docs.openclaw.ai/start/getting-started)
  - Verify: `openclaw --version`

## Option 1: OpenClaw Skill (Recommended)

Install as an OpenClaw skill for full integration.

### Step 1: Install GitHub CLI

**macOS**:
```bash
brew install gh
```

**Linux (Debian/Ubuntu)**:
```bash
sudo apt update
sudo apt install gh
```

**Linux (Fedora)**:
```bash
sudo dnf install gh
```

**Linux (Arch)**:
```bash
sudo pacman -S github-cli
```

### Step 2: Authenticate with GitHub

```bash
gh auth login
```

Follow the prompts:
1. Choose `GitHub.com`
2. Choose `HTTPS` protocol
3. Choose `Login with a web browser`
4. Copy the one-time code
5. Press Enter to open browser
6. Paste code in browser and authorize

Verify:
```bash
gh auth status
```

### Step 3: Install the Skill

```bash
# Navigate to OpenClaw skills directory
cd ~/.openclaw/workspace/skills

# Clone the repository
git clone https://github.com/onoht/repo-maintainer.git

# Verify installation
ls repo-maintainer/SKILL.md
```

### Step 4: Start the Daemon

```bash
# Start daemon
~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh start

# Check status
~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh status
```

## Option 2: Standalone Installation

Use without OpenClaw integration.

### Step 1: Install Dependencies

Install GitHub CLI (see Option 1, Step 1)

Install Python (if not already installed):

**macOS**:
```bash
brew install python3
```

**Linux (Debian/Ubuntu)**:
```bash
sudo apt update
sudo apt install python3 python3-pip
```

**Linux (Fedora)**:
```bash
sudo dnf install python3 python3-pip
```

### Step 2: Authenticate with GitHub

```bash
gh auth login
gh auth status
```

### Step 3: Clone Repository

```bash
# Choose installation directory
cd ~
mkdir -p tools
cd tools

# Clone
git clone https://github.com/onoht/repo-maintainer.git
cd repo-maintainer

# Verify
ls scripts/daemon.sh
```

### Step 4: Make Scripts Executable

```bash
chmod +x scripts/*.sh scripts/*.py
```

### Step 5: Start the Daemon

```bash
./scripts/daemon.sh start
./scripts/daemon.sh status
```

## Post-Installation Setup

### Configure Monitored Repos

The daemon auto-detects your repos on first run, but you can customize:

```bash
# Edit config
nano ~/.config/repo-maintainer/repos.yaml
```

Example configuration:
```yaml
repos:
  yourname/project-a:
    issues:
      auto_label: true
      stale_days: 30
    prs:
      auto_merge: true
      require_tests: true

daemon:
  poll_interval: 60
  log_level: info
```

### Set Environment Variables (Optional)

```bash
# Add to ~/.bashrc or ~/.zshrc
export REPO_MAINTAINER_CONFIG="$HOME/.config/repo-maintainer/repos.yaml"
export POLL_INTERVAL=60
```

### Create Systemd Service (Linux)

For automatic startup on boot:

```bash
# Create service file
sudo nano /etc/systemd/system/repo-maintainer.service
```

Content:
```ini
[Unit]
Description=Repo Maintainer Daemon
After=network.target

[Service]
Type=simple
User=yourusername
WorkingDirectory=/home/yourusername/tools/repo-maintainer
ExecStart=/home/yourusername/tools/repo-maintainer/scripts/daemon.sh _run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable repo-maintainer
sudo systemctl start repo-maintainer
sudo systemctl status repo-maintainer
```

### Create LaunchAgent (macOS)

For automatic startup on boot:

```bash
# Create plist
nano ~/Library/LaunchAgents/com.user.repo-maintainer.plist
```

Content:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.repo-maintainer</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/yourusername/tools/repo-maintainer/scripts/daemon.sh</string>
        <string>_run</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/repo-maintainer.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/repo-maintainer.err</string>
</dict>
</plist>
```

Load:
```bash
launchctl load ~/Library/LaunchAgents/com.user.repo-maintainer.plist
launchctl start com.user.repo-maintainer
```

## Verification

### Check Daemon Status

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

### Test Issue Triage

```bash
# Create test issue
gh issue create --repo yourname/test-repo \
  --title "Test bug report" \
  --body "This is a test issue"

# Wait 60 seconds
sleep 60

# Check logs
tail /data/.clawdbot/repo-maintainer/daemon.log
```

### Test PR Verification

```bash
# Verify a PR manually
./scripts/verify-pr.sh owner/repo 42
```

## Upgrading

### Upgrade OpenClaw Skill

```bash
cd ~/.openclaw/workspace/skills/repo-maintainer
git pull origin main
./scripts/daemon.sh restart
```

### Upgrade Standalone Installation

```bash
cd ~/tools/repo-maintainer
git pull origin main
./scripts/daemon.sh restart
```

## Uninstallation

### Remove OpenClaw Skill

```bash
# Stop daemon
~/.openclaw/workspace/skills/repo-maintainer/scripts/daemon.sh stop

# Remove skill
rm -rf ~/.openclaw/workspace/skills/repo-maintainer

# Remove config (optional)
rm -rf ~/.config/repo-maintainer

# Remove state (optional)
rm -rf /data/.clawdbot/repo-maintainer
```

### Remove Standalone Installation

```bash
# Stop daemon
~/tools/repo-maintainer/scripts/daemon.sh stop

# Remove installation
rm -rf ~/tools/repo-maintainer

# Remove config (optional)
rm -rf ~/.config/repo-maintainer

# Remove state (optional)
rm -rf /data/.clawdbot/repo-maintainer
```

### Remove Systemd Service

```bash
sudo systemctl stop repo-maintainer
sudo systemctl disable repo-maintainer
sudo rm /etc/systemd/system/repo-maintainer.service
sudo systemctl daemon-reload
```

### Remove LaunchAgent (macOS)

```bash
launchctl stop com.user.repo-maintainer
launchctl unload ~/Library/LaunchAgents/com.user.repo-maintainer.plist
rm ~/Library/LaunchAgents/com.user.repo-maintainer.plist
```

## Troubleshooting

### "GH_TOKEN not found"

```bash
# Check auth
gh auth status

# Re-authenticate
gh auth login
```

### "Permission denied"

```bash
# Make scripts executable
chmod +x scripts/*.sh scripts/*.py
```

### "Config not found"

```bash
# Create config directory
mkdir -p ~/.config/repo-maintainer

# Daemon will auto-generate config on first run
./scripts/daemon.sh start
```

### "Daemon not starting"

```bash
# Check logs
cat /data/.clawdbot/repo-maintainer/daemon.log

# Check if already running
ps aux | grep daemon.sh

# Kill stale process
kill $(cat /data/.clawdbot/repo-maintainer/daemon.pid)
./scripts/daemon.sh start
```

## Next Steps

- Read the [Quick Start Guide](QUICKSTART.md)
- Review the [full README](README.md)
- Check [example configurations](assets/repos.yaml.example)
- Explore [workflow diagrams](references/workflows.md)

## Support

- **Issues**: [github.com/onoht/repo-maintainer/issues](https://github.com/onoht/repo-maintainer/issues)
- **Discord**: [discord.gg/clawd](https://discord.gg/clawd)
- **OpenClaw Docs**: [docs.openclaw.ai](https://docs.openclaw.ai)
