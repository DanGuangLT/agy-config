# Third-party sources

This repository does not copy third-party skills. `core/sources.json` records where each one comes from, and `core/sources.lock.json` records the version installed. The scripts download them from the original location at install time. Each one keeps its own license.

| Source id | Where it comes from | License |
|---|---|---|
| `mattpocock-skills` | https://github.com/mattpocock/skills | MIT |
| `vercel-labs-skills` | https://github.com/vercel-labs/skills | MIT |
| `superpowers` | https://github.com/obra/superpowers | MIT |
| `engineering`, `design` | https://github.com/anthropics/knowledge-work-plugins | Apache-2.0 |
| `anthropic-dev-skills` | https://github.com/anthropics/skills (folders `skills/mcp-builder`, `skills/pdf`, `skills/docx`, `skills/xlsx`, `skills/pptx`) | Apache-2.0 (a `LICENSE.txt` in each skill folder; the repository README says the document skills are Apache-2.0 as well) |
| `graphify` | https://pypi.org/project/graphifyy/ | Apache-2.0 |
| `chrome-devtools-plugin`, `gemini-api`, `modern-web-guidance-plugin` | agy marketplace `antigravity-plugins-official` | See each marketplace listing |

When `engineering`, `design` and `anthropic-dev-skills` are installed, they are repackaged as agy plugins. The upstream `LICENSE` file is copied into each plugin when the upstream repository has one at its root.

Adding a source? Add a row here in the same pull request. CI checks that every repository in `sources.json` is listed.
