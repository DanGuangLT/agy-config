# Design: Shared agy configuration with automatic backups and updates

Date: 2026-11-11 - Repo: `DanGuangLT/Pre-configured-skills-for-the-antigravity-agent` (public)

## 1. Purpose and motivation

The user (the repo owner) has spent time configuring Antigravity CLI (`agy`): working rules, command permissions, skills, and plugins. They want:

- **Never set up everything from scratch again**: when moving to another machine, one command makes the new machine match the old one.
- **Never lose backups**: every change on the machine is automatically pushed to the repo.
- **Keep up with technology**: AI changes quickly, so skills/plugins must update automatically to new versions, with a way to return to an older version if an update breaks.
- **Self-sufficiency**: once built, `agy` itself handles all maintenance at the user's request; Claude Code or anyone else is not needed.
- **Sharing**: the repo is public so both Vietnamese and international users can install it and contribute through PRs.

## 2. Goals, non-goals, and unacceptable outcomes

**Goals**

1. Install on a new machine that only has `agy`: a single command gives agy all the rules, permissions, skills, plugins, and automation.
2. The owner's machine automatically syncs machine -> repo during weekly maintenance when agy starts; changes made through the `agy-self-config` skill are backed up immediately after each change.
3. The owner's machine automatically updates skills/plugins from their original sources every week, with locked versions for rollback. Every machine automatically receives repo -> machine updates, only from `main`.
4. agy has a dedicated skill to maintain this configuration at the user's request.
5. The README guides users who have just downloaded agy, in English (`README.md`) and Vietnamese (`README.vi.md`).

**Non-goals (for now)**

- The Antigravity desktop/IDE application: only agy CLI is in scope.
- macOS/Linux: leave room for contributors to add support later; the first version is Windows only.
- Syncing Claude Code configuration.

**Unacceptable outcomes** (any of these means failure even if everything "works")

- Secrets (tokens, passwords, API keys, personal email addresses) reach the public repo.
- agy conversation history, logs, or caches reach the repo.
- Code that the owner has not approved runs automatically on users' machines.
- An update breaks agy without a way to roll back.
- A user's personal settings in `settings.json` are overwritten and lost.

## 3. agy configuration map (verified on the owner's machine, agy 1.5.5)

| Item | Location on the machine | How the repo manages it |
|---|---|---|
| Global rules | `~/.gemini/GEMINI.md` | Generated from `core` + `profile` (section 5.2) |
| CLI settings | `~/.gemini/antigravity-cli/settings.json` | Merge only `permissions.allow`; preserve all other keys |
| Standalone skills | `~/.gemini/config/skills/<name>/` | The vercel-labs `skills` tool (`npx skills add ... -g -a antigravity`), with a lock at `~/.agents/.skill-lock.json` |
| Plugins | `~/.gemini/config/plugins/<name>/` (with `plugin.json` + `skills/`) | See section 4 |
| Marketplace plugin list | `~/.gemini/config/config.json` -> `plugins` | Read through `agy plugin list --json` |
| MCP | `~/.gemini/config/mcp_config.json` | Store server definitions; replace secret values with `${VARIABLE_NAME}` |
| Global hooks | `~/.gemini/config/hooks.json` | Not used; hooks are bundled with the repo's own plugin |
| History, logs, caches | `~/.gemini/antigravity*/{conversations,brain,cache,...}`, `*.db`, `history.jsonl`, `cli.log` | **Never** sync |

Verified agy behavior that this design relies on:

- `permissions.allow` matches the **entire command exactly** (`command(git status)` does not allow `git status --short`); `*` is not supported.
- `agy plugin install <directory-path>` installs a local plugin; `agy plugin validate <directory>` validates a plugin.
- Plugins can include their own `hooks.json`. The repo's hook uses the `SessionStart` event. Hooks run through `cmd /c` on Windows, have a default timeout of 30 seconds, receive JSON through stdin, and must print JSON to stdout.
- In `--print` mode (background execution), commands that have not been allowed are automatically denied.

## 4. Skill and plugin sources: record sources instead of copying them

The repo **does not contain copies** of third-party skills. It only records where they come from (`sources.json`) and versions known to work (`sources.lock.json`). Benefits: access to new versions, a small repo, license compliance, and rollback.

