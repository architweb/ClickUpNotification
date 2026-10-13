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
| Current version | `v3.3.0`, which is the first `## [v…]` heading in [CHANGELOG](CHANGELOG) |
| License | MIT ([LICENSE](LICENSE)) |

**What it does, in order:**

1. Normalizes `workflow_status` to `success`, `failure`, or `cancelled`, and decides whether to notify at all (`notify_on_failure` / `notify_on_cancel`).
2. Computes how long the current workflow run has taken so far.
3. On success only, finds the changelog base and fetches the commits from it to `GITHUB_SHA` through the GitHub API. The base is the first of:
   - the head SHA of the **last successful run of the same workflow on the same branch**;
   - `since_ref`;
   - the **last 30 days** of history.
4. Filters and formats those commits (merge commits, agent and bot commits, duplicates), groups them by author or by Conventional Commit type, optionally truncates to `max_commits`, and converts task IDs and PR references into links.
5. Optionally appends a compare link and a statistics block built from local `git diff` and `git show`.
6. Builds a Markdown message (a success, failure, or cancelled variant) and `POST`s it to the ClickUp v3 Chat API, retrying on 429 and 5xx responses. In test mode it prints the message to the log instead.
7. Exposes the outputs `message_id`, `message`, `commit_count`, `previous_sha`, and `compare_url`.

**Boundaries and limitations:**

- The action only posts to ClickUp **chat channels**. It does not create or update tasks.
- Every GitHub API call fails soft: it falls back to an empty value or `unknown`. Only the final ClickUp `POST` fails the step, and only after its retries are used up.
- The compare API returns at most 250 commits. The "young repository" fallback lists at most 100.

---

## 2. Technology Stack

