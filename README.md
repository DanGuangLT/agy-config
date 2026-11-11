[Tiếng Việt](README.vi.md)

# Pre-configured skills for the Antigravity agent

A Windows setup for the Antigravity CLI (`agy`), with shared working rules, skills, and plugins.
Your own GitHub fork can back up your configuration automatically and restore it on another machine.
Weekly source updates arrive through a reviewable pull request; agy can maintain the setup through conversation.

## Just installed agy? Start here

Open Windows PowerShell on Windows 10 or 11. The scripts use Windows PowerShell 5.1 and run as your current user without administrator rights.

The script commands below use `powershell -NoProfile -ExecutionPolicy Bypass -File` so they work when local scripts are disabled by default. This applies only to that process and does not change your saved execution policy. Read the script before running it.

1. Check `agy --version`; you need agy 1.5 or newer.
2. Check `git --version`. If Git is missing, run `winget install Git.Git`, reopen PowerShell, and check again.
3. For the default project map tool, graphify, install Python 3.10 or newer if needed: `winget install Python.Python.3.13`. Check `python --version` afterward.
4. Node.js and `npx` are optional for finding new skills with `npx skills find`. GitHub CLI is not needed on your machine.

You can choose another installed project map skill, or `none`, instead of graphify. If you choose graphify without Python, the installer continues with the rest, reports what is missing, and `apply` retries at later logons.

## Install

### Recommended: fork and clone for your own backup

Fork [this repository](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent) on GitHub first. Replace `<your-account>` in the command below with the account that owns your fork. Configure Git authentication so this machine can push to it.

```powershell
git clone https://github.com/<your-account>/Pre-configured-skills-for-the-antigravity-agent.git
cd Pre-configured-skills-for-the-antigravity-agent
Get-Content .\scripts\install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Choose or create your own profile when asked. The installer asks for the reply language and project map tool, backs up the existing configuration, shows its planned actions, and asks for confirmation before registering scheduled tasks. It is safe to run again.

Role is determined per machine by a dry-run push to `origin`, then stored locally. A machine with push access is an **owner**: it backs up configuration changes and runs weekly source updates. A machine without push access is a **follower**: it receives configuration and updates from `main` without publishing changes. A direct clone of the public upstream normally makes you a follower and gives you no automatic GitHub backup.

### Use the shared configuration as a follower

```powershell
git clone https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent.git
cd Pre-configured-skills-for-the-antigravity-agent
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### One-line install

Read [install.ps1](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/blob/main/scripts/install.ps1) first: this command downloads and executes it. It clones the upstream repository into `~/.agy-config` by default; use the fork-and-clone method above for your own backup.

```powershell
irm https://raw.githubusercontent.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/main/scripts/install.ps1 | iex
```

From a clone, the supported installer options are:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language en -ProjectMapTool graphify
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language en -ProjectMapTool none -Yes -RepoPath .
```

`-ProfileName` selects or creates a profile; `-Language` selects its reply language; `-ProjectMapTool` selects graphify, another installed skill, or `none`. `-RepoPath` selects the repository location. `-Yes` accepts the displayed actions without confirmation. An existing clone is used in place. The full interface is `install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-Yes] [-RepoPath <path>]`.

## What gets installed

This table follows [core/sources.json](core/sources.json). A profile can add sources or replace a core source with the same `id`.

| Source | Skills or plugins | Installation |
|---|---|---|
| [Matt Pocock skills](https://github.com/mattpocock/skills) | Engineering, planning, research, writing, and other skills listed in the source file | Individual skills at a locked Git commit |
| [Vercel Labs skills](https://github.com/vercel-labs/skills) | `find-skills` | Individual skill at a locked Git commit |
| [Superpowers](https://github.com/obra/superpowers) | Development workflow plugin | Git plugin at a locked commit |
| [Anthropic Engineering](https://github.com/anthropics/knowledge-work-plugins) | `engineering` | Packaged plugin at a locked Git commit |
| [Anthropic Design](https://github.com/anthropics/knowledge-work-plugins) | `design` | Packaged plugin at a locked Git commit |
| [Anthropic developer and document skills](https://github.com/anthropics/skills) | `anthropic-dev-skills`: MCP builder, PDF, Word, Excel, PowerPoint | Packaged plugin at a locked Git commit |
| [graphifyy](https://pypi.org/project/graphifyy/) | `graphify` project map | Python package at a locked version, only when selected |
| [Chrome DevTools](core/sources.json) | `chrome-devtools-plugin` | `antigravity-plugins-official` marketplace |
| [Gemini API](core/sources.json) | `gemini-api` | `antigravity-plugins-official` marketplace |
| [Modern web guidance](core/sources.json) | `modern-web-guidance-plugin` | `antigravity-plugins-official` marketplace |

The repo also installs its own `agy-self-config` plugin, shared rules, the profile's rules, and eight read-only Git permissions. Other CLI settings are preserved. Profile MCP definitions use environment variable placeholders such as `${SERVICE_TOKEN}`; set the matching user environment variables separately on each machine.

Third-party content is downloaded from upstream rather than stored in this repository. Git sources use locked commits and Python tools use locked package versions. The marketplace cannot install an exact version: versions are recorded and the last working plugin copy is kept locally for rollback.

## Daily use

Talk to agy normally, for example: “From now on, explain your changes before running them,” “Install skill X,” or “I'm moving to a new machine.” The `agy-self-config` skill helps edit the right profile or source file, run the scripts, and check the logs. You do not need another coding agent to maintain this setup.

| When | Every machine | Owner machines additionally |
|---|---|---|
| At logon | `agy-config-apply`: receive configuration from `main` | `agy-config-sync`: capture local changes |
| After agy finishes a turn | The Stop hook returns immediately | Starts a detached sync process |
| Daily at 12:00 | — | `agy-config-sync` |
| Sunday at 10:00 | — | `agy-config-update`: test upstream updates and push `update/sources` |

Sync waits at least 10 minutes between automatic runs and prevents overlapping runs. Owner configuration changes go directly to `main`. Weekly source versions are reviewed in a PR before followers receive them; failed source updates roll back individually. The owner uses tested pending versions locally while the PR is awaiting review. Review and merge the weekly PR to publish those versions.

Manual commands, run from the clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync.ps1 -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1 -NoPush
```

