---
name: agy-self-config
description: Maintain this agy setup and its config repo. Use when the user wants to change how you work ("from now on..."), install, remove or find skills and plugins, back up, restore or move to a new machine, update skills, check why sync or update failed, sort out unknown skills, or contribute a change back to the shared repo.
---

# agy self-config

Your configuration lives in a git repo and is installed by its scripts. Change the repo, then let the scripts apply it. Editing files under `~/.gemini` directly works too, but only because `sync` copies them back into the repo afterwards.

## Find the repo first

Read `~/.agy-config-state/machine.json`. It holds `repoPath`, `profile` and `role` (`owner` can push to the repo; `follower` only receives).

This step is done when you know all three values. If the file is missing, the setup is not installed: follow "New machine" below.

## Pick the branch that matches the request

**Change how you work** (rules, language, habits):
1. Edit `<repoPath>/profiles/<profile>/GEMINI.profile.md`. A rule meant for every user goes into `<repoPath>/core/GEMINI.core.md` instead, and only on an owner machine.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File <repoPath>/scripts/apply.ps1`.
3. Done when the new rule appears in `~/.gemini/GEMINI.md` and apply exits 0.

**Install a third-party skill**:
1. Find it with `npx skills find <topic>` and show the user the options.
2. Install the one they pick: `npx skills add <owner/repo> --skill <name> -g -a antigravity -y`.
3. Run `scripts/sync.ps1 -Force`. Sync records it as a source in `profiles/<profile>/sources.json` with a locked version.
4. Done when the skill folder exists in `~/.gemini/config/skills/<name>` and the profile's `sources.json` lists it.

**Remove a skill or plugin**:
1. Delete its entry from the profile's `sources.json`. An owner removing it for everyone deletes it from `core/sources.json` and its row in `THIRD_PARTY.md`.
2. Run `apply.ps1`. Apply uninstalls only what it installed itself.
3. Done when it is gone from `~/.gemini/config/skills` or from `agy plugin list`.

**A skill the user wrote themselves**:
1. Put it in `~/.gemini/config/skills/<name>/SKILL.md` with `name` and `description` frontmatter.
2. Add `<name>` to `ownSkills` in the profile's `profile.json`. Use `ownPlugins` for a plugin.
3. Run `sync.ps1 -Force`.
4. Done when `profiles/<profile>/skills/<name>` exists in the repo.

**Allow a command without asking**:
1. Add the exact string, for example `command(npm test)`, to `profiles/<profile>/permissions.json`. Matching is exact, and `*` is not supported.
2. Run `apply.ps1`.
3. Done when the string is in `~/.gemini/antigravity-cli/settings.json` under `permissions.allow`.

**Unknown skills** (`~/.agy-config-state/unknown.json` lists them):
1. Ask the user about each item. It is one of:
   - their own: add it to `ownSkills`/`ownPlugins`;
   - from somewhere else: add a source entry with its repository and a `THIRD_PARTY.md` row;
   - to be ignored: add it to `ignored`.
2. Run `sync.ps1 -Force`.
3. Done when the next `unknown.json` no longer lists it.

**Back up now**: run `sync.ps1 -Force` on an owner machine. Done when it exits 0 and `git -C <repoPath> log -1` shows a `sync(...)` commit.

**New machine or restore**:
1. Run the one-line installer from the repo README, or `git clone` the repo and run `scripts/install.ps1 -ProfileName <profile>`.
2. Done when install prints its summary and `agy plugin list` shows `agy-self-config`.

**Update skills to newer versions**:
1. On an owner machine, run `scripts/update.ps1`. It installs the newest versions on this machine and pushes branch `update/sources`, which GitHub turns into a pull request.
2. Tell the user to review and merge that pull request. Other machines receive the update after the merge.
3. Done when the log shows "pushed update/sources" or "no source updates".

**Sync or update failed**: read [references/troubleshooting.md](references/troubleshooting.md). Done when the cause is named to the user with the log line that shows it.

**Contribute a change to the shared repo** (follower, or user of a fork): follow [references/contributing.md](references/contributing.md).

## Boundaries

- Ask the user before every push, merge, branch deletion or uninstall. Each one needs its own yes.
- Tokens, passwords and personal email addresses never go into the repo. MCP secrets stay as `${VARIABLE}` placeholders, with the real values in environment variables.
- File layout, script flags and exit codes: [references/files-and-scripts.md](references/files-and-scripts.md).
