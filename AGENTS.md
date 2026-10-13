# AGENTS.md

Guidance for AI coding agents working on **ClickUpNotification**, a GitHub composite action that posts a deployment summary (changelog, duration, statistics) to a ClickUp chat channel.

Read this file completely before changing anything. [README.md](README.md) is the public, consumer-facing documentation (it is also the GitHub Marketplace page); this file covers how the action is built and how to change it safely.

---

## 1. Project Overview

| Item | Value |
| --- | --- |
| Type | GitHub Action, `runs.using: composite` |
| Consumers | Other repositories' workflows: `uses: architweb/ClickUpNotification@vX.Y.Z` |
| Published to | GitHub Marketplace (`branding` in [action.yml](action.yml)) |
| Current version | `v3.2.0`, which is the first `## [v…]` heading in [CHANGELOG](CHANGELOG) |
| License | MIT ([LICENSE](LICENSE)) |

**What it does, in order:**

1. Computes how long the current workflow run has taken so far.
2. Finds the head SHA of the **last successful run of the same workflow on the same branch**, then fetches the commits between that SHA and `GITHUB_SHA` through the GitHub compare API.
3. Filters and formats those commits (merge commits, agent and bot commits, duplicates), groups them by author or by Conventional Commit type, and converts task IDs and PR references into links.
4. Optionally appends a statistics block built from local `git diff` and `git show`.
5. Builds a Markdown message and `POST`s it to the ClickUp v3 Chat API. In test mode it prints the message to the log instead.
6. On a failed workflow, it can send a short failure message instead.

**Boundaries and limitations:**

- No changelog is produced on the first run of a workflow or branch, because there is no previous successful run to compare against. The same happens when the previous SHA equals the current SHA.
- The action only posts to ClickUp **chat channels**. It does not create or update tasks.
- Every network call except the final ClickUp `POST` fails soft: it falls back to an empty value or `unknown`.

---

## 2. Technology Stack

| Area | Details (verified from source) |
| --- | --- |
| Language | Bash (`#!/bin/bash`, `set -e`). Uses bash arrays, `[[ ]]`, `<<<` |
| Action format | GitHub composite actions (`action.yml`) |
| Runtime tools on the runner | `bash`, `gh` (GitHub CLI), `jq`, `curl`, `git`, `awk`, `sed`, `grep`, `date` |
| Platform assumptions | GNU `date -d` in [steps/fetch-duration/action.yml](steps/fetch-duration/action.yml). On BSD/macOS `date` the duration falls back to `unknown`. Primary target: `ubuntu-latest` |
| External APIs | GitHub REST API (via `gh api` and `curl`); ClickUp API **v3** `POST /workspaces/{id}/chat/channels/{id}/messages`; ClickUp API **v2** `GET /team` (test-mode name resolution only) |
| Package manager | None. No `package.json`; `node_modules/` in `.gitignore` is a placeholder only |
| Tests | None automated. Manual validation through [.github/workflows/test-package.yml](.github/workflows/test-package.yml) and `test_mode` |
| Lint / format | None configured. `shellcheck` and `actionlint` are not set up in the repo |
| Database | None |

---

## 3. Repository Structure

```
.
├── action.yml                       # Root composite action (public entry point)
├── steps/
│   ├── fetch-duration/action.yml    # Inline bash: run duration via gh api
│   ├── fetch-commits/
│   │   ├── action.yml               # Orchestrates 4 scripts below
│   │   └── scripts/
│   │       ├── get-commit-data.sh       # Previous successful SHA + compare API -> JSON (+ .meta)
│   │       ├── process-commits.sh       # Filter, format, group -> Markdown changelog
│   │       ├── generate-statistics.sh   # git diff/show based stats block
│   │       └── build-changelog.sh       # Joins "Change Log" + stats
│   └── send-notification/
│       ├── action.yml               # Orchestrates scripts; test vs live branch
│       └── scripts/
│           ├── get-user-info.sh         # Triggering actor display name
│           ├── resolve-names.sh         # Workspace name (test mode only)
│           ├── build-message.sh         # Header, description, duration, changelog
│           ├── preview-message.sh       # Test-mode console output
│           └── send-to-clickup.sh       # POST to ClickUp v3 chat API
├── .github/workflows/
│   ├── test-package.yml             # Runs `uses: ./` on push to release/staging
│   ├── publish-beta.yml             # release/beta -> GitHub prerelease
│   └── publish.yml                  # release/production -> stable release
├── assets/                          # README screenshots (PNG)
├── CHANGELOG                        # Release notes; ALSO the version source of truth
├── README.md                        # Marketplace / consumer docs
├── LICENSE
└── Reports/                         # Git-ignored local working files
```

