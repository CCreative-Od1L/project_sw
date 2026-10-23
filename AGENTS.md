# AGENTS.md · PROJECT_SW

> 本文件为 Codex 的项目指令文件。项目文档以 `docs/` 为准(见 [README.md](./README.md) 文档导航);安全以 [docs/SECURITY.md](./docs/SECURITY.md) 为权威来源。

## Agent skills

### Git branches

Active task branches must share the common code baseline and remain independent: do not base one task on another unmerged task branch or mix their changes. Use a separate worktree per task. See `docs/GIT_WORKFLOW.md` for the branch rules and `docs/BRANCH_ORGANIZATION.md` for the current baseline, worktrees, and archive refs.

### Issue tracker

GitHub Issues (via `gh` CLI); external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
