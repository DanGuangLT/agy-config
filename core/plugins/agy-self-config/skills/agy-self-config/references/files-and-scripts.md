# Files and scripts

## Repo layout

`<repoPath>` is the shared clone recorded in `machine.json`. Resolve `<profileDir>` before editing: use `profileRoot` when set, otherwise `<repoPath>/profiles/<profile>/`. A personal clone holds the profile files at its root. `<profileGitRoot>` is `profileRoot` in personal mode, otherwise `repoPath`.

| Path | What it is |
|---|---|
| `core/GEMINI.core.md` | Rules for every user (owner edits only) |
| `core/permissions.json` | Read-only commands allowed for everyone |
| `core/sources.json`, `core/sources.lock.json` | Shared third-party sources and their locked versions |
| `core/plugins/agy-self-config/` | This plugin: the weekly SessionStart hook and this skill |
| `<profileDir>/profile.json` | `language`, `projectMap.tool`, `ownSkills`, `ownPlugins`, `ignored`, `sync.debounceMinutes`, optional `upstream` |
| `<profileDir>/shared/` | User-controlled copies of shared rules, permissions, sources and locked versions while following is stopped |
| `<profileDir>/GEMINI.profile.md` | Personal rules, including the reply language |
| `<profileDir>/permissions.json` | Extra allowed commands |
| `<profileDir>/sources.json`, `<profileDir>/sources.lock.json` | Personal third-party sources |
| `<profileDir>/skills/`, `<profileDir>/plugins/` | Skills and plugins the user wrote |
| `<profileDir>/mcp.json` | MCP servers; secret values are `${VARIABLE}` placeholders |

`profile.json` records a stopped follower as `"upstream": { "follow": false, "stoppedAt": "<ISO time>", "commit": "<shared HEAD sha at stop>" }`. A missing `upstream` means following. This state is saved with the profile and restored on a new machine.

While stopped, scripts read `<profileDir>/shared/GEMINI.core.md`, `permissions.json`, `sources.json` and `sources.lock.json` instead of the files in `core/`. The user can change these copies, including removing original skills. Their own extra sources stay in `<profileDir>/sources.json`. The shared clone is no longer pulled, so its scripts and the agy-self-config plugin are not updated either.

## Machine state (`~/.agy-config-state/`)

- `machine.json`: `profile`, `role` (`owner` or `follower`), `repoPath`, and optional `profileRoot` and `backupRepo`. `profileRoot` is the personal clone (default `~/.agy-config-personal`); `backupRepo` is its push URL. Role describes push access to the shared clone, so a follower with a personal backup can still publish its profile.
- `applied.json`: what the last `apply` installed. It is the base for three-way merges.
- `pending.lock.json`: newer versions waiting for the weekly PR. Dropped after 14 days.
- `unknown.json`: skills and plugins with no known source. Never pushed.
- `weekly.last`: time of the last fully successful maintenance run.
- `weekly-attempt.last`: time of the last maintenance attempt or missing-repo warning, successful or not.
- `logs/<apply|sync|update|maintain|hook>-yyyyMMdd.log`: one log per script per day.

Use `$env:AGYCFG_HOME` instead of `~` for these home-relative paths when set.

## Scripts

Every script runs with `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/<name>.ps1`.

- `install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-BackupRepo <url|none>] [-Reinstall] [-Yes] [-RepoPath <path>]`: finds `~/.gemini` and installs the shared configuration. Followers can supply a personal backup URL or press Enter to skip. A saved profile at that repository's root is restored. Owners and fork users keep their profile in the shared clone and are not asked for a backup repo. Running install again shows the setup; `-Reinstall` runs full setup again. If the recorded clone folder no longer exists, running install from its new folder repairs `repoPath`. Registers no scheduled tasks; removes the three left by older versions.
- `apply.ps1 [-SkipPull]`: repo to machine. Pulls the shared clone while following and, in personal mode, also the personal clone before reading `<profileDir>`. While stopped, uses `<profileDir>/shared/` instead of `core/`. Exit 1 means a source failed and nothing was recorded.
- `follow.ps1 [-Stop | -Resume]`: followers only. No switch shows the state. `-Stop` copies the shared files into `<profileDir>/shared/`, records `upstream` and stops pulling the shared clone. Nothing is uninstalled. In personal mode it pushes the change to the backup right away. `-Resume` saves `shared/` to `~/.agy-config-backup/<stamp>-shared`, removes it and `upstream`, then runs apply at once to pull and install the shared list. Personal extra sources stay. On an owner it explains that the owner maintains the shared repository and exits 1.
- `sync.ps1 [-Force] [-CaptureOnly]`: machine to profile. Publishes on owners and machines with a personal backup. In personal mode it pulls, commits and pushes in `profileRoot` to `backupRepo` (`origin`, branch `main`); shared core text is not captured. Without `profileRoot`, owners publish the profile and shared core files from `repoPath`. A follower without personal backup does not publish. Exit codes:
  - 0: synced or nothing to do
  - 2: possible secret found, nothing committed
  - 3: conflict, changes pushed to branch `sync/<profile>-<stamp>`
  - 4: push failed
- `update.ps1 [-NoPush]`: owner only. Newer upstream versions, then branch `update/sources`. Sources listed only in the personal backup stay at their saved versions.
- `maintain.ps1`: runs weekly maintenance now, bypassing the hook's timing checks. Owner: `apply` (full sync backup, then pull and installation), then `update`; follower: `apply` only. Marks the week done only if everything succeeds.
- `uninstall.ps1 [-RestoreBackup <stamp>]`: removes this plugin and any scheduled tasks left by older versions.

The plugin has only a `SessionStart` hook: `agy-config-weekly` → `hooks/on-start.ps1`. When agy starts, it checks both stamps. If `weekly.last` is at least 7 days old and `weekly-attempt.last` is at least 1 day old (or the respective stamps are missing), it starts `scripts/maintain.ps1` hidden in the background and returns immediately. If that script is missing, it appends a `[WARN]` line to `logs/hook-yyyyMMdd.log`, writes `weekly-attempt.last`, and returns the fix as startup context using `injectSteps[].systemMessage.systemMessage`. Otherwise it prints `{}`. Failed weeks and missing-repo warnings are retried at most daily at the next agy start. Nothing runs in the background while agy is closed.

The legacy tasks removed by install and uninstall are `agy-config-apply`, `agy-config-sync`, and `agy-config-update`.
