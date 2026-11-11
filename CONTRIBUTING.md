[Tiếng Việt](CONTRIBUTING.vi.md)

# Contributing

This repository configures the Antigravity CLI (`agy`) on Windows. Contributions arrive as pull requests to [the upstream repository](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent). Start with [README.md](README.md) for installation and the owner/follower model.

## Add a skill or plugin source

1. Fork and clone the repo, then make a branch for your change.
2. Edit `core/sources.json` for a shared source, or `profiles/<profile>/sources.json` for a profile-specific source. Use a unique `id`; a profile entry overrides a core entry with the same `id`.
3. Choose the matching type: `github-skills`, `git-plugin`, `packaged-plugin`, `pip-tool`, or `marketplace`. Follow an existing entry in [core/sources.json](core/sources.json), including `provides` for classification. For example:

   ```json
   {
     "id": "example-skills",
     "type": "github-skills",
     "repo": "https://github.com/example/skills",
     "skills": [{"name": "example-skill", "path": "skills/example-skill"}],
     "provides": ["example-skill"]
   }
   ```

4. For every new core source, add both a row to [THIRD_PARTY.md](THIRD_PARTY.md) and a locked version under its `id` in [core/sources.lock.json](core/sources.lock.json). The row includes the source, license, and exact `repo` URL. For a `pip-tool`, list its `package` name and PyPI link instead. Marketplace entries identify the plugin and marketplace. Profile sources need a version in that profile's `sources.lock.json`; their repo URL is recorded in `sources.json`, and they do not need a THIRD_PARTY row. Do not copy upstream skills into this repo.
5. On a configured owner machine, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1 -NoPush` to install and validate candidate upstream versions locally. This changes installed sources and local pending state; it does not push a branch or open a PR. Review the update log and record the tested commits or package versions in the appropriate `sources.lock.json` for your PR. If you cannot run the installation locally, let CI check repository structure and state that limitation in the PR; CI does not replace a live source installation check.
6. Add tests for behavior changes, run the checks below, and open a PR with the supplied template. Include what changed, why, and the validation results.

## Development rules and checks

- Windows PowerShell 5.1 only; keep every `.ps1` ASCII-only. Localized messages belong in `scripts/i18n/*.json`. Markdown may contain Vietnamese.
- Write text as UTF-8 without BOM through `Write-TextFile`; reuse the library helpers in `scripts/lib/`. Wrap external tools and network calls with `Invoke-External` and `Invoke-Http` so tests can mock them.
- Write a failing Pester 5 test before changing script behavior, then make it pass. Tests need to cover the actual behavior.
- Keep third-party content at its original source with a locked version. Do not vendor it into the repo.
- Never include secrets, personal email addresses, machine-specific user paths, conversation history, logs, or caches. MCP definitions use `${VARIABLE}` placeholders. Unknown skills stay in the local `unknown.json` until classified.
- Use [the PR template](.github/PULL_REQUEST_TEMPLATE.md), including the source attribution checklist when adding a source.

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-Repo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
$issues = @(Invoke-ScriptAnalyzer -Path scripts -Recurse -Severity Error)
$issues
if ($issues.Count -gt 0) { throw 'PSScriptAnalyzer reported errors.' }
```

The test runner requires Pester 5.5 or newer and installs it for the current user if missing. To run just the validator tests, append `-Path tests/unit/ValidateRepo.Tests.ps1` to the test command. Run the whole suite again before submitting.

Repository validation checks JSON, skill and plugin metadata, core source attribution, locked versions for core and profile sources, the 1 MB file limit, ASCII scripts, secrets, and personal data. Fake scanner inputs under `tests/` and local `.superpowers/` notes are excluded only from the validator's secret and personal-data checks; other checks still apply. Gitleaks uses [.gitleaks.toml](.gitleaks.toml) to allowlist test fixtures.

## Review and delivery

[CODEOWNERS](.github/CODEOWNERS) names `@DanGuangLT` as owner, with explicit rules for `scripts/`, plugin code and hooks under `core/plugins/`, `core/sources*.json`, and `.github/`. These paths run code or select downloaded code and require code owner review. Changes to `main` go through a PR, one approving review, and green checks; the owner bypass exists for automatic configuration sync.

Validation runs on PRs and pushes to `main` and `update/**`. The weekly update workflow creates or edits the PR for `update/sources`; when PR creation is unavailable, its summary links to manual PR creation. Report vulnerabilities privately using [SECURITY.md](SECURITY.md).
