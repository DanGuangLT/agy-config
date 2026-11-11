# Files and scripts

## Repo layout

| Path | What it is |
|---|---|
| `core/GEMINI.core.md` | Rules for every user (owner edits only) |
| `core/permissions.json` | Read-only commands allowed for everyone |
| `core/sources.json`, `core/sources.lock.json` | Shared third-party sources and their locked versions |
| `core/plugins/agy-self-config/` | This plugin: the Stop hook and this skill |
| `profiles/<name>/profile.json` | `language`, `projectMap.tool`, `ownSkills`, `ownPlugins`, `ignored`, `sync.debounceMinutes`, `update.day` |
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
- `logs/<script>-yyyyMMdd.log`: one log per script per day.

## Scripts

Every script runs with `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/<name>.ps1`.

- `install.ps1 [-ProfileName] [-Language] [-ProjectMapTool] [-Yes] [-RepoPath]`: first setup, safe to re-run.
- `apply.ps1 [-SkipPull]`: repo to machine. Exit 1 means a source failed and nothing was recorded.
- `sync.ps1 [-Force] [-CaptureOnly]`: machine to repo. Exit codes:
  - 0: synced or nothing to do
  - 2: possible secret found, nothing committed
  - 3: conflict, changes pushed to branch `sync/<profile>-<stamp>`
  - 4: push failed
- `update.ps1 [-NoPush]`: owner only. Newer upstream versions, then branch `update/sources`.
- `uninstall.ps1 [-RestoreBackup <stamp>]`: removes the scheduled tasks and this plugin.

Scheduled tasks:
- `agy-config-apply`: at logon.
- `agy-config-sync`: daily and at logon, owner only.
- `agy-config-update`: weekly, owner only.
