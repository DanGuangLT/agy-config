# Pre-configured skills for the Antigravity agent

A Windows setup for the Antigravity CLI (`agy`), with shared working rules, skills, and plugins.
A private GitHub repository can back up your configuration automatically and restore it on another machine.
Weekly source updates arrive through a reviewable pull request; agy can maintain the setup through conversation.

## Just installed agy? Start here

Open Windows PowerShell on Windows 10 or 11. The scripts use Windows PowerShell 5.1 and run as your current user without administrator rights.

The script commands below use `powershell -NoProfile -ExecutionPolicy Bypass -File` so they work when local scripts are disabled by default. This applies only to that process and does not change your saved execution policy. Read the script before running it.

1. Check `agy --version`; you need agy 1.5 or newer.
2. Check `git --version`. If Git is missing, run `winget install Git.Git`, reopen PowerShell, and check again.
3. For the default project map tool, graphify, install Python 3.10 or newer if needed: `winget install Python.Python.3.13`. Check `python --version` afterward.
4. Node.js and `npx` are optional for finding new skills with `npx skills find`. GitHub CLI is not needed on your machine.

You can choose another installed project map skill, or `none`, instead of graphify. If you choose graphify without Python, the installer continues with the rest, reports what is missing, and `apply` retries during later weekly maintenance or when run manually.

## Install

### Simplest: clone and install once

Before running install, create an **empty private repository** on GitHub for your backup. Add no README or license. Make sure Git on this machine can push to it. Git Credential Manager signs you in on the first push.

```powershell
git clone https://github.com/DanGuangLT/agy-config.git
cd agy-config
Get-Content .\scripts\install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Run install once. It finds agy's folder (`~/.gemini`) by itself and installs all shared skills and plugins. If you have not started agy yet, install creates the folders it needs.

Install asks for the backup repository URL. Paste it, or press Enter to skip backup. It asks for your reply language and project map tool, backs up the current agy files locally, and applies the setup. With a backup URL, it saves your profile in `~/.agy-config-personal` and pushes it to that repository.

On a new machine, run install and give it the **same backup URL**. It restores the saved configuration without asking the language and project map questions again. Set any MCP secret environment variables on that machine separately.

Running install again on a machine that is already set up just shows the current setup. Use `-Reinstall` to run the full setup again. After moving or renaming the clone, run install once from its new folder to update the saved path.

Install registers no Windows scheduled tasks. It removes the three tasks older versions created: `agy-config-apply`, `agy-config-sync`, and `agy-config-update`.

### One-line install

Read [install.ps1](https://github.com/DanGuangLT/agy-config/blob/main/scripts/install.ps1) first: this command downloads and executes it. It clones the shared repository into `~/.agy-config` by default, then runs the same setup and asks for your backup URL.

```powershell
irm https://raw.githubusercontent.com/DanGuangLT/agy-config/main/scripts/install.ps1 | iex
```

### Fork to change the shared configuration or contribute

Fork [this repository](https://github.com/DanGuangLT/agy-config) on GitHub. Replace `<your-account>` with your account and make sure Git can push to your fork.

```powershell
git clone https://github.com/<your-account>/agy-config.git
cd agy-config
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Choose or create a profile when asked. Your fork is your backup, with the profile in `profiles/<name>/`. Install does not ask for a separate backup repository when this machine can push to the fork.

Role is determined per machine by a dry-run push to the shared clone's `origin`, then stored locally. A machine with push access is an **owner** and can publish shared changes and weekly source updates. A machine without push access is a **follower** and receives shared updates from `main`. Followers with a personal backup repository also publish their own profile there. If you skip the backup URL, there is no automatic GitHub backup.

### Installer options

`install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-BackupRepo <url|none>] [-Reinstall] [-Yes] [-RepoPath <path>]`

From a clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language en -ProjectMapTool graphify
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language en -ProjectMapTool none -BackupRepo https://github.com/<your-account>/agy-config-backup.git -Yes -RepoPath .
```

The second example is non-interactive. `-ProfileName` selects or creates a profile. `-Language` selects its reply language. `-ProjectMapTool` selects graphify, another installed skill, or `none`. `-BackupRepo` supplies the backup URL; `none` skips backup. With `-Yes`, no backup prompt is shown, so supply `-BackupRepo` to enable backup. `-Yes` accepts the displayed actions without confirmation. `-RepoPath` selects the shared repository location. An existing clone is used in place.

Script prompts and messages are English only (`scripts/i18n/en.json`). By default agy replies in the same language you write in (profile language `auto`). To pin one language, set `language` in your `profile.json` to a code such as `vi` or `ja`; the rule is generated in English, for example "Always reply to the user in Vietnamese".

## Stop or resume following the shared repository

Followers follow the shared repository by default. Weekly maintenance brings new skills, versions and shared rules. Only followers can stop or resume. On an owner machine, the command explains that the owner maintains the shared repository and exits 1.

Run these commands from the shared clone. Without a switch, `follow.ps1` shows the current state.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\follow.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\follow.ps1 -Stop
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\follow.ps1 -Resume
```

