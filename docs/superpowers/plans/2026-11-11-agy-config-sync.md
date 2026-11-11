# agy Config Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public repo that installs a pre-configured Antigravity CLI (`agy`) on any Windows machine with one command, backs the owner's configuration up automatically, updates third-party skills weekly with a locked, reviewable version list, and teaches `agy` to maintain all of this by itself.

**Architecture:** PowerShell scripts (`install`, `apply`, `sync`, `update`, `uninstall`) built on small dot-sourced libraries in `scripts/lib/`. Third-party skills are recorded as sources plus a lock file and fetched from upstream at pinned versions. Personal settings live in `profiles/<name>/`. A repo-owned agy plugin (`agy-self-config`) ships the `Stop` hook that triggers sync and the skill that lets agy maintain the setup. GitHub Actions validate PRs and open the weekly update PR.

**Tech Stack:** Windows PowerShell 5.1, Pester ≥ 5.5, git, `agy` CLI ≥ 1.5, Python ≥ 3.10 (graphify only), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-11-agy-config-sync-design.md`. Read it before any task. Section numbers below (§) refer to it.

## Global Constraints

- Runs on Windows PowerShell 5.1 with no admin rights. Use no PowerShell 7-only syntax (`??`, `?.`, ternary, `&&`, `-Parallel`).
- Every `.ps1` file is ASCII-only. User-facing text in other languages lives in `scripts/i18n/en.json` and `scripts/i18n/vi.json`.
- Every text file is written as UTF-8 **without BOM** through `Write-TextFile` (Task 1). Never use `Set-Content`/`Out-File` defaults.
- Every machine path comes from `Get-AgyPaths` (Task 1). Tests set `$env:AGYCFG_HOME` to a temp folder, which replaces `$HOME` for every path.
- Every call to `git`, `agy`, `python`, the graphify executable or the network goes through `Invoke-External` / `Invoke-Http` (Task 1), so tests can `Mock` them.
- Never synced (§6.3): `trustedWorkspaces`, `model`, machine name, chat history, logs, caches, unknown-source skills.
- The 8 read-only permissions (§3): `command(git status)`, `command(git status --short)`, `command(git branch --show-current)`, `command(git log --oneline -15)`, `command(git diff)`, `command(git diff --stat)`, `command(git diff --cached)`, `command(git remote -v)`.
- Default clone `~/.agy-config`. State `~/.agy-config-state`. Backups `~/.agy-config-backup/<yyyyMMdd-HHmmss>`.
- Branches: weekly update `update/sources`; sync conflict `sync/<profile>-<yyyyMMdd-HHmmss>`.
- Sync debounce 10 minutes; weekly update on Sunday (§11).
- Scheduled task names: `agy-config-apply` (at logon), `agy-config-sync` (daily 12:00 plus at logon, owner only), `agy-config-update` (Sunday 10:00, owner only).

## Review Focus

1. **Vietnamese or other non-ASCII text in `GEMINI.md`, profile files and user names** (`C:\Users\Nguyễn Văn A`). Must round-trip byte-for-byte through build, split, write and read under PowerShell 5.1. Tested in Task 2 (`round-trips Vietnamese text`) and Task 1 (`writes UTF-8 without BOM`).
2. **Scheduled-task context, where `agy`, `git` or `python` are not on PATH.** Tools must be found at known install locations, or the run fails with a log line instead of hanging. Tested in Task 1 (`Resolve-Tool falls back to known locations`).
3. **Offline at logon, or a fetch failing halfway through `apply`.** Nothing is uninstalled, `applied.json` is unchanged, the exit code is non-zero and the error is logged. Tested in Task 8 (`leaves state untouched when a source fails`).
4. **Two syncs at once** (hook plus scheduled task). The second exits at once. A lock older than 30 minutes is treated as stale and taken over. Tested in Task 9 (`second run exits while lock held`, `takes over stale lock`).
5. **`GEMINI.md` edited with markers deleted or mangled.** No text may be lost: the whole file goes into the profile region. Tested in Task 2 (`keeps all text when markers are missing`).

---

## File Structure

```text
.gitattributes .gitignore LICENSE THIRD_PARTY.md SECURITY.md
README.md README.vi.md CONTRIBUTING.md CONTRIBUTING.vi.md
core/GEMINI.core.md core/permissions.json core/sources.json core/sources.lock.json
core/plugins/agy-self-config/{plugin.json,hooks.json,hooks/on-stop.ps1,skills/agy-self-config/SKILL.md,skills/agy-self-config/references/*.md}
profiles/_template/{profile.json,GEMINI.profile.md,sources.json,sources.lock.json,permissions.json}
profiles/lianharman/{profile.json,GEMINI.profile.md,sources.json,sources.lock.json,permissions.json}   # sync may add mcp.json, skills/, plugins/
scripts/install.ps1 scripts/apply.ps1 scripts/sync.ps1 scripts/update.ps1 scripts/uninstall.ps1
scripts/i18n/en.json scripts/i18n/vi.json
scripts/lib/Core.ps1        # paths, json, text io, logging, external calls, tool resolution
scripts/lib/GeminiMd.ps1    # build/split GEMINI.md
scripts/lib/Settings.ps1    # permissions merge, MCP protect/expand
scripts/lib/State.ps1       # machine/applied/pending state, three-way set merge, run lock
scripts/lib/Profile.ps1     # load/create profiles
scripts/lib/Sources.ps1     # source model, dispatch, lock read/write
scripts/lib/Source.GitHub.ps1     # github-skills, git-plugin, packaged-plugin
scripts/lib/Source.Other.ps1      # pip-tool, marketplace
scripts/lib/Inventory.ps1   # machine inventory, skill-lock import, classification
scripts/lib/SecretScan.ps1
scripts/lib/Repo.ps1        # git ops on the config repo, push access
scripts/lib/Scheduler.ps1
scripts/lib/All.ps1         # dot-sources every lib file in order
tests/Invoke-Tests.ps1      # bootstraps Pester 5, runs tests/unit and tests/integration
tests/Validate-Repo.ps1     # repo hygiene checks used by CI
tests/unit/*.Tests.ps1 tests/integration/*.Tests.ps1 tests/fixtures/...
.github/workflows/validate.yml .github/workflows/update-pr.yml
.github/CODEOWNERS .github/PULL_REQUEST_TEMPLATE.md
```

---

### Task 1: Scaffold, test harness and core library

**Files:**
- Create: `.gitattributes` (`* text=auto eol=lf`), `.gitignore` (`.agy-tmp/`, `*.log`), `LICENSE` (MIT, holder "DanGuangLT and contributors", 2026)
- Create: `scripts/lib/Core.ps1`, `scripts/lib/All.ps1`, `tests/Invoke-Tests.ps1`
- Test: `tests/unit/Core.Tests.ps1`

**Interfaces:**
- Produces:
  - `Get-AgyPaths() -> hashtable` with keys `Home, GeminiMd, CliSettings, SkillsDir, PluginsDir, McpConfig, SkillLock, StateDir, LogDir, SnapshotDir, StagingDir, CacheDir, BackupRoot, DefaultRepo`. Values:
    - `$h\.gemini\GEMINI.md`
    - `$h\.gemini\antigravity-cli\settings.json`
    - `$h\.gemini\config\skills`
    - `$h\.gemini\config\plugins`
    - `$h\.gemini\config\mcp_config.json`
    - `$h\.agents\.skill-lock.json`
    - `$h\.agy-config-state`, plus its `logs`, `snapshots`, `staging`, `cache`
    - `$h\.agy-config-backup`
    - `$h\.agy-config`

    Here `$h = $env:AGYCFG_HOME` if set, else `$HOME`.
  - `Read-TextFile([string]$Path) -> string`, `Write-TextFile([string]$Path, [string]$Text)` (creates parent dirs, UTF-8 no BOM).
  - `Read-JsonFile([string]$Path, $Default) -> hashtable|array` (returns `$Default` when missing; converts PSCustomObject to nested hashtables/arrays), `Write-JsonFile([string]$Path, $Object)` (depth 20, 2-space indent via `Format-Json`).
  - `Write-AgyLog([string]$Script, [string]$Message, [ValidateSet('INFO','WARN','ERROR')]$Level='INFO')`: appends `yyyy-MM-dd HH:mm:ss [LEVEL] message` to `LogDir\<Script>-yyyyMMdd.log`.
  - `Invoke-External([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory) -> @{ExitCode; StdOut; StdErr}` (never throws on non-zero).
  - `Invoke-Http([string]$Uri) -> object` (thin `Invoke-RestMethod` wrapper).
  - `Resolve-Tool([ValidateSet('git','agy','python','node')]$Name) -> string|null`. Tries `Get-Command` first, then known locations:
    - agy: `$env:LOCALAPPDATA\agy\bin\agy.exe`
    - git: `$env:ProgramFiles\Git\cmd\git.exe`
    - python: newest `$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe`, `C:\Python3*\python.exe`
    - node: `$env:ProgramFiles\nodejs\node.exe`

- [ ] **Step 1: Write `tests/Invoke-Tests.ps1`**: if `Get-Module -ListAvailable Pester | ? Version -ge 5.5` is empty, run `Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck`; then `Invoke-Pester -Path tests/unit,tests/integration -Output Detailed -CI`. If the module install is blocked, stop and ask the user to install Pester 5.

- [ ] **Step 2: Write the failing tests** in `tests/unit/Core.Tests.ps1`. `BeforeAll` dot-sources `scripts/lib/All.ps1` and sets `$env:AGYCFG_HOME = Join-Path $TestDrive 'home'`.
  - `Get-AgyPaths honors AGYCFG_HOME`: `(Get-AgyPaths).SkillsDir | Should -Be (Join-Path $TestDrive 'home\.gemini\config\skills')`.
  - `writes UTF-8 without BOM`: after `Write-TextFile $p "Trả lời bằng tiếng Việt"`, the first 3 bytes `Should -Not -Be @(0xEF,0xBB,0xBF)` and `Read-TextFile $p | Should -Be "Trả lời bằng tiếng Việt"`. Build the string from code points in the test file to keep it ASCII, e.g. `[char]0x1EA3`.
  - `Read-JsonFile returns default when missing` and `Read-JsonFile returns hashtables`: `(Read-JsonFile $p @{}).permissions.allow[0] | Should -Be 'command(git status)'`, and the type `Should -BeOfType [hashtable]`.
  - `Write-JsonFile round-trips non-ASCII`.
  - `Invoke-External returns exit code without throwing`: `(Invoke-External 'cmd.exe' @('/c','exit 3')).ExitCode | Should -Be 3`.
  - `Resolve-Tool falls back to known locations`: `Mock Get-Command { $null }`, create a fake `$env:LOCALAPPDATA\agy\bin\agy.exe` under `$TestDrive` with `$env:LOCALAPPDATA` redirected; `Resolve-Tool agy | Should -Be <that path>`. Also: `Resolve-Tool agy` returns `$null` when nothing is found.

- [ ] **Step 3: Run** `powershell -NoProfile -File tests/Invoke-Tests.ps1`. Expected: FAIL (functions not defined).
- [ ] **Step 4: Implement `scripts/lib/Core.ps1`** with the interfaces above, and `scripts/lib/All.ps1` dot-sourcing every `scripts/lib/*.ps1` except itself, in the order listed in File Structure.
- [ ] **Step 5: Run tests.** Expected: PASS.
- [ ] **Step 6: Commit** `feat: core library and test harness`.

---

### Task 2: GEMINI.md build/split, core rules and profiles

**Files:**
- Create: `scripts/lib/GeminiMd.ps1`, `core/GEMINI.core.md`, `profiles/_template/*`, `profiles/lianharman/*`, `scripts/lib/Profile.ps1`
- Test: `tests/unit/GeminiMd.Tests.ps1`, `tests/unit/Profile.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 text/json IO.
- Produces:
  - `Build-GeminiMd([string]$CoreText, [string]$ProfileText, [string]$ProjectMapTool) -> string`: exactly `<!-- agy-config:core:start -->\n{core}\n<!-- agy-config:core:end -->\n<!-- agy-config:profile:start -->\n{projectMapLine}{profile}\n<!-- agy-config:profile:end -->\n`.
    - `projectMapLine`: `Project map tool: {tool}\n\n` when the tool is not `none`; empty when it is `none`.
  - `Split-GeminiMd([string]$Text) -> @{Core=[string]|$null; Profile=[string]}`: strips the `Project map tool:` line from the profile. Text outside markers is appended to `Profile`. Missing or mangled markers return `Core=$null` and put the whole text in `Profile`.
  - `Get-Profile([string]$RepoRoot, [string]$Name) -> hashtable`: `profile.json` merged with defaults `@{language='en'; sync=@{debounceMinutes=10}; update=@{day='Sunday'}; projectMap=@{tool='graphify'}; ownSkills=@(); ownPlugins=@(); ignored=@()}`. Also adds `GeminiProfileText`, and `Sources`/`Lock` from the profile's `sources.json`/`sources.lock.json`.
  - `New-ProfileFromTemplate([string]$RepoRoot, [string]$Name, [string]$Language, [string]$ProjectMapTool) -> string(path)`: copies `_template`, sets fields, writes the language rule line from `scripts/i18n/<lang or en>.json` key `languageRule`.

- [ ] **Step 1: Write content files**:
  - `core/GEMINI.core.md`: an **English** translation of the current `~/.gemini/GEMINI.md`, with sections Orientation, Working, Boundaries, Pausing, When another agent asks. Leave out the Vietnamese-language rule.
    - Add orientation step 2b, *Project map*: "If `Project map tool` is `graphify`: when `graphify-out/` exists read `graphify-out/GRAPH_REPORT.md` and answer file questions with `graphify query/path/explain`; when it does not, run `/graphify .`, then tell the user. For another tool, invoke that skill the same way."
    - Add one pointer line: "To change how you work, install or remove skills, back up, restore, update, or fix sync: use the `agy-self-config` skill."
  - `profiles/_template/profile.json`: defaults above with `"name": "_template"`. `GEMINI.profile.md`: a `{{LANGUAGE_RULE}}` line. `sources.json`: `[]`. `sources.lock.json`: `{}`. `permissions.json`: `[]`.
  - `profiles/lianharman/profile.json`: `language: "vi"`, `projectMap.tool: "graphify"`. `GEMINI.profile.md`: the Vietnamese language rule paragraph from the current `~/.gemini/GEMINI.md`, verbatim.
- [ ] **Step 2: Write the failing tests**:
  - `Build-GeminiMd places markers in order` (index of core:start < core:end < profile:start < profile:end).
  - `Split-GeminiMd inverts Build-GeminiMd` (core and profile equal to the inputs).
  - `round-trips Vietnamese text` (profile with `[char]0x1EBF` etc., written with `Write-TextFile`, read back, split).
  - `appends text outside markers to profile`.
  - `keeps all text when markers are missing` (`Core | Should -BeNullOrEmpty`, `Profile | Should -Be $original`).
  - `omits project map line for none`.
  - Profile: `Get-Profile applies defaults` (`projectMap.tool` = `graphify` when the key is absent); `New-ProfileFromTemplate writes language rule` (`vi` → file contains the `vi.json` `languageRule` value).
- [ ] **Step 3: Run tests**, expect FAIL. **Step 4: Implement.** Create `scripts/i18n/en.json` and `vi.json` with key `languageRule` (`"Always reply to the user in English."` and the Vietnamese sentence from the current `GEMINI.md`). Prompt keys get added here as later tasks need them. **Step 5: Run tests**, expect PASS. **Step 6: Commit** `feat: GEMINI.md assembly and profiles`.

---

### Task 3: Settings: permissions and MCP

**Files:**
- Create: `scripts/lib/Settings.ps1`, `core/permissions.json` (array of the 8 Global-Constraint strings)
- Test: `tests/unit/Settings.Tests.ps1`

**Interfaces:**
- Produces:
  - `Merge-Permissions([string]$SettingsPath, [string[]]$Allow) -> string[] (added)`: adds missing entries to `permissions.allow`; every other key (`model`, `trustedWorkspaces`, unknown keys) stays byte-identical in value.
  - `Get-MachinePermissions([string]$SettingsPath) -> string[]`.
  - `Remove-Permissions([string]$SettingsPath, [string[]]$Remove)`.
  - `Protect-McpConfig($Config) -> @{Config; Variables=string[]}`: every value under any server's `env` and every `headers` value becomes `${<SERVERNAME>_<KEY>}` (upper-case, non-alphanumerics to `_`). Values already of the form `${...}` are kept.
  - `Expand-McpConfig($Config) -> @{Config; Missing=string[]}`: replaces `${NAME}` from the user environment; unresolved names are listed in `Missing` and left as-is.
- [ ] **Step 1: Failing tests**:
  - `adds missing permissions and keeps other keys` (fixture: the real settings shape `{model, trustedWorkspaces, permissions.allow:[...]}` → after the merge `model`/`trustedWorkspaces` are unchanged).
  - `does not duplicate`.
  - `creates permissions block when absent`.
  - `protects env secrets` (`{mcpServers:{gh:{env:{GITHUB_TOKEN:'ghp_x'}}}}` → value `${GH_GITHUB_TOKEN}`, Variables contains it).
  - `expands from environment and reports missing`.
- [ ] **Step 2–4:** run tests (FAIL), implement, run tests (PASS). **Step 5: Commit** `feat: permissions and MCP settings handling`.

---

### Task 4: State, three-way merge and run lock

**Files:**
- Create: `scripts/lib/State.ps1`
- Test: `tests/unit/State.Tests.ps1`

**Interfaces:**
- Produces:
  - `Get-MachineState() / Set-MachineState($s)`: `StateDir\machine.json`, holding `{profile, role ('owner'|'follower'), repoPath}`.
  - `Get-AppliedState() / Set-AppliedState($s)`: `applied.json`, holding `{sources:{<id>:<version>}, ownSkills:[], ownPlugins:[], permissions:[], mcpServers:[], appliedAt}`.
  - `Get-PendingLock() / Set-PendingLock($lock) / Clear-PendingLock()`: `pending.lock.json`, holding `{createdAt, versions:{<id>:<version>}}`. `Get-PendingLock` returns `$null` and deletes the file when `createdAt` is older than 14 days. The spec leaves stale PRs open; 14 days is this plan's choice.
  - `Merge-ThreeWaySet([string[]]$Repo, [string[]]$Base, [string[]]$Current) -> string[]`: `(Repo ∪ (Current − Base)) − (Base − Current)`, sorted, unique.
  - `Enter-RunLock([string]$Name, [int]$StaleMinutes=30) -> bool / Exit-RunLock([string]$Name)`: lock file `StateDir\<Name>.lock` containing PID and time. Returns `$false` when the lock is held and fresh.
  - `Test-Debounce([string]$Name, [int]$Minutes) -> bool`: `$true` when the last run (`StateDir\<Name>.last`) is older than `$Minutes`; `Register-Run([string]$Name)` stamps it.
- [ ] **Step 1: Failing tests**:
  - `Merge-ThreeWaySet adds what this machine added`: repo `a,b`, base `a`, current `a,c` → `a,b,c`.
  - `removes what this machine removed`: repo `a,b`, base `a,b`, current `b` → `b`.
  - `keeps what another machine added`: repo `a,b,x`, base `a,b`, current `a,b` → `a,b,x`.
  - `second run exits while lock held`.
  - `takes over stale lock` (lock written 31 minutes ago → `Enter-RunLock` returns `$true`).
  - `Test-Debounce is false within window`.
  - `drops pending lock after 14 days`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: state, three-way merge, run lock`.

---

### Task 5: Sources: model and GitHub-based types

**Files:**
- Create: `scripts/lib/Sources.ps1`, `scripts/lib/Source.GitHub.ps1`
- Test: `tests/unit/Sources.Tests.ps1`, `tests/integration/GitHubSources.Tests.ps1` (uses a local bare repo created in `$TestDrive` as the "upstream")

**Interfaces:**
- Source entry shapes in `sources.json`:
  - Common fields: `id`, `type`, `provides` (skill or plugin names, used for classification), optional `when` (`@{projectMap='graphify'}`).
  - `github-skills`: `{repo, skills:[{name, path}]}`.
  - `git-plugin`: `{repo, plugin}`.
  - `packaged-plugin`: `{repo, plugin, displayName, description, paths:[...] }`. When `paths` holds a single folder with its own `skills/`, that folder's `skills/` is used. Otherwise each path is one skill folder.
- Lock shape (`sources.lock.json`): `{ "<id>": "<sha-or-version>" }`.
- Produces:
  - `Get-SourceList([string]$RepoRoot, $ProfileData) -> hashtable[]`: core and profile entries, profile winning on equal `id`. Entries whose `when.projectMap` differs from `$ProfileData.projectMap.tool` are dropped.
  - `Get-EffectiveLock([string]$RepoRoot, $ProfileData, $Pending) -> hashtable`: core lock < profile lock < pending versions.
  - `Install-Source($Source, [string]$Version) -> @{Ok; Error}`, `Uninstall-Source($Source)`, `Get-LatestVersion($Source) -> string`, `Test-Source($Source) -> @{Ok; Error}`. Each dispatches on `type` to `Install-GitHubSkills`/`Install-GitPlugin`/`Install-PackagedPlugin` here, and to the Task 6 functions for the other types.
  - GitHub behaviour:
    - Latest version = `git ls-remote <repo> HEAD`.
    - Fetching = a partial clone cached in `CacheDir\<id>` (`--filter=blob:none --no-checkout`, `sparse-checkout set` paths, `checkout <sha>`).
    - `github-skills` copies each path to `SkillsDir\<name>`, replacing what is there.
    - `git-plugin` clones into `PluginsDir\<plugin>` and checks out the sha. An existing clone is fetched and checked out.
    - `packaged-plugin` builds `StagingDir\<plugin>` with a generated `plugin.json` (`name, displayName, version=<sha short 7>, description, author.name 'Anthropic', license`) plus `skills/`, then runs `agy plugin install <staging>`.
  - `Test-Source`:
    - skills: each `SkillsDir\<name>\SKILL.md` has `name:` and `description:` frontmatter.
    - plugins: `agy plugin validate <PluginsDir\<plugin>>` exits 0.
- [ ] **Step 1: Failing tests**:
  - Unit, with `Mock Invoke-External`:
    - `Get-SourceList drops graphify when projectMap is none`.
    - `profile entry overrides core entry`.
    - `Get-EffectiveLock prefers pending`.
    - `packaged-plugin writes plugin.json with short sha version`.
  - Integration, against a real local bare repo with commits A and B:
    - `installs github skill at locked sha` (file content equals the A version).
    - `upgrades to latest`.
    - `git-plugin checks out locked sha in an existing clone`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: source model and GitHub source types`.

---

### Task 6: Sources: pip-tool and marketplace

**Files:**
- Create: `scripts/lib/Source.Other.ps1`
- Test: `tests/unit/SourceOther.Tests.ps1`

**Interfaces:**
- Shapes:
  - `pip-tool`: `{package, postInstall:[args...], provides}`. Example graphify: `package 'graphifyy'`, `postInstall @('install','--platform','antigravity-windows')`, `provides @('graphify')`, `when @{projectMap='graphify'}`.
  - `marketplace`: `{plugin, marketplace}`.
- Produces:
  - `Install-PipTool`: needs `Resolve-Tool python` with version ≥ 3.10; otherwise returns `@{Ok=$false; Error='python-missing'}` without throwing. Then runs `python -m pip install --user <package>==<version> -q`. Then runs the post-install with the user-scripts `graphify.exe`; the folder comes from `python -c "import sysconfig;print(sysconfig.get_path('scripts','nt_user'))"`.
  - `Get-PipLatestVersion`: `Invoke-Http https://pypi.org/pypi/<package>/json` → `.info.version`.
  - `Install-Marketplace`: `agy plugin install <plugin>@<marketplace>`. Before installing, copy the existing plugin folder into `SnapshotDir\<plugin>`.
  - `Get-MarketplaceVersion` reads `agy plugin list --json`.
  - `Restore-MarketplaceSnapshot($Source)` copies the snapshot back.
- [ ] **Step 1: Failing tests** (mocks only):
  - `pip-tool reports python-missing`.
  - `pip-tool rejects python 3.9`.
  - `pip-tool installs pinned version then runs postInstall` (assert the `Invoke-External` call order and args).
  - `marketplace snapshots before install`.
  - `marketplace version read from plugin list json` (fixture: the real `agy plugin list --json` shape `[{name,enabled,version,source,path,skills}]`).
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: pip-tool and marketplace sources`.

---

### Task 7: Inventory, classification, secret scan, and seeding core sources

**Files:**
- Create: `scripts/lib/Inventory.ps1`, `scripts/lib/SecretScan.ps1`, `core/sources.json`, `core/sources.lock.json`, `THIRD_PARTY.md`
- Test: `tests/unit/Inventory.Tests.ps1`, `tests/unit/SecretScan.Tests.ps1`

**Interfaces:**
- Produces:
  - `Get-MachineInventory() -> @{Skills=string[]; Plugins=hashtable[]; SkillLock=hashtable}`: skill folder names in `SkillsDir`, `agy plugin list --json`, `~/.agents/.skill-lock.json`.
  - `ConvertFrom-SkillLock($SkillLock, [string[]]$OnlySources) -> hashtable[]`: groups entries by `source` into `github-skills` entries.
    - `id`: `source` with `/` → `-`.
    - `repo`: `sourceUrl` without `.git`.
    - skills: `name` + dir of `skillPath`.
    - `provides`: the skill names.
  - `Get-Classification($Inventory, [hashtable[]]$Sources, $ProfileData, [string[]]$RepoOwnedPlugins) -> @{Sourced=string[]; Own=string[]; Ignored=string[]; Unknown=string[]}`. Follows the §4 rule. `RepoOwnedPlugins` = `@('agy-self-config')`, which counts as sourced.
  - `Find-Secrets([string[]]$Paths) -> @{Path; Line; Rule}[]`.
    - Rules: `ghp_[A-Za-z0-9]{20,}`, `github_pat_[A-Za-z0-9_]{20,}`, `sk-[A-Za-z0-9]{20,}`, `AIza[0-9A-Za-z_\-]{30,}`, `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `(?i)password\s*[=:]\s*\S+`, the email regex, and `(?i)[A-Z]:\\Users\\[^\\\s"]+`.
    - Allowed: `${NAME}` placeholders, and emails listed in `tests/fixtures/allowed-emails.txt` (empty to start).
- [ ] **Step 1: Failing tests**:
  - `ConvertFrom-SkillLock groups mattpocock skills` (fixture: three real-shaped entries).
  - `classifies graphify as sourced via provides`.
  - `classifies unlisted skill as unknown`.
  - `own skill listed in profile is own`.
  - `Find-Secrets flags ghp token and user path`.
  - `Find-Secrets allows placeholders`.
- [ ] **Steps 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Seed `core/sources.json`** from this machine:
  - `ConvertFrom-SkillLock` over the real lock for `mattpocock/skills` (38 skills) and `vercel-labs/skills` (find-skills).
  - Plus `superpowers` (git-plugin `https://github.com/obra/superpowers`).
  - `engineering` and `design` (packaged-plugin `https://github.com/anthropics/knowledge-work-plugins`, paths `engineering` / `design`).
  - `anthropic-dev-skills` (packaged-plugin `https://github.com/anthropics/skills`, paths `skills/mcp-builder`, `skills/pdf`, `skills/docx`, `skills/xlsx`, `skills/pptx`).
  - `graphify` (pip-tool, as in Task 6).
  - The three marketplace plugins `chrome-devtools-plugin`, `gemini-api`, `modern-web-guidance-plugin` @ `antigravity-plugins-official`.

  Then write `core/sources.lock.json` with `Get-LatestVersion` for each (graphify: the installed `0.9.100`; marketplace: the installed versions from `agy plugin list --json`).
- [ ] **Step 6: Write `THIRD_PARTY.md`**: one row per source with repo URL and license (MIT superpowers, MIT mattpocock/skills, MIT vercel-labs/skills, Apache-2.0 knowledge-work-plugins, Apache-2.0 anthropics/skills, Apache-2.0/MIT graphifyy, marketplace plugins "see marketplace listing"). Verify vercel-labs/skills' license through the GitHub API before writing it.
- [ ] **Step 7: Commit** `feat: inventory, classification, secret scan; seed core sources`.

---

### Task 8: `apply.ps1` (repo → machine)

**Files:**
- Create: `scripts/lib/Repo.ps1`, `scripts/apply.ps1`
- Test: `tests/integration/Apply.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces:
  - `Repo.ps1`:
    - `Update-ConfigRepo([string]$RepoRoot) -> @{Ok; Error}`: `git pull --rebase --autostash`; on failure, `git rebase --abort` and `Ok=$false`.
    - `Test-PushAccess([string]$RepoRoot) -> bool`: `git push --dry-run origin HEAD:refs/heads/agy-config-probe`, exit 0 means `$true`.
    - `Invoke-RepoGit([string]$RepoRoot, [string[]]$Args)`.
  - `apply.ps1 [-RepoRoot <path>] [-SkipPull] [-Quiet]` → exit 0 on success, 1 on any failed source. Steps follow §6.2:
    0. Capture (call `sync.ps1 -CaptureOnly`; owner: `sync.ps1` in full).
    1. Pull.
    2. Sources by `Get-EffectiveLock`: install where `applied.sources[id]` differs from the target; uninstall ids in applied but no longer listed.
    3. Install `core/plugins/agy-self-config` and the profile's own plugins and skills.
    4. Write `GEMINI.md`.
    5. `Merge-Permissions` (core + profile `permissions.json`).
    6. MCP: merge servers from the profile `mcp.json`, expand variables.
    7. Validate.
    8. `Set-AppliedState` only when every source succeeded. Otherwise keep the previous applied state, log the failures and exit 1.
  - Owner: when the effective lock equals the repo lock for every pending id, call `Clear-PendingLock`.
- [ ] **Step 1: Failing tests** (fake home in `$TestDrive`, repo fixture copied from the working tree, `Mock Install-Source/Uninstall-Source/Invoke-External`):
  - `installs only changed sources`.
  - `uninstalls source removed from repo but only if previously applied`.
  - `writes GEMINI.md with profile language rule`.
  - `keeps trustedWorkspaces`.
  - `leaves state untouched when a source fails` (one `Install-Source` returns `Ok=$false` → `applied.json` unchanged, exit code 1, a log line containing the source id).
  - `pending versions win on owner`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: apply script`.

---

### Task 9: `sync.ps1` (machine → repo)

**Files:**
- Create: `scripts/sync.ps1`
- Test: `tests/integration/Sync.Tests.ps1` (real git: a bare "origin" in `$TestDrive`, two clones standing for two machines)

**Interfaces:**
- `sync.ps1 [-RepoRoot] [-CaptureOnly] [-Force]`. Steps follow §6.3:
  - Run lock `sync`; debounce from `profile.sync.debounceMinutes`, skipped when `-Force`.
  - Capture, with `Merge-ThreeWaySet` for permissions, profile sources (new `ConvertFrom-SkillLock` entries not in any `sources.json`, pinned to `git ls-remote` HEAD), own skills/plugins (copied into `profiles/<p>/skills|plugins`), marketplace plugins and MCP servers (`Protect-McpConfig`, written to `profiles/<p>/mcp.json`).
  - GEMINI regions via `Split-GeminiMd` (core region only when role is owner).
  - Unknown items go to `StateDir\unknown.json`.
  - `-CaptureOnly` stops here.
  - Follower also stops here (never commits).
  - `Find-Secrets` on `git diff --name-only` plus untracked files: any finding → log ERROR, `git checkout -- .`/`git clean` the captured changes, exit 2.
  - No changes → exit 0.
  - Commit `sync(<profile>): <yyyy-MM-dd HH:mm>`, `Update-ConfigRepo`, `git push origin main`. If the rebase fails: `git rebase --abort`, `git push origin HEAD:sync/<profile>-<stamp>`, log WARN, exit 3.
- [ ] **Step 1: Failing tests**:
  - `pushes a new permission from machine A`.
  - `machine B with stale base does not remove A's permission` (three-way).
  - `never commits trustedWorkspaces or model`.
  - `aborts and discards when a secret is captured` (MCP value `ghp_...` placed raw into a profile file → exit 2, origin unchanged).
  - `follower captures but does not commit`.
  - `second run exits while lock held` and `takes over stale lock` (via `Enter-RunLock` from Task 4, exercised here end to end).
  - `conflict goes to sync branch`.
  - `unknown skill reported not pushed`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: sync script`.

---

### Task 10: `update.ps1` (weekly, owner only)

**Files:**
- Create: `scripts/update.ps1`
- Test: `tests/integration/Update.Tests.ps1`

**Interfaces:**
- `update.ps1 [-RepoRoot] [-NoPush]`:
  - Exits 0 with an INFO log when the role is not owner.
  - For each source: `Get-LatestVersion`; if it differs from the effective lock, `Install-Source` then `Test-Source`. On failure, reinstall the locked version (marketplace: `Restore-MarketplaceSnapshot`) and record it as "rolled back".
  - `Set-PendingLock` with the new versions.
  - Create or reset local branch `update/sources` from `origin/main`. Write the new versions into `core/sources.lock.json` and the profile lock. Commit with title `chore(sources): weekly update <yyyy-MM-dd>` and a Markdown body table `| source | old | new | result |`. Then `git push --force-with-lease origin update/sources`.
  - Log `https://github.com/<owner>/<repo>/compare/main...update/sources?expand=1` (built from the `origin` URL).
- [ ] **Step 1: Failing tests** (mocks for `Install-Source`/`Get-LatestVersion`, real git against a bare origin):
  - `follower exits without changes`.
  - `rolls back failing source and keeps others`.
  - `writes pending lock`.
  - `pushes update/sources with summary table in commit body`.
  - `logs compare url`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: weekly update script`.

---

### Task 11: `agy-self-config` plugin (hook + skill)

**Files:**
- Create: `core/plugins/agy-self-config/plugin.json` (`name agy-self-config`, `version 1.0.0`, `license MIT`)
- Create: `hooks.json`, `hooks/on-stop.ps1`
- Create: `skills/agy-self-config/SKILL.md`, `references/{files-and-scripts.md,troubleshooting.md,contributing.md}`
- Test: `tests/unit/OnStop.Tests.ps1`

**Interfaces:**
- `hooks.json`: `{"Stop":[{"type":"command","command":"powershell -NoProfile -ExecutionPolicy Bypass -File ./hooks/on-stop.ps1","timeout":10}]}`.
- `on-stop.ps1`:
  - Reads and ignores stdin.
  - If `machine.json` role is `owner` and the repo path exists, starts `powershell -NoProfile -WindowStyle Hidden -File <repo>\scripts\sync.ps1` with `Start-Process` (detached).
  - Always writes `{}` to stdout and exits 0, even on error (errors go to the log).
- `SKILL.md`, written with the `writing-for-agents` skill:
  - Frontmatter `description` front-loads the branches: change how you work; install, remove or find skills/plugins; back up; restore or move to a new machine; update; sync or update failed; contribute upstream.
  - Body steps cover:
    - Edit the right file: profile vs core (owner only) vs `sources.json`.
    - Run `scripts/apply.ps1` or `sync.ps1 -Force`, then confirm with the log.
    - Resolve `unknown.json` with the user.
    - Merge a `sync/*` branch.
    - Find skills with `npx skills find`.
    - Open a PR from a fork for followers.
  - Each step ends with a checkable criterion.
- [ ] **Step 1: Failing tests**:
  - `on-stop prints {} and exits 0 when state missing`.
  - `on-stop starts sync for owner` (`Mock Start-Process`, assert `-FilePath powershell` and an argument containing `sync.ps1`).
  - `on-stop does nothing for follower`.
- [ ] **Steps 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Validate the plugin**: `agy plugin validate core/plugins/agy-self-config`. Expected: `✔ Validation passed`.
- [ ] **Step 6: Commit** `feat: agy-self-config plugin`.

---

### Task 12: Scheduler, `install.ps1`, `uninstall.ps1`

**Files:**
- Create: `scripts/lib/Scheduler.ps1`, `scripts/install.ps1`, `scripts/uninstall.ps1`; extend `scripts/i18n/*.json` with prompt keys
- Test: `tests/unit/Scheduler.Tests.ps1`, `tests/integration/Install.Tests.ps1`

**Interfaces:**
- `Register-AgyTasks([string]$RepoRoot, [ValidateSet('owner','follower')]$Role)`: uses `Register-ScheduledTask` for the current user, with `-RunLevel Limited` and actions `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File <script>`.
  - Task names and triggers come from Global Constraints.
  - Followers get only `agy-config-apply`.
  - Re-registering replaces the tasks.
- `Unregister-AgyTasks()`.
- `install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-Yes] [-RepoPath <path>]`:
  - If not running from inside a clone, `git clone` the repo to `DefaultRepo` and re-invoke from there. The `irm | iex` path carries the repo URL as a constant.
  - Prerequisites: `git` and `agy` are required. `node` and `python` produce warnings only.
  - Choose or create the profile, asking language and project map with i18n prompts. The prompt language defaults to `en` and becomes `vi` when `(Get-Culture).Name` starts with `vi`.
  - Back up `GEMINI.md`, `settings.json`, `config\skills`, `config\plugins` and `mcp_config.json` to `BackupRoot\<stamp>`.
  - `Test-PushAccess` decides the role; `Set-MachineState`.
  - Show the plan of actions and ask to confirm unless `-Yes`.
  - Run `apply.ps1`, then `Register-AgyTasks`. Print a summary: installed counts, role, tasks, backup path, uninstall command.
  - Safe to re-run.
- `uninstall.ps1 [-RestoreBackup <stamp>]`: `Unregister-AgyTasks`, `agy plugin uninstall agy-self-config`, and optionally copies a backup back. Third-party skills are left in place.
- [ ] **Step 1: Failing tests**:
  - `follower registers only apply task` (`Mock Register-ScheduledTask`).
  - `owner registers three tasks with expected names`.
  - `install backs up before apply` (`Mock` `apply.ps1` invocation, assert the backup folder exists first).
  - `install picks vi prompts for vi culture`.
  - `install is idempotent` (second run: no new profile, tasks re-registered).
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `feat: installer, scheduler, uninstaller`.

---

### Task 13: CI and contribution plumbing

**Files:**
- Create: `tests/Validate-Repo.ps1`, `.github/workflows/validate.yml`, `.github/workflows/update-pr.yml`, `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md`
- Test: `tests/unit/ValidateRepo.Tests.ps1`

**Interfaces:**
- `Validate-Repo.ps1 [-Root]` → exit 1 with one line per problem. Checks:
  - every `*.json` parses;
  - every `SKILL.md` has `name` + `description`;
  - every `plugin.json` has `name` + `version`;
  - `Find-Secrets` over tracked files finds nothing;
  - no file over 1 MB;
  - every `core/sources.json` and `profiles/*/sources.json` repo URL appears in `THIRD_PARTY.md`;
  - every `.ps1` is ASCII.
- `validate.yml`:
  - Triggers: `on: pull_request`, and `push` to `main` and `update/**`.
  - Job `test` on `windows-latest` with `shell: powershell`: `tests/Validate-Repo.ps1`, `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`, `Invoke-ScriptAnalyzer -Path scripts -Recurse -Severity Error` (fail on any result), `tests/Invoke-Tests.ps1`.
  - Job `secrets` on `ubuntu-latest`: `gitleaks/gitleaks-action@v2` with `fetch-depth: 0`.
- `update-pr.yml`:
  - Trigger `on: push: branches: [update/sources]`; permissions `contents: read`, `pull-requests: write`.
  - Step with `GH_TOKEN: ${{ github.token }}`: `gh pr list --head update/sources --state open --json number`.
    - None open → `gh pr create --base main --head update/sources --title "Weekly source updates / Cập nhật nguồn tuần này" --body "$(git log -1 --format=%b)"`.
    - One open → `gh pr edit <n> --body ...`.
  - On failure, append the compare link to `$GITHUB_STEP_SUMMARY` and exit 0.
- `CODEOWNERS`: `* @DanGuangLT`, plus explicit lines for `/scripts/`, `/core/plugins/`, `/core/sources*.json`, `/.github/`.
- PR template: checklist covering what changed, `tests/Invoke-Tests.ps1` passes, no secrets or personal paths, new source added to `THIRD_PARTY.md`.
- [ ] **Step 1: Failing tests**:
  - `flags invalid json`.
  - `flags SKILL.md without description`.
  - `flags source missing from THIRD_PARTY`.
  - `flags non-ASCII ps1`.
  - `passes on the real repo` (runs against the working tree).
- [ ] **Steps 2–4:** FAIL → implement → PASS. **Step 5: Commit** `ci: validation and weekly update PR workflows`.

---

### Task 14: Documentation

**Files:**
- Create: `README.md`, `README.vi.md`, `CONTRIBUTING.md`, `CONTRIBUTING.vi.md`, `SECURITY.md`

**Content requirements** (both languages say the same thing; each README links to the other in its first line):

- README sections:
  1. What this is, in 3 lines.
  2. **"Just installed agy? Start here"**: check `agy --version`; install git (`winget install Git.Git`); optionally Python for graphify.
  3. Install: fork-and-clone (recommended, gives you your own backup), plain clone (follower), or the `irm … | iex` one-liner with a "read it first" note.
  4. What gets installed: a table generated by hand from `core/sources.json` with links.
  5. Daily use: talk to agy ("from now on…", "install skill X", "I'm moving to a new machine"), and it uses `agy-self-config`.
  6. Moving to a new machine.
  7. One-time repo settings for owners and fork owners: Actions → "Allow GitHub Actions to create and approve pull requests"; branch protection on `main` with PR + 1 review + checks, and the owner allowed to bypass.
  8. Uninstall.
  9. Troubleshooting: logs in `~/.agy-config-state/logs`, `unknown.json`.
  10. License and `THIRD_PARTY.md`.
- `CONTRIBUTING`:
  - How to add a skill source: edit `sources.json`, run `update.ps1 -NoPush` locally or let CI check, add a `THIRD_PARTY.md` row.
  - Rules: no vendored third-party content, ASCII `.ps1`, tests required, PR template.
  - CODEOWNERS review for scripts and hooks.
- `SECURITY.md`: report privately through GitHub Security Advisories. List what the scripts execute and when.

- [ ] **Step 1:** Write all five files.
- [ ] **Step 2:** `powershell -File tests/Validate-Repo.ps1`. Expected: exit 0.
- [ ] **Step 3:** Commit `docs: README (en/vi), contributing, security`.

---

### Task 15: Owner rollout on this machine

**Files:** none new. Uses the real machine.

- [ ] **Step 1:** Run the full test suite: `powershell -NoProfile -File tests/Invoke-Tests.ps1`. Expected: all PASS.
- [ ] **Step 2:** Get explicit user confirmation, then run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -ProfileName lianharman`. Expected summary:
  - role `owner`;
  - 3 scheduled tasks;
  - backup path printed;
  - `agy plugin list` shows `agy-self-config`, `engineering`, `design`, `anthropic-dev-skills`, `superpowers` and the 3 marketplace plugins;
  - `~/.gemini/GEMINI.md` contains both marker pairs and the Vietnamese rule.
- [ ] **Step 3:** Orientation check: from `D:\Coding\LienThuan04`, run `agy --print "Mình vừa mở dự án này cho bạn. Bạn làm gì đầu tiên?" --mode plan`. Expected: a Vietnamese summary that mentions the project map step.
- [ ] **Step 4:** With user confirmation, remove `~/.gemini/local-plugins` (made by hand on 2026-11-11, now replaced by packaged sources).
- [ ] **Step 5:** With user confirmation, run `git push origin main`, then trigger a manual sync: `scripts/sync.ps1 -Force`. Expected: exit 0 and the GitHub Actions `validate` run green.
- [ ] **Step 6:** Hand the user the README section 7 settings to switch on in the GitHub web UI. Confirm after they do it.