| Area | Details (verified from source) |
| --- | --- |
| Language | Bash (`#!/bin/bash`, `set -e`). Uses bash arrays, `[[ ]]`, `<<<`, process substitution |
| Action format | GitHub composite actions (`action.yml`) |
| Runtime tools on the runner | `bash`, `gh` (GitHub CLI), `jq` (≥ 1.6, uses `--rawfile` and `fromdateiso8601`), `curl` (≥ 7.55, uses `-H @file`), `git`, `awk`, `sed`, `grep`, `od` |
| Platform | Primary target is `ubuntu-latest`. No GNU-only `date` flags are used (timestamps are parsed by `jq`) |
| External APIs | GitHub REST API (`gh api`, `curl`); ClickUp API **v3** `POST /workspaces/{id}/chat/channels/{id}/messages`; ClickUp API **v2** `GET /team` (test-mode name resolution only) |
| Package manager | None. `node_modules/` in `.gitignore` is a placeholder only |
| Tests | [bats-core](https://github.com/bats-core/bats-core) 1.11.0, run through `npx`, in `tests/` |
| Lint | ShellCheck (scripts and test helper) and actionlint 1.7.7 (workflows), both in [ci.yml](.github/workflows/ci.yml) |
| Database | None |

---

## 3. Repository Structure

```text
.
├── action.yml                       # Root composite action (public entry point)
├── steps/
│   ├── fetch-duration/action.yml    # Inline bash: run duration via gh api + jq
│   ├── fetch-commits/
│   │   ├── action.yml               # Orchestrates 4 scripts below
│   │   └── scripts/
│   │       ├── get-commit-data.sh       # Base SHA (prev run / since_ref / 30 days) -> JSON (+ .meta)
│   │       ├── process-commits.sh       # Filter, format, group, truncate -> Markdown changelog
│   │       ├── generate-statistics.sh   # git diff/show based stats block
│   │       └── build-changelog.sh       # Joins "Change Log" + compare link + stats
│   └── send-notification/
│       ├── action.yml               # Orchestrates scripts; test vs live branch; outputs
│       └── scripts/
│           ├── get-user-info.sh         # Triggering actor display name
│           ├── resolve-names.sh         # Workspace name (test mode only)
│           ├── build-message.sh         # success / failure / cancelled message, emoji map
│           ├── preview-message.sh       # Test-mode console output
│           └── send-to-clickup.sh       # POST to ClickUp v3 chat API with retries
├── tests/
│   ├── test_helper.bash             # Shared setup, gh/curl stubs, refute_contains helpers
│   ├── fixtures/commits.json        # Commit fixture covering most formatting rules
│   └── *.bats                       # One file per script
├── .github/workflows/
│   ├── ci.yml                       # ShellCheck + actionlint + bats on PRs and staging pushes
│   ├── test-package.yml             # End-to-end run of `uses: ./` with local sub-actions
│   ├── publish-beta.yml             # release/beta -> GitHub prerelease
│   └── publish.yml                  # release/production -> stable release
├── .gitattributes                   # Forces LF for scripts, YAML, Markdown, CHANGELOG
├── assets/                          # README screenshots (PNG)
├── CHANGELOG                        # Release notes; ALSO the version source of truth
├── README.md                        # Marketplace / consumer docs
├── LICENSE
└── Reports/                         # Git-ignored local working files
```

| Path | Purpose | Agents may modify? | Notes |
| --- | --- | --- | --- |
| `action.yml` | Public inputs and outputs, status resolution, step wiring | Yes, carefully | Public API. See §6 |
| `steps/*/action.yml` | Internal sub-actions | Yes | Pinned by tag from the root action. See §6.1 |
| `steps/*/scripts/*.sh` | All business logic | Yes | Positional-argument contracts. See §5.3 |
| `tests/` | Unit tests | Yes, and expected with every behaviour change | See §8 |
| `.github/workflows/` | CI and release automation | `ci.yml` and `test-package.yml` yes; `publish*.yml` only when asked | Publishing changes affect releases |
| `CHANGELOG` | Release notes and version source | Yes, when releasing or documenting changes | No file extension. The format is parsed by CI |
| `README.md` | Consumer docs | Yes | Keep in sync with inputs and outputs |
| `assets/` | Screenshots | Only replace when the message format changes visibly | Binary |
| `Reports/` | Local, git-ignored (`/Reports/*`) | Do not commit or reference | Not part of the product |

No files in this repository are generated. Everything is hand-maintained.

---

## 4. Instructions Directory and Files

No dedicated instructions directory or tool-specific rules files exist. Checked: `CLAUDE.md`, `GEMINI.md`, `AI.md`, `CONTRIBUTING.md`, `.cursor/`, `.windsurf/`, `.agent/`, `instructions/`, `docs/`, `.github/copilot-instructions.md`, and nested `AGENTS.md` files.

| Path | Purpose | Scope | When to read |
| --- | --- | --- | --- |
| `AGENTS.md` (this file) | Agent operating rules | Whole repository | Always, before any change |
| [README.md](README.md) → "Development" / "Contributing" | Short human contribution and release guidelines | Whole repository | Before opening a PR or releasing |
| [CHANGELOG](CHANGELOG) | History of behaviour changes and migration notes | Whole repository | Before changing inputs or output format, to understand compatibility promises |

**Precedence:** explicit user instructions, then this file, then README contribution notes. If nested `AGENTS.md` files are added later, the deeper file applies to its own subtree and overrides this file there.

---

## 5. Architecture and Data Flow

### 5.1 Root action ([action.yml](action.yml))

1. **🚦 Resolve Workflow Status** (`id: status`) outputs `status` (`success`, `failure`, or `cancelled`; anything else counts as `success`) and `notify` (`false` for a failure without `notify_on_failure`, or a cancelled run without `notify_on_cancel`).
2. **⏱️ Fetch Duration** runs if `notify` and `show_fetch_duration`. It runs for every status.
3. **📝 Fetch Commits** runs if `notify`, `status == success`, and `show_changelog_commits`.
4. **📢 Send ClickUp Notification** (`id: notify`) runs if `notify`. It receives the normalized `workflow_status`, and `build-message.sh` picks the message variant from it.

The root action exports **nothing** to `$GITHUB_ENV`. Every value reaches a script through the step's `env:` block or a sub-action input.

### 5.2 Inter-step contract: temp files plus step outputs

Steps never pass content through outputs. Each script writes to a `mktemp` file, and the **path** is passed on through `$GITHUB_OUTPUT`. The exception is the `message` output, which is written with a random heredoc delimiter.

| Producer | File | Format | Consumer |
| --- | --- | --- | --- |
| `get-commit-data.sh` | `$COMMITS_DATA` | JSON `[{sha, message, author}]` (oldest first), or `[]` | `process-commits.sh`, `generate-statistics.sh` |
| `get-commit-data.sh` | `$COMMITS_DATA.meta` | Shell `KEY=VALUE`: `CURRENT_SHA`, `BASE_SOURCE` (`previous_run`, `since_ref`, `last_30_days`), and optionally `PREVIOUS_SHA` and `COMPARE_URL`. Loaded with `source` and read with `sed` | `generate-statistics.sh`, `fetch-commits` outputs |
| `process-commits.sh` | `$COMMITS_OUTPUT` | Markdown changelog body (real newlines) | `build-changelog.sh` |
| `generate-statistics.sh` | `$STATS_OUTPUT` | Markdown stats block | `build-changelog.sh` |
| `build-changelog.sh` | `$COMMIT_FILE` → output `commit_file` | Markdown | `send-notification` → `build-message.sh` |
| `get-user-info.sh` | `$USER_INFO` | `TRIGGERING_USER_NAME="…"` (sanitized), loaded with `source` | `build-message.sh` |
| `resolve-names.sh` | `$NAMES_FILE` | `WORKSPACE_NAME="…"` (sanitized), loaded with `source` | `preview-message.sh` |
| `build-message.sh` | `$MESSAGE_FILE` | Final Markdown | `preview-message.sh` or `send-to-clickup.sh`; `message` output |
| `send-to-clickup.sh` | `$MESSAGE_ID_FILE` | ClickUp message ID | `message_id` output |

The steps that read these temp files also delete them.

### 5.3 Script argument contracts (positional)

Scripts take **positional arguments**. When you change the order or count, edit the calling `action.yml` **and** the tests in the same change. Append new arguments at the end.

| Script | Arguments | Env vars read |
| --- | --- | --- |
| `get-commit-data.sh` | `OUTPUT_FILE SINCE_REF` | `GH_TOKEN`, `GITHUB_REPOSITORY`, `GITHUB_RUN_ID`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_SERVER_URL` |
| `process-commits.sh` | `COMMITS_FILE FULL_COMMIT_MESSAGE OUTPUT_FILE FILTER_AGENT_COMMITS GROUP_BY_TYPE SHOW_PR_LINKS MAX_COMMITS COMPARE_URL` | `CLICKUP_WORKSPACE_ID`, `GITHUB_REPOSITORY`, `GITHUB_SERVER_URL` |
| `generate-statistics.sh` | `COMMITS_FILE META_FILE OUTPUT_FILE` | none (uses `git` in the working directory) |
| `build-changelog.sh` | `COMMITS_OUTPUT STATS_OUTPUT SHOW_STATS FINAL_OUTPUT SHOW_COMPARE_LINK COMPARE_URL` | none |
| `get-user-info.sh` | `OUTPUT_FILE` | `GH_TOKEN` (or `GITHUB_TOKEN`), `GITHUB_ACTOR` (or `TRIGGERING_ACTOR`), `GITHUB_API_URL` |
| `resolve-names.sh` | `WORKSPACE_ID OUTPUT_FILE` | `CLICKUP_API_TOKEN` |
| `build-message.sh` | `USER_INFO_FILE TITLE DESCRIPTION FORMATTED_DURATION COMMIT_FILE OUTPUT_FILE WORKFLOW_STATUS` | `CLICKUP_PROJECT_NAME`, `GITHUB_REF_NAME`, `STAGING_EMOJI`, `PRODUCTION_EMOJI`, `ENVIRONMENT_EMOJIS`, `GITHUB_SERVER_URL`, `GITHUB_REPOSITORY`, `GITHUB_RUN_ID` |
| `preview-message.sh` | `MESSAGE_FILE NAMES_FILE WORKSPACE_ID` | none |
| `send-to-clickup.sh` | `MESSAGE_FILE WORKSPACE_ID CHANNEL_ID [MESSAGE_ID_FILE]` | `CLICKUP_API_TOKEN`, `CLICKUP_MAX_ATTEMPTS` (default 3), `CLICKUP_RETRY_BASE_DELAY` (default 2 s; tests set it to 0) |

**Never pass a secret as a positional argument.** Secrets come from env vars, and `curl` receives them through `-H @file` or `-H @<(…)`.

### 5.4 Message format (from `build-message.sh`)

```text
{emoji} **{branch}** | **{project}** | {title}          # success, title set
{emoji} **{project}** deployed to **{branch}**          # success, no title
_{description}_                                         # only if set; directly under header

_Triggered by: {name}, Done in: {MM:SS}min_             # ", Done in" omitted when duration unknown

**Change Log:**                                         # only if commits remain
_*{Author or Type label}:*_
* **Feat(scope)!:** message

_…and N more commit(s)_ [View all](compare)             # only when truncated by max_commits

🔗 [View full diff](compare)                            # only if show_compare_link

📊 **Stats:**                                           # only if show_commit_statistics
```

- Failure: `❌ {emoji} **{project}** deployment to **{branch}** failed!`, then the triggered-by line, a warning line, and `🔗 [View Workflow Run](…)`.
- Cancelled: `⚠️ {emoji} **{project}** deployment to **{branch}** was cancelled.`, then the triggered-by line and the workflow-run link.
- Emoji: the first `ENVIRONMENT_EMOJIS` line `<glob>=<emoji>` whose glob matches the lower-cased branch (lines starting with `#` are comments). Otherwise `STAGING_EMOJI` if the branch contains `staging`, else `PRODUCTION_EMOJI`.
- Task links: ``task `ID` `` → `[ID](https://app.clickup.com/t/ID)`; ``ctask `ID` `` → `[ID](https://app.clickup.com/t/{CLICKUP_WORKSPACE_ID}/ID)`.
- Conventional types recognized (`CONVENTIONAL_COMMIT_TYPES` in `process-commits.sh`): `build|chore|docs|feat|fix|refactor|revert|style|test|release|security|deps|api`. They match case-insensitively; the type is capitalized while the scope and `!` are kept as written.
- `max_commits` keeps the **most recent** N entries after filtering and deduplication. Group order follows first appearance among the kept entries.

---

## 6. Change Rules

### 6.1 Sub-actions are pinned by tag (most important rule)

[action.yml](action.yml) calls its sub-actions by **published tag**, not by relative path:

```yaml
uses: architweb/ClickUpNotification/steps/fetch-duration@v3.3.0
uses: architweb/ClickUpNotification/steps/fetch-commits@v3.3.0
uses: architweb/ClickUpNotification/steps/send-notification@v3.3.0
```

Relative `./steps/` paths resolve against the **consumer's** workspace, which broke external users before v2.0.1. Do **not** change these refs to `./steps/...` in the committed file.

- When releasing `vX.Y.Z`, update all three refs to `@vX.Y.Z` in the same commit that adds the CHANGELOG entry. The release workflow tags that commit.
- [test-package.yml](.github/workflows/test-package.yml) rewrites these refs to `./steps/...` with `sed` **inside CI only**, so the staging test exercises the branch's own sub-actions. If you rename a step directory or change the ref format, update that `sed` expression too. It fails loudly if any ref is left unrewritten.

### 6.2 Public inputs and outputs (backward compatibility)

- Inputs and outputs in the root `action.yml` are a public API.
  - Adding an optional input whose default keeps today's behaviour is non-breaking.
  - Removing or renaming an input or output, or changing a default, is **breaking**. List it under "⚠️ Breaking Changes" or "⚠️ Behaviour Changes" in CHANGELOG with a migration guide.
- Boolean inputs are the **strings** `"true"`/`"false"`, compared as `== 'true'`. Keep that convention.
- A new input that a sub-action needs must be added in three places: root `inputs:`, the sub-action's `inputs:`, and the `with:` that passes it. Then map it into the step's `env:` and pass it to the script as a new positional argument at the end.
- Never put `${{ … }}` expressions inside input `description` strings.
- Update the README "Inputs" and "Outputs" tables and, if relevant, the examples.

### 6.3 Adding a script

- Place it under `steps/<step>/scripts/`, starting with `#!/bin/bash`, a one-line purpose comment, and `set -e`.
- Files are committed as `100644`. Every call site runs `chmod +x "$GITHUB_ACTION_PATH/scripts/<name>.sh"` before invoking it, so follow that pattern.
- Read inputs from positional args, write results to an output file path argument, and expose the path through `"$GITHUB_OUTPUT"`.
- Add a `tests/<name>.bats` file.

### 6.4 Configuration, dependencies, generated files

- Do not introduce Node, Python, or other runtime dependencies into the action itself without user approval. It intentionally relies only on tools preinstalled on GitHub-hosted runners. Tests may use `npx` for bats.
- No generated files, migrations, or schemas exist.

---

## 7. Coding Conventions (observed and enforced)

- Variables are `UPPER_SNAKE_CASE`, and helper functions are `lower_snake_case` (`format_task_links`, `format_conventional_commit`, `title_case`, `is_copilot_agent`, `extract_coauthor_name`, `linkify_pr_refs`, `resolve_emoji`). Function locals use `local`, declared separately from assignment.
- **Never use `echo -e` on content.** Build multi-line strings with `NL=$'\n'` and write them with `printf '%s\n'`. Pipe user-controlled text with `printf '%s\n' "$x" |`, not `echo`.
- **Inputs reach `run:` blocks only through `env:`.** Never write `${{ inputs.* }}` inside a `run:` script.
- **Fail soft** on optional data, for example `$(gh api … 2>/dev/null || echo "")` and `grep -c … || true`. Empty results produce an empty output file, not an error.
- **Fail hard** only on the final ClickUp send: `::error::` annotation plus `exit 1`. Use `::warning::` for degraded but continuing behaviour (retries, invalid `max_commits`, an unresolvable `since_ref`).
- JSON is built with `jq -n --arg/--rawfile` (never by string concatenation) and parsed with `jq -r`.
- Temp files come from `mktemp`, and the consuming step removes them (`rm -f` or `trap … EXIT`).
- Values written to files that are loaded with `source` are sanitized with `tr -c` allow-lists and quoted.
- `"$GITHUB_OUTPUT"` is always quoted (actionlint enforces this).
- Step names in `action.yml` use an emoji prefix (`🚦`, `⏱️`, `📝`, `📢`).
- Commit messages follow **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `chore:`, `test:`, `docs:`).

