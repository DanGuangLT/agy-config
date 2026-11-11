# Security policy

Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/security/advisories/new) using **Report a vulnerability**. Include the affected script or source, reproduction steps, impact, and relevant redacted logs. Do not post live credentials or sensitive configuration in a public issue or pull request. For a fork, use that fork's private reporting channel; upstream issues belong in the advisory link above.

If a credential has been exposed, revoke or rotate it with its provider immediately. Removing a file from the current branch does not remove it from Git history.

## What runs on your machine

Read the scripts before installation. They run as the current Windows user without administrator rights and can change that user's agy configuration.

| Component | When it runs | Commands and effects |
|---|---|---|
| `scripts/install.ps1` | When you run it | Checks tools and push access, may clone with Git, backs up configuration, applies the chosen profile, and registers scheduled tasks after showing the actions and asking for confirmation (`-Yes` accepts them). |
| `scripts/apply.ps1` | During installation, at logon, or manually | Captures local edits, fetches the configuration repo, installs sources and local plugins, writes rules, merges permissions, expands MCP environment variables, and checks installed plugins. |
| `scripts/sync.ps1` | Owner: after an agy turn through a detached Stop hook, at logon, daily at 12:00, or manually | Reads allowed configuration, scans for secrets, and uses Git to commit and push owner changes. Conflicts are kept on a `sync/*` branch. A follower can capture locally but does not publish. |
| `scripts/update.ps1` | Owner: Sunday at 10:00 or manually | Queries upstream versions, installs and validates candidate sources, rolls back failed sources, saves a local pending lock, and pushes `update/sources`. `-NoPush` skips publication but still changes installed sources and local pending state. |
| `scripts/uninstall.ps1` | When you run it | Removes scheduled tasks and `agy-self-config` through the agy CLI; optionally restores a selected backup. Third-party skills remain. |
| `agy-self-config` Stop hook | After agy finishes a turn | Reads local machine state, starts a hidden detached PowerShell sync for an owner, returns `{}` immediately, and does not wait for the sync. |

Source installation invokes Git for pinned GitHub content, `agy plugin install` and `agy plugin validate` for plugins, and `python -m pip install --user` plus `graphify install --platform antigravity-windows` when graphify is selected. The `agy-self-config` skill may guide `npx skills find` for discovery. Installed plugins and skills can instruct agy to run tools, and plugins may include executable hooks: review their sources and licenses before enabling them.

Git sources use locked commits and Python tools use locked package versions. Marketplace plugins cannot be pinned to an exact version; their last working copies are kept locally for rollback. Owners use candidate updates immediately; other machines receive reviewed lock changes through `main` after the weekly PR is merged.

## Data and review boundaries

- Rules, allowed permissions, declared custom skills/plugins, source definitions, and protected MCP definitions may be published in your fork. Review this content before allowing automatic sync to a public repository.
- MCP secret values are replaced by `${VARIABLE}` placeholders. Provide real values through user environment variables on each machine. Secret scanning is a safeguard; it cannot prove arbitrary text contains no confidential information.
- The selected model, `trustedWorkspaces`, machine names, history, logs, caches, and unknown-source skills are excluded from sync. Unknown items are reported at `~/.agy-config-state/unknown.json` for classification.
- Logs and machine state live outside the clone in `~/.agy-config-state`; installation backups live in `~/.agy-config-backup/<stamp>`. These may contain sensitive local data. Redact logs before sharing.
- CI checks metadata, attribution, file size, ASCII scripts, secrets and personal data, runs PSScriptAnalyzer, and runs Pester. Intentional fake scanner inputs under `tests/` are allowlisted in `.gitleaks.toml`; the validator excludes `tests/` and `.superpowers/` only from secret and personal-data scanning.
- [CODEOWNERS](.github/CODEOWNERS) requires owner review for scripts, plugins/hooks, workflows, and source manifests. Configure branch protection and the owner sync bypass as described in the README. Weekly PR automation uses `GITHUB_TOKEN` on GitHub; it needs no GitHub CLI or additional PR token on users' machines.
