# 当前待工作项 · PROJECT_SW

> 核验日期：2026-10-23。源码基线为 `master` 的 `cf15300f5400fa87054f1d86c8b486926f367004`；GitHub 状态取自本日 13:47 UTC 的只读查询，并再次点验发布环境和主干保护配置。起点分析与后续状态分开记录；依赖处理结果见 [本轮维护记录](DEPENDENCY_MAINTENANCE.md)。

v0.1、v0.5 Android MVP 已验收，共同基线 PR #99 及分支清理已完成。擦除代码已交付，迁移候选 #113 已完成并待验收/合并；当前主要工作是剩余自动化补证、Android 整合验收和正式发布。实现和验收状态分别见 [当前进度](PROGRESS.md)、[待验证清单](PENDING_VALIDATION.md)；分支与恢复依据见 [分支整理记录](BRANCH_ORGANIZATION.md)。

## 初始核验时的起点（后续状态见各项与维护记录）

- 本地保留 5 个分支：`master`、三个独立任务分支及旧迁移候选归档。迁移、擦除任务都还停在共同基线，尚无本任务实现提交。
- 进度、验证、清理与本清单由 `docs/v1-progress-and-validation` 独立文档包交付，不含迁移或擦除实现；交付状态以对应文档 PR 为准，合入后按工作流删除该分支。
- 主干已有 270 项 Flutter 测试通过记录及成功的 CI、Android 模拟器集成、Android/iOS 验证构建；本次分析未重跑功能测试。
- GitHub 开放 Issue 为 [#47](https://github.com/CCreative-Od1L/project_sw/issues/47)、[#49](https://github.com/CCreative-Od1L/project_sw/issues/49)–[#53](https://github.com/CCreative-Od1L/project_sw/issues/53)。开放 PR 为 [#64](https://github.com/CCreative-Od1L/project_sw/pull/64) 和 11 个 Dependabot PR，尚无 tag 或 GitHub Release。

## 工作总表

“先做”指优先完成的代码或交付前置；“可并行”指现有基线即可开始的工作；“后置”指应等待相应实现或整合结果。平台验收可先覆盖当前已接入的功能，最终证据须对应选定的发布提交。

| 编号 | 顺序 | 类型 | 待完成工作 | 前置或归属 | 完成标准 |
|------|------|------|------------|------------|----------|
| W01 | 实现完成，待平台验收 | 实现 | 擦除进度跨重启持久化、启动阻塞及安全重试 | `fix/v1-wipe-restart-recovery`；#51、#52 | 中断/失败后重启仍识别未完成擦除；所有目标验证删除后才允许建库；部分删除后的重试可达且可重复执行 |
| W02 | 候选完成，待设备验收/合并 | 实现/整合 | 迁移 UI、主密码门控、当前会话接口、生产装配和单条选择 | `feat/v1-lan-migration-integration`；#49、#50、#52 | 发送/接收均接入生产入口；认证和中断规则正确；全库/单条迁移范围可选且可验证 |
| W03 | 部分完成 | 自动化补证 | A02/A03 已补；仍需恢复异常和新建表单清空测试 | 见下表；擦除相关测试随 W01 交付 | 各组有直接断言及通过记录，区分用例、页面、生产路由和真实平台层级 |
| W04 | 可并行 | Android 联调 | 常规改密、生物辅助恢复、恢复窗口/冷却的进程重启 | V01–V03；#49、#51 | 生产设置页、系统二次生物确认、新旧密码及真实重启后的期限加载均有证据 |
| W05 | 后置 | Android 联调 | 正常/死锁擦除到真实平台删除与重新建库 | W01、对应 W03；V04–V05；#51 | Keystore/平台 envelope 与显式文件目标均确认删除；部分失败、重启和重试不绕过保护 |
| W06 | 可并行 | Android 联调 | 真实生命周期、高敏活动中断及应用内秘密清理 | V06–V07；#52；新流程最终依赖 W01/W02 | 系统生物提示与真正后台能正确区分；旧异步结果不恢复会话，页面/表单/复制状态不恢复旧内容 |
| W07 | 后置 | 双设备联调 | 扫码、配对、选定范围迁移、冲突处理与异常中断 | W02；V08；#50 | 两台 Android 真机验证迁移结果、取消/过期码/权限拒绝/断网/后台锁定，不发布部分导入 |
| W08 | 先做，可并行 | 发布配置 | `release` environment、签名配置及 `master` 合并门禁 | #53；可与代码任务并行 | 环境与四个签名配置项就绪；主干要求 PR 和实际 CI 检查，规则生效且与工作流名称一致 |
| W09 | 可并行 | 文档/任务状态 | 独立交付进度、验证、分支及本清单；校正 Issue #50 的人工验收标签 | 当前文档分支 | 文档经规定检查和独立 PR 交付；Issue 状态反映仍有代码前置，不以 `ready-for-human` 代替实现完成 |
| W10 | 后置 | 旧候选收敛 | 关闭被新迁移方案替代的 #64，清理其来源分支/归档 | W02 交付并核对覆盖关系 | 记录替代 PR/提交及保留证据后，再处理旧 PR 和引用；当前继续保留 #64 与迁移归档 |
| W11 | 逐项处理 | 依赖维护 | #106/#107/#104 已验证并合并；#105/#109/#108 转 SDK 任务 #114 | 各自独立分支；见 [维护记录](DEPENDENCY_MAINTENANCE.md) | 可采用项验证交付；不可解析候选记录前置并按精确版本暂缓 |
| W12 | 后置 | 最终交付 | 最终主干 CI、真实 Android tag → Release 及干净环境重建 | W01–W08 的相关实现/测试/验收；V09；#53 | 正式 annotated tag、三个发布 job、Release/AAB 及同一 tag 重建均有可追溯证据 |

## W01：擦除保护已实现，待平台验收

生产擦除现已使用独立的持久化 marker：删除密钥及文件前 flush，所有目标验证完成后清除；marker 写入失败不执行删除，清除失败不放行首次设置。启动优先识别 marker，无论主库是否仍存在，均恢复 `wipeStarted` 锁。

恢复页禁用认证，提供复用 `DELETE` 确认和倒计时的可见入口；共用协调器确保并发请求不会重复执行，界面可观察已在进行的擦除。已有 [真实文件/启动回归](../test/features/auth/data/file_vault_wipe_progress_store_test.dart) 和 [路由/并发/重试回归](../test/app/wipe_restart_flow_test.dart)。W05 的真实 Android 删除与 OS 重启仍待验收。

## W02：迁移候选已完成，待验收与合并

[独立迁移 PR #113](https://github.com/CCreative-Od1L/project_sw/pull/113) 已补生产入口、主密码 step-up、全过程 activity lease/guard、全库/单条选择及对应回归，原提交 `5844a5a` 已通过 297 项本地测试和五项远端检查。代码尚未合入主干；本轮依赖交付后将从共同主干同步并重新验证。

Android 相机权限与 iOS 相机用途说明已在 #113 中接入；此前将 iOS 相机说明误记为已存在，现更正。原主干已有 iOS 局域网用途说明。双设备权限、网络、中断和迁移结果继续归 W07/V08，不把代码或自动化通过当作设备验收。

## W03：四组自动化补证

| 组别 | 现有实现与证据 | 补证结论或剩余断言 | 分支安排 |
|------|----------------|--------------|----------|
| A01 恢复异常 | [`RecoverMasterPassword`](../lib/features/auth/domain/recovery/recover_master_password.dart#L84) 已映射生物取消、不可用与失效；已有取消/门不可用测试 | `BiometricUnavailableException`、`BiometricInvalidatedException` 各自返回预期失败，未预约冷却、未修改库 | 可从共同主干开独立测试任务 |
| A02 认证擦除 | 原有认证测试及 [实际路由/恢复测试](../test/app/wipe_restart_flow_test.dart) | 正确密码到首次设置、失败阻塞和安全重试已有直接断言 | 随 #112 交付；真实平台删除仍待 W05 |
| A03 死锁擦除 | 原倒计时测试及 [故障/重试 UI 测试](../test/app/wipe_restart_flow_test.dart) | 可见失败、重新确认/倒计时及重试成功已有直接断言 | 随 #112 交付；保留已验证时间规则 |
| A04 新建表单 | [`clearUnlockedSession`](../lib/app/pages/home_page.dart#L114) 已清空输入控制器 | 在尚未保存的表单输入中锁定，直接检查各控制器文本归空；不能只观察页面关闭 | 可从共同主干开独立测试任务 |

A02/A03 已补齐，剩余 A01/A04 是特定场景的证据缺口，不代表相应功能完全未经验证。测试任务有新增公共前置时，先交付主干，再同步该前置；不在未合并的兄弟任务上串接分支。

## W04–W07：平台联调的边界

- 改密/恢复验收覆盖主密码与生物会话、系统二次生物确认、新旧密码有效性、条目与生物路径保留，以及真实退出/重启后的窗口或冷却加载。10 分钟与 7 天的到期规则已有可控时钟测试，不要求在真机等待一周。
- 正常和死锁擦除共享删除后端，可复用真实平台删除证据；两条入口和故障后的用户路径分别记录。跨重启保护先实现再验收。
- 生命周期联调关注真实 Android `inactive/paused` 组合、系统生物提示及生产 adapter；已有确定性 guard/旧 Future/计时器测试不重新列作首次验证。
- 应用内秘密清理覆盖表单、弹窗、详情、生成器、复制明文/计时器/反馈。系统、厂商、输入法剪贴板清除能力已经确认不可保证，不重新加入验收门禁。
- 双设备迁移验收包含全库/单条范围、冲突覆盖/跳过、条目字段及版本保留、断网/取消/后台中断；目标设备先建空库，生物设置不随迁移转移。

逐项场景与既有证据继续在 [V01–V09](PENDING_VALIDATION.md) 中维护，平台结果记录 commit、设备/OS、日期、预期/实际和证据链接。

## W08、W12：发布前置与最终证据

只读 API 的当前结果为：

| 检查 | 结果 | 后续动作 |
|------|------|----------|
| `GET /repos/CCreative-Od1L/project_sw/environments` | `total_count: 0`，列表为空 | 建立 `release` environment 并核对发布策略 |
| `GET /repos/CCreative-Od1L/project_sw/environments/release/secrets` | 404，无法列出该环境的配置项 | 四个签名 secret 是否已就绪尚不能确认；环境建立后按手册配置并验证，不读取或记录值 |
| `GET /repos/CCreative-Od1L/project_sw/branches/master/protection` | 404，`Branch not protected` | 配置主干保护及所需 PR/CI 检查 |
| `GET /repos/CCreative-Od1L/project_sw/rulesets` | 可访问，返回 `[]` | 当前没有 ruleset 提供替代门禁 |
| tag / GitHub Release | 均为空 | 正式发布与历史 tag 重建尚无演练证据 |

签名项为 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD`，操作遵循 [发布运行手册](RELEASE_RUNBOOK.md)。本次只查询配置状态，没有创建环境、修改保护或写入 secret。

功能及 Android 验收完成后，在最终主干提交上跑规定检查、集成与构建，再执行 annotated tag → metadata / Android / publish 三个 job → GitHub Release。记录 tag、commit、run URL、Release URL、AAB SHA-256；在干净环境检出同一 tag 重建，核对版本、锁定工具链/依赖和产物可用性。

当前 [`verify_release_metadata.sh`](../scripts/verify_release_metadata.sh#L44) 的 checksum 对象是 `pubspec.lock`，不是 AAB；发布 workflow 没有自动生成 AAB checksum 附件。按手册记录 AAB SHA-256 即可作为本次证据，自动附件属于可选改进。重建不默认要求两次 AAB 字节完全相同。

## W09–W11：交付与维护

- 文档按 `docs/v1-progress-and-validation` 独立审查交付，提交前执行仓库规定的格式、分析和测试。合入后迁移与擦除分支从最新主干同步，不把未合并文档分支作为代码前置；W09 中的 Issue 状态校正单独跟踪。
- #50 保留 `ready-for-human`；迁移代码前置已由独立 #113 补齐，仍需真实双设备验收和合并。旧 #64 当前保留。
- 新迁移方案合并且覆盖关系核对后，再记录替代关系、关闭 #64 并清理其引用；目前保留来源供移植。

以下为 13:47 UTC 的原始 Dependabot 检查快照；后续已定位原因并逐项处理，当前结论以 [维护记录](DEPENDENCY_MAINTENANCE.md) 为准：

| 现有检查结果 | PR | 待处理 |
|--------------|----|--------|
| 列出的检查通过 | #101、#102、#103、#110 | 审核兼容性及范围，按当时 head 重新确认检查后分别处理 |
| Quality gate 失败 | #100 | 定位质量检查失败原因 |
| Android debug / emulator integration 失败 | #104 | 定位 Android 构建与集成失败原因 |
| 列出的检查均失败 | #105–#109 | 逐项定位依赖解析/工具链/代码或检查原因，不预断根因 |

列表见 [开放依赖 PR](https://github.com/CCreative-Od1L/project_sw/pulls?q=is%3Apr+is%3Aopen+author%3Aapp%2Fdependabot)。依赖维护独立于功能整合，不要求先合并全部更新才发布；若发现影响当前锁定版本的实际漏洞或兼容问题，再调整优先级。

## 建议推进顺序

1. W01 和 A02/A03 已交付；W02 在 #113 等待设备验收与合并。W03 的恢复/表单补证和 W08 发布配置可独立推进。
2. 每条代码任务经独立 PR 进入共同主干，再把需要的公共变更同步到其他任务；擦除、迁移的最终平台联调分别等待对应实现。W04/W06 可先记录当前已接入流程的结果。
3. 在选定的整合提交完成 W04–W07，补齐 #49–#52 的证据与状态；依赖维护分批处理，#64 按替代关系收敛。
4. 代码/验收/发布配置齐备后推进 W12，完成 #53 与总任务 #47 的交付判断。

当前不再安排共同基线收敛或重复清理旧分支；iOS 软件发布、桌面/Web、云同步、商店分发、可配置超时和可靠清除系统剪贴板均不加入本次 Android v1.0 门禁。

## W11：本轮处理结果

依赖已按 #106 → #107 → #104 → #105/#109/#108 顺序修复或确认前置。三项 SDK 约束已在临时目录复现，后续由 [#114](https://github.com/CCreative-Od1L/project_sw/issues/114) 接续；对应精确版本暂缓规则与原 PR 处置见 [维护记录](DEPENDENCY_MAINTENANCE.md)。
