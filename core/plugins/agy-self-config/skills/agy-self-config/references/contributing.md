# Contributing a change upstream

Use this when the user is a follower, or works from a fork, and wants a change to go into the shared repo `DanGuangLT/agy-config`.

1. Make sure the change belongs in `<repoPath>/core/`. Personal preferences stay in `<profileDir>`: `profileRoot` from `machine.json` when set, otherwise `<repoPath>/profiles/<profile>/`. The personal clone holds these files at its root and backs them up to `backupRepo`.
2. In `<repoPath>`, create a branch: `git checkout -b <short-topic>`.
3. Make the change:
   - New source: add the entry to `core/sources.json` (type, repository and `provides`), plus a row in `THIRD_PARTY.md` with its license.
   - Rule change: edit `core/GEMINI.core.md`.
   - Scripts: change them only with tests in `tests/`.
4. Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` and `tests/Validate-Repo.ps1`. Done when both pass.
5. With the user's approval, push the branch to their fork and open a pull request against `DanGuangLT/agy-config:main`. Fill in the pull request template.
6. To bring upstream improvements into a fork, use "Sync fork" on GitHub, or run `git fetch upstream` and merge `upstream/main` with the user's approval.
