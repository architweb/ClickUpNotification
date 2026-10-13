# ClickUpNotification

[![GitHub release](https://img.shields.io/github/v/release/architweb/ClickUpNotification?color=orange)](https://github.com/architweb/ClickUpNotification/releases)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-ClickUp%20Notification-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/clickup-notification)
[![GitHub stars](https://img.shields.io/github/stars/architweb/ClickUpNotification?color=blue)](https://github.com/architweb/ClickUpNotification/stargazers)
[![GitHub last commit](https://img.shields.io/github/last-commit/architweb/ClickUpNotification)](https://github.com/architweb/ClickUpNotification/commits)
![GitHub Action](https://img.shields.io/badge/GitHub-Action-informational?style=flat&logo=github-actions&logoColor=white)
[![License](https://img.shields.io/badge/license-MIT-black.svg)](https://opensource.org/licenses/MIT)

**ClickUpNotification** is a GitHub Action that posts a deployment summary to a ClickUp chat channel. The summary includes who triggered the run, how long it took, and a changelog of every commit since the last successful run, grouped by author or by commit type.

## Features

- Custom **title** and **description**
- **Project name**, **branch**, and **triggered by**
- **Duration** of the workflow run
- **Changelog** since the last successful run, grouped by author or by Conventional Commit type
- **Commit statistics**: files and lines changed, release type, contributors, time since last deploy
- **ClickUp task links** from `task`/`ctask` IDs in commit messages
- **Single-line** or **full** commit message mode
- Emphasized **Conventional Commit** types
- Filtering of **merge commits** and **agent/bot commits**, plus **Copilot agent attribution**
- **Environment emojis** (staging 🧪 / production 🚀)
- **PR links** for `#123` references
- **Failure notifications** with a link to the workflow run
- **Test mode** to preview the message without sending it

## Screenshots

<img src="assets/screenshot.png" alt="Screenshot" style="width:90%;">
<img src="assets/screenshot-multiline.png" alt="Screenshot-multiline" style="width:90%;">

## Requirements

- **Runner:** `ubuntu-latest` is recommended. The action uses `bash`, `gh`, `jq`, `curl`, and `git`, which are preinstalled on GitHub-hosted runners. Duration calculation needs GNU `date`; on other runners it shows as `unknown`.
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

| Input                    | Description                                                    | Required | Default   |
| ------------------------ | -------------------------------------------------------------- | -------- | --------- |
| `clickup_api_token`      | ClickUp API token                                              | Yes      |           |
| `clickup_workspace_id`   | ClickUp workspace (team) ID                                    | Yes      |           |
| `clickup_channel_id`     | ClickUp chat channel ID                                        | Yes      |           |
| `clickup_project_name`   | Project name shown in the message                              | Yes      |           |
| `title`                  | Custom title (switches to the "titled" header format)          | No       | `""`      |
| `description`            | Custom description, shown in italics under the header          | No       | `""`      |
| `show_fetch_duration`    | Show workflow duration                                         | No       | `"true"`  |
| `show_changelog_commits` | Show the changelog                                             | No       | `"true"`  |
| `full_commit_message`    | Use full commit messages instead of the first line only        | No       | `"true"`  |
| `show_commit_statistics` | Append the statistics block                                    | No       | `"false"` |
| `filter_agent_commits`   | Hide agent/bot commits and strip `Co-authored-by:` lines       | No       | `"true"`  |
| `group_commits_by_type`  | Group by Conventional Commit type instead of by author         | No       | `"false"` |
| `show_pr_links`          | Turn `#123` into links to the repository's pull requests       | No       | `"false"` |
| `staging_emoji`          | Emoji used when the branch name contains `staging`             | No       | `🧪`      |
| `production_emoji`       | Emoji used for every other branch                              | No       | `🚀`      |
| `notify_on_failure`      | Send a failure message when `workflow_status` is `failure`     | No       | `"false"` |
| `workflow_status`        | Pass `${{ job.status }}`                                       | No       | `success` |
| `test_mode`              | Print the message in the job log instead of sending it         | No       | `"false"` |

Boolean inputs are strings: `"true"` or `"false"`.

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
        uses: architweb/ClickUpNotification@v3.2.0
        if: always() # needed for failure notifications
        with:
          clickup_api_token: ${{ secrets.CLICKUP_API_TOKEN }}
          clickup_workspace_id: ${{ secrets.CLICKUP_WORKSPACE_ID }}
          clickup_channel_id: ${{ secrets.CLICKUP_CHANNEL_ID }}
          clickup_project_name: ${{ secrets.CLICKUP_PROJECT_NAME }}
          title: "🎉 Staging Deployment Complete" # optional
          description: "New features deployed to staging" # optional
          show_commit_statistics: "true"
          notify_on_failure: "true"
          workflow_status: ${{ job.status }}
```

### Minimal (no duration or changelog)

```yaml
- uses: architweb/ClickUpNotification@v3.2.0
  with:
    clickup_api_token: ${{ secrets.CLICKUP_API_TOKEN }}
    clickup_workspace_id: ${{ secrets.CLICKUP_WORKSPACE_ID }}
    clickup_channel_id: ${{ secrets.CLICKUP_CHANNEL_ID }}
    clickup_project_name: ${{ secrets.CLICKUP_PROJECT_NAME }}
    title: "⚡ Hotfix Applied"
    show_fetch_duration: "false"
    show_changelog_commits: "false"
```

### Production release with full details

```yaml
- uses: architweb/ClickUpNotification@v3.2.0
  with:
    # ... required inputs ...
    title: "🚀 Production Release"
    show_commit_statistics: "true"
    group_commits_by_type: "true"
    show_pr_links: "true"
```

## How It Works

### Changelog range

The changelog covers the commits between the head SHA of the **last successful run of the same workflow on the same branch** and the current commit. The first run on a branch therefore has no changelog. Merge commits (`Merge branch …`, `Merge pull request …`) and duplicate messages are skipped.

### Message format

```md
🚀 **Project Name** deployed to **branch-name**
_Optional description_

_Triggered by: Username, Done in: 02:15min_

**Change Log:**
_*Author Name:*_
* **Feat:** commit message
```

When `title` is set, the first line becomes `🚀 **branch-name** | **Project Name** | Title`. The `Done in` part is omitted when the duration is unknown or disabled.

### ClickUp task links

Reference ClickUp tasks in commit messages:

```md
task `86ddd0y92` Add new login functionality
ctask `TST-747` Add global log out functionality
```

These become `[86ddd0y92](https://app.clickup.com/t/86ddd0y92)` and `[TST-747](https://app.clickup.com/t/<WORKSPACE_ID>/TST-747)`. `ctask` is for custom task IDs.

### Conventional Commits

The types `build`, `chore`, `docs`, `feat`, `fix`, `refactor`, `revert`, `style`, `test`, `release`, `security`, `deps`, and `api` are recognized in any letter case and shown in bold, for example `**Feat(auth):**`. With `group_commits_by_type: "true"`, commits are listed under headings such as 🎯 Features, 🔧 Fixes, and 🔄 Refactors, and any other commits appear under 📋 Other.

### Commit statistics

With `show_commit_statistics: "true"`, a **📊 Stats** block is appended. A line is shown only when it is meaningful:

| Line | Shown when |
| --- | --- |
| 📝 Count | Always |
| 🎯 Release Type (Major / Minor / Patch) | A breaking change (`!:`), `feat`, or `fix` commit is present |
| 📁 Changed, ➕ Added, ➖ Removed | The value is non-zero |
| 🔧 Fixes, 🔄 Refactor | At least one such commit |
| ⏰ Last Deploy | At least 30 minutes since the previous run's commit |
| 👥 Contributor(s) | 2 or more authors |
| 🏆 Top Contributor | 3 or more authors |

### Agent commit filtering

With `filter_agent_commits: "true"` (the default), commits whose first line is `Initial plan`, or starts with `Agent-Logs-Url:` or `Co-authored-by:`, are hidden, and `Co-authored-by:` trailers are removed from message bodies. Commits authored by the Copilot SWE agent bot are attributed as `Contributor Name (Copilot Agent)`, using the co-author name when one is found.

### Failure notifications

When `notify_on_failure: "true"` and `workflow_status` is `failure`, the normal message is skipped. A short failure message is sent instead, containing the project, branch, triggering user, and a link to the workflow run. Add `if: always()` to the step so it runs after a failed step.

### Test mode

`test_mode: "true"` prints the full message, the resolved workspace name, and the character count to the job log. It does not send anything, and the API token is never printed.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| No "Change Log" section | First run on this branch, no previous successful run of this workflow, or every commit was filtered out. Check that `actions: read` permission is granted. |
| Stats show no file or line counts | History is missing. Use `actions/checkout` with `fetch-depth: 0`. |
| No `Done in` duration | `show_fetch_duration` is `"false"`, `gh` is unavailable, or the runner lacks GNU `date` (for example macOS). |
| Failure message never arrives | You need all three: `if: always()`, `notify_on_failure: "true"`, and `workflow_status: ${{ job.status }}`. |
| `Failed to send notification to ClickUp. HTTP code: …` | Check the token and IDs. The ClickUp response body is printed in the log below the error. |

## Development

The action is a **composite action** written in Bash, and has no build step or dependencies.

```
action.yml                 # public inputs and step wiring
steps/fetch-duration/      # run duration
steps/fetch-commits/       # commit fetch, formatting, statistics (scripts/*.sh)
steps/send-notification/   # message build, preview, send (scripts/*.sh)
.github/workflows/         # test (staging), prerelease (beta), release (production)
CHANGELOG                  # release notes; first "## [vX.Y.Z]" heading is the version
```

**Checks:**

```bash
for f in steps/*/scripts/*.sh; do bash -n "$f" && echo "OK $f"; done
```

**Testing:** pushing to `release/staging` runs [test-package.yml](.github/workflows/test-package.yml), which runs the action from the working tree. You can also run any workflow with `test_mode: "true"`. Note that the root `action.yml` loads its sub-steps from the pinned release tag, so changes under `steps/` take effect only after release.

**Releasing:**

1. Add a `## [vX.Y.Z] - YYYY-MM-DD` entry at the top of [CHANGELOG](CHANGELOG).
2. Update the three `steps/...@vX.Y.Z` refs in [action.yml](action.yml), and the examples in this README.
3. Merge to `release/beta` to create a prerelease, then to `release/production` to create a stable release (or promote the prerelease).

AI agents and maintainers: see [AGENTS.md](AGENTS.md) for architecture, conventions, and change rules.

## Contributing

1. Fork the repository and branch from `release/staging`.
2. Make your change in `action.yml` or `steps/`, following the existing script patterns.
3. Use [Conventional Commits](https://www.conventionalcommits.org/) messages.
4. Update this README and the CHANGELOG when inputs or behaviour change.
5. Open a pull request against `release/staging` with a clear description.

## Support

- [GitHub Issues](https://github.com/architweb/ClickUpNotification/issues): bugs and feature requests. Please include the action version, logs, steps to reproduce, and expected vs actual behaviour.
- [Changelog](CHANGELOG): release notes and migration guides.

---

_© 2025-2026 ArchitWeb. Released under the [MIT License](LICENSE)._