| Path | Purpose | Agents may modify? | Notes |
| --- | --- | --- | --- |
| `action.yml` | Public inputs, env setup, step wiring, inline failure notification | Yes, carefully | Public API. See §6 |
| `steps/*/action.yml` | Internal sub-actions | Yes | Pinned by tag from the root action. See §6.1 |
| `steps/*/scripts/*.sh` | All business logic | Yes | Positional-argument contracts with their `action.yml`. See §5 |
| `.github/workflows/` | This repo's own CI and release automation | Only when asked | Changes affect releases |
| `CHANGELOG` | Release notes and version source | Yes, when releasing or documenting changes | No file extension. The format is parsed by CI |
| `README.md` | Consumer docs | Yes | Keep in sync with inputs |
| `assets/` | Screenshots | Only replace when the message format changes visibly | Binary |
| `Reports/` | Local, git-ignored (`/Reports/*`) | Do not commit or reference | Not part of the product |

No files in this repository are generated. Everything is hand-maintained.

---

## 4. Instructions Directory and Files

No dedicated instructions directory or tool-specific rules files were found. Checked: `CLAUDE.md`, `GEMINI.md`, `AI.md`, `CONTRIBUTING.md`, `.cursor/`, `.windsurf/`, `.agent/`, `instructions/`, `docs/`, `.github/copilot-instructions.md`, and nested `AGENTS.md` files.

| Path | Purpose | Scope | When to read |
| --- | --- | --- | --- |
| `AGENTS.md` (this file) | Agent operating rules | Whole repository | Always, before any change |
| [README.md](README.md) → "Contributing" | Short human contribution guidelines | Whole repository | Before opening a PR |
| [CHANGELOG](CHANGELOG) | History of behaviour changes and migration notes | Whole repository | Before changing inputs or output format, to understand compatibility promises |

**Precedence:** explicit user instructions, then this file, then README contribution notes. If nested `AGENTS.md` files are added later, the deeper file applies to its own subtree and overrides this file there.

---

## 5. Architecture and Data Flow

### 5.1 Root action ([action.yml](action.yml))

1. **Set Environment Variables** writes these to `$GITHUB_ENV` so every later step (and the scripts) can read them:
   `CLICKUP_WORKSPACE_ID`, `CLICKUP_PROJECT_NAME`, `GITHUB_TOKEN` (from `github.token`), `REPO_NAME`, `TRIGGERING_ACTOR`, `STAGING_EMOJI`, `PRODUCTION_EMOJI`.
2. **⏱️ Fetch Duration** runs if `show_fetch_duration == 'true'` and `workflow_status != 'failure'`.
3. **📝 Fetch Commits** runs if `show_changelog_commits == 'true'` and not failure.
4. **📢 Send ClickUp Notification** runs if not failure.
5. **❌ Send Failure Notification** runs only if `notify_on_failure == 'true'` and `workflow_status == 'failure'`. It is written as **inline bash** and duplicates logic from `get-user-info.sh`, `build-message.sh` (emoji), and `send-to-clickup.sh`. If you change any of those, update this step too.

`workflow_status` values other than `failure` (for example `cancelled`) take the normal success path.

### 5.2 Inter-step contract: temp files plus step outputs

Steps never pass content through outputs. Each script writes to a `mktemp` file, and the **path** is passed on through `$GITHUB_OUTPUT`.

| Producer | File | Format | Consumer |
| --- | --- | --- | --- |
| `get-commit-data.sh` | `$COMMITS_DATA` | JSON `[{sha, message, author}]`, or `[]` | `process-commits.sh`, `generate-statistics.sh` |
| `get-commit-data.sh` | `$COMMITS_DATA.meta` | Shell `KEY=VALUE` (`PREVIOUS_SHA`, `CURRENT_SHA`), loaded with `source` | `generate-statistics.sh` |
| `process-commits.sh` | `$COMMITS_OUTPUT` | Markdown changelog body | `build-changelog.sh` |
| `generate-statistics.sh` | `$STATS_OUTPUT` | Markdown stats block (contains literal `\n` expanded by `echo -e`) | `build-changelog.sh` |
| `build-changelog.sh` | `$COMMIT_FILE` → output `commit_file` | Markdown | `send-notification` → `build-message.sh` |
| `get-user-info.sh` | `$USER_INFO` | `TRIGGERING_USER_NAME="…"`, loaded with `source` | `build-message.sh` |
| `resolve-names.sh` | `$NAMES_FILE` | `WORKSPACE_NAME=…`, loaded with `source` | `preview-message.sh` |
| `build-message.sh` | `$MESSAGE_FILE` | Final Markdown | `preview-message.sh` or `send-to-clickup.sh` |