There are five source types. Every GitHub source is downloaded using `git` at the exact commit SHA, which makes version locking and rollback reliable:

| Type | Current examples | Installation (at the locked SHA) | Update | Version lock |
|---|---|---|---|---|
| `github-skills` | `mattpocock/skills` (38 skills), `vercel-labs/skills` (find-skills) | Download individual skill directories (sparse checkout), then copy them to `~/.gemini/config/skills/<name>` | Get the latest SHA on the default branch | Commit SHA |
| `git-plugin` | `obra/superpowers` (MIT) | `git clone` into `~/.gemini/config/plugins/<name>`, then `checkout` the SHA | `git fetch` + latest SHA | Commit SHA |
| `packaged-plugin` | `anthropics/knowledge-work-plugins` -> `engineering`, `design`; `anthropics/skills` -> `mcp-builder`, `pdf`, `docx`, `xlsx`, `pptx` | Download the subdirectory, package it as a plugin (`plugin.json` + `skills/`), then run `agy plugin install <directory>` | Download the latest version and repackage it | Commit SHA |
| `pip-tool` | `graphifyy` (graphify; Apache-2.0 + MIT). The default **project mapping tool**; installed only when selected by the profile (section 5.1) | `python -m pip install --user graphifyy==<version>`, then `graphify install --platform antigravity-windows` (the tool installs its own Antigravity skill) | Install the latest version from PyPI, then run `graphify install` again | PyPI version number |
| `marketplace` | `chrome-devtools-plugin`, `gemini-api`, `modern-web-guidance-plugin` (`antigravity-plugins-official` marketplace) | `agy plugin install <name>@<marketplace>` | Reinstall the latest version | Record the version number for tracking. `agy` cannot install an exact version, so this type **accepts version drift**; for rollback, keep the last known working copy at `~/.agy-config-state/snapshots/<name>/` |

The vercel-labs `skills` tool (`npx skills ...`) is used only to **find** new skills and to let `sync` detect skills the user has installed manually: read the source + path from `~/.agents/.skill-lock.json`, then record a `github-skills` entry.

