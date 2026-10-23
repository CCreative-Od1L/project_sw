# 分支整理与共同代码基线交付记录

> 更新日期：2026-10-22。采用用户确认的方式：共同代码基线先交付主干，文档、迁移整合和擦除修复分支相互独立。

## 当前结果

- [共同基线 PR #99](https://github.com/CCreative-Od1L/project_sw/pull/99) 已通过正常 rebase 流程合入 `master`，合并时间（UTC）：`2026-10-23T05:46:41Z`。
- 本地与远端 `master` 均为 `cf15300f5400fa87054f1d86c8b486926f367004`；共同基线候选原 head 为 `4fa3c7a`。
- GitHub rebase 重写了提交 SHA；已逐一核验 36 对提交的稳定 patch-id 相同，最终源码 tree 均为 `6a229a07528198a0ce0175fac1f4574d700e76a4`。
- #65–#98 共 34 个旧 PR 的原 head 均已映射到新主干中的等价提交；已注明被 #99 替代并关闭，未重复合并它们。
- 迁移旧 PR #64（`b2c9a79`）仍保留；Issue #47、#49–#53 继续开放，基线交付不等于完成真机或正式发布验收。
- 远端临时候选 `chore/v1-common-baseline` 已删除；本地原 head 保留为 `archive/landed-20261022/v1-common-baseline`。34 个旧 PR 的远端源分支仍保留，后续可在核对无引用后单独清理。

完整提交映射、旧 PR 处理结果和检查链接见 [共同基线交付清单](branches/2026-10-22-baseline-convergence.json)。

## 独立任务分支与工作区

| 分支/视图 | 当前基线或内容 | 工作区 |
|-----------|----------------|--------|
| `master` | `cf15300`，共同代码基线已交付 | 本地引用与 `origin/master` 对齐 |
| 共同基线只读视图 | detached HEAD `cf15300` | `/home/pleGGen/projects/password_manager_worktrees/baseline` |
| `docs/v1-progress-and-validation` | 仅重放自身文档提交到 `cf15300`，随后记录本次交付 | `/home/pleGGen/projects/password_manager` |
| `fix/v1-wipe-restart-recovery` | `cf15300`，尚无修复提交 | `/home/pleGGen/projects/password_manager_worktrees/wipe-restart` |
| `feat/v1-lan-migration-integration` | `cf15300`，尚无迁移移植提交 | `/home/pleGGen/projects/password_manager_worktrees/lan-migration` |

三个任务分支从同一主干基线出发，不互相继承任务改动。迁移与擦除工作区目前是干净起点；创建或同步分支不代表功能修复已经完成。后续各自开发、验证，并分别创建以 `master` 为目标的 PR。

原 `/tmp` 工作区已失效，本次恢复到项目旁的持久目录，未混入任何分支任务改动。后续不以 `/tmp` 作为工作区的持久依赖。

## 本次验证

共同基线 PR #99 本次触发的六项检查均成功：

- [质量门禁和密码学安全测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800238)：Quality gate 2m09s，Cryptography safety tests 1m58s。
- [Android 模拟器集成测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800239)：7m39s。
- [Android APK 与 iOS 无签名验证构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800258)：5m12s / 2m49s。
- [依赖与工具链审计](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800237)：1m27s。

合并前另核对 head 未变、普通合并状态为 CLEAN，并在 PR 中记录范围自审；未使用管理员绕过。合并后核对最终源码 tree、36 对提交补丁和全部 34 个旧 PR 的覆盖映射。

合并后 `master` 自动触发的 [CI](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644931)、[双平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644907)、[Android 集成](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644936) 也均为 success，全部对应 `cf15300`。

此前本地格式检查为 149 个文件零改动，静态分析无问题，270 项 Flutter 测试通过。本次提交只更新文档与分支记录；新迁移/擦除改动将来仍须分别验证。真实生物恢复、平台删除、双设备迁移和正式发布不由本次绿色 CI 代替。

## 原始历史与恢复依据

整理前本地 `master` 为 `4fa3c7a`，领先当时 `origin/master` 的 `fd1b880` 36 个提交。原有功能分支多为串联关系，不能仅修改 PR 的目标分支就视为独立。

- 原 36 个本地分支均保留为 `archive/pre-independent-20261022/<原分支名>`，与原 SHA 一致并解除 upstream。
- 原迁移候选为 `archive/pre-independent-20261022/feat/v1-lan-migration-ui`，仍指向 `b2c9a79`。
- [原始引用与 PR 清单](branches/2026-10-22-original-refs.json) 保存原分支、upstream、归档名、35 个旧 PR 及最初 8 份未提交文档的指纹；该历史快照不随本次合并改写。
- `.git/branch-backups/2026-10-22/before-baseline-convergence.bundle` 已校验，包含本次交付前的全部引用。提交覆盖、自审前置和旧 PR 关闭结果也保存在该目录。
- 早期 `/tmp/password-manager-branch-reorg-20261022/` 仅是临时辅助备份；当前恢复依据是持久归档引用、上述 bundle 和入库的历史/交付清单。

## 尚待推进

1. 文档分支单独审查交付；不将其专属提交作为迁移或擦除分支的前置。
2. 擦除分支实现跨进程失败/中断保护，迁移分支移植 #64 并补齐 step-up、lease/guard 和生产装配；分别验证并提交 PR。
3. 新迁移方案交付后，再确认替代关系并收敛旧 PR #64。
4. 34 个已关闭旧 PR 的远端源分支保留至专门清理步骤；核对不存在开放 PR 的 head/base 引用后再删除。
5. 主干启用的 Dependabot 自动生成依赖更新 PR，这些新 PR 按独立维护任务处理，不属于本次被替代的 #65–#98。
6. 按 [待验证清单](PENDING_VALIDATION.md) 完成剩余平台联调和发布验收；关闭旧 PR 不关闭这些验收要求。