`sync` and `update` publish only on owner machines; `-NoPush` tests source updates locally without pushing. Configuration capture excludes `trustedWorkspaces`, the selected model, machine names, conversation history, logs, caches, and unclassified skills. Secrets stop publication. Since the repository may be public, review your own rules and explicitly declared custom content before sharing them.

## Moving to a new machine

1. Install agy and Git, plus Python if you use graphify.
2. Clone your fork, authenticate Git for push access if you want an owner machine, and run `scripts/install.ps1`.
3. Select the same profile and set any user environment variables needed by MCP servers. Secrets are not restored from Git.
4. Check the installer summary and the logs. Existing configuration is backed up to `~/.agy-config-backup/<yyyyMMdd-HHmmss>` before it is changed.

Forks receive upstream improvements when you use GitHub's **Sync fork** or ask agy to merge `upstream/main`; this is a deliberate action, separate from your automatic backup.

## One-time repository settings for owners and fork owners

In your repository on GitHub:

1. Open **Settings → Actions → General** and enable **Allow GitHub Actions to create and approve pull requests**. The weekly workflow uses the built-in `GITHUB_TOKEN`, so your machine needs no GitHub CLI or extra PR token.
2. Protect `main`: require a pull request, one approving review, and passing CI checks. Enable code owner review for the sensitive paths listed in [CODEOWNERS](.github/CODEOWNERS).
3. Allow the repository owner to bypass those requirements so automatic configuration sync can push directly to `main`.

The weekly workflow creates or updates one PR from `update/sources`. If GitHub does not permit PR creation, the workflow succeeds and places a **Create pull request** compare link in its run summary; the local update log also contains the link. Open it manually. Validation also runs on pushes to `update/**` because PRs created by `GITHUB_TOKEN` do not trigger other workflows automatically.

## Uninstall

From the clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
# Optionally restore a backup; replace the example stamp with yours.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RestoreBackup 20261111-120000
```

The interface is `scripts/uninstall.ps1 [-RestoreBackup <stamp>]`. It unregisters the scheduled tasks and uninstalls `agy-self-config`. Third-party skills remain installed. Passing `-RestoreBackup` also restores the saved configuration from `~/.agy-config-backup/<stamp>`.

## Troubleshooting

- Read `~/.agy-config-state/logs` for install, apply, sync, and update results. Start with the latest file for the failing script.
- Check `~/.agy-config-state/unknown.json` for unclassified skills or plugins. Ask agy to declare their upstream source, mark them as your own in `ownSkills`/`ownPlugins`, or add them to `ignored`. They stay local until classified.
- If graphify is missing, install Python 3.10 or newer, then run `scripts/apply.ps1` or sign in again.
- If MCP variables are missing, set the named user environment variables and reopen PowerShell before applying again.
- If sync reports a conflict, ask agy to review and merge the `sync/<profile>-<yyyyMMdd-HHmmss>` branch. The conflicting edits are kept there for review.
- If updates cannot open a PR, use the compare link in the workflow summary or update log and check the repository settings above.

## License and contributions

Repository code is [MIT licensed](LICENSE). Upstream content retains its own license; see [THIRD_PARTY.md](THIRD_PARTY.md). Read [CONTRIBUTING.md](CONTRIBUTING.md) to add a source or improve the scripts, and [SECURITY.md](SECURITY.md) to report a vulnerability privately.