Files that are loaded with `source` are executed as shell. Any value written into them must stay sanitized (see §9).

### 5.3 Script argument contracts (positional)

Scripts take **positional arguments only**. Changing the order or count requires editing the calling `action.yml` in the same change.

| Script | Arguments |
| --- | --- |
| `get-commit-data.sh` | `OUTPUT_FILE` |
| `process-commits.sh` | `COMMITS_FILE FULL_COMMIT_MESSAGE OUTPUT_FILE FILTER_AGENT_COMMITS GROUP_BY_TYPE SHOW_PR_LINKS` |
| `generate-statistics.sh` | `COMMITS_FILE META_FILE OUTPUT_FILE` |
| `build-changelog.sh` | `COMMITS_OUTPUT STATS_OUTPUT SHOW_STATS FINAL_OUTPUT` |
| `get-user-info.sh` | `OUTPUT_FILE` |
| `resolve-names.sh` | `API_TOKEN WORKSPACE_ID OUTPUT_FILE` |
| `build-message.sh` | `USER_INFO_FILE TITLE DESCRIPTION FORMATTED_DURATION COMMIT_FILE OUTPUT_FILE` |
| `preview-message.sh` | `MESSAGE_FILE NAMES_FILE WORKSPACE_ID` |
| `send-to-clickup.sh` | `MESSAGE_FILE API_TOKEN WORKSPACE_ID CHANNEL_ID` |