---

## 8. Development Workflow and Validation

There is no install, build, or local run step. Validation commands (all of these were run on v3.3.0):

```bash
shellcheck steps/*/scripts/*.sh tests/*.bash     # must be clean (CI runs default severity)
npx --yes bats@1.11.0 tests                       # 49 tests; needs jq + git on PATH
npx --yes bats@1.11.0 tests/process-commits.bats  # one file
npx --yes bats@1.11.0 -f 'max_commits' tests      # tests whose name matches
actionlint                                        # workflows; CI uses rhysd/actionlint:1.7.7
```

**Writing tests:**

- `load test_helper` and call `common_setup` in `setup()`. It sets the `GITHUB_*` variables (`GITHUB_REPOSITORY=org/repo`, `GITHUB_SHA=headsha`, `GITHUB_RUN_ID=42`, `GITHUB_REF_NAME=main`) and `CLICKUP_WORKSPACE_ID=999`.
- Use `stub_gh` for GitHub API calls. Put canned responses in `$GH_RESP/{run,run-history,compare,ref,commits-until,commits-since}.json`; the calls made are logged to `$GH_CALLS`.
- Use `stub_curl <code>...` for ClickUp calls. It returns one HTTP code per call, `$CURL_BODY` as the body, logs arguments to `$CURL_ARGS`, and saves the last payload to `$CURL_PAYLOAD`.
- **Do not write `! grep …` in the middle of a test.** Bats does not fail on it. Use `refute_contains FILE TEXT` or `refute_contains_i`.
- On Windows/Cygwin the suite is slow (around 10 minutes) because of process spawning. On Linux it takes seconds.

