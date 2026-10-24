# 分支整理与共同代码基线交付记录

> 更新日期：2026-10-23。采用用户确认的方式：共同代码基线先交付主干，文档、迁移整合和擦除修复分支相互独立。

## 当前结果

- [共同基线 PR #99](https://github.com/CCreative-Od1L/project_sw/pull/99) 已通过正常 rebase 流程合入 `master`，合并时间（UTC）：`2026-10-23T05:46:41Z`。
- 共同代码基线提交为 `cf15300f5400fa87054f1d86c8b486926f367004`，后续主干文档提交另计；共同基线候选原 head 为 `4fa3c7a`。
- GitHub rebase 重写了提交 SHA；已逐一核验 36 对提交的稳定 patch-id 相同，最终源码 tree 均为 `6a229a07528198a0ce0175fac1f4574d700e76a4`。
- #65–#98 共 34 个旧 PR 的原 head 均已映射到新主干中的等价提交；已注明被 #99 替代并关闭，未重复合并它们。
- 迁移旧 PR #64（`b2c9a79`）仍保留；Issue #47、#49–#53 继续开放，基线交付不等于完成真机或正式发布验收。
- 远端临时候选 `chore/v1-common-baseline` 已删除；原 head `4fa3c7a` 由持久 bundle 保存。2026-10-23 复核后，#65–#98 的 34 个远端源分支也已按完整 SHA 租约原子删除，并清理相应的本地 `origin/*` 跟踪引用。
- 远端清理结束时分支从 47 个减为 13 个：`master`、迁移候选 `feat/v1-lan-migration-ui` 和 11 个 Dependabot 分支；该清理步骤未改变保留 head、12 个开放 PR 的 head/base 与版本标签。完整分支名与执行结果见 [远端清理记录](branches/2026-10-23-remote-cleanup-candidates.md) 和 [执行数据](branches/2026-10-23-remote-cleanup-results.json)。
- 本地随后删除 36 个已交付归档分支（34 个旧 PR 归档和 2 个旧基线归档），从 41 个分支减为 5 个；保留 `master`、三个独立任务分支和旧迁移候选归档。已用 bundle 完成独立恢复及对象连通性校验，原有 worktree、未提交文件和任务分支 head 均未变化。详见 [本地清理与恢复记录](branches/2026-10-23-local-cleanup.md)。

完整提交映射、旧 PR 处理结果和检查链接见 [共同基线交付清单](branches/2026-10-22-baseline-convergence.json)。

## 独立任务分支与工作区

| 分支/视图 | 当前内容与归属 | 工作区 |
|---|---|---|
| `master` | #99 代码、#111 文档、#100 下载依赖、#112 擦除、#106/#107 依赖及 #104 工具链均已交付（主干 `60bec47`） | `/home/pleGGen/projects/password_manager` |
| 共同基线只读视图 | detached `cf15300`，保留原基线对照 | `/home/pleGGen/projects/password_manager_worktrees/baseline` |
| `feat/v1-lan-migration-integration` | #113 已独立实现，仍需双设备验收；依赖维护交付后只从最新主干同步 | `/home/pleGGen/projects/password_manager_worktrees/lan-migration` |
| `chore/dependency-update-policy`（本交付分支） | 从已合并主干独立维护 SDK 暂缓策略和记录，合入后删除 | `/home/pleGGen/projects/password_manager_worktrees/dependency-policy` |
| 旧迁移本地归档 | `archive/pre-independent-20261022/feat/v1-lan-migration-ui` → `b2c9a79`，#64 对照来源 | 无 worktree |

#111、#100、#112、#106、#107、#104 的交付分支及 worktree 已清理并保留备份；每项只从已合并主干创建。依赖维护全过程与最终处置见 [维护记录](DEPENDENCY_MAINTENANCE.md)。

仍活动的迁移任务不继承任何未合并兄弟任务；维护交付后从主干同步并重新验证。原 `/tmp` 工作区已迁至项目旁持久目录，`/tmp` 仅用于日志和可重复的临时解析探测。

## 本次验证

共同基线 PR #99 本次触发的六项检查均成功：

- [质量门禁和密码学安全测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800238)：Quality gate 2m09s，Cryptography safety tests 1m58s。
- [Android 模拟器集成测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800239)：7m39s。
- [Android APK 与 iOS 无签名验证构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800258)：5m12s / 2m49s。
- [依赖与工具链审计](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800237)：1m27s。

合并前另核对 head 未变、普通合并状态为 CLEAN，并在 PR 中记录范围自审；未使用管理员绕过。合并后核对最终源码 tree、36 对提交补丁和全部 34 个旧 PR 的覆盖映射。

合并后 `master` 自动触发的 [CI](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644931)、[双平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644907)、[Android 集成](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644936) 也均为 success，全部对应 `cf15300`。

此前本地格式检查为 149 个文件零改动，静态分析无问题，270 项 Flutter 测试通过。以上为 #99 当时的验证记录。后续 #100、#112 和依赖维护已分别验证；#113 原候选通过 297 项测试，仍需基线更新后的复验。真实生物恢复、平台删除、双设备迁移和正式发布不由本次绿色 CI 代替。

## 原始历史与恢复依据

整理前本地 `master` 为 `4fa3c7a`，领先当时 `origin/master` 的 `fd1b880` 36 个提交。原有功能分支多为串联关系，不能仅修改 PR 的目标分支就视为独立。

- 整理时曾将原 36 个本地分支归档为 `archive/pre-independent-20261022/<原分支名>`，与原 SHA 一致并解除 upstream。2026-10-23 本地清理删除其中已交付的 35 个，仅保留旧迁移候选；另删除 `archive/landed-20261022/v1-common-baseline`，合计 36 个。删除前 SHA 与 bundle 内的恢复源引用均记录在 [本地清理数据](branches/2026-10-23-local-cleanup-results.json)。
- 原迁移候选为 `archive/pre-independent-20261022/feat/v1-lan-migration-ui`，仍指向 `b2c9a79`。
- [原始引用与 PR 清单](branches/2026-10-22-original-refs.json) 保存原分支、upstream、归档名、35 个旧 PR 及最初 8 份未提交文档的指纹；该历史快照不随本次合并改写。
- `.git/branch-backups/2026-10-22/before-baseline-convergence.bundle` 已校验，包含本次交付前的全部引用。提交覆盖、自审前置和旧 PR 关闭结果也保存在该目录。
- 早期 `/tmp/password-manager-branch-reorg-20261022/` 仅是临时辅助备份；已清理分支的恢复依据是上述持久 bundle 及历史/交付/清理清单。保留的迁移候选还可直接通过其本地归档引用读取。

## 尚待推进

完整工作清单、依赖及完成标准见 [当前待工作项](WORK_ITEMS.md)。

1. 文档 #111、下载 #100、擦除 #112 和依赖 #106/#107/#104 已交付；本轮修复及 SDK 暂缓处置见 [依赖维护](DEPENDENCY_MAINTENANCE.md)。
2. #113 只从维护后的最新主干同步并复验，再完成双设备验收及合并；旧 #64 保留至替代交付和覆盖关系确认。
3. 恢复异常与新建表单清空两组自动化补证、真实平台联调及发布验收继续推进。
4. #105/#109/#108 的 SDK 前置由 [#114](https://github.com/CCreative-Od1L/project_sw/issues/114) 接续，其他可选依赖独立维护。
5. 原始依赖来源及修复提交分别保存在 `.git/branch-backups/2026-10-23/` 的 `before-dependency-ci-repairs.bundle`、`cupertino-icons-repaired.bundle`、`get-it-repaired.bundle`、`before-toolchain-and-sdk-pr-handling.bundle` 等文件；均经 bundle 校验，删除远端引用使用完整 SHA 租约。
