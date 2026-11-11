# Implementation notes: agy config sync (2026-11-11)

Decisions made during implementation that the plan or spec did not settle, and small issues deferred for later. Kept so future maintainers (including agy) can see why the code looks the way it does.

## Rulings

- - T8 apply step 0 calls scripts/sync.ps1 -CaptureOnly, but sync.ps1 is created in T9. Ruling: apply invokes sync.ps1 only if it exists (Test-Path); T9 adds it — cost if wrong: capture skipped until T9 lands (only during development).
- - T11 on-stop.ps1 runs from the installed plugin copy (~/.gemini/config/plugins), so it cannot dot-source repo libs. Ruling: on-stop reads <home>\.agy-config-state\machine.json directly (home = $env:AGYCFG_HOME or $HOME) and is self-contained — cost if wrong: duplicated path logic in one small file.
- Ruling: Invoke-Tests bootstraps the NuGet provider + TLS1.2 before Install-Module — PS 5.1 prompts otherwise and fails non-interactively — cost if wrong: none (only when Pester 5 is missing).
- Ruling: Write-JsonFile sorts object keys — deterministic diffs for synced JSON — cost if wrong: agy settings.json key order changes cosmetically.
- Ruling: Get-Profile also returns Permissions (profiles/<p>/permissions.json) and Path — Task 8 needs profile permissions; spec §5 lists permissions per profile — cost if wrong: one extra key.
- Ruling: Invoke-Tests splits comma-joined -Path values — powershell -File passes arrays as one string — cost if wrong: none.
- Ruling: Merge-ThreeWaySet emits items on the pipeline (callers wrap in @()) instead of returning one array object — idiomatic PowerShell, tests pipe into Should — cost if wrong: none.
- Ruling: Read-JsonFile now emits a top-level JSON array item by item (callers wrap with @()) — the Task 1 comma-return nested arrays inside @() and broke Get-SourceList — cost if wrong: a caller that forgets @() gets a scalar for one-item arrays.
- Ruling: packaged plugin.json takes author/license from the source entry (fallback 'See repository') and adds `repository` — plan hardcoded author 'Anthropic', but sources are generic — cost if wrong: none.
- Ruling: an existing non-git folder at a git-plugin destination is moved to snapshots/<plugin>-<stamp> before cloning — never delete user data — cost if wrong: disk space.
- Ruling: pip-tool source gets an optional `command` field (exe name; default first `provides`) and installs with --upgrade; Uninstall-PipTool removes only the provided agy skill folders, not the Python package — graphify's own `uninstall` would also remove it from Claude Code and other agents — cost if wrong: package stays installed.
- Ruling: Install-Marketplace returns the actually installed Version (agy cannot pin) so callers record it in the lock — cost if wrong: none.
- Ruling: Find-Secrets returns a Rule name per finding (github-token, openai-key, google-key, private-key, password, email, user-path) and always allows example.* / users.noreply.github.com emails, ${...} placeholders and C:\Users\<name>-style doc paths; also matches JSON-escaped double backslashes — cost if wrong: a doc example gets flagged or a real path slips through.
- Ruling: THIRD_PARTY lists graphify by its PyPI URL (pip-tool sources have no repo field) and notes anthropics/skills has no root LICENSE but per-skill Apache-2.0 files — verified via GitHub API/raw files — cost if wrong: attribution wording.
- Ruling: apply/sync/update logic lives in scripts/lib/{Apply,Sync,Update}.ps1 as Invoke-Apply/Invoke-Sync/Invoke-Update; scripts/*.ps1 are thin wrappers that exit with the returned code — makes them testable with Pester mocks — cost if wrong: none.
- Ruling: applied.json also stores sourceDefs (the source entries) so a source deleted from the repo can still be uninstalled, and geminiManaged=true once apply has written GEMINI.md (Task 9 uses it to tell a pre-existing GEMINI.md from one we generated) — cost if wrong: larger state file.
- Ruling: a source with no locked version installs the latest and records it — new sources added without a lock still work — cost if wrong: an unreviewed version on that machine until the lock exists.
- Ruling: minimal core/plugins/agy-self-config/plugin.json created now so apply can install it; Task 11 completes the plugin — cost if wrong: none.
- Ruling: GEMINI.md regions are merged three-way (base = text apply last wrote, stored as applied.geminiProfileText/geminiCoreText); if both the machine and the repo changed a region since the base, the machine's version goes to a sync/<profile>-<stamp> branch instead of overwriting main — the spec's plain "write profile region back" would silently drop another machine's edit — cost if wrong: an extra branch to merge by hand.
- Ruling: owner sync pulls (rebase+autostash) before capturing, so three-way set merges see the other machines' latest additions — cost if wrong: one extra fetch per sync.
- Ruling: after pushing a conflict branch, local main is reset to origin/main (the work is safe on the remote branch) so later syncs do not keep conflicting — cost if wrong: unmerged local changes live only on the sync/* branch until merged.
- Ruling: exit codes 0 done/skipped, 2 secret found, 3 conflict branch, 4 push failed; files are written only when content changes (Update-TextFile/Update-JsonFile) and commit is skipped when nothing is staged — line-ending-only diffs made empty commits fail — cost if wrong: none.
- Ruling: update/sources is built in a separate git worktree (StateDir\update-worktree) from origin/main and pushed with --force (plan said --force-with-lease) — the branch is rebuilt from main each week and owned by the owner machine; a worktree keeps the main checkout and its captured changes untouched — cost if wrong: a hand edit pushed to update/sources by someone else is overwritten.
- Ruling: update also writes the new versions into applied.json so the next apply does not reinstall them — cost if wrong: none.
- Ruling: hooks.json uses agy's named-hook format {"agy-config-sync": {"Stop": [...]}} (verified in agy docs; the plan's flat {"Stop": [...]} was wrong) — cost if wrong: hook not loaded (agy plugin validate reports hooks 1).
- Ruling: on-stop.ps1 quotes the sync.ps1 path in one ArgumentList string (PS 5.1 does not quote array elements) — cost if wrong: none.
- Ruling: install logic lives in scripts/lib/Install.ps1 (Invoke-Install/Invoke-Uninstall) with thin wrappers; install.ps1 wraps its body in a script block and only calls `exit` when run as a file, so `irm | iex` never closes the user's window — cost if wrong: none.
- Ruling: install asks for confirmation BEFORE creating a profile or backing up, so "No" changes nothing; first apply runs with -SkipCapture (a pre-existing GEMINI.md is only backed up, and the summary tells the user how to keep its rules) — cost if wrong: old custom rules need a manual copy.
- Ruling: scheduled tasks live under Task Scheduler folder \agy-config\, run as the current user with RunLevel Limited; a follower's leftover sync/update tasks are removed — cost if wrong: logon-trigger registration may need admin on some Windows editions (checked during rollout).
- Ruling: yes-answers are per language in i18n (vi accepts c/co/có/y/yes) so .ps1 files stay ASCII — cost if wrong: none.
- Codex reworded two scanner-triggering examples in the plan and spec (a password assignment and a Windows user path) so Validate-Repo passes on docs — cost if wrong: none.
- Ruling: Codex could not run Pester in its sandbox (no network for Install-Module); the lead ran the whole suite after merge (above) — cost if wrong: none.
- Ruling (C2 fix shape): on a secret hit, sync leaves the captured changes uncommitted in the working tree instead of reverting them (spec 6.3 only says "do not commit"); apply's autostash keeps them, so hand edits are never lost and pre-existing untracked files are never deleted — cost if wrong: a blocked secret sits in the local working tree until the user removes it.
- Ruling (C3 fix shape): apply always runs steps 3-6; failed sources keep their previous applied entry; python-missing/too-old is a warning (source skipped, not a failure) per spec 9; install registers tasks even when some sources failed — cost if wrong: a machine with a broken source reports exit 1 at every logon until fixed.
- Ruling (I11 fix shape): Validate-Repo requires THIRD_PARTY rows only for core/sources.json; profile sources are personal and carry their repo URL — cost if wrong: personal sources in a public profile have no attribution row.
- Rollout: maintenance runs from the agy SessionStart hook at most once a week instead of Windows scheduled tasks (owner request: no background work while agy is closed, to save RAM). The per-turn Stop hook was removed; changes made through the agy-self-config skill are synced by the skill itself.
- Rollout: the project is English-only (owner request): Vietnamese README/CONTRIBUTING removed, the spec translated, and Validate-Repo rejects Vietnamese text. A profile's reply language stays configurable; its rule text is generated in English.
- Rollout: wrapper scripts resolve their repo path in the script body, because Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults (found when the hook started maintain.ps1 without -RepoRoot).
- Rollout: pulling from a brand-new remote without main counts as nothing to pull.
- Rollout: agy-self-config falls back to copying its folder when 'agy plugin install' fails while agy has it open.
- Rollout: pip tools with a 'module' run their setup through 'python -m'; if Windows Smart App Control blocks the pip launcher exe, it is replaced by a .cmd shim that runs 'python -m <module>'.
- Rollout: commits in this repo use the owner's GitHub noreply address, so automatic backups never publish a personal email.

## Deferred minor issues

- SecretScan skips UTF-16 text files; own-plugin copies include node_modules/.env/caches
- Copy-Folder can nest when Remove-Item partially fails on a locked file
- hooks.json relative ./hooks path depends on agy using the plugin root as cwd (verify in Task 15)
- spec 6.2 step 7 (check agy plugin list has every expected name) not implemented
- marketplace drift reinstalls at every logon when installed version != lock
- backup omits ~/.gemini/config/config.json and ~/.agents/.skill-lock.json; restore has no safety backup
- sync commits use the global git identity (email may be public)
- Update rollback result not checked
- transient own-plugin install failure keeps it listed but does not retry immediately
- Resolve-Tool misses Store Python and user-scope Git; pip "already satisfied" in global site-packages leaves no user-scripts exe
- workflows pin actions by tag, not SHA
- Marketplace plugins cannot be pinned; the weekly update may record a lower version number than the lock when the marketplace serves one (seen: modern-web-guidance-plugin 1.0.6 -> 1.0.0).
- Headless 'agy --print' cannot approve commands outside the read-only allowlist, so orientation's graphify step needs an interactive session.