**End-to-end validation (CI):**

1. Pull requests run [ci.yml](.github/workflows/ci.yml) (lint and unit tests).
2. Pushing to `release/staging` runs [test-package.yml](.github/workflows/test-package.yml). It sends a real message using the branch's sub-actions, checks the outputs, and previews the grouped/limited, failure, and cancelled messages in test mode.

Required repository secrets for these workflows: `CLICKUP_API_TOKEN`, `CLICKUP_WORKSPACE_ID`, `CLICKUP_CHANNEL_ID`, `CLICKUP_PROJECT_NAME`.

---

## 9. Security and Privacy

- **Never** print, log, or echo `clickup_api_token` or the GitHub token. `preview-message.sh` prints `API Token: Provided (hidden for security)`. Keep it that way.
- Tokens are passed as env vars (`CLICKUP_API_TOKEN`, `GH_TOKEN`) on the steps that need them, and to `curl` through a header file. A test asserts the token never appears in `curl` arguments.
- Do not add anything to `$GITHUB_ENV`. It leaks into the consumer's later steps.
- `resolve-names.sh` skips API calls when values are masked (`***`). Preserve this guard.
- Files loaded with `source` (`USER_INFO`, `.meta`, `NAMES_FILE`) must only contain sanitized or known-safe values. Never write raw commit text or API responses into them. A test checks that a malicious workspace name does not execute.
- Never add real IDs, tokens, or workspace URLs to docs, tests, or examples. Use `${{ secrets.* }}` placeholders and fake IDs (`111`, `999`).
- `Reports/` is git-ignored. Do not move its contents into tracked paths.

