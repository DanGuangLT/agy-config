# Files and scripts

## Repo layout

| Path | What it is |
|---|---|
| `core/GEMINI.core.md` | Rules for every user (owner edits only) |
| `core/permissions.json` | Read-only commands allowed for everyone |
| `core/sources.json`, `core/sources.lock.json` | Shared third-party sources and their locked versions |
| `core/plugins/agy-self-config/` | This plugin: the weekly SessionStart hook and this skill |
| `profiles/<name>/profile.json` | `language`, `projectMap.tool`, `ownSkills`, `ownPlugins`, `ignored`, `sync.debounceMinutes` |
| `profiles/<name>/GEMINI.profile.md` | Personal rules, including the reply language |
| `profiles/<name>/permissions.json` | Extra allowed commands |
| `profiles/<name>/sources.json`, `sources.lock.json` | Personal third-party sources |
| `profiles/<name>/skills/`, `plugins/` | Skills and plugins the user wrote |
| `profiles/<name>/mcp.json` | MCP servers; secret values are `${VARIABLE}` placeholders |

## Machine state (`~/.agy-config-state/`)

- `machine.json`: `profile`, `role` (`owner` or `follower`), `repoPath`.
- `applied.json`: what the last `apply` installed. It is the base for three-way merges.
- `pending.lock.json`: newer versions waiting for the weekly PR. Dropped after 14 days.
- `unknown.json`: skills and plugins with no known source. Never pushed.
- `weekly.last`: time of the last fully successful maintenance run.
- `weekly-attempt.last`: time of the last maintenance attempt, successful or not.
- `logs/<apply|sync|update|maintain>-yyyyMMdd.log`: one log per script per day.

## Scripts

Every script runs with `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/<name>.ps1`.

- `install.ps1 [-ProfileName] [-Language] [-ProjectMapTool] [-Yes] [-RepoPath]`: first setup, safe to re-run. Registers no scheduled tasks; removes the three left by older versions.
- `apply.ps1 [-SkipPull]`: repo to machine. Exit 1 means a source failed and nothing was recorded.
- `sync.ps1 [-Force] [-CaptureOnly]`: machine to repo. Exit codes:
  - 0: synced or nothing to do
  - 2: possible secret found, nothing committed
  - 3: conflict, changes pushed to branch `sync/<profile>-<stamp>`
  - 4: push failed
- `update.ps1 [-NoPush]`: owner only. Newer upstream versions, then branch `update/sources`.
- `maintain.ps1`: runs weekly maintenance now, bypassing the hook's timing checks. Owner: `apply` (full sync backup, then pull and installation), then `update`; follower: `apply` only. Marks the week done only if everything succeeds.
- `uninstall.ps1 [-RestoreBackup <stamp>]`: removes this plugin and any scheduled tasks left by older versions.

The plugin has only a `SessionStart` hook: `agy-config-weekly` → `hooks/on-start.ps1`. When agy starts, it checks both stamps. If `weekly.last` is at least 7 days old and `weekly-attempt.last` is at least 1 day old (or the respective stamps are missing), it starts `scripts/maintain.ps1` hidden in the background and returns immediately. Otherwise it does nothing. Failed weeks are retried at most daily at the next agy start. Nothing runs in the background while agy is closed.

The legacy tasks removed by install and uninstall are `agy-config-apply`, `agy-config-sync`, and `agy-config-update`.
