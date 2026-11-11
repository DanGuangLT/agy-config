# Security policy

Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/security/advisories/new) using **Report a vulnerability**. Include the affected script or source, reproduction steps, impact, and relevant redacted logs. Do not post live credentials or sensitive configuration in a public issue or pull request. For a fork, use that fork's private reporting channel; upstream issues belong in the advisory link above.

If a credential has been exposed, revoke or rotate it with its provider immediately. Removing a file from the current branch does not remove it from Git history.

## What runs on your machine

Read the scripts before installation. They run as the current Windows user without administrator rights and can change that user's agy configuration.

| Component | When it runs | Commands and effects |
|---|---|---|
| `scripts/install.ps1` | When you run it | Checks tools and push access, may clone with Git, backs up configuration, applies the chosen profile, and removes the three scheduled tasks left by older versions. Shows the actions and asks for confirmation (`-Yes` accepts them). |
| `scripts/maintain.ps1` | Via the SessionStart hook when weekly maintenance is due, or manually | Owner: runs `apply` (full sync backup, then pull and installation), then `update`. Follower: runs `apply` only. Records the attempt and marks the week done only if everything succeeds. |
| `scripts/apply.ps1` | During installation, weekly maintenance, skill-guided changes, or manually | Captures local edits, fetches the configuration repo, installs sources and local plugins, writes rules, merges permissions, expands MCP environment variables, and checks installed plugins. |
| `scripts/sync.ps1` | Before owner `apply`, after each skill-guided configuration change, or manually | Reads allowed configuration, scans for secrets, and uses Git to commit and push owner changes. Conflicts are kept on a `sync/*` branch. A follower can capture locally but does not publish. |
| `scripts/update.ps1` | Owner: during weekly maintenance or manually | Queries upstream versions, installs and validates candidate sources, rolls back failed sources, saves a local pending lock, and pushes `update/sources`. `-NoPush` skips publication but still changes installed sources and local pending state. |
| `scripts/uninstall.ps1` | When you run it | Removes `agy-self-config` through the agy CLI and any scheduled tasks left by older versions; optionally restores a selected backup. Third-party skills remain. |
| `agy-self-config` SessionStart hook (`agy-config-weekly` → `hooks/on-start.ps1`) | When agy starts | Checks `weekly.last` (at least 7 days old) and `weekly-attempt.last` (at least 1 day old) in `~/.agy-config-state`; missing stamps are treated as due. If both checks pass, starts a hidden PowerShell maintenance process and returns `{}` immediately. Otherwise does nothing. |

No Windows scheduled tasks are registered, and nothing runs in the background while agy is closed. Successful automatic maintenance runs at most once a week; a failed week is retried at most once a day, at the next agy start.

Source installation invokes Git for pinned GitHub content, `agy plugin install` and `agy plugin validate` for plugins, and `python -m pip install --user` plus `graphify install --platform antigravity-windows` when graphify is selected. The `agy-self-config` skill may guide `npx skills find` for discovery. Installed plugins and skills can instruct agy to run tools, and plugins may include executable hooks: review their sources and licenses before enabling them.

Git sources use locked commits and Python tools use locked package versions. Marketplace plugins cannot be pinned to an exact version; their last working copies are kept locally for rollback. Owners use candidate updates immediately; other machines receive reviewed lock changes through `main` after the weekly PR is merged.

## Data and review boundaries

- Rules, allowed permissions, declared custom skills/plugins, source definitions, and protected MCP definitions may be published in your fork. Review this content before allowing automatic sync to a public repository.
- MCP secret values are replaced by `${VARIABLE}` placeholders. Provide real values through user environment variables on each machine. Secret scanning is a safeguard; it cannot prove arbitrary text contains no confidential information.
- The selected model, `trustedWorkspaces`, machine names, history, logs, caches, and unknown-source skills are excluded from sync. Unknown items are reported at `~/.agy-config-state/unknown.json` for classification.
- Logs and machine state live outside the clone in `~/.agy-config-state`; installation backups live in `~/.agy-config-backup/<stamp>`. These may contain sensitive local data. Redact logs before sharing.
- CI checks metadata, attribution, file size, ASCII scripts, secrets and personal data, runs PSScriptAnalyzer, and runs Pester. Intentional fake scanner inputs under `tests/` are allowlisted in `.gitleaks.toml`; the validator excludes `tests/` and `.superpowers/` only from secret and personal-data scanning.
- [CODEOWNERS](.github/CODEOWNERS) requires owner review for scripts, plugins/hooks, workflows, and source manifests. Configure branch protection and the owner sync bypass as described in the README. Weekly PR automation uses `GITHUB_TOKEN` on GitHub; it needs no GitHub CLI or additional PR token on users' machines.
