# 当前进度 · PROJECT_SW

> 更新日期：2026-10-23。共同代码基线已由 PR #99 交付，基线提交为 `cf15300`，后续主干文档提交另计；基线源码 tree 与原候选 `4fa3c7a` 相同。本轮记录经 `docs/v1-progress-and-validation` 的独立文档 PR 交付。本页记录实现、合并、验收与发布状态；目标规格仍以 `specs/` 和 `SECURITY.md` 为准。

已开发功能尚缺哪些验证、已有自动化的边界和逐项验收场景，见 [待验证清单](PENDING_VALIDATION.md)。

当前可推进的代码、测试、平台验收及发布配置工作，按依赖和完成标准整理在 [待工作项](WORK_ITEMS.md)。

共同基线、任务工作区、历史归档与远端 PR 收敛顺序见 [分支整理记录](BRANCH_ORGANIZATION.md)。

## 版本进度

| 阶段 | 当前状态 | 依据 |
|------|----------|------|
| v0.1 tracer bullet | 已完成建库、主密码解锁、条目 CRUD、锁定/重解锁及 Argon2id 真机校准 | #13–#19、#28 均已关闭；[质量验收 #19](https://github.com/CCreative-Od1L/project_sw/issues/19) |
| v0.5 Android MVP | 已完成双语/主题/导航、密码生成器、摘要搜索、后台/超时锁定、敏感复制和只读安全设置；Android 真机验收已完成 | #30–#36 均已关闭；[验收 #36](https://github.com/CCreative-Od1L/project_sw/issues/36) 于 2026-08-07 关闭 |
| v1.0 | 共同代码基线已交付主干；擦除跨重启保护已实现，迁移接入、最终真机验收与 Android 发布演练仍未完成 | [总任务 #47](https://github.com/CCreative-Od1L/project_sw/issues/47) 及 #49–#53 保持开放；`1.0.0+1` 仍为 Unreleased |

敏感复制不承诺固定 20 秒自动清除；继续遵循 [数据卫生规范](specs/data_hygiene.md) 的平台边界。

系统剪贴板无法由应用可靠、全面控制，已经是确认的能力限制，不再作为待验证功能或发布门禁。后续敏感数据清理回归仅验收应用持有的复制明文、计时器与反馈等可控状态，见 [ADR-0011](adr/0011-clipboard-cleanup-platform-boundary.md)。

## 代码所在位置与合并状态

- 整理前本地 `master` 为 `4fa3c7a`，领先远端 36 个提交。现这些代码已通过 [PR #99](https://github.com/CCreative-Od1L/project_sw/pull/99) rebase 合入主干，共同代码基线提交为 `cf15300`；文档交付后继续从最新 `origin/master` 同步独立任务。
- 已核验合并前后 36 对提交补丁等价、最终源码 tree 相同；#65–#98 共 34 个旧 PR 已注明被 #99 替代并关闭。原始 SHA 与等价新提交映射见 [交付清单](branches/2026-10-22-baseline-convergence.json)。
- [PR #64](https://github.com/CCreative-Od1L/project_sw/pull/64)（旧候选 `feat/v1-lan-migration-ui`，`b2c9a79`）仍为 OPEN。主干未包含该切片；迁移整合分支已同步至新主干，目前尚无移植提交。
- 文档、迁移、擦除修复分支均从 `cf15300` 创建，后续仅从共同主干同步，工作区恢复在持久目录中。2026-10-23 已复核并删除 #65–#98 的 34 个旧远端源分支；清理结束时远端保留 `master`、#64 迁移候选和 11 个 Dependabot 分支，开放 PR 与标签未变。分支名、原 SHA、备份及执行结果见 [远端清理记录](branches/2026-10-23-remote-cleanup-candidates.md)。
- 本地已清理 36 个已交付归档分支，清理结束时保留 `master`、三个独立任务分支和旧迁移候选归档，共 5 个；已交付任务分支随后按工作流删除。原提交仍可从已完成独立恢复校验的持久 bundle 恢复；清理未改变 worktree 和原有未提交文件。详见 [本地清理记录](branches/2026-10-23-local-cleanup.md)。
- 主干上的 Dependabot 配置生效后自动生成新的依赖更新 PR，这些维护任务不属于本次关闭的旧 PR。

## v1.0 任务现状

| 任务 | 已有实现与证据 | 剩余工作 |
|------|----------------|----------|
| [#48 生物解锁主路径](https://github.com/CCreative-Od1L/project_sw/issues/48) | 已关闭；Keychain/Keystore 适配、生物设置与解锁主路径已实现 | 后续失效与高敏入口归 #49 |
| [#49 生物失效回退与 step-up](https://github.com/CCreative-Od1L/project_sw/issues/49) | 生物失效回退、生物设置 step-up 已合并；2026-08-08 的 Android P0 真机验收已记录。共同代码基线另有主密码变更及其认证升级流程 | 整合后续高敏入口，完成迁移入口的 step-up 与最终 Android 回归验收；Issue 仍为 OPEN / ready-for-agent |
| [#50 局域网迁移](https://github.com/CCreative-Od1L/project_sw/issues/50) | 协议/能力协商、crypto_kx、TCP、逐条加密、transcript MAC、DEK 重包裹、冲突处理和原子导入已实现；页面/扫码候选在 PR #64 | 补迁移主密码 step-up、当前 lease/guard 与生产装配；规格要求的单条选择尚未实现，当前导出遍历全库。完成后做双 Android 真机验收。Issue 为 OPEN / ready-for-human，标签与仍有代码前置的现状不匹配 |
| [#51 忘码恢复与擦除](https://github.com/CCreative-Od1L/project_sw/issues/51) | 恢复门控、二次生物确认、恢复窗口/冷却持久化、两类擦除及目标删除验证已由 #99 交付；时间规则和本进程失败保锁已有自动化 | 生产恢复/重启联调、平台密钥删除及 UI 补证；擦除跨进程保护与可见恢复入口已实现并补文件/启动/路由自动化；真实进程重启及平台删除仍待验收，Issue 开放 |
| [#52 高级会话与敏感清理](https://github.com/CCreative-Od1L/project_sw/issues/52) | 会话 lease、step-up/解锁归属 guard、后台中断、CRUD 提交保护及跨页面秘密清理已由 #99 交付；有状态机、生命周期与旧异步结果测试 | Android 真实生命周期/系统提示接线回归；迁移 guard 仍待补接；擦除跨进程恢复已有实现和自动化，待真实平台联调，Issue 开放 |
| [#53 CI/CD 与发布](https://github.com/CCreative-Od1L/project_sw/issues/53) | 完整发布链、质量门禁、Android 模拟器集成、双平台验证构建和依赖审计已由 #99 交付；本次六项 PR 检查成功 | 只读 API 显示环境列表为空、master 无经典分支保护且无 ruleset；须配置发布环境/签名与合并门禁，再执行完整 tag → Release 和干净环境 tag 重建，Issue 开放 |

V1.0 软件发布仅覆盖 Android；iOS 保留原生代码和无签名构建验证，不代表已完成 iOS 功能真机验收或签名发布资格。发布步骤见 [Android 发布运行手册](RELEASE_RUNBOOK.md)。

## 已核验的验证记录

共同基线 [PR #99](https://github.com/CCreative-Od1L/project_sw/pull/99) 本次六项检查全部通过：[质量/密码学](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800238)、[Android 集成](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800239)、[双平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800258)、[依赖审计](https://github.com/CCreative-Od1L/project_sw/actions/runs/39906800237)。合并后的源码 tree 与原候选相同，逐提交覆盖记录已入库。

合并后的 `master`（`cf15300`）自动运行 [CI](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644931)、[双平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644907) 和 [Android 集成](https://github.com/CCreative-Od1L/project_sw/actions/runs/39907644936)，三条 workflow 均成功。

本次读取 GitHub Actions 记录，确认 `4fa3c7a` 的以下 PR 工作流均为 success（运行日期为 2026-08-25 UTC）：

- [CI：质量门禁与加密安全测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116189)
- [Android 模拟器集成测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116275)
- [Android/iOS 平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116421)
- [依赖维护检查](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116172)

[#53 最新进展记录](https://github.com/CCreative-Od1L/project_sw/issues/53#issuecomment-5403771353) 另记录该基线的 270 项 Flutter 测试通过，以及临时签名 AAB 构建成功。2026-10-22 的分支整理阶段对相同源码重新执行了格式检查、静态分析和全量 Flutter 测试，270 项通过，详见 [本次验证](BRANCH_ORGANIZATION.md#本次验证)；没有重新构建 AAB、执行真机验收或真实发布。

共同基线交付没有创建版本 tag 或软件 Release；本地 AAB、发布脚本及成功的 PR 构建均不代表正式 tag 发布演练已通过。

## 下一步

1. 擦除跨重启/安全重试已实现并补自动化；继续独立推进迁移接入（step-up、lease/guard、生产装配及单条选择），并行补恢复/表单测试、交付文档、配置 release 环境与主干保护。归属、前置及完成标准见 [待工作项 W01–W03、W08–W09](WORK_ITEMS.md#工作总表)。
2. 保留时间规则、guard、控制器清理等已有自动化结论，补齐四组明确的异常/UI 断言，并完成真实生命周期、恢复重启、平台删除和双设备迁移联调；记录证据后同步 #49–#52 的状态。11 个 Dependabot PR 单独审核，当前 4 个现有检查通过、7 个有失败，不预设必须全部升级。
3. 在最终主干和验收结果上执行真实 Android tag 发布与干净环境重建，完成 #53 后再将 v1.0 标记为已发布。旧迁移 #64 在替代方案交付、覆盖关系明确后单独收敛。

擦除修复新增专用持久化 marker：不可逆删除前落盘，全部目标验证后清除；生产启动优先恢复擦除锁，并提供继续删除入口。相关自动化见 [持久化与启动回归](../test/features/auth/data/file_vault_wipe_progress_store_test.dart) 和 [路由与安全重试回归](../test/app/wipe_restart_flow_test.dart)。这些测试不代替真实 Android Keystore 删除或 OS 进程重启验收。
