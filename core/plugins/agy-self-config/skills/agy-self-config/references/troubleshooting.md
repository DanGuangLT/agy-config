# Troubleshooting

Start with today's log: `~/.agy-config-state/logs/<apply|sync|update|maintain|hook>-yyyyMMdd.log`. Find the newest `[ERROR]` or `[WARN]` line. Use `$env:AGYCFG_HOME` instead of `~` when set.

Read `machine.json` first. Scripts live in `<repoPath>/scripts/`. `<profileDir>` and `<profileGitRoot>` are `profileRoot` in personal mode; otherwise they are `<repoPath>/profiles/<profile>/` and `<repoPath>` respectively. Personal backups push to `backupRepo`.

To force maintenance now, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\maintain.ps1` from the clone. To make the SessionStart hook run again sooner, delete `~/.agy-config-state/weekly.last`, then start agy. The hook still waits at least 1 day after `weekly-attempt.last`; the manual command bypasses those timing checks. A failed run leaves the week due and is retried at the next agy start after that day has passed.

| Log says | Meaning | What to do |
|---|---|---|
| Updates from the shared repo stopped arriving | Following may be stopped in the profile | Run `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/follow.ps1` without a switch to check the state. If stopped, follow "Stop or resume following the shared repo" in the skill; explain the consequences and get a yes before `-Resume`. |
| `pull failed, nothing changed` | Offline, or a clone cannot fast-forward | Check the network and the clone named in the log. Run `git -C <repoPath> status`; in personal mode also check `git -C <profileRoot> status`. Show the user the result. |
| `source failed: <id>: ...` | One source could not be installed at its locked version | Retry `apply.ps1`. If it fails again, show the error. A locked commit that no longer exists upstream needs a new lock: run `update.ps1` on an owner machine. |
| `python-missing` / `python-too-old` | graphify needs Python 3.10+ | Tell the user to run `winget install Python.Python.3.13`, then `apply.ps1`. |
| `agy-missing` | `agy` was not found in the maintenance process's PATH | Confirm `%LOCALAPPDATA%\agy\bin\agy.exe` exists and its directory is on PATH, then restart agy. |
| `possible secret (...) in <file>:<line>` | Sync stopped before committing (exit 2) | Open the file and line. Replace the value with a `${VARIABLE}` placeholder or remove it. Then run `sync.ps1 -Force`. |
| `pushed them to branch sync/...` | This machine and the repo both changed the same text (exit 3) | In `<profileGitRoot>`, show the user the diff between `origin/main` and `origin/sync/...`. Merge only with their approval, then push. |
| `push failed` | No network or no push rights (exit 4) | Check `git -C <profileGitRoot> remote -v` and the user's GitHub access. |
| Backup repo push fails during install or sync | Git cannot push to `backupRepo`, or the personal clone's `origin` is wrong | Check the network, Git authentication and push rights to that URL. Inspect `git -C <profileRoot> remote -v`. Git Credential Manager signs in on the first push. Keep local profile files, fix access, then retry install if setup failed or `<repoPath>/scripts/sync.ps1 -Force` if already set up. |
| Shared clone was moved or renamed | `machine.json` still records the old `repoPath` | Run `scripts/install.ps1` once from the clone's new folder. When the old folder no longer exists, install repairs the saved path. If the old folder still exists, follow the installer's `-Reinstall` guidance. |
| `hook-*.log`: `repo folder was not found` | The due SessionStart hook could not find `<repoPath>/scripts/maintain.ps1` | Run `scripts/install.ps1` from the clone's new folder. The hook logs and adds this warning as startup context at most once a day; `weekly-attempt.last` limits retries. |
| `rolled back <id>` | A newer upstream version failed validation; the old version stays | Nothing urgent. Mention it to the user. |
| `MCP variable X is not set` | An MCP server needs a secret from an environment variable | Ask the user to set it (`setx X <value>`), then run `apply.ps1`. |

To look at a single script live, run it in a terminal without `-WindowStyle Hidden`, then read the log.
