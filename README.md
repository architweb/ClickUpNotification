# ClickUpNotification

[![GitHub release](https://img.shields.io/github/v/release/architweb/ClickUpNotification?color=orange)](https://github.com/architweb/ClickUpNotification/releases)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-ClickUp%20Notification-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/clickup-notification)
[![GitHub stars](https://img.shields.io/github/stars/architweb/ClickUpNotification?color=blue)](https://github.com/architweb/ClickUpNotification/stargazers)
[![GitHub last commit](https://img.shields.io/github/last-commit/architweb/ClickUpNotification)](https://github.com/architweb/ClickUpNotification/commits)
![GitHub Action](https://img.shields.io/badge/GitHub-Action-informational?style=flat&logo=github-actions&logoColor=white)
[![License](https://img.shields.io/badge/license-MIT-black.svg)](https://opensource.org/licenses/MIT)

**ClickUpNotification** is a GitHub Action that posts a deployment summary to a ClickUp chat channel. The summary includes who triggered the run, how long it took, and a changelog of every commit since the last successful run, grouped by author or by commit type.

Add it as the last step of a deploy job, and your team gets a readable "what just shipped" message in ClickUp, with links to tasks, pull requests, and the full diff.

## Features

- Custom **title** and **description**
- **Project name**, **branch**, and **triggered by**
- **Duration** of the workflow run
- **Changelog** since the last successful run (or since a ref, or the last 30 days on the first run), grouped by author or by Conventional Commit type
- **Commit limit**: list only the N most recent commits, with a link to the rest
- **Compare link** to the full diff on GitHub
- **Commit statistics**: files and lines changed, release type, contributors, time since last deploy
- **ClickUp task links** from `task`/`ctask` IDs in commit messages
- **Single-line** or **full** commit message mode
- Emphasized **Conventional Commit** types
- Filtering of **merge commits** and **agent/bot commits**, plus **Copilot agent attribution**
- **Environment emojis**: staging 🧪 / production 🚀, or your own branch → emoji map
- **PR links** for `#123` references
- **Failure and cancellation notifications** with a link to the workflow run
- **Outputs** such as the message ID and commit count, for later steps
- **Automatic retries** when ClickUp is rate-limited or temporarily down
- **Test mode** to preview the message without sending it

## Screenshots

<img src="assets/screenshot.png" alt="Screenshot" style="width:90%;">
<img src="assets/screenshot-multiline.png" alt="Screenshot-multiline" style="width:90%;">

## Requirements

- **Runner:** `ubuntu-latest` is recommended. The action uses `bash`, `gh`, `jq`, `curl`, and `git`, which are preinstalled on GitHub-hosted runners.
- **Job permissions:** `contents: read` and `actions: read`. The action uses the job's `github.token` to look up workflow runs, compare commits, and fetch user names.
- **Checkout:** `actions/checkout` with `fetch-depth: 0` is needed when `show_commit_statistics` is enabled, because statistics are computed from local git history.
- **ClickUp:** an API token and the workspace and chat channel IDs (see below).

## Setup on ClickUp

Messages appear as sent by the user who owns the API token. We recommend creating a guest user such as "GitHub Actions" or "CI/CD Messenger" and generating the token from that account:

1. Log in to that account at [ClickUp](https://app.clickup.com).
2. Open **Settings** from the top-right menu, then **Apps**.
3. Click **Generate** under **API Token**.

To get the workspace and channel IDs, open the target chat channel and copy them from the URL:
`https://app.clickup.com/<WORKSPACE_ID>/chat/r/<CHANNEL_ID>`

Store all of these as repository secrets, for example `CLICKUP_API_TOKEN`, `CLICKUP_WORKSPACE_ID`, `CLICKUP_CHANNEL_ID`, and `CLICKUP_PROJECT_NAME`.

## Inputs

| Input                    | Description                                                                      | Required | Default   |
| ------------------------ | -------------------------------------------------------------------------------- | -------- | --------- |
| `clickup_api_token`      | ClickUp API token                                                                | Yes      |           |
| `clickup_workspace_id`   | ClickUp workspace (team) ID                                                      | Yes      |           |
| `clickup_channel_id`     | ClickUp chat channel ID                                                          | Yes      |           |
| `clickup_project_name`   | Project name shown in the message                                                | Yes      |           |
| `title`                  | Custom title (switches to the "titled" header format)                            | No       | `""`      |
| `description`            | Custom description, shown in italics under the header                            | No       | `""`      |
| `show_fetch_duration`    | Show workflow duration                                                           | No       | `"true"`  |
| `show_changelog_commits` | Show the changelog                                                               | No       | `"true"`  |
| `full_commit_message`    | Use full commit messages instead of the first line only                          | No       | `"true"`  |
| `show_commit_statistics` | Append the statistics block                                                      | No       | `"false"` |
| `filter_agent_commits`   | Hide agent/bot commits and strip `Co-authored-by:` lines                         | No       | `"true"`  |
| `group_commits_by_type`  | Group by Conventional Commit type instead of by author                           | No       | `"false"` |
| `show_pr_links`          | Turn `#123` into links to the repository's pull requests                         | No       | `"false"` |
| `show_compare_link`      | Add a `🔗 View full diff` link below the changelog                               | No       | `"false"` |
| `max_commits`            | List only the N most recent commits, then "…and N more". Empty or `0` = all      | No       | `""`      |
| `since_ref`              | Start ref (tag/branch/SHA) when no previous run exists. Default: last 30 days    | No       | `""`      |
| `staging_emoji`          | Emoji used when the branch name contains `staging`                               | No       | `🧪`      |
| `production_emoji`       | Emoji used for every other branch                                                | No       | `🚀`      |
| `environment_emojis`     | Branch → emoji map, one `<glob>=<emoji>` per line (see below)                    | No       | `""`      |
| `notify_on_failure`      | Send a failure message when `workflow_status` is `failure`                       | No       | `"false"` |
| `notify_on_cancel`       | Send a cancellation message when `workflow_status` is `cancelled`                | No       | `"false"` |
| `workflow_status`        | Pass `${{ job.status }}`                                                         | No       | `success` |
| `test_mode`              | Print the message in the job log instead of sending it                           | No       | `"false"` |

Boolean inputs are strings: `"true"` or `"false"`.

## Outputs

| Output         | Description                                                                 |
| -------------- | --------------------------------------------------------------------------- |
| `message_id`   | ID of the created ClickUp chat message. Empty in test mode or when skipped  |
| `message`      | The message that was sent or previewed. Empty when skipped                  |
| `commit_count` | Number of commits in the changelog range, before filtering                  |
| `previous_sha` | First commit (base) of the changelog range. Empty if there is none          |
| `compare_url`  | GitHub compare URL for the changelog range                                  |

## Usage

```yaml
name: Staging Deployment

on:
  push:
    branches: ["release/staging"]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: read

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # ... your build, test and deploy steps ...

      - name: Send ClickUp Notification
        id: clickup
        uses: architweb/ClickUpNotification@v3.3.0
        if: always() # needed for failure/cancel notifications
        with:
          clickup_api_token: ${{ secrets.CLICKUP_API_TOKEN }}
          clickup_workspace_id: ${{ secrets.CLICKUP_WORKSPACE_ID }}
          clickup_channel_id: ${{ secrets.CLICKUP_CHANNEL_ID }}
          clickup_project_name: ${{ secrets.CLICKUP_PROJECT_NAME }}
          title: "🎉 Staging Deployment Complete" # optional
          description: "New features deployed to staging" # optional
          show_commit_statistics: "true"
          show_compare_link: "true"
          notify_on_failure: "true"
          notify_on_cancel: "true"
          workflow_status: ${{ job.status }}
```

### Minimal (no duration or changelog)

```yaml
- uses: architweb/ClickUpNotification@v3.3.0
  with:
    clickup_api_token: ${{ secrets.CLICKUP_API_TOKEN }}
    clickup_workspace_id: ${{ secrets.CLICKUP_WORKSPACE_ID }}
    clickup_channel_id: ${{ secrets.CLICKUP_CHANNEL_ID }}
    clickup_project_name: ${{ secrets.CLICKUP_PROJECT_NAME }}
    title: "⚡ Hotfix Applied"
    show_fetch_duration: "false"
    show_changelog_commits: "false"
```

### Production release for a busy repository

```yaml
- uses: architweb/ClickUpNotification@v3.3.0
  with:
    # ... required inputs ...
    title: "🚀 Production Release"
    show_commit_statistics: "true"
    group_commits_by_type: "true"
    show_pr_links: "true"
    max_commits: "25" # older commits collapse into "…and N more"
    since_ref: "v2.0.0" # first run on this branch starts from this tag
```

### Using the outputs

```yaml
- run: echo "ClickUp message ${{ steps.clickup.outputs.message_id }} (${{ steps.clickup.outputs.commit_count }} commits)"
```

## How It Works

### Changelog range

The changelog starts at the first of these that exists:

1. The commit of the **last successful run of the same workflow on the same branch**.
2. `since_ref`, when it is set.
3. The **last 30 days** of history on the branch.

It ends at the current commit. Merge commits (`Merge branch …`, `Merge pull request …`) and duplicate messages are skipped. When `max_commits` is set, only the most recent commits are listed, followed by `…and N more commit(s)` and a link to the full diff.

### Message format

```md
🚀 **Project Name** deployed to **branch-name**
_Optional description_

_Triggered by: Username, Done in: 02:15min_

**Change Log:**
_*Author Name:*_
* **Feat:** commit message

🔗 [View full diff](https://github.com/org/repo/compare/abc...def)
```

When `title` is set, the first line becomes `🚀 **branch-name** | **Project Name** | Title`. The `Done in` part is omitted when the duration is unknown or disabled.

### Environment emojis

The emoji is picked in this order:

1. The first line of `environment_emojis` whose glob matches the branch name (case-insensitive).
2. `staging_emoji`, if the branch name contains `staging`.
3. `production_emoji`.

```yaml
environment_emojis: |
  release/beta=🅱️
  *hotfix*=🔥
  feature/*=🧩
```

Patterns are matched against the whole branch name, so use `*word*` to match part of it.

### ClickUp task links

Reference ClickUp tasks in commit messages:

```md
task `86ddd0y92` Add new login functionality
ctask `TST-747` Add global log out functionality
```

These become `[86ddd0y92](https://app.clickup.com/t/86ddd0y92)` and `[TST-747](https://app.clickup.com/t/<WORKSPACE_ID>/TST-747)`. `ctask` is for custom task IDs.

### Conventional Commits

The types `build`, `chore`, `docs`, `feat`, `fix`, `refactor`, `revert`, `style`, `test`, `release`, `security`, `deps`, and `api` are recognized in any letter case and shown in bold, keeping the scope and breaking marker, for example `**Feat(auth)!:**`. With `group_commits_by_type: "true"`, commits are listed under headings such as 🎯 Features, 🔧 Fixes, and 🔄 Refactors, and any other commits appear under 📋 Other.

### Commit statistics

With `show_commit_statistics: "true"`, a **📊 Stats** block is appended. A line is shown only when it is meaningful:

| Line | Shown when |
| --- | --- |
| 📝 Count | Always |
| 🎯 Release Type (Major / Minor / Patch) | A breaking change (`!:`), `feat`, or `fix` commit is present |
| 📁 Changed, ➕ Added, ➖ Removed | The value is non-zero |
| 🔧 Fixes, 🔄 Refactor | At least one such commit |
| ⏰ Last Deploy | The range starts at a previous run, at least 30 minutes earlier |
| 👥 Contributor(s) | 2 or more authors |
| 🏆 Top Contributor | 3 or more authors |

### Agent commit filtering

With `filter_agent_commits: "true"` (the default), commits whose first line is `Initial plan`, or starts with `Agent-Logs-Url:` or `Co-authored-by:`, are hidden, and `Co-authored-by:` trailers are removed from message bodies. Commits authored by the Copilot SWE agent bot are attributed as `Contributor Name (Copilot Agent)`, using that commit's co-author.

### Failure and cancellation notifications

Pass `workflow_status: ${{ job.status }}` and add `if: always()` to the step.

| `workflow_status` | Sent message |
| --- | --- |
| `success` | Normal deployment message |
| `failure` | `❌ … deployment to … failed!` with a link to the run, only if `notify_on_failure: "true"` |
| `cancelled` | `⚠️ … deployment to … was cancelled.` with a link to the run, only if `notify_on_cancel: "true"` |

### Delivery and test mode

Network errors, HTTP 429, and HTTP 5xx responses from ClickUp are retried up to 3 times with increasing delays. `test_mode: "true"` prints the full message, the resolved workspace name, and the character count to the job log. It sends nothing, and the API token is never printed.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| No "Change Log" section | No commits in the range, or every commit was filtered out. Check that `actions: read` permission is granted. |
| First run shows a month of commits | Expected: there is no previous successful run. Set `since_ref` to start from a tag or branch instead. |
| Stats show no file or line counts | History is missing. Use `actions/checkout` with `fetch-depth: 0`. |
| No `Done in` duration | `show_fetch_duration` is `"false"`, or the run's start time could not be read (`gh` unavailable). |
| Failure or cancel message never arrives | You need `if: always()`, `workflow_status: ${{ job.status }}`, and `notify_on_failure` / `notify_on_cancel` set to `"true"`. |
| `Failed to send notification to ClickUp. HTTP code: …` | Check the token and IDs. The ClickUp response body is printed in the log below the error. |

## Development

The action is a **composite action** written in Bash, with no build step and no runtime dependencies.

```text
action.yml                 # public inputs/outputs, status handling, step wiring
steps/fetch-duration/      # run duration
steps/fetch-commits/       # commit range, formatting, statistics (scripts/*.sh)
steps/send-notification/   # message build, preview, send with retries (scripts/*.sh)
tests/                     # bats unit tests and fixtures
.github/workflows/         # CI, staging test, prerelease (beta), release (production)
CHANGELOG                  # release notes; first "## [vX.Y.Z]" heading is the version
```

**Checks** (the same ones [ci.yml](.github/workflows/ci.yml) runs on every pull request):

```bash
shellcheck steps/*/scripts/*.sh tests/*.bash
npx --yes bats@1.11.0 tests       # needs jq and git on PATH
actionlint                        # if installed
```

**End-to-end testing:** pushing to `release/staging` runs [test-package.yml](.github/workflows/test-package.yml). It points the action at the checked-out `steps/`, sends a real message, and previews the grouped, failure, and cancelled variants in the log.

**Releasing:**

1. Add a `## [vX.Y.Z] - YYYY-MM-DD` entry at the top of [CHANGELOG](CHANGELOG).
2. Update the three `steps/...@vX.Y.Z` refs in [action.yml](action.yml), and the examples in this README.
3. Merge to `release/beta` to create a prerelease, then to `release/production` to create a stable release (or promote the prerelease).

AI agents and maintainers: see [AGENTS.md](AGENTS.md) for architecture, conventions, and change rules.

## Contributing

1. Fork the repository and branch from `release/staging`.
2. Make your change in `action.yml` or `steps/`, following the existing script patterns, and add or update tests in `tests/`.
3. Use [Conventional Commits](https://www.conventionalcommits.org/) messages.
4. Update this README and the CHANGELOG when inputs or behaviour change.
5. Open a pull request against `release/staging` with a clear description.

## Support

- [GitHub Issues](https://github.com/architweb/ClickUpNotification/issues): bugs and feature requests. Please include the action version, logs, steps to reproduce, and expected vs actual behaviour.
- [Changelog](CHANGELOG): release notes and migration guides.

---

_© 2025-2026 ArchitWeb. Released under the [MIT License](LICENSE)._
