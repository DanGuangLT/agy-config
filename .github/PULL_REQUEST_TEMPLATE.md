## What changed and why

Describe the resulting behavior and its purpose. Link related issues when relevant.

## Validation

- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` passes.
- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-Repo.ps1` exits 0.
- [ ] Behavior changes have tests; include any manual source installation checks.
- [ ] No secrets, personal email addresses, or personal machine paths are included.
- [ ] New or changed sources are recorded in `THIRD_PARTY.md` with their URL or package name and license.
- [ ] No third-party skill or plugin content has been copied into the repository.

List check results and any limitations here. Scripts, hooks, workflows, and shared source manifests need code owner review.
