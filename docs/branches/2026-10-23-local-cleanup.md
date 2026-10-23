# 本地归档分支清理与恢复记录

> 执行完成时间（UTC）：`2026-10-23T13:38:23.109032+00:00`。本地分支由 **41** 个减为 **5** 个，已删除 **36** 个已交付归档分支。

范围为 #65–#98 的 34 个旧 PR 归档，以及 `archive/pre-independent-20261022/master`、`archive/landed-20261022/v1-common-baseline` 两个旧基线归档。旧迁移候选仍保留，供 #64 移植使用。

完整 SHA、恢复源引用及核验结果见 [执行数据](2026-10-23-local-cleanup-results.json)。原始引用与提交覆盖分别见 [原始清单](2026-10-22-original-refs.json) 和 [共同基线交付记录](2026-10-22-baseline-convergence.json)。

## 核验与执行

- 删除前逐一核对当前 SHA、归档范围、主干等价提交和 worktree 占用；所有候选均符合原清理范围。
- 备份文件通过 SHA-256 与 `git bundle verify` 校验；另克隆到独立 bare 仓库，完成 `git fsck --no-reflogs --connectivity-only`，逐一核对全部待删分支的恢复源引用及 commit 对象。
- 使用 `git update-ref --stdin` 单次事务，为 36 个删除指定预期旧 SHA，并对 5 个保留分支指定 SHA 校验；事务 prepare/commit 均成功。
- 同时清理两个已删分支的 `vscode-merge-base` 配置，原值均为 `origin/master`；具体键名记录在执行数据中。
- 删除后 11 项检查全部通过：候选全部消失，保留分支及独立任务基线、worktree、原有未提交文件、远端跟踪引用、标签及备份均保持完整。原有未提交文件的比较在本次文档更新前完成。
- 本次未访问或修改远端、未创建提交；应用代码没有变化。验证针对 Git 引用、备份恢复与文档数据，未重复运行 Flutter 功能测试。

## 保留的 5 个本地分支

| 分支 | head | 用途 |
|------|------|------|
| `archive/pre-independent-20261022/feat/v1-lan-migration-ui` | `b2c9a79` | 旧 PR #64 移植来源 |
| `docs/v1-progress-and-validation` | `53cf9b0` | 独立文档任务，保留未提交更新 |
| `feat/v1-lan-migration-integration` | `cf15300` | 独立迁移整合任务 |
| `fix/v1-wipe-restart-recovery` | `cf15300` | 独立擦除修复任务 |
| `master` | `cf15300` | 共同代码基线 |

## 已删除的 36 个本地归档分支