Licenses verified in the original repos: `obra/superpowers` MIT, `mattpocock/skills` MIT, `anthropics/knowledge-work-plugins` Apache-2.0, `anthropics/skills` Apache-2.0 (the repo's README explicitly states that `docx`, `pdf`, `pptx`, and `xlsx` are all Apache-2.0).

Why `engineering` and `design` are plugins rather than standalone skills: they contain skills with the same names as standalone skills (`code-review` exists in both Matt Pocock's skills and `engineering`). Plugins have their own namespaces, so they do not overwrite each other.

**Classifying skills/plugins found on a machine** (the single set of rules applied by `sync`):

1. Matches an entry in `sources.json` -> an external source; record only the source.
2. Named in `ownSkills`/`ownPlugins` in `profile.json` -> user-authored content. Store it verbatim in `profiles/<name>/skills/` or `profiles/<name>/plugins/` and push it.
3. Named in `ignored` in `profile.json` -> ignore it.
4. Everything else is **unknown**. Unknown items are **never** pushed; they are recorded only in `~/.agy-config-state/unknown.json`. The `agy-self-config` skill asks the user, then assigns each item to one of the three groups above: declare its source, mark it as user-authored, or ignore it.

## 5. Repo structure

```text
README.md                 # English, with a link to README.vi.md
README.vi.md              # Vietnamese
LICENSE                   # MIT for this repo's own content
THIRD_PARTY.md            # sources + licenses for every source in sources.json
CONTRIBUTING.md / CONTRIBUTING.vi.md
SECURITY.md               # how to report vulnerabilities
core/
  GEMINI.core.md          # shared rules (English, without a fixed reply language)
  permissions.json        # 8 read-only git commands
  sources.json            # shared sources (section 4)
  sources.lock.json       # verified versions
  plugins/agy-self-config/  # the repo's own plugin: maintenance skill + hook
profiles/
  _template/              # template for new users
  lianharman/             # the owner's profile
    profile.json          # language, owner/sync flags, extra sources and permissions
    GEMINI.profile.md     # personal rules (e.g. reply in Vietnamese)
    sources.json / sources.lock.json   # sources used only by this profile
    plugins/ skills/      # user-authored content
scripts/
  install.ps1             # first-time installation
  apply.ps1               # repo -> machine
  sync.ps1                # machine -> repo (owner profile only)
  update.ps1              # weekly updates from original sources
  maintain.ps1            # weekly maintenance when agy starts, or manual execution
  lib/                    # shared functions
tests/                    # Pester
.github/
  workflows/validate.yml  # validate every PR
  CODEOWNERS
  PULL_REQUEST_TEMPLATE.md
docs/
```

### 5.1 `profile.json`

```json
{
  "name": "lianharman",
  "language": "vi",
  "sync": { "debounceMinutes": 10 },
  "projectMap": { "tool": "graphify" },
  "ownSkills": [],
  "ownPlugins": [],
  "ignored": []
}
```

`projectMap.tool` selects the skill agy uses to obtain a knowledge map when entering a project (section 7):

- `"graphify"` (default): install the `graphifyy` source.
- The name of another skill the user already uses: do not install graphify; the orientation rules call that skill.
- `"none"`: skip the project mapping step.

### 5.3 Role of each machine

The role is determined **per machine**, not stored in a shared file. `install` tries `git push --dry-run` to `origin`, then saves the result along with the profile name in `~/.agy-config-state/machine.json`:

- **owner**: has push access to `origin`. The machine runs `sync` to push changes and `update` to update sources.
- **follower**: has no push access. The machine only runs `apply` and follows the lock files on `main` exactly. It never commits.

Other users are advised to **fork the repo and install from their own fork**. They then own their fork, and their configuration is backed up too. To receive improvements from the original repo, click "Sync fork" on GitHub or ask agy (the `agy-self-config` skill) to merge `upstream/main`. This merge is not automatic. Cloning the original repo directly is still supported, but only as a follower, without backups.

### 5.2 Generated `GEMINI.md`

`apply` combines files using marked regions:

```markdown
<!-- agy-config:core:start -->
...contents of core/GEMINI.core.md...
<!-- agy-config:core:end -->
<!-- agy-config:profile:start -->
...contents of profiles/<name>/GEMINI.profile.md, including language rules...
<!-- agy-config:profile:end -->
```

`sync` reads the regions back: edits in the `profile` region -> `GEMINI.profile.md`. Edits in the `core` region -> `core/GEMINI.core.md`, only when the profile is an owner. Text outside the regions is merged into the `profile` region.

## 6. Flows

### 6.1 First-time installation (`install.ps1`)

Ways to run it, documented in the README:

1. `git clone` the repo, then run `.\scripts\install.ps1` (recommended: users can read the script before running it).
2. Or use the one-liner `irm <raw-url>/scripts/install.ps1 | iex`. This clones into `~/.agy-config` automatically.

Script steps:

1. Check for `git`, `node`/`npx`, and `agy`; if anything is missing, print an installation link and stop.
2. Ask which profile to use: an existing profile, or a new one created from `_template`. When creating a profile, ask for:
   - the reply language (`vi`/`en`/another language);
   - the project mapping tool: press Enter to use graphify, enter the name of another skill already in use, or enter `none`.
3. Back up the existing agy configuration to `~/.agy-config-backup/<timestamp>/` before making any changes.
4. Run `apply`.
5. Determine the machine's role (section 5.3). Do not register any Windows Task Scheduler tasks; remove the three tasks created by older versions: `agy-config-apply`, `agy-config-sync`, `agy-config-update`. Weekly maintenance is triggered by the `SessionStart` hook when agy starts (section 7).
6. Print a summary of what was installed, with uninstall instructions.

Running `install.ps1` repeatedly is safe (idempotent).

Script prompts and messages use English only, from `scripts/i18n/en.json`; there is no Vietnamese i18n file. Each profile's reply language remains configurable; its rules are generated in English, for example, "Always reply to the user in Vietnamese".

### 6.2 Repo -> machine (`apply.ps1`)

0. **Collect first**: run the "collect" part of `sync` (step 1 in section 6.3), writing into the repo's working tree without committing. This prevents step 4 from deleting the user's manual edits to `GEMINI.md`. Owner machines run the full `sync`.
1. `git pull --ff-only` on `main`. If a fast-forward is not possible, stop and log it.
2. Install/update every source in `core` + the profile **exactly as specified by the lock files**. Remove items installed by the previous `apply` that are no longer in the repo. The list of installed items is stored in `~/.agy-config-state/applied.json`. `apply` removes only what it installed itself and leaves items the user installed outside the system alone.
3. Install the `agy-self-config` plugin and the profile's user-authored content.
4. Generate `GEMINI.md` (5.2).
5. Merge `permissions.allow`: add missing commands and preserve all other keys.
6. Write `mcp_config.json`: add missing servers and resolve `${VARIABLE_NAME}` from the user's environment variables.
7. Verify: run `agy plugin validate` on each installed plugin and check that `agy plugin list --json` includes all names.

### 6.3 Machine -> repo (`sync.ps1`, owner only)

Triggered from three places:

- `apply` runs the full sync before pulling and installing on owner machines, including during weekly maintenance when agy starts.
- The `agy-self-config` skill runs `scripts/sync.ps1 -Force` immediately after every configuration change.
- The manual command `scripts/sync.ps1 -Force`.

Debouncing: skip the run if less than `debounceMinutes` has passed since the previous run (unless `-Force` is used), or if another sync process is running (lock file).

Steps:

1. Collect into the repo using a **three-way** comparison: compare the machine's current state with `~/.agy-config-state/applied.json` (the most recent `apply`), then write only what **this machine** has added or removed since then. An outdated or newly installed machine will not delete another machine's content. Collect:
   - `GEMINI.md` regions (5.2).
   - `permissions.allow`, excluding entries already in `core`.
   - The skill-cli list from `~/.agents/.skill-lock.json` (source + skill name + hash).
   - The marketplace plugin list from `agy plugin list --json`.
   - User-authored plugins/skills (items that do not match any source).
   - MCP definitions, with secret values replaced by `${VARIABLE_NAME}`.
2. **Do not collect**: `trustedWorkspaces`, `model`, machine names, history, logs, caches, or skills with unknown sources (record these in a local report).
3. Scan every file about to be committed for secrets. If a suspicious pattern is found (`ghp_`, `github_pat_`, `sk-`, `AIza`, `-----BEGIN`, a value assigned to `password`, an email address, or a `C:\Users\<name>` path), **stop completely without committing** and log it.
4. Exit if there are no changes.
5. If there are changes: commit `sync(<profile>): <date time>`, then `git pull --rebase` and `git push`. If the rebase conflicts, abort it, push to `sync/<profile>-<timestamp>`, and log it for agy to handle (section 7).

Logs are stored at `~/.agy-config-state/logs/<apply|sync|update|maintain>-yyyyMMdd.log`, outside the repo.

### 6.4 Technology updates (`update.ps1`, run by weekly maintenance, owner machines only)

`scripts/maintain.ps1` runs `apply` first (a full sync to back up the owner machine's configuration, then pull and install), followed by `update`. Follower machines only run `apply`. Users can run `scripts/update.ps1` manually, add `-NoPush` to try it locally without pushing the branch, or run `scripts/maintain.ps1` for immediate maintenance.

1. For each source, get the latest SHA/version and try installing it on the owner's machine.
2. Validate each source (`agy plugin validate`, a valid `SKILL.md`). If a source fails, **roll it back to the version in the lock file**; other sources still update.
3. Record the new versions in the lock files. New lock files reach `main` as described in section 6.5.
4. Write a one-line log summary: which sources moved to which versions, and which were rolled back.

Follower machines never fetch the latest versions from external sources on their own. They receive updates when the lock files on `main` change, through `apply` during weekly maintenance when agy starts or through a manual run.

### 6.5 How new lock files reach `main`

The owner chose: **through a PR, with one click each week**.

1. `update` pushes the new lock files to `update/sources`, then opens a PR titled "Weekly source updates" into `main`. The PR body is a table: source, old -> new version, and rolled-back sources. If the previous week's PR has not been merged, update that PR instead of opening a new one.
2. The owner's machine still **uses the new versions immediately**: the pending lock is stored at `~/.agy-config-state/pending.lock.json`. On the owner's machine, `apply` prefers the pending lock for sources listed in it, preventing a downgrade during the next maintenance run. Delete the pending lock when the PR is merged. If the PR is closed without merging, the next `apply` returns to the lock files on `main`.
3. **No additional software is needed on the machine** to open PRs: the owner's machine only runs `git push` for `update/sources`. The `.github/workflows/update-pr.yml` workflow runs on GitHub when that branch is pushed, then creates or updates the PR using the built-in `GITHUB_TOKEN`.
   - A one-time repo setting is required: Settings -> Actions -> General -> "Allow GitHub Actions to create and approve pull requests". The README explains this step for the owner and users who fork the repo.
   - PRs created by `GITHUB_TOKEN` do not automatically trigger other workflows, so `validate.yml` also runs on pushes to `update/**`. Check results are attached to the commit, so they still appear on the PR.
   - If the workflow cannot open the PR (permission has not been enabled), it writes a "Create pull request" link in the run summary; `update` also writes that link to the local log.
4. The owner's personal configuration changes (`sync`: rules, user-authored skills, permissions) still go directly to `main`, without a PR.

## 7. Self-maintenance: the `agy-self-config` plugin

The repo's own plugin, installed on every machine. It includes:

- **Only a `SessionStart` hook**, named `agy-config-weekly`, which calls `hooks/on-start.ps1` when agy starts. The hook checks two timestamps in `~/.agy-config-state`: `weekly.last` (the last successful maintenance run) and `weekly-attempt.last` (the last attempt). If at least 7 days have passed since the last success and at least 1 day since the last attempt (or the corresponding timestamp is missing), the hook starts `scripts/maintain.ps1` hidden in the background, prints `{}`, and returns immediately; otherwise, it does nothing.
  - Owner machines run `apply` (a full sync to back up first, then pull and install), followed by `update`; followers only run `apply`.
  - Write `weekly.last` only when every step succeeds. A failed weekly run is retried at most once per day on a subsequent agy start. No background tasks run while agy is closed.
  - Run `scripts/maintain.ps1` for immediate maintenance, bypassing the hook's timing checks. Delete `~/.agy-config-state/weekly.last` to make the hook run sooner on the next agy start; at least 1 day must still have passed since the last attempt.
- **The `agy-self-config` skill**, with a description that triggers when the user wants to change how agy works; install, remove, or find skills/plugins; back up, restore, or move to another machine; update; or investigate a sync failure. The skill instructs agy to:
  - Edit the correct file: personal changes go in the profile; shared changes go in `core` (owner only); external skills/plugins go in the profile's `sources.json`.
  - Run `apply`/`sync`/`update`/`maintain` and read logs in `~/.agy-config-state/logs/`. On owner machines, run `scripts/sync.ps1 -Force` after every change for an immediate backup.
  - Resolve conflicts on `sync/*` branches with the user.
  - Find new skills with `npx skills find` and suggest them to the user.
  - Contribute to the original repo through PRs when the user is not the owner.
- `core/GEMINI.core.md` adds a **project mapping** step to orientation when entering a project, using the tool in `projectMap.tool`. `apply` writes the tool's name into the `profile` region of `GEMINI.md`.
  - With graphify: if `graphify-out/` exists, read `GRAPH_REPORT.md` and use `graphify query/path/explain` instead of opening many files. If it does not exist, automatically run `/graphify .` to create it, then tell the user.
  - With another tool: call that skill in the same way.
  - Reason (requested by the owner): agy immediately has a knowledge map of the project and uses fewer tokens to find files.
- `core/GEMINI.core.md` includes a line pointing to this skill. After installation, every request like "from now on, please..." goes through the skill, keeping the configuration aligned with the user's wishes and backed up.

## 8. Contributions and safety

- `main` is protected: PRs, 1 reviewer, and passing CI are required. The owner can bypass protection so `sync` can push directly (GitHub branch protection, "allow bypass" for the owner).
- `CODEOWNERS`: `scripts/`, `core/plugins/`, `.github/`, and `core/sources*.json` require the owner's review because they run commands on users' machines or determine which code is downloaded.
- `validate.yml` runs on every PR:
  - Valid JSON.
  - `SKILL.md` has `name` + `description`.
  - Valid `plugin.json`.
  - Secret scanning (gitleaks).
  - No personal paths or email addresses.
  - No binary files > 1 MB.
  - Every source in `sources.json` has an entry in `THIRD_PARTY.md`.
  - PSScriptAnalyzer for `scripts/`.
  - Run Pester tests.
- Machines receive updates only from `main`.
- `install.ps1` prints what it will do and asks for confirmation before backing up, applying the configuration, and cleaning up old tasks. `uninstall.ps1` removes the `agy-self-config` plugin and any Windows Task Scheduler tasks left over from older versions.

## 9. Constraints

- Windows 10/11, Windows PowerShell 5.1 (built in), no administrator privileges required.
- Prerequisites: `git`, `agy` >= 1.5, Node.js (only to find skills with `npx skills`). Python >= 3.10 is needed only when graphify is selected. GitHub CLI is not required.
- If graphify is selected but Python is missing, `install` still installs everything else and clearly reports that graphify could not be installed, with Python installation instructions (`winget install Python.Python.3.13`). `apply` retries during the next weekly maintenance run or when run manually.
- Scripts call agy through CLI commands (`agy plugin ...`) and do not directly edit agy's internal files except those in the table in section 3. Reason: scripts continue to work if agy changes its internal file formats.
- The `SessionStart` hook has a 10-second timeout and returns immediately; all heavy work runs separately.
- No background tasks run while agy is closed: maintenance runs when agy starts, at most once per week. Reason: leave RAM available for games and other work; a failed weekly run is retried at most once per day when agy starts.

## 10. Owner decisions

- The repo is public; anyone can use it and contribute through PRs.
- Target users: both Vietnamese and international users.
- Automation: automatic syncing and technology updates on owner machines, without asking first.
- No background tasks run while agy is closed: maintenance runs when agy starts, at most once per week.
- Source updates reach other users' machines only after the owner merges the weekly PR (section 6.5).
- Do not install GitHub CLI on the machine; GitHub Actions opens PRs.
- Orientation always uses a project mapping tool. graphify is the default, not mandatory: users who already have a similar skill use that skill without installing graphify.
- The owner approved the entire design (2026-11-11).
- Self-sufficiency: once built, agy handles maintenance without Claude Code.
- The README guides users who have just downloaded agy.

## 11. Designer decisions (the owner may change them)

- MIT license for the repo's own content.
- Main README in English + a Vietnamese version; the installation script asks for the reply language. Script text uses English only (`scripts/i18n/en.json`); profile language rules are also generated in English.
- Do not copy third-party skills into the repo; record sources + locked versions.
- Replace the 3 Anthropic plugins manually installed on the owner's machine (from `~/.gemini/local-plugins`) with versions downloaded from their original repos through `packaged-plugin`.
- Do not sync `trustedWorkspaces`, `model`, or machine names.
- Default clone directory: `~/.agy-config`; if the user clones elsewhere and runs `install.ps1` there, use that location.
- Download every GitHub source using `git` at a commit SHA (do not install with `npx skills add`); the `skills` tool is only for finding skills and detecting skills the user has installed manually.
- Marketplace plugins accept version drift, with rollback through the last known working backup.
- Determine the owner/follower role from each machine's push access; advise other users to fork.
- `sync` writes changes using a three-way comparison against the most recent `apply`; `apply` removes only what it installed itself.
- User-authored content must be declared in `ownSkills`/`ownPlugins`; items with unknown sources are never pushed automatically.
- Debounce sync for 10 minutes; `-Force` bypasses the wait. Weekly maintenance runs through `SessionStart`, as decided by the owner in section 10.
- Skills with unknown sources/licenses are not pushed automatically.
- Windows first; leave macOS/Linux support to contributors.

## 12. Left to the implementer

- Script internals, log format, and specific secret-scanning patterns.
- How to notify users when sync/update fails (Windows toast or logs only).
- The `tests/` directory structure and how to mock agy in tests.
- Detailed README and CONTRIBUTING content (following sections 6 and 8).
