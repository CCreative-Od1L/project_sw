# 当前进度 · PROJECT_SW

> 核验日期：2026-10-22。代码基线：`chore/v1-common-baseline` 的 `4fa3c7a`（2026-08-24）。本地 `master` 已对齐远端的 `fd1b880`；本轮文档独立保存在 `docs/v1-progress-and-validation`。本页记录实现、合并、验收与发布状态；目标规格仍以 `specs/` 和 `SECURITY.md` 为准。

已开发功能尚缺哪些验证、已有自动化的边界和逐项验收场景，见 [待验证清单](PENDING_VALIDATION.md)。

共同基线、任务工作区、历史归档与远端 PR 收敛顺序见 [分支整理记录](BRANCH_ORGANIZATION.md)。

## 版本进度

| 阶段 | 当前状态 | 依据 |
|------|----------|------|
| v0.1 tracer bullet | 已完成建库、主密码解锁、条目 CRUD、锁定/重解锁及 Argon2id 真机校准 | #13–#19、#28 均已关闭；[质量验收 #19](https://github.com/CCreative-Od1L/project_sw/issues/19) |
| v0.5 Android MVP | 已完成双语/主题/导航、密码生成器、摘要搜索、后台/超时锁定、敏感复制和只读安全设置；Android 真机验收已完成 | #30–#36 均已关闭；[验收 #36](https://github.com/CCreative-Od1L/project_sw/issues/36) 于 2026-08-07 关闭 |
| v1.0 | 多项实现已汇入共同代码基线候选，远端交付、迁移接入、擦除跨重启保护、最终真机验收与 Android 发布演练仍未完成 | [总任务 #47](https://github.com/CCreative-Od1L/project_sw/issues/47) 及 #49–#53 保持开放；`1.0.0+1` 仍为 Unreleased |

敏感复制不承诺固定 20 秒自动清除；继续遵循 [数据卫生规范](specs/data_hygiene.md) 的平台边界。

系统剪贴板无法由应用可靠、全面控制，已经是确认的能力限制，不再作为待验证功能或发布门禁。后续敏感数据清理回归仅验收应用持有的复制明文、计时器与反馈等可控状态，见 [ADR-0011](adr/0011-clipboard-cleanup-platform-boundary.md)。

## 代码所在位置与合并状态

- 整理前本地 `master` 为 `4fa3c7a`，领先远端 36 个提交。现这些代码固定在 `chore/v1-common-baseline`；本地 `master` 与 `origin/master` 均为 `fd1b880`。
- 共同代码基线与 `origin/fix/android-release-pub-regeneration` 的提交相同；这些实现已有远端候选分支，但尚未交付远端主干。
- [PR #64](https://github.com/CCreative-Od1L/project_sw/pull/64)（旧候选 `feat/v1-lan-migration-ui`，`b2c9a79`）仍为 OPEN。共同代码基线未包含该切片；迁移整合分支已从共同基线独立创建，目前尚无移植提交，不能宣称当前应用已具备扫码迁移闭环。
- #65–#98 共 34 个 PR 的 head 已包含在共同代码基线中，但远端 PR 仍未收敛。原本地分支均已归档；文档、迁移、擦除修复各有独立分支/worktree，共享代码基线而不互相继承任务提交。

## v1.0 任务现状

| 任务 | 已有实现与证据 | 剩余工作 |
|------|----------------|----------|
| [#48 生物解锁主路径](https://github.com/CCreative-Od1L/project_sw/issues/48) | 已关闭；Keychain/Keystore 适配、生物设置与解锁主路径已实现 | 后续失效与高敏入口归 #49 |
| [#49 生物失效回退与 step-up](https://github.com/CCreative-Od1L/project_sw/issues/49) | 生物失效回退、生物设置 step-up 已合并；2026-08-08 的 Android P0 真机验收已记录。共同代码基线另有主密码变更及其认证升级流程 | 整合后续高敏入口，完成迁移入口的 step-up 与最终 Android 回归验收；Issue 仍为 OPEN / ready-for-agent |
| [#50 局域网迁移](https://github.com/CCreative-Od1L/project_sw/issues/50) | 协议/能力协商、crypto_kx、TCP、逐条加密、transcript MAC、DEK 重包裹、冲突处理和原子导入已实现；页面/扫码候选在 PR #64 | 候选尚缺迁移主密码 step-up，旧会话 suppression API 与当前 lease/guard 不兼容，需补接实现及生产装配后再做双 Android 真机验收。Issue 为 OPEN / ready-for-human，但代码并非仅剩人工验收 |
| [#51 忘码恢复与擦除](https://github.com/CCreative-Od1L/project_sw/issues/51) | 当前本地已有恢复门控、二次生物确认、恢复窗口/冷却持久化、隐藏死锁擦除入口、确认/倒计时、主密码认证擦除及目标删除验证；时间规则和本进程失败保锁已有自动化 | 生产恢复/重启联调、平台密钥删除及 UI 补证；擦除失败状态未跨进程持久化，重启保护是实现缺口。远端 PR 交付仍待整合，Issue 开放 |
| [#52 高级会话与敏感清理](https://github.com/CCreative-Od1L/project_sw/issues/52) | 当前本地已有会话活动 lease、step-up/解锁归属 guard、后台中断、CRUD 提交保护及跨页面秘密清理；有状态机、生命周期与旧异步结果测试 | Android 真实生命周期/系统提示接线回归；迁移 guard 补接及擦除失败后的跨进程恢复仍需实现；远端 PR 交付待整合，Issue 开放 |
| [#53 CI/CD 与发布](https://github.com/CCreative-Od1L/project_sw/issues/53) | 当前本地已有完整发布链源码、质量门禁、Android 模拟器集成、Android debug APK / iOS 无签名验证构建及依赖审计；脚本/合同测试和临时签名 AAB 构建已验证 | 正式 Android release 环境配置核验、完整 tag → Release 演练与干净环境 tag 重建；远端 PR 合并是交付前提，本地并不缺这些发布链代码，Issue 开放 |

V1.0 软件发布仅覆盖 Android；iOS 保留原生代码和无签名构建验证，不代表已完成 iOS 功能真机验收或签名发布资格。发布步骤见 [Android 发布运行手册](RELEASE_RUNBOOK.md)。

## 已核验的验证记录

本次读取 GitHub Actions 记录，确认 `4fa3c7a` 的以下 PR 工作流均为 success（运行日期为 2026-08-25 UTC）：

- [CI：质量门禁与加密安全测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116189)
- [Android 模拟器集成测试](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116275)
- [Android/iOS 平台构建](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116421)
- [依赖维护检查](https://github.com/CCreative-Od1L/project_sw/actions/runs/32797116172)

[#53 最新进展记录](https://github.com/CCreative-Od1L/project_sw/issues/53#issuecomment-5403771353) 另记录该基线的 270 项 Flutter 测试通过，以及临时签名 AAB 构建成功。2026-10-22 的分支整理阶段对相同源码重新执行了格式检查、静态分析和全量 Flutter 测试，270 项通过，详见 [本次验证](BRANCH_ORGANIZATION.md#本次验证)；没有重新构建 AAB、执行真机验收或真实发布。

本次 GitHub 查询未发现任何 Release；不能将本地 AAB、发布脚本或成功的 PR 构建视为正式 tag 发布演练已通过。

## 下一步

1. 先解决迁移 step-up/lease/生产装配及擦除失败后跨进程保护的实现缺口；梳理候选 PR 的交付顺序。具体证据见 [待验证清单](PENDING_VALIDATION.md#实现整合缺口先解决再验收)。
2. 保留时间规则、guard、控制器清理等已有自动化结论，补充缺失的 UI/异常分支断言，并完成真实生命周期、恢复重启、平台删除和双设备迁移联调；记录证据后同步 #49–#52 的状态。
3. 按运行手册确认正式 Android 签名环境，执行真实 tag 发布与重建演练，完成 #53 后再将 v1.0 标记为已发布。
