---
name: repo-maintainer
description: "Autonomous GitHub repository maintenance for anyone. Fully automatic issue triage, labeling, PR verification, and merging — no human approval needed. Use when: (1) Managing GitHub repos, (2) Wanting automatic issue triage and labeling, (3) Needing PR verification and auto-merge, (4) Building a proactive maintainer. Triggers on: 'maintain my repos', 'setup repo maintenance', 'start github daemon', or heartbeat checks."
---

# Repo Maintainer

Fully autonomous GitHub repository maintenance. No human approval needed.

## Design Decisions

- **Trigger**: Direct polling (5 min interval)
- **Multi-tenant**: Works for any GitHub user
- **Processing**: One event at a time, sequential
- **Approval**: None — fully autonomous
- **Integration**: OpenClaw skill

## Quick Start

```bash
# Start daemon (auto-detects repos from gh auth)
~/workspace/skills/repo-maintainer/scripts/daemon.sh start

# Check status
~/workspace/skills/repo-maintainer/scripts/daemon.sh status

# Stop
~/workspace/skills/repo-maintainer/scripts/daemon.sh stop
```

First run creates default config at `~/.config/repo-maintainer/repos.yaml`.

## How It Works

```
Direct Polling → State Tracking → Signal Files → Main Agent → Subagents
```

**Daemon polls repos directly** every 5 minutes:
- Fetches all open issues/PRs via `gh` CLI
- Compares `updated_at` against stored state
- Only creates signals for new/changed items

**Fully autonomous**:
- Issues auto-labeled and triaged
- PRs auto-verified and merged (if passing)
- Reviews auto-addressed
- No approval gates

## Signal Files

`/data/.clawdbot/repo-maintainer/`:

| File | Meaning | Auto-Action |
|------|---------|-------------|
| `pending-pr.json` | New PR by you | Verify + merge |
| `pending-issue-*.json` | New issue | Triage + fix |
| `pending-review` | PR review | Address comments |
| `new-activity` | Comments | Respond if needed |

## Workflows

### Issue → Triage → Fix

1. New issue detected
2. Auto-label (bug/enhancement/docs/question)
3. Assess priority (P0-P3)
4. If unclear scope: ask clarifying questions
5. If actionable: spawn subagent to fix
6. Subagent opens PR

### PR → Verify → Merge

1. Your PR detected
2. Checkout locally
3. Detect project type, run tests:
   - Rust: `cargo test`
   - Node: `npm test`
   - Python: `pytest`
   - Makefile: `make test`
   - Static: skip
4. If passing: merge (squash)
5. If failing: comment, don't merge

### Review → Address → Push

1. Review comment detected
2. Checkout branch
3. Make requested changes
4. Run tests
5. Push + reply to comments

## Configuration

`~/.config/repo-maintainer/repos.yaml`:

```yaml
# Auto-generated on first run with your repos

repos:
  yourname/repo:
    issues:
      auto_label: true
      stale_days: 30
    prs:
      auto_merge: true
      require_tests: true

daemon:
  poll_interval: 300  # 5 minutes
```

To monitor specific repos only:
```yaml
repos:
  yourname/project-a:
    issues: {auto_label: true}
    prs: {auto_merge: true}
  yourname/project-b:
    issues: {auto_label: true}
    prs: {auto_merge: true}
```

## Multi-Tenant Usage

Anyone can use this skill:

1. **Install** the skill
2. **Authenticate** with `gh auth login`
3. **Start** daemon
4. **Config** auto-generated from your repos

The daemon reads your GitHub identity and monitors repos you own/maintain.

## Scripts

| Script | Purpose |
|--------|---------|
| `daemon.sh start/stop/status/scan` | Issue/PR poller |
| `scan-now.sh` | Manual scan (immediate) |
| `triage.py --repo X --issue N` | Label + prioritize issue |
| `verify-pr.sh repo pr-number` | Build + test PR |

## References

- [config-schema.md](references/config-schema.md) — Full config options
- [workflows.md](references/workflows.md) — Detailed flow diagrams
