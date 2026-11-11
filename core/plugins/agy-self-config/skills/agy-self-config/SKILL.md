---
name: agy-self-config
description: Maintain this agy setup and its config repo. Use when the user wants to change how you work ("from now on..."), install, remove or find skills and plugins, back up, restore or move to a new machine, update skills, stop or resume following the shared repo, check why sync or update failed, sort out unknown skills, or contribute a change back to the shared repo.
---

# agy self-config

Your configuration lives in a profile folder and is installed by the shared repo's scripts. Change the profile, then let the scripts apply it. Editing files under `~/.gemini` directly works too, but only because `sync` copies them back into the profile afterwards.

Weekly maintenance runs automatically when agy starts (at most once a week; failed runs retry at most daily). Force it now with `scripts/maintain.ps1`.

## Find the repo first

Read `~/.agy-config-state/machine.json`. It holds `repoPath`, `profile` and `role` (`owner` can push to the shared clone; `follower` receives shared updates). It may also hold `profileRoot` and `backupRepo`. These paths use `$env:AGYCFG_HOME` instead of `~` when set.

Resolve these folders before editing:

- `<repoPath>` is the shared clone. Always run scripts from `<repoPath>/scripts/`.
- `<profileDir>` is `profileRoot` when set, otherwise `<repoPath>/profiles/<profile>/`. In personal mode, files such as `profile.json` live directly at the root of the personal clone, not inside another `profiles/` folder.
- `<profileGitRoot>` is `profileRoot` in personal mode, otherwise `repoPath`. Personal sync pushes to `backupRepo` on branch `main`, even when the machine's role is `follower`.

This step is done when you know the role, shared clone, profile folder and backup destination. If the state file is missing, follow "New machine" below. If the shared clone was moved, run `scripts/install.ps1` from its new folder to repair the saved path.

After each configuration change, run `<repoPath>/scripts/sync.ps1 -Force` to back it up immediately when the machine is an owner or has a personal backup. A follower without a personal backup does not publish changes.

## Pick the branch that matches the request

