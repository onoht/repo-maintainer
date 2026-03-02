# Configuration Schema

Full documentation for `~/.config/repo-maintainer/repos.yaml`.

## Structure

```yaml
repos:
  owner/repo:
    issues:
      enabled: true
      auto_label: true
      triage: true
      stale_days: 30
      auto_close_stale: false
    prs:
      enabled: true
      auto_merge_owner: true
      require_tests: true
      review_checklist: true

daemon:
  poll_interval: 60
  log_level: info

labels:
  bug: ["pattern1", "pattern2"]
  enhancement: [...]
  # etc

priority:
  P0: ["critical patterns"]
  P1: [...]
  # etc

notifications:
  telegram:
    enabled: false
    channel: "-100123456789"
  # or other channels
```

## Repo Settings

### `issues.enabled`
- Type: `boolean`
- Default: `true`
- If `false`, skip issue processing for this repo

### `issues.auto_label`
- Type: `boolean`
- Default: `true`
- Automatically apply detected labels to new issues

### `issues.triage`
- Type: `boolean`
- Default: `true`
- Perform full triage (labeling + priority + clarification check)

### `issues.stale_days`
- Type: `integer`
- Default: `30`
- Days before an issue is considered stale

### `issues.auto_close_stale`
- Type: `boolean`
- Default: `false`
- Automatically close stale issues after warning period

### `prs.enabled`
- Type: `boolean`
- Default: `true`
- If `false`, skip PR processing for this repo

### `prs.auto_merge_owner`
- Type: `boolean`
- Default: `true`
- Automatically merge PRs by the repo owner after verification

### `prs.require_tests`
- Type: `boolean`
- Default: `true`
- Require tests to pass before merging

### `prs.review_checklist`
- Type: `boolean`
- Default: `true`
- Check for review requirements before merging

## Daemon Settings

### `daemon.poll_interval`
- Type: `integer`
- Default: `60`
- Seconds between notification polls

### `daemon.log_level`
- Type: `string`
- Values: `debug`, `info`, `warn`, `error`
- Default: `info`

## Label Patterns

Customize label detection patterns:

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
  documentation:
    - "docs?"
    - "readme"
    - "example"
  question:
    - "how do i"
    - "what is"
    - "help"
  security:
    - "vulnerability"
    - "security"
    - "cve"
  performance:
    - "slow"
    - "performance"
    - "optimize"
```

Patterns are regex-compatible.

## Priority Patterns

```yaml
priority:
  P0:  # Critical - immediate attention
    - "security"
    - "data loss"
    - "production down"
    - "outage"
  P1:  # High - fix soon
    - "regression"
    - "breaking change"
    - "workaround exists"
  P2:  # Normal - standard priority
    # Default for most issues
  P3:  # Low - nice to have
    - "nice to have"
    - "polish"
    - "minor"
```

## Notifications

Configure where to send alerts:

```yaml
notifications:
  telegram:
    enabled: true
    channel: "-1002381931352"
    events:
      - pr_merged
      - issue_created
      - verification_failed
```

## Environment Variables

Override config with environment variables:

- `REPO_MAINTAINER_CONFIG` — Path to config file
- `REPO_MAINTAINER_BOT` — Bot username (default: from gh auth)
- `POLL_INTERVAL` — Poll interval in seconds
- `GH_TOKEN` — GitHub token (default: from gh auth token)