`-Stop` copies the shared rules, permissions and skill list with its locked versions into your profile's `shared/` folder (`<profileDir>/shared/`). You fully control those copies, including removing original skills. Nothing is uninstalled at that moment. The shared clone is no longer pulled, so its local scripts and the agy-self-config plugin are not updated either. The stopped state and `shared/` are saved with your personal backup and restored on a new machine.

`-Resume` keeps a copy of `shared/` in `~/.agy-config-backup/<stamp>-shared`, removes it from the profile, then pulls and installs the current shared list at once. Skills you added yourself in the profile's own `sources.json` stay.

You can also just ask agy: "Stop syncing with the original repo" or "Sync again."

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

When agy starts, the plugin's only hook, `SessionStart` (`agy-config-weekly` → `hooks/on-start.ps1`), checks `weekly.last` and `weekly-attempt.last` in `~/.agy-config-state`. If the last successful maintenance is at least 7 days old and the last attempt is at least 1 day old (or the respective stamps are missing), it starts `scripts/maintain.ps1` hidden in the background and returns immediately. If the script is missing, it writes a warning to `logs/hook-yyyyMMdd.log` and adds startup context with the fix, at most once a day. Otherwise it does nothing. Nothing runs in the background while agy is closed, keeping RAM free for games and other work.

On an owner machine, maintenance runs `apply` (first a full sync to back up this machine's configuration, then a pull and installation) followed by `update`, which tests upstream versions and pushes `update/sources` for a PR. A follower runs `apply` only. The week is marked done only if everything succeeds; failures are retried at the next agy start after at least 1 day.

Changes made through the `agy-self-config` skill are backed up immediately with `scripts/sync.ps1 -Force` after each change. Owner configuration changes go directly to `main` in the shared clone. Personal backups go to `main` in the repository recorded as `backupRepo`; the profile files live at the root of `profileRoot` (`~/.agy-config-personal` by default). Without `profileRoot`, they live in `<repoPath>/profiles/<profile>/`. Weekly source versions are reviewed in a PR before followers receive them; failed source updates roll back individually. The owner uses tested pending versions locally while the PR is awaiting review. Review and merge the weekly PR to publish those versions. Sources listed only in a personal backup stay at their saved versions.

Manual commands, run from the clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync.ps1 -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1 -NoPush
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\maintain.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\follow.ps1
```

`sync` publishes on owner machines and machines with a personal backup repository. `update` publishes only on owner machines; `-NoPush` tests source updates locally without pushing. `apply` pulls shared updates while following and, when configured, the personal backup before installing the profile. `follow.ps1` shows the following state; use `-Stop` or `-Resume` to change it. Configuration capture excludes `trustedWorkspaces`, the selected model, machine names, conversation history, logs, caches, and unclassified skills. Secrets stop publication. Since the repository may be public, review your own rules and explicitly declared custom content before sharing them.

## Moving to a new machine

1. Install agy and Git, plus Python if you use graphify.
2. Clone the shared repo and run `scripts/install.ps1`. Give the same personal backup URL to restore your saved configuration. If you use a fork for backup, clone it instead, authenticate Git for push access, and select the same profile during install.
3. Set any user environment variables needed by MCP servers. Secrets are not restored from Git.
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

The interface is `scripts/uninstall.ps1 [-RestoreBackup <stamp>]`. It uninstalls `agy-self-config`, removes any scheduled tasks left by older versions, and forgets this machine's setup so the next install runs in full. Third-party skills and your personal backup repository remain. Passing `-RestoreBackup` also restores the saved configuration from `~/.agy-config-backup/<stamp>`.

## Troubleshooting

- Read `~/.agy-config-state/logs/<apply|sync|update|maintain|hook>-yyyyMMdd.log`. Start with the latest file for the failing script.
- If the clone was moved or renamed, run `scripts/install.ps1` once from its new folder. A warning in `hook-*.log` means the hook could not find the recorded repo's maintenance script; install repairs the saved path when the old folder is gone.
- If the personal backup cannot push, check Git authentication and push access to `backupRepo`. Check `git -C <profileRoot> remote -v`, then retry `scripts/sync.ps1 -Force`. Keep your local profile files while fixing access.
- Run `scripts/maintain.ps1` to force maintenance now. To make the hook run again sooner, delete `~/.agy-config-state/weekly.last`, then start agy; the 1-day limit since the last attempt still applies.
- Check `~/.agy-config-state/unknown.json` for unclassified skills or plugins. Ask agy to declare their upstream source, mark them as your own in `ownSkills`/`ownPlugins`, or add them to `ignored`. They stay local until classified.
- If graphify is missing, install Python 3.10 or newer, then run `scripts/apply.ps1` or wait for weekly maintenance at a later agy start.
- If MCP variables are missing, set the named user environment variables and reopen PowerShell before applying again.
- If sync reports a conflict, ask agy to review and merge the `sync/<profile>-<yyyyMMdd-HHmmss>` branch. The conflicting edits are kept there for review.
- If updates cannot open a PR, use the compare link in the workflow summary or update log and check the repository settings above.

## License and contributions

Repository code is [MIT licensed](LICENSE). Upstream content retains its own license; see [THIRD_PARTY.md](THIRD_PARTY.md). Read [CONTRIBUTING.md](CONTRIBUTING.md) to add a source or improve the scripts, and [SECURITY.md](SECURITY.md) to report a vulnerability privately.