**Change how you work** (rules, language, habits):
1. Edit `<profileDir>/GEMINI.profile.md`. A rule meant for every user goes into `<repoPath>/core/GEMINI.core.md` instead, and only on an owner machine.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/apply.ps1`.
3. Done when the new rule appears in `~/.gemini/GEMINI.md` and apply exits 0.

**Install a third-party skill**:
1. Find it with `npx skills find <topic>` and show the user the options.
2. Install the one they pick: `npx skills add <owner/repo> --skill <name> -g -a antigravity -y`.
3. Run `scripts/sync.ps1 -Force`. Sync records it as a source in `<profileDir>/sources.json` with a locked version in `<profileDir>/sources.lock.json`.
4. Done when the skill folder exists in `~/.gemini/config/skills/<name>` and the profile's `sources.json` lists it.

**Remove a skill or plugin**:
1. For a shared skill while stopped, use the files named in "Stop or resume following the shared repo" below. For a personal source, delete its entry from `<profileDir>/sources.json`. An owner removing it for everyone deletes it from `<repoPath>/core/sources.json` and its row in `<repoPath>/THIRD_PARTY.md`.
2. Run `apply.ps1`. Apply uninstalls only what it installed itself.
3. Done when it is gone from `~/.gemini/config/skills` or from `agy plugin list`.

**Stop or resume following the shared repo**:
1. Run `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/follow.ps1` without a switch to show the state. Only followers can stop or resume. On an owner, the command explains that the owner maintains the shared repository and exits 1; explain this to the user and end this branch.
2. For `-Stop`, explain that shared rules, permissions and the skill list with its lock are copied into `<profileDir>/shared/`. The user fully controls those copies, including removing original skills. Nothing is uninstalled at stop. The shared clone, local scripts and this plugin no longer get updates. In personal mode the change is pushed to the backup right away. The stopped state and copies are restored with that backup on a new machine.
3. For `-Resume`, explain that `shared/` is saved to `~/.agy-config-backup/<stamp>-shared` and removed from the profile. Apply then pulls and installs the current shared list at once. The user's extra sources stay.
4. Get a yes from the user before running `-Stop` or `-Resume`. Then run `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/follow.ps1 -Stop`, or use `-Resume` instead for resume.
5. Run `follow.ps1` without a switch again. For resume, also check the apply result.
6. Done when status shows the new state; for resume, apply exits 0.

While stopped, remove or change a shared skill in `<profileDir>/shared/sources.json` and its lock, `<profileDir>/shared/sources.lock.json`. Edit shared rules in `<profileDir>/shared/GEMINI.core.md`. Run `apply.ps1` after editing. The user's own extra sources stay in `<profileDir>/sources.json`.

**A skill the user wrote themselves**:
1. Put it in `~/.gemini/config/skills/<name>/SKILL.md` with `name` and `description` frontmatter.
2. Add `<name>` to `ownSkills` in `<profileDir>/profile.json`. Use `ownPlugins` for a plugin.
3. Run `sync.ps1 -Force`.
4. Done when `<profileDir>/skills/<name>` exists. A custom plugin is saved under `<profileDir>/plugins/<name>`.

**Allow a command without asking**:
1. Add the exact string, for example `command(npm test)`, to `<profileDir>/permissions.json`. Matching is exact, and `*` is not supported.
2. Run `apply.ps1`.
3. Done when the string is in `~/.gemini/antigravity-cli/settings.json` under `permissions.allow`.

**Unknown skills** (`~/.agy-config-state/unknown.json` lists them):
1. Ask the user about each item. It is one of:
   - their own: add it to `ownSkills`/`ownPlugins` in `<profileDir>/profile.json`;
   - from somewhere else: add a source entry with its repository to `<profileDir>/sources.json` and a locked version to `<profileDir>/sources.lock.json`; shared sources also need a `<repoPath>/THIRD_PARTY.md` row;
   - to be ignored: add it to `ignored` in `<profileDir>/profile.json`.
2. Run `sync.ps1 -Force`.
3. Done when the next `unknown.json` no longer lists it.

**Back up now**: run `<repoPath>/scripts/sync.ps1 -Force` on an owner machine or one with a personal backup. Check the sync log and `git -C <profileGitRoot> log -1`. Done when sync exits 0 and the log confirms publication or nothing to do. In personal mode, check `origin` points to `backupRepo`.

**New machine or restore**:
1. Clone the shared repo and run `scripts/install.ps1`, or use the one-line installer from its README. Supply the same personal backup URL when asked, or pass `-BackupRepo <url>`. Install restores a saved profile from that repository into `profileRoot`. For first-time backup, create an empty private GitHub repo with no README or license and make sure Git can push to it; Enter skips backup.
2. For a fork used as the backup, clone that fork with push access and select the same profile. Install keeps the profile under `profiles/<profile>/` in that clone and does not ask for a separate backup repo.
3. Set any MCP secret environment variables on this machine. Done when install prints its summary and `agy plugin list` shows `agy-self-config`.

Running install again shows the current setup. Use `-Reinstall` for full setup again. After moving or renaming the shared clone, run install from the new folder once; it updates `repoPath` when the recorded folder no longer exists.

**Update skills to newer versions**:
1. On an owner machine, run `scripts/update.ps1`. It installs the newest versions on this machine and pushes branch `update/sources`, which GitHub turns into a pull request. Sources listed only in the personal backup stay at their saved versions.
2. Tell the user to review and merge that pull request. Other machines receive the update after the merge.
3. Done when the log shows "pushed update/sources" or "no source updates".

**Sync or update failed**: read [references/troubleshooting.md](references/troubleshooting.md). Done when the cause is named to the user with the log line that shows it.

**Contribute a change to the shared repo** (follower, or user of a fork): follow [references/contributing.md](references/contributing.md).

## Boundaries

- Ask the user before every push, merge, branch deletion or uninstall. Each one needs its own yes.
- Tokens, passwords and personal email addresses never go into the repo. MCP secrets stay as `${VARIABLE}` placeholders, with the real values in environment variables.
- File layout, script flags and exit codes: [references/files-and-scripts.md](references/files-and-scripts.md).
