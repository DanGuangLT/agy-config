# One-run setup with a personal backup repository

Date: 2026-11-12. Extends `2026-11-11-agy-config-sync-design.md`.

## Why

A newcomer should be able to clone the shared repository (`DanGuangLT/agy-config`), run one command once, and get:

- agy's configuration folder found on its own (`~/.gemini`), with all shared skills and plugins installed;
- an automatic backup of *their own* configuration into *their own* GitHub repository, which they can restore on another machine by giving the same repository again;
- weekly updates of the shared skills from the shared repository.

Today they must fork first; a direct clone makes them a follower with no backup. Running install again also re-asks everything and reinstalls. And when the clone folder is moved or renamed, `machine.json` keeps the old `repoPath` and the start hook silently skips maintenance for good (this happened on 2026-11-12).

## Goals

1. **Personal backup repository.** On a first install where this machine cannot push to the shared clone's `origin` (a follower), install asks for a personal GitHub repository URL (an empty private repository is recommended). Press Enter to skip.
2. **Restore.** If that repository already holds a saved configuration (`profile.json` at its root), install restores it instead of asking the language and project map questions.
3. **Run once.** Running install again on a machine that is already set up prints the current setup and exits 0 without reinstalling. `-Reinstall` runs the full setup again.
4. **Moved folder.** Running install from a moved or renamed clone updates `repoPath` when the recorded folder no longer exists.
5. **Finds agy's folder.** Install prints the agy configuration folder it uses (`~/.gemini`) and notes when it does not exist yet (agy was never started); setup still continues and creates the folders it needs.
6. **No more silent stop.** When maintenance is due but `<repoPath>\scripts\maintain.ps1` is missing, the start hook logs a warning naming the fix (run install again from the new folder) instead of doing nothing.

## Non-goals

- Weekly version updates for skills that only the personal repository lists. They stay at the version captured when they were installed. Shared sources update through the shared repository as before.
- Changing the owner flow. A machine with push access to the clone's `origin` (the maintainer, or anyone using their own fork) keeps its profile in `profiles/<name>/` of that clone and is not asked for a personal repository.
- Hosting other than a git URL the user can push to.

## Design

### Where the profile lives

`machine.json` gains two optional fields:

| Field | Meaning |
|---|---|
| `backupRepo` | URL of the personal repository |
| `profileRoot` | Local clone of it: `~/.agy-config-personal` |

When `profileRoot` is set, the profile files live at the **root** of that clone: `profile.json`, `GEMINI.profile.md`, `permissions.json`, `sources.json`, `sources.lock.json`, and optionally `skills/`, `plugins/`, `mcp.json`, plus a short `README.md` that install writes. Otherwise the profile lives in `<repoPath>/profiles/<name>/` as before.

`Get-ProfileLocation` returns `Dir` (the profile folder), `GitRoot` (the repository that sync commits to), `Personal` (bool) and `Managed` (paths sync may stage: everything in the personal clone; or `profiles/<name>/` plus the core files for an owner).

### Sync and apply

- **Sync** publishes when the machine is an owner or has a personal repository. In personal mode it pulls, commits and pushes in `profileRoot` (`origin`, branch `main`), using the same secret scan, conflict branches and debounce as the shared clone. Core text is not captured in personal mode.
- **Apply** pulls the shared clone (as today; for a follower this brings the shared updates) and, in personal mode, also pulls the personal clone before reading the profile.
- **Update** (owner only) skips sources that only the personal repository lists.
- A brand-new empty personal repository works: the first sync creates `main`. The clone is put on branch `main`. If git has no `user.email`, the personal clone gets a local identity (`agy-config` / `agy-config@users.noreply.github.com`) so commits never fail.

### Install

`install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-BackupRepo <url|none>] [-Reinstall] [-Yes] [-RepoPath <path>]`

1. Check git and agy. Print the agy folder (`~/.gemini`) and whether it exists.
2. If `machine.json` already has a profile and `-Reinstall` is not given: if the recorded `repoPath` no longer exists, record this clone instead; if it exists and differs, say so and point to `-Reinstall`. Print profile, role, backup repository and agy folder; reinstall the agy-self-config plugin if it is missing. Exit 0.
3. Determine the role (push access to `origin`).
4. Follower: use `-BackupRepo`, or ask (not with `-Yes`). `none` or empty means no backup. Clone it to `~/.agy-config-personal` (an existing clone of the same URL is pulled; a folder holding something else stops install). Check push access; stop with a clear message when it fails.
5. Personal repository with `profile.json`: restore it. Otherwise create the profile from `profiles/_template` at the clone root. The profile name is `-ProfileName`, else the repository owner from the URL, else `me`.
6. Back up the current agy configuration, record `machine.json`, apply, and in personal mode sync once with `-Force` so the new profile is pushed right away.

## Stop and resume following the shared repository

By default a follower follows the shared repository: weekly maintenance pulls it, so new skills, versions and shared rules arrive. A user who wants to manage everything themselves can stop that, and resume later. (Owner decision 2026-11-12: when stopped, the user gets full control, including removing the original skills.)

Command: `scripts/follow.ps1 [-Stop | -Resume]`. Without a switch it shows the current state. agy runs it through the agy-self-config skill when the user asks ("stop syncing with the original repo" / "sync again").

- **State** lives in the profile, so it is backed up and restored with it: `profile.json` → `"upstream": { "follow": false, "stoppedAt": "<ISO time>", "commit": "<shared HEAD sha at stop>" }`. A missing `upstream` means following.
- **Stop** copies the shared files the scripts read from `core/` into `<profileDir>/shared/`: `GEMINI.core.md`, `permissions.json`, `sources.json`, `sources.lock.json`. From then on the scripts read those copies instead of `core/` (so the user can edit or remove the original skills and rules), and apply no longer pulls the shared clone. Nothing is uninstalled at stop. In personal mode the change is pushed to the backup repository right away.
- **Resume** saves `shared/` to `~/.agy-config-backup/<stamp>-shared`, deletes it, removes `upstream`, and runs apply at once: it pulls the shared repository and installs its current list. Sources the user added through sync (in the profile's own `sources.json`) stay.
- Only followers stop or resume; an owner maintains the shared repository itself, and the command says so.
- The scripts and the agy-self-config plugin still come from the local shared clone, which is no longer updated while stopped.

## Left to the builder

Exact message wording (English, in `scripts/i18n/en.json`), README layout, test structure.
