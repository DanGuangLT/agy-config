# Troubleshooting

Start with today's log: `~/.agy-config-state/logs/<apply|sync|update|maintain>-yyyyMMdd.log`. Find the newest `[ERROR]` or `[WARN]` line.

To force maintenance now, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\maintain.ps1` from the clone. To make the SessionStart hook run again sooner, delete `~/.agy-config-state/weekly.last`, then start agy. The hook still waits at least 1 day after `weekly-attempt.last`; the manual command bypasses those timing checks. A failed run leaves the week due and is retried at the next agy start after that day has passed.

| Log says | Meaning | What to do |
|---|---|---|
| `pull failed, nothing changed` | Offline, or the local repo cannot fast-forward | Check the network. Then run `git -C <repoPath> status` and show the user the result. |
| `source failed: <id>: ...` | One source could not be installed at its locked version | Retry `apply.ps1`. If it fails again, show the error. A locked commit that no longer exists upstream needs a new lock: run `update.ps1` on an owner machine. |
| `python-missing` / `python-too-old` | graphify needs Python 3.10+ | Tell the user to run `winget install Python.Python.3.13`, then `apply.ps1`. |
| `agy-missing` | `agy` was not found in the maintenance process's PATH | Confirm `%LOCALAPPDATA%\agy\bin\agy.exe` exists and its directory is on PATH, then restart agy. |
| `possible secret (...) in <file>:<line>` | Sync stopped before committing (exit 2) | Open the file and line. Replace the value with a `${VARIABLE}` placeholder or remove it. Then run `sync.ps1 -Force`. |
| `pushed them to branch sync/...` | This machine and the repo both changed the same text (exit 3) | Show the user the diff between `origin/main` and `origin/sync/...`. Merge only with their approval, then push. |
| `push failed` | No network or no push rights (exit 4) | Check `git -C <repoPath> remote -v` and the user's GitHub access. |
| `rolled back <id>` | A newer upstream version failed validation; the old version stays | Nothing urgent. Mention it to the user. |
| `MCP variable X is not set` | An MCP server needs a secret from an environment variable | Ask the user to set it (`setx X <value>`), then run `apply.ps1`. |

To look at a single script live, run it in a terminal without `-WindowStyle Hidden`, then read the log.
