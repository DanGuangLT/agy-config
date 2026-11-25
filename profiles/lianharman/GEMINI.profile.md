## Language

Reply in the same language the user writes in; if a message mixes languages, use the main one. Keep file names, commands and technical terms as they are, with a short explanation when needed. Code, comments, commit messages and pull requests are written in English.

<!-- custom:engineering-skills:start -->
## Software Engineering Skills & Weekly Auto-Update

### 1. Mandatory Matt Pocock Skills (`https://github.com/mattpocock/skills`)
- **Scope:** Whenever working inside a Git repository with a configured remote (`git remote -v` is non-empty), always apply the applicable engineering skills from `mattpocock/skills` (alongside `using-superpowers`) to build, architect, refactor, and test projects to senior software-engineering standards.
- **Case 1 — Not installed yet:** Check the local Antigravity skills directory (`%USERPROFILE%\.gemini\antigravity\skills` on Windows or `$HOME/.gemini/antigravity/skills` on Unix). If `mattpocock/skills` is not installed yet, automatically install the latest version using:
  `npx skills@latest add mattpocock/skills -a antigravity`
  Then immediately run the `agy-self-config` backup sync if configured.

### 2. Weekly Skill Version Check & Update (Every New Week)
- Track the last checked ISO week (e.g., `2026-W48`) in `%USERPROFILE%\.agy-config-state\skill-update-state.json` (Windows) or `$HOME/.agy-config-state/skill-update-state.json` (Unix) so update checks run **at most once per calendar week**, not on every prompt.
- **Case 2 — Already installed (on the first session of a new week):**
  1. **CLI-managed skills (including `mattpocock/skills`):** Run `npx skills@latest check` (or `npx skills@latest update` if newer versions are available) to pull the latest skill updates automatically.
  2. **App-installed / Git-backed skills (such as `obra/superpowers` installed directly via Antigravity App):**
     - Inspect their local install path inside `%USERPROFILE%\.gemini\antigravity\` (or `.gemini\config\plugins\`).
     - If backed by Git, compare local HEAD against remote HEAD (`git fetch --quiet` + `git status -uno`) and fast-forward pull (`git pull --ff-only`) if updates exist.
     - If managed purely by the Antigravity App UI without a CLI/Git updater, notify the user briefly that a weekly check is due in the Antigravity App Skills/Marketplace panel.
  3. Update the `lastCheckedWeek` value in `skill-update-state.json`. If any skill was installed or updated, immediately run the `agy-self-config` backup sync (`sync.ps1 -Force`) and briefly summarize what was updated.
<!-- custom:engineering-skills:end -->
<!-- custom:dual-memory:start -->
## Persistent Memory Protocol (Mem0 + Supermemory)

You have two active cloud memory MCP servers: `mem0` and `supermemory`. Always use BOTH silently in the background across every session without waiting for the user to ask.

### 1. Automatic Retrieval (Orientation & Before Acting)
- **During project orientation** (alongside step 1 of `Joining a project: orient first`) and **before answering** questions about user preferences, environment setup, past bugs, or architectural decisions:
  1. Query `mem0` for atomic facts, personal coding conventions, preferred CLI/tooling, and past quick fixes.
  2. Query `supermemory` for deep project architecture, technical specs, implementation history, and cross-session handoff context.
- Merge retrieved context silently into your understanding before producing your orientation summary, plan, or code.

### 2. Automatic Storage (While Working & Pausing Mid-Task)
- Whenever you learn a user preference, establish a repo convention, resolve a non-trivial bug, or complete a feature:
  - **Save to `mem0`:** Atomic rules, coding style, command/environment habits, and root-cause bug fixes.
  - **Save to `supermemory`:** Architectural decisions, module relationships, API/DB schemas, and session summaries.
  - **Save to BOTH:** Critical evergreen rules or project-wide constraints so neither store drifts out of sync.
- **When pausing mid-task:** In addition to updating the plan file, persist the handoff state (progress, next step, failing test command) to `supermemory` and key blockers/facts to `mem0`.

### 3. Execution & Boundary Rules
- **Silent operation:** Never clutter responses with "Searching Mem0/Supermemory..." or "Saved to memory" notices unless the user explicitly asks about memory state.
- **Conflict resolution:** If `mem0` and `supermemory` disagree, prefer the newer record; if ambiguous, ask once and update both.
- **Strict privacy boundary:** Both `mem0` and `supermemory` transmit data outside this machine. Strictly obey the `Boundaries` rule above: NEVER store API keys, tokens, passwords, `.env` secrets, or personal email addresses in either memory server.
<!-- custom:dual-memory:end -->
