# Workflows

Detailed workflow diagrams for repo-maintainer.

## Event → Action Mapping

```
GitHub Event              Signal File              Action
─────────────────────────────────────────────────────────────
Issue opened       →     pending-issue-N.json  →  Triage
Issue comment      →     new-activity          →  Check if response needed
PR opened (owner)  →     pending-pr.json       →  Verify + Merge
PR opened (other)  →     pending-pr.json       →  Review checklist
PR review          →     pending-review        →  Respond to comments
PR comment         →     new-activity          →  Check if response needed
```

## Workflow 1: Issue Triage

```
┌─────────────────┐
│ New Issue       │
│ (signal file)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Read issue      │
│ title + body    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     No      ┌──────────────────┐
│ Is author =     ├────────────►│ Start convo to   │
│ repo owner?     │             │ clarify scope    │
└────────┬────────┘             └──────────────────┘
         │ Yes
         ▼
┌─────────────────┐
│ Detect labels   │
│ (triage.py)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Apply labels    │
│ (if auto_label) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Assess priority │
│ (P0-P3)         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Yes     ┌──────────────────┐
│ Needs           ├────────────►│ Ask clarifying   │
│ clarification?  │             │ questions        │
└────────┬────────┘             └──────────────────┘
         │ No
         ▼
┌─────────────────┐
│ Spawn subagent  │
│ with gh-issues   │
│ skill to fix    │
└─────────────────┘
```

## Workflow 2: PR Verification

```
┌─────────────────┐
│ New PR by owner │
│ (signal file)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Checkout PR     │
│ locally         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Detect project  │
│ type            │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Rust    ┌──────────────────┐
│                 ├────────────►│ cargo build      │
│                 │             │ cargo test       │
│                 │             └──────────────────┘
│                 │
│                 │    Node.js  ┌──────────────────┐
│                 ├────────────►│ npm install      │
│                 │             │ npm test         │
│                 │             └──────────────────┘
│                 │
│                 │    Python   ┌──────────────────┐
│                 ├────────────►│ pytest           │
│                 │             └──────────────────┘
│                 │
│                 │    Makefile ┌──────────────────┐
│                 ├────────────►│ make test        │
│                 │             └──────────────────┘
│                 │
│                 │    Other    ┌──────────────────┐
│                 ├────────────►│ No tests needed  │
│                 │             └──────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Pass    ┌──────────────────┐
│ Verification    ├────────────►│ Merge PR         │
│ result          │             │ (squash)         │
└────────┬────────┘             └──────────────────┘
         │ Fail
         ▼
┌─────────────────┐
│ Comment failure │
│ on PR           │
│ DO NOT MERGE    │
└─────────────────┘
```

## Workflow 3: Review Response

```
┌─────────────────┐
│ PR Review       │
│ (signal file)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Fetch review    │
│ comments        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Analyze for     │
│ actionability   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     No      ┌──────────────────┐
│ Actionable?     ├────────────►│ Skip             │
│                 │             │ (e.g., LGTM)     │
└────────┬────────┘             └──────────────────┘
         │ Yes
         ▼
┌─────────────────┐
│ Checkout branch │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Make requested  │
│ changes         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Run tests       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Commit + push   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Reply to each   │
│ comment         │
└─────────────────┘
```

## Workflow 4: Stale Issue Management

```
┌─────────────────┐
│ Daily check     │
│ (cron)          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Find issues     │
│ stale_days old  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     No      ┌──────────────────┐
│ Any found?      ├────────────►│ Done             │
└────────┬────────┘             └──────────────────┘
         │ Yes
         ▼
┌─────────────────┐
│ For each:       │
│ - Add stale     │
│   label         │
│ - Comment with  │
│   warning       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ After 7 days:   │
│ Close if no     │
│ response        │
└─────────────────┘
```

## Subagent Delegation

When the main agent decides to fix an issue, it spawns a subagent:

```bash
# Main agent spawns subagent with task:
sessions_spawn(
    runtime="subagent",
    task="Fix issue #N in owner/repo: [title]. Use gh-issues skill.",
    cleanup="keep"
)
```

The subagent:
1. Reads the issue
2. Explores the codebase
3. Implements the fix
4. Runs tests
5. Creates a PR
6. Reports back

The main agent continues to process other signals while the subagent works.

## State File Locations

All state in `/data/.clawdbot/repo-maintainer/`:

| File | Purpose |
|------|---------|
| `daemon.pid` | Daemon process ID |
| `daemon.log` | Daemon log |
| `pending-pr.json` | PR awaiting verification |
| `pending-issue-N.json` | Issue awaiting triage |
| `pending-review` | Flag for review activity |
| `new-activity` | Flag for comment activity |
| `processed-notifications` | IDs of processed notifications |
| `audit.log` | Action audit trail |