---

## 10. Build, Release, and Deployment

Branches: `release/staging` (default branch, PR base), `release/beta`, `release/production`.

| Branch push | Workflow | Result |
| --- | --- | --- |
| any PR, `release/staging` | `ci.yml` | ShellCheck, actionlint, bats |
| `release/staging` | `test-package.yml` | End-to-end run with local sub-actions |
| `release/beta` | `publish-beta.yml` | Reads the version from CHANGELOG, then `gh release create --prerelease`. Fails if the tag already exists |
| `release/production` | `publish.yml` | Creates a stable release, **or** promotes an existing prerelease to `--latest`. Fails if a stable release with that tag exists |

**Version source of truth.** CI extracts the version with `grep -m 1 "## \[v" CHANGELOG`, and the release notes are the text from that heading to the next `## [vX.Y.Z]` heading. Keep the exact heading format `## [vX.Y.Z] - YYYY-MM-DD` at the top of the file.

**Release checklist:**

1. Add `## [vX.Y.Z] - YYYY-MM-DD` at the top of `CHANGELOG`, using the existing emoji sections and a migration guide if needed.
2. Update the three sub-action refs in `action.yml` to `@vX.Y.Z` (§6.1).
3. Update `@vX.Y.Z` in README examples.
4. The dogfooding step in `publish*.yml` (currently `@v3.1.0`) must **not** point at the version being released. GitHub resolves `uses:` refs when the job starts, before the job creates the tag. Bump it only to an already-published version, and only when asked.
5. Merge to `release/beta`, then to `release/production`.

