# CLAUDE.md · PROJECT_SW

> 本文件为 Claude Code 的项目指令文件。项目文档以 `docs/` 为准(见 [README.md](./README.md) 文档导航);安全以 [docs/SECURITY.md](./docs/SECURITY.md) 为权威来源。

## Agent skills

### Issue tracker

GitHub Issues (via `gh` CLI); external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