Scripts also read env vars set by the root action (`CLICKUP_WORKSPACE_ID`, `CLICKUP_PROJECT_NAME`, `REPO_NAME`, `TRIGGERING_ACTOR`, `GITHUB_TOKEN`, `*_EMOJI`) and default runner vars (`GITHUB_REPOSITORY`, `GITHUB_REPOSITORY_OWNER`, `GITHUB_RUN_ID`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_SERVER_URL`). Because of this, the sub-actions are **not fully standalone**: used without the root action, they lose ctask links, the project name, and `REPO_NAME`.

### 5.4 Message format (from `build-message.sh`)

```
{emoji} **{branch}** | **{project}** | {title}          # when title is set
{emoji} **{project}** deployed to **{branch}**          # otherwise
_{description}_                                         # only if set; directly under header
                                                        
_Triggered by: {name}, Done in: {MM:SS}min_             # ", Done in" omitted when duration is unknown
                                                        
**Change Log:**                                         # only if commits remain
_*{Author or Type label}:*_
* **Feat(scope):** message
                                                        
📊 **Stats:**                                           # only if show_commit_statistics
```

- Emoji: `STAGING_EMOJI` if `GITHUB_REF_NAME` contains `staging` (case-insensitive), otherwise `PRODUCTION_EMOJI`.
- Task links: ``task `ID` `` → `[ID](https://app.clickup.com/t/ID)`; ``ctask `ID` `` → `[ID](https://app.clickup.com/t/{CLICKUP_WORKSPACE_ID}/ID)`.
- Conventional types recognised (`CONVENTIONAL_COMMIT_TYPES` in `process-commits.sh`): `build|chore|docs|feat|fix|refactor|revert|style|test|release|security|deps|api`, matched case-insensitively and normalised to `**Type(scope)!:**`.
- Stats lines are shown conditionally. Release Type is hidden for non-conventional commits, Last Deploy if under 30 min, Contributor(s) if fewer than 2, Top Contributor if fewer than 3, and zero-valued file/line/fix/refactor lines are hidden.

---

## 6. Change Rules

### 6.1 Sub-actions are pinned by tag (most important rule)

[action.yml](action.yml) calls its sub-actions by **published tag**, not by relative path:

```yaml
uses: architweb/ClickUpNotification/steps/fetch-duration@v3.2.0
uses: architweb/ClickUpNotification/steps/fetch-commits@v3.2.0
uses: architweb/ClickUpNotification/steps/send-notification@v3.2.0
```

This was a deliberate fix in v2.0.1: relative `./steps/` paths broke for external consumers. Do **not** change them back to `./steps/...`.

Consequences:

- When releasing version `vX.Y.Z`, update all three refs to `@vX.Y.Z` in the same commit that adds the `## [vX.Y.Z]` CHANGELOG entry. The release workflow tags that commit, so the refs resolve to the code being released.
- [test-package.yml](.github/workflows/test-package.yml) uses `uses: ./`, which loads the **local root** `action.yml`, but the root still pulls sub-actions from the **published tag**. Changes under `steps/` are therefore **not exercised** by the staging test until they are tagged. Say this explicitly when reporting validation of sub-step changes.

### 6.2 Public inputs (backward compatibility)

- Inputs in the root `action.yml` are a public API. Adding an optional input with a default that keeps today's behaviour is non-breaking. Removing or renaming an input, or changing a default, is **breaking**: it needs a major bump, or must at least be called out under "⚠️ Breaking Changes" with a migration guide in CHANGELOG (see the v3.1.0 entry for the established pattern).
- Boolean inputs are the **strings** `"true"`/`"false"`, compared as `== 'true'`. Keep that convention.
- A new input that a sub-action needs must be added in three places: root `inputs:`, the sub-action's `inputs:`, and the `with:` that passes it. Then thread it to the script as a new positional argument appended at the end, so existing argument positions do not shift.
- Update the README "Inputs" table and, if relevant, the "Example Usage" block.

### 6.3 Adding a script

- Place it under `steps/<step>/scripts/`, start it with `#!/bin/bash`, a one-line purpose comment, and `set -e`.
- Files are committed as `100644`. Every call site runs `chmod +x "$GITHUB_ACTION_PATH/scripts/<name>.sh"` before invoking it, so follow the same pattern.
- Read inputs from positional args, write results to an output file path argument, and expose the path through `$GITHUB_OUTPUT`.

### 6.4 Configuration, dependencies, generated files

- No dependency manifests exist. Do not introduce Node, Python, or other runtimes without user approval. The action intentionally relies only on tools preinstalled on GitHub-hosted runners.
- No generated files, migrations, or schemas exist.

---

## 7. Coding Conventions (observed)

**Confirmed from the code:**

- Variables are `UPPER_SNAKE_CASE`, and helper functions are `lower_snake_case` (`format_task_links`, `format_conventional_commit`, `title_case`, `extract_coauthor_name`, `linkify_pr_refs`). Function locals use `local`.
- Inputs are read as positional args into named variables at the top of the script.
- **Fail soft** on optional data, for example `$(gh api … 2>/dev/null || echo "")` and `grep -c … || echo "0"`. Empty results produce an empty output file, not an error.
- **Fail hard** only on the final ClickUp send: `::error::` annotation plus `exit 1`.
- Errors use GitHub workflow commands (`echo "::error::…"`). Success logs use `--- … ---`.
- JSON is built with `jq -n --arg` (never string concatenation) and parsed with `jq -r`.
- Temp files come from `mktemp` and are removed with `rm -f` after use.
- User-supplied names are sanitized with `tr -c '[:alnum:] ' ' ' | tr -s ' '` before being written to files that are loaded with `source`.
- Step names in `action.yml` use an emoji prefix (`⏱️`, `📝`, `📢`, `❌`).
- Commit messages in this repo follow **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `chore:`, `test:`). The action renders these specially, so keep using them.

**Recommendations (not currently enforced):**

- Pass `${{ inputs.* }}` into `run:` blocks through `env:` rather than interpolating them into the script text (see §9).
- Run `shellcheck` locally if it is available. It is not part of CI.

---

## 8. Development Workflow and Validation

There is no install, build, or local run step. Verified commands:

```bash
# Syntax-check every script (verified working on this repo)
for f in steps/*/scripts/*.sh; do bash -n "$f" && echo "OK $f"; done
```

Optional, only if installed (neither is configured in the repo):

```bash
shellcheck steps/*/scripts/*.sh
actionlint
```

**Exercising script logic locally (unverified recipe).** Most scripts can be driven with a fixture file plus the env vars they expect. For example, for `process-commits.sh`:

```bash
echo '[{"sha":"1","message":"feat: add x\n\nbody","author":"jane doe"}]' > /tmp/c.json
CLICKUP_WORKSPACE_ID=123 GITHUB_REPOSITORY=o/r \
  bash steps/fetch-commits/scripts/process-commits.sh /tmp/c.json true /tmp/out.md true false false
cat /tmp/out.md
```

Scripts that call `gh`, `curl`, or `git diff` need network access, credentials, or real history, so validate them in CI.

**End-to-end validation (CI):**

1. Push to `release/staging`. [test-package.yml](.github/workflows/test-package.yml) runs `uses: ./` with statistics, duration, and changelog enabled and posts to the test channel. Remember §6.1: sub-actions still come from the pinned tag.
2. Consumers and maintainers can set `test_mode: "true"` to print the message in the job log instead of sending it.

Required repository secrets for these workflows: `CLICKUP_API_TOKEN`, `CLICKUP_WORKSPACE_ID`, `CLICKUP_CHANNEL_ID`, `CLICKUP_PROJECT_NAME`.

---

## 9. Security and Privacy

- **Never** print, log, or echo `clickup_api_token` or `GITHUB_TOKEN`. `preview-message.sh` deliberately prints `API Token: Provided (hidden for security)`. Keep it that way.
- `resolve-names.sh` skips API calls when values are masked (`***`). Preserve this guard.
- The root action writes `GITHUB_TOKEN` to `$GITHUB_ENV`, which exposes it to **all later steps in the consumer's job**. Do not add more secrets to `$GITHUB_ENV`.
- **Injection surface:** `title`, `description`, and the ClickUp IDs and token are interpolated directly into `run:` scripts with `${{ inputs.* }}`. A value containing `"`, `` ` `` or `$(` can break or alter the script. When touching these lines, prefer moving values into `env:` and referencing `"$VAR"`.
- Files loaded with `source` (`USER_INFO`, `.meta`, `NAMES_FILE`) must only contain sanitized values. Do not write raw commit text or API responses into them.
- Never add real IDs, tokens, or workspace URLs to docs, tests, or examples. Use `${{ secrets.* }}` placeholders.
- `Reports/` is git-ignored. Do not move its contents into tracked paths.

---

## 10. Build, Release, and Deployment

Branches: `release/staging` (default branch, PR base), `release/beta`, `release/production`.

| Branch push | Workflow | Result |
| --- | --- | --- |
| `release/staging` | `test-package.yml` | Runs the action from the working tree and posts a test notification |
| `release/beta` | `publish-beta.yml` | Reads the version from CHANGELOG, then `gh release create --prerelease`. Fails if the tag already exists |
| `release/production` | `publish.yml` | Creates a stable release, **or** promotes an existing prerelease to `--latest`. Fails if a stable release with that tag exists |

**Version source of truth.** CI extracts the version with `grep -m 1 "## \[v" CHANGELOG`, and the release notes are the text from that heading to the next `## [vX.Y.Z]` heading. Keep the exact heading format `## [vX.Y.Z] - YYYY-MM-DD` at the top of the file.

**Release checklist:**

1. Add `## [vX.Y.Z] - YYYY-MM-DD` at the top of `CHANGELOG`, using the existing emoji sections and a migration guide if needed.
2. Update the three sub-action refs in `action.yml` to `@vX.Y.Z` (§6.1).
3. Update `@vX.Y.Z` in README examples.
4. Optionally update the action version used by `publish*.yml`. These currently pin `@v3.1.0`, so confirm with the user before bumping.
5. Merge to `release/beta`, then to `release/production`.

Do not push to, merge into, or create tags on `release/*` branches without explicit user approval. These actions publish releases.

---

## 11. Known Issues (observed, not yet fixed)

Report these rather than silently "fixing" them inside unrelated changes:

1. **Test-mode temp files are not cleaned up.** In [steps/send-notification/action.yml](steps/send-notification/action.yml) "Preview Message", the line before `rm -f` ends with a trailing `\`. The `rm -f …` line therefore becomes extra arguments to `preview-message.sh` and never runs.
2. **The staging test does not exercise sub-step changes** (see §6.1).
3. **`echo -e` is applied to the full message** in `build-message.sh` and `build-changelog.sh`. Backslash sequences inside commit messages (for example `\t`) are interpreted.
4. **Copilot co-author attribution is global.** `process-commits.sh` pre-scans for the *first* `Co-authored-by:` across all commits and uses that one name for every Copilot-bot commit.
5. **Duration needs GNU `date`.** On macOS runners it always shows `unknown`.
6. **`cancelled` runs** send the normal success-style message.

---

## 12. Agent Operating Procedure

1. Read this file, then [action.yml](action.yml) and the `action.yml` of the step you are changing.
2. Read the target script fully. Most behaviour lives in `process-commits.sh` and `build-message.sh`.
3. Trace the data path (§5.2) and argument contract (§5.3) for anything you touch.
4. Make the smallest change that fits existing patterns (§7). Keep inputs backward compatible (§6.2).
5. If you change inputs or the message format, update `README.md` (Inputs table and examples) and add a CHANGELOG entry under an unreleased or next-version heading. Ask which version to use if it is unclear.
6. If you change the failure path or user, emoji, or send logic, keep the inline failure step in `action.yml` consistent.
7. Run `bash -n` on every changed script. Run `shellcheck` if available.
8. Review the full diff (`git diff`). Confirm that no secrets or real IDs were added and nothing under `Reports/` is staged.
9. Report what you verified locally, what only CI can verify, and whether sub-step changes need a tag before they take effect (§6.1).
