# 分支整理记录与执行顺序

> 整理日期：2026-10-22。采用用户确认的方式：先固定共同代码基线，后续迁移、擦除修复和文档分支相互独立。本文记录本地已执行结果及远端后续步骤。

## 共同基线

整理前，本地 `master` 为 `4fa3c7a2412935a108ab55b2b7d6933ee1ccf832`，领先 `origin/master` 的 `fd1b880dbf2b129959af9e7230e102de28c098f8` 36 个提交。35 个开放 PR 中，#65–#98 的分支提交已包含在这条本地历史内；#64 的迁移 UI `b2c9a79` 是未包含的另一条候选分支。

历史分支多以其他未合并分支为基线；部分 PR 虽以 `master` 为目标，仍累计携带前序功能提交。改密 UI 依赖改密核心、恢复依赖门控与重包裹、guard 依赖会话 lease，发布流水线依赖脚本和签名配置。因此不能仅把所有 PR 的目标改成 `master` 就称其独立。

现固定 `chore/v1-common-baseline` 为 `4fa3c7a`，源码 tree 为 `6a229a07528198a0ce0175fac1f4574d700e76a4`，与整理前代码完全相同。既有 270 项测试和 CI 记录仍对应这份源码；它保留 [待验证清单](PENDING_VALIDATION.md) 中的已知缺口，尚未完成真机/正式发布验收，也尚未交付远端主干。

## 已建立的独立分支

| 分支 | 基线/内容 | 工作区与状态 |
|------|-----------|--------------|
| `master` | `origin/master` 的 `fd1b880` | 已对齐远端主干，未直接推送 |
| `chore/v1-common-baseline` | 原本地代码 `4fa3c7a` | `/tmp/password-manager-independent-20261022/baseline`；源码无改动的共同基线候选 |
| `docs/v1-progress-and-validation` | 从 `4fa3c7a` 创建，只提交本轮文档与分支记录 | 主工作区 `/home/pleGGen/projects/password_manager` |
| `fix/v1-wipe-restart-recovery` | 从 `4fa3c7a` 创建 | `/tmp/password-manager-independent-20261022/wipe-restart`；尚无修复提交 |
| `feat/v1-lan-migration-integration` | 从 `4fa3c7a` 创建 | `/tmp/password-manager-independent-20261022/lan-migration`；尚无迁移移植提交 |

三个任务分支共享同一代码基线，不互相继承任务提交。迁移与擦除分支目前是干净的独立起点；创建分支不代表相应功能或修复已经完成。迁移旧候选留在归档引用中，后续移植须解决 step-up、lease/guard 与生产装配差异。

## 本次验证

分支整理阶段在文档工作区执行并通过：

- `fvm dart format --output=none --set-exit-if-changed .`：149 个 Dart 文件，零改动。
- `fvm flutter analyze --no-pub`：无问题。
- `fvm flutter test --no-pub --reporter compact`：270 项测试通过；日志为 `/tmp/password-manager-branch-reorg-20261022/flutter-tests.log`。
- 36 个归档 head、共同基线 tree、本地/远端 `master` 对齐、34 个旧 PR head 的包含关系、独立 worktree 初始清洁状态及文档链接均已校验。

应用源码保持原样，新的工作仅为文档、分支规则和引用清单。本次没有运行移动端集成测试、真机验收或真实发布；新迁移/擦除改动将来仍须在各自分支验证。

## 历史与未提交改动保存

- 整理前的全部 36 个本地分支（含原 `master`）已按原提交归档为 `archive/pre-independent-20261022/<原分支名>`，并解除其 upstream，作为静态历史保存。
- 原迁移候选引用为 `archive/pre-independent-20261022/feat/v1-lan-migration-ui`，仍指向 `b2c9a79`。
- [原始引用与 PR 清单](branches/2026-10-22-original-refs.json) 保存原分支 SHA、upstream、归档名称、35 个 PR 的目标与 head，以及原 8 份未提交文档的 SHA-256。
- Git bundle、原工作区文档副本和 tracked patch 保存在 `/tmp/password-manager-branch-reorg-20261022/`，bundle 已执行完整性校验。持久的恢复抓手是仓库内的归档 refs 与上述清单；`/tmp` 仅作本机辅助备份。
- 本轮文档改动移入独立文档分支，不进入迁移或擦除工作区。

本次只整理本地分支和 worktree。远端分支、35 个既有 PR 及其基线均未改写、删除或关闭；远端历史依赖仍存在，需按下一节收敛。不能将本地整理完成写成远端 PR 已经全部独立。

## 远端收敛顺序

1. 将共同代码基线候选作为一个整体进行审核，明确它包含 #65–#98 的已有开发工作和当前未修复缺口；通过仓库 PR 流程交付 `master`。本地现已备齐该候选，尚未推送或创建新的 PR。
2. 基线交付后，逐项确认 #65–#98 的 head 提交已经进入主干，再关闭被基线覆盖的旧 PR。清理远端旧分支前核对没有其他开放 PR 仍以其为目标，并保留原始引用记录。
3. 文档、擦除修复和迁移整合分支统一同步至同一 `origin/master`；每个分支只保留自己的改动，分别创建以 `master` 为目标的 PR。
4. 迁移旧 PR #64 继续作为移植来源。新迁移分支完成接口适配、主密码门控与生产接线后，记录其替代关系，再收敛旧 PR；不能把旧候选直接覆盖当前组合根。
5. 后续验收按 [待验证清单](PENDING_VALIDATION.md) 执行；每项证据记录实际分支与 commit，不能将共同基线的历史 CI 通过当成新修复或移植已经通过。

## 独立性验收

- 原 36 个本地 head 均可由对应归档引用逐项还原；共同基线 tree 与整理前一致。
- 本地 `master` 与 `origin/master` 相同；共同基线候选和任务分支不借用主干名称冒充已交付代码。
- 文档分支相对共同基线仅有文档与引用清单；迁移和擦除 worktree 初始干净且均指向共同基线。
- 后续功能开发分别在其 worktree 进行；只在各自分支运行适当验证，并在交付主干后再同步其他分支。
