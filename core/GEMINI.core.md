# How to work

## Joining a project: orient first

Do all of these steps, in order, before changing anything. Browse folders and find and read files with your built-in file tools; keep the terminal for the git commands in step 2 and for build/test commands.

1. Read the project's own instructions if present: `AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, then `README`.
2. Check git state with exactly these commands (they are pre-approved): `git status`, `git branch --show-current`, `git log --oneline -15`.
3. Project map, using the `Project map tool` named in your profile section below:
   - `graphify`: when `graphify-out/` exists, read `graphify-out/GRAPH_REPORT.md` and answer questions about files and structure with `graphify query`, `graphify path` and `graphify explain` instead of opening many files. When it does not exist, run `/graphify .` to build it, then tell the user.
   - Any other tool: invoke that skill the same way.
   - `none` or no tool named: skip this step.
4. Find unfinished work: plans and specs in `docs/superpowers/plans/` and `docs/superpowers/specs/` (tasks still `- [ ]`), an "In progress" section at the end of a plan, a `TODO` or `HANDOFF` file.
5. Find the build, test and run commands in the manifest (`package.json`, `pyproject.toml`, `*.csproj`, ...).

Orientation is done when you can state in 3-5 lines: what the project is, where work stopped, what the test command is, and 1-3 next steps. Send that summary to the user with the step you recommend first, then wait for their choice.

## While working

- Start every request with the `using-superpowers` skill to pick the process: `brainstorming` before building something new, `writing-plans` for multi-step work, `systematic-debugging` for bugs, `test-driven-development` when writing code, `verification-before-completion` before saying you are done.
- Keep changes inside the scope of the request and in the project's existing style.
- Report results with evidence: the command you ran and its real output. Say plainly which tests failed or which steps you skipped.
- To change how you work, install or remove skills, back up, restore, move to a new machine, update, or fix sync: use the `agy-self-config` skill.

## Boundaries

- Commit, push, deploy, delete files or branches, and change other repositories or services only when the user asks for it explicitly in the current conversation. Each such action needs its own approval.
- Keep tokens, passwords and personal email addresses out of commits, logs and anything sent outside this machine.

## Pausing mid-task

Tick the finished tasks in the plan file, then add an "In progress" section at the end of the plan: how far you got, the next step, and which test command is failing. The next agent (agy or another coding agent) reads it during orientation.

## When another agent asks for advice

When you are called with `agy --print` for advice (for example by another coding agent): read files, answer in text in the language of the question, and leave every file unchanged. Be brief and specific, and end with your strongest recommendation.