Do not push to, merge into, or create tags on `release/*` branches without explicit user approval. These actions publish releases.

---

## 11. Known Limitations

1. The GitHub compare API returns at most **250 commits**, and the young-repository fallback lists at most **100**. Larger ranges are cut off silently.
2. In full-message mode, a commit body is separated from its header by a line containing two spaces. This is cosmetic and kept for output stability.
3. `since_ref` is only a fallback. It does not override an existing previous successful run.
4. `message_id` depends on ClickUp returning `id` (or `data.id`) in the create-message response. It is empty otherwise.

---

## 12. Agent Operating Procedure

1. Read this file, then [action.yml](action.yml) and the `action.yml` of the step you are changing.
2. Read the target script and its `tests/*.bats` file fully.
3. Trace the data path (§5.2) and the argument and env contract (§5.3) for anything you touch.
4. Make the smallest change that fits existing patterns (§7). Keep inputs and outputs backward compatible (§6.2).
5. Add or update bats tests for every behaviour change, and run them (§8).
6. If you change inputs, outputs, or the message format, update `README.md` and add a CHANGELOG entry. Ask which version to use if it is unclear.
7. Run `shellcheck` and, for workflow changes, `actionlint`.
8. Review the full diff (`git diff`). Confirm that no secrets or real IDs were added and nothing under `Reports/` is staged.
9. Report what you verified locally, what only CI can verify, and that sub-step changes take effect for consumers only after a release (§6.1).