| 分支 | 删除前 head | 等价主干提交 | 来源 |
|------|-------------|--------------|------|
| `archive/pre-independent-20261022/chore/v1-ci-quality-gate` | `d3a5139` | `571e6f3` | 旧 PR #65 |
| `archive/pre-independent-20261022/chore/v1-platform-builds` | `b5ad7b4` | `325b1c6` | 旧 PR #66 |
| `archive/pre-independent-20261022/chore/v1-dependency-audit` | `c281b63` | `bf36657` | 旧 PR #67 |
| `archive/pre-independent-20261022/chore/v1-android-integration-ci` | `7f78db4` | `26a6266` | 旧 PR #68 |
| `archive/pre-independent-20261022/feat/v1-master-password-change-core` | `64274d7` | `a28ac28` | 旧 PR #69 |
| `archive/pre-independent-20261022/feat/v1-master-password-change-ui` | `57aeabe` | `eb9f04a` | 旧 PR #70 |
| `archive/pre-independent-20261022/feat/v1-recovery-gate` | `5bc89a5` | `328e528` | 旧 PR #71 |
| `archive/pre-independent-20261022/feat/v1-biometric-recovery-core` | `224dade` | `8511203` | 旧 PR #72 |
| `archive/pre-independent-20261022/feat/v1-biometric-recovery-ui` | `c8ea753` | `4456f3b` | 旧 PR #73 |
| `archive/pre-independent-20261022/feat/v1-recovery-resume-window` | `244156e` | `c789e52` | 旧 PR #74 |
| `archive/pre-independent-20261022/feat/v1-deadlock-wipe-core` | `3dbaa70` | `c33a9f5` | 旧 PR #75 |
| `archive/pre-independent-20261022/feat/v1-deadlock-wipe-ui` | `d34147c` | `ce784b8` | 旧 PR #76 |
| `archive/pre-independent-20261022/feat/v1-authenticated-wipe-ui` | `133b47d` | `0bbdb38` | 旧 PR #77 |
| `archive/pre-independent-20261022/feat/v1-session-transition-guards` | `869333c` | `726eb36` | 旧 PR #78 |
| `archive/pre-independent-20261022/feat/v1-session-activity-state` | `b7311a1` | `584e4ce` | 旧 PR #79 |
| `archive/pre-independent-20261022/fix/v1-step-up-challenge-lifecycle` | `3950e34` | `4b538fe` | 旧 PR #80 |
| `archive/pre-independent-20261022/fix/v1-password-change-activity-guard` | `dbb5074` | `97da485` | 旧 PR #81 |
| `archive/pre-independent-20261022/fix/v1-biometric-configuration-guard` | `8111feb` | `e203cc1` | 旧 PR #82 |
| `archive/pre-independent-20261022/fix/v1-clipboard-lock-cleanup` | `7b68321` | `597489d` | 旧 PR #83 |
| `archive/pre-independent-20261022/fix/v1-dialog-secret-cleanup` | `c401baf` | `13b17c2` | 旧 PR #84 |
| `archive/pre-independent-20261022/fix/v1-authenticated-wipe-guard` | `9991757` | `f58083f` | 旧 PR #85 |
| `archive/pre-independent-20261022/fix/v1-vault-crud-activity-guard` | `a0c9f7a` | `7645992` | 旧 PR #86 |
| `archive/pre-independent-20261022/fix/v1-session-state-contract` | `42fc892` | `b4a9b23` | 旧 PR #87 |
| `archive/pre-independent-20261022/test/v1-cross-entry-sensitive-cleanup` | `551e309` | `a2c9e63` | 旧 PR #88 |
| `archive/pre-independent-20261022/test/v1-background-lock-cleanup` | `ab04786` | `7d07333` | 旧 PR #89 |
| `archive/pre-independent-20261022/fix/v1-unlock-attempt-ownership` | `036c428` | `9e8695c` | 旧 PR #90 |
| `archive/pre-independent-20261022/chore/v1-release-metadata-preflight` | `1929c55` | `61c6b98` | 旧 PR #91 |
| `archive/pre-independent-20261022/chore/android-release-signing-seam` | `c4bb9b6` | `91afe5f` | 旧 PR #92 |
| `archive/pre-independent-20261022/chore/platform-build-scripts` | `d6c794f` | `83d4fdd` | 旧 PR #93 |
| `archive/pre-independent-20261022/chore/android-signed-aab-release` | `b5da96b` | `2e51fae` | 旧 PR #94 |
| `archive/pre-independent-20261022/chore/github-release-aggregation` | `5d951d4` | `35e25fa` | 旧 PR #95 |
| `archive/pre-independent-20261022/docs/android-only-release-scope` | `5b764aa` | `7119fd1` | 旧 PR #96 |
| `archive/pre-independent-20261022/docs/android-release-runbook` | `190f4a9` | `66dc2b5` | 旧 PR #97 |
| `archive/pre-independent-20261022/fix/android-release-pub-regeneration` | `4fa3c7a` | `cf15300` | 旧 PR #98 |
| `archive/pre-independent-20261022/master` | `4fa3c7a` | `cf15300` | 旧基线重复归档 |
| `archive/landed-20261022/v1-common-baseline` | `4fa3c7a` | `cf15300` | 旧基线重复归档 |

## 恢复依据与方法

- 持久备份：`.git/branch-backups/2026-10-22/before-baseline-convergence.bundle`。
- SHA-256：`08e077bb0ecf27849f4ef79d83b21acbea44bc8b25e021fe750a1b8c1a19682b`。
- 删除前快照及执行回执还保存在 `.git/branch-backups/2026-10-23/local-cleanup-preflight.json` 与 `local-cleanup-results.json`。
- 恢复时在执行数据中查找目标条目的 `bundle_source_ref` 和 `branch`，在仓库根目录按以下格式执行；实际操作需替换尖括号占位内容。两个旧基线归档的恢复源名称可能与目标名称不同，应以记录为准。

```text
git fetch .git/branch-backups/2026-10-22/before-baseline-convergence.bundle <bundle_source_ref>:refs/heads/<branch>
```

例如，恢复已删的旧质量门禁归档：

```bash
git fetch .git/branch-backups/2026-10-22/before-baseline-convergence.bundle \
  refs/heads/archive/pre-independent-20261022/chore/v1-ci-quality-gate:refs/heads/archive/pre-independent-20261022/chore/v1-ci-quality-gate
```

恢复后用 `git rev-parse refs/heads/<branch>` 与执行数据中的完整 `head` 比对。原始历史清单和远端删除回执保持为各自执行时的快照；当前本地分支状态以本记录和实际 Git 引用为准。
