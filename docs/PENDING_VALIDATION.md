# 已开发功能的待验证清单

> 复核日期：2026-10-23。共同基线已由 PR #99 交付 `master`（`cf15300`），该基线源码与原候选 `4fa3c7a` 相同，后续功能交付另计；本次已补擦除跨重启保护及安全重试自动化，迁移 UI 旧候选仍为 PR #64 的 `b2c9a79`。下列 9 组主题分别标明自动化已验证、待平台联调、测试待补证及实现/整合缺口，不代表 9 项功能完全未经验证。实现状态见 [当前进度](PROGRESS.md)，工作顺序见 [待工作项](WORK_ITEMS.md)，分支/worktree 归属见 [分支整理记录](BRANCH_ORGANIZATION.md)。

## 验证证据的范围

当前基线已有 270 项 Flutter 测试通过记录，以及成功的 CI、Android 模拟器集成和平台构建记录，链接见 [进度文档](PROGRESS.md#已核验的验证记录)。本文 `[x]` 引用该基线的既有自动化或验收证据；`[ ]` 只列对应层级仍缺的验证。配置、未实现能力和代码整合前提另行说明，不混同于真机验收。

系统剪贴板无法由应用可靠、全面控制，属于既有验证和评估已经确认的能力边界；“20 秒可靠清除”及系统/厂商/输入法副本清除已退出验收要求，见 [ADR-0011](adr/0011-clipboard-cleanup-platform-boundary.md)。本清单不再将系统剪贴板清除效果列为待验证功能或发布门禁；应用自身持有的复制明文、计时器、排队操作与反馈状态清理归入 V07。

当前 `integration_test/` 只有三类场景：Argon2id 校准、sodium isolate 探测，以及使用真实 crypto/文件仓库的建库、CRUD、手动锁定与重解锁。[Vault 集成测试](../integration_test/unlock_vault_flow_test.dart#L22) 直接调用 Cubit/repository，没有挂载完整应用页面；它没有驱动系统生物提示、恢复/擦除 UI、摄像头扫码或真实后台切换。

## 待验证概览

| 编号 | 主题 | 已有验证 | 剩余验证或前置缺口 |
|------|------|----------|--------------------|
| V01 | 常规修改主密码与认证强度升级 | 仓库重包、错误密码不改库、UI 提交及认证升级已有自动化 | Android 生产设置页到重启/生物解锁的完整联调 |
| V02 | 生物辅助忘码恢复 | 门控、弱密码拒绝、取消、MVK 重包与数据保留已有自动化 | 系统二次生物认证与恢复后真实解锁；生物不可用/失效分支的专门测试待补证 |
| V03 | 恢复续接与冷却持久化 | 10 分钟/7 天到期规则、文件原子读写、对象重建加载已验证 | 生产存储路径、真实进程重启和设置页续接联调，无需真机等待 7 天 |
| V04 | 正常认证擦除 | 错误密码拒绝、成功调用、验证中锁定、临时目录删除和本进程失败保锁已验证 | 生产路由成功转场、故障恢复及 marker 重建已有自动化；待真实平台删除和 OS 重启联调 |
| V05 | 死锁擦除 | 手势、确认词、十次倒计时与取消已有自动化 | 故障/重试 UI 与路由已有自动化；待真实入口到平台删除及 OS 重启联调 |
| V06 | 解锁归属与敏感活动中断 | 旧结果隔离、提交 guard、活动和计时器已有确定性测试 | Android 真实生命周期与系统生物提示接线回归 |
| V07 | 页面与应用内复制状态清理 | 详情/弹窗控制器、生成器、复制状态及排队操作已有自动化 | 真实后台/路由清理联调；新建条目表单锁定清空的专门测试待补证 |
| V08 | 扫码配对与完整迁移 | 协议/TCP/仓库测试，以及候选发送页展示/取消测试 | 先补迁移 step-up、更新 lease/guard、生产装配及规格要求的单条选择；再进行双设备验收 |
| V09 | Android 发布与 tag 重建 | 发布脚本/合同测试及临时签名 AAB 构建已验证，本地已有发布链代码 | 配置发布环境/签名与主干保护，再验证真实 tag → Release、干净环境 tag 重建 |

## V01：常规修改主密码

已有仓库测试验证 [只重包 MVK、保留条目与生物 envelope](../test/features/auth/data/encrypted_vault_repository_test.dart#L154)，也有 [设置页 widget 测试](../test/app/settings_page_test.dart#L108)。[PR #70 的进展记录](https://github.com/CCreative-Od1L/project_sw/issues/49#issuecomment-5358934121) 明确后续真机验收仍待完成。

- [x] 新 salt、仅重包 MVK、保留条目密文/生物 envelope、错误密码不改库，以及改密成功后的认证升级已有仓库/Cubit/widget 测试。
- [ ] 在 Android 生产设置页分别由主密码会话、生物会话完成改密，随后锁定或重启，确认新密码、条目读取和真实生物解锁可用，旧密码失效。

改密中断的 guard 已有自动化；真实后台与系统提示的联调统一记录在 V06，不重复作为独立的未验证规则。

## V02：生物辅助忘码恢复

已有 [恢复用例测试](../test/features/auth/domain/recover_master_password_test.dart)、[仓库重包测试](../test/features/auth/data/encrypted_vault_repository_test.dart#L284) 和 [恢复 UI widget 测试](../test/app/settings_page_test.dart#L161)。系统确认器和 UI 测试使用替身；[#51 的最新验收说明](https://github.com/CCreative-Od1L/project_sw/issues/51#issuecomment-5360599079) 仍要求真机生物恢复验收。

- [x] 三次改密失败后浮现入口、接管告知、弱密码拒绝、取消不预约冷却、恢复重包及条目/生物 envelope 保留已有自动化。
- [ ] 从真实恢复页面触发系统第二次生物确认，检查成功、取消和失败的交互；成功后用新密码和真实生物路径重新解锁并读取测试条目，核对冷备同步提醒。

自动化补证：本轮未在恢复用例测试中找到生物不可用/生物失效异常的专门断言。[实现](../lib/features/auth/domain/recovery/recover_master_password.dart#L84) 在预约冷却前处理这些异常；应补充该分支的测试证据，不应直接写成已完成验证。恢复中断统一归 V06，重启后的期限加载归 V03。

## V03：恢复续接窗口与冷却持久化

已有 [门控/时钟测试](../test/features/auth/domain/master_password_recovery_gate_test.dart#L88)，也有使用临时文件、重建 store 实例的 [真实文件读写测试](../test/features/auth/data/file_master_password_recovery_store_test.dart#L20)。这些验证尚未覆盖实际应用进程重启后的完整设置页流程；[#74 进展](https://github.com/CCreative-Od1L/project_sw/issues/51#issuecomment-5360090221) 保留真机验收。

- [x] 10 分钟窗口到期隐藏/重置计数、7 天冷却及到期后重新计错，已有注入时钟测试；文件原子替换、store/gate 重建和 Cubit 加载也有自动化证据。
- [ ] 在生产路径下分别保存可续接窗口和成功恢复后的冷却期限，真实退出并重启应用，再解锁进入设置，确认加载原截止时间，窗口可续接、冷却仍生效。

到期边界接受已有可控时钟测试作为证据，无需在真机上等待 10 分钟或 7 天，也不把修改设备系统时间作为验收前提。

## V04：正常认证擦除

已有 [错误密码/验证中锁定测试](../test/features/auth/domain/authenticated_wipe_vault_test.dart)、[设置页测试](../test/app/settings_page_test.dart#L254) 和 [删除目标测试](../test/features/auth/data/file_vault_wipe_repository_test.dart)。文件测试使用临时目录，平台 key-store 使用替身，不能据此确认真实 Android Keystore 已删除。

- [x] 领域测试已覆盖错误密码不调用擦除、正确密码调用、验证期间锁定中断；临时目录目标删除和当前进程内失败保留 `wipeStarted` 也已有测试。
- [ ] 使用专用测试库，从生产设置页验证错误密码拒绝，以及正确密码提交后真实平台密钥/显式文件目标删除、路由进入首次设置和重新建库。

已补自动化：[路由回归](../test/app/wipe_restart_flow_test.dart) 覆盖正确主密码从设置页提交到首次设置、恢复入口禁用认证、失败后重新确认/重试及观察同一个进行中擦除；[文件回归](../test/features/auth/data/file_vault_wipe_progress_store_test.dart) 覆盖部分目标删除后的启动恢复。

跨重启保护现由独立持久化 marker 与生产启动接线实现；文件/对象重建测试已通过，真实 Android 进程重启仍待验收。不可逆删除开始前的验证中断归 V06；已经开始的擦除按 `WipeVault` 完成/失败语义判断。

## V05：死锁擦除

已有 [手势/确认/计时器单测](../test/features/auth/presentation/deadlock_wipe_cubit_test.dart) 和 [隐藏入口 widget 测试](../test/app/deadlock_wipe_widget_test.dart)。[#51](https://github.com/CCreative-Od1L/project_sw/issues/51#issuecomment-5360599079) 尚未关闭平台删除验收。

- [x] 3 秒内 7 次点击、精确 `DELETE`、十次倒计时完成才调用擦除、取消不调用擦除，已有 Cubit/widget 测试。
- [ ] 使用专用测试库，在真实锁屏页面完成隐藏入口、告知、确认到实际擦除/重建库的用户流程；与 V04 共用的删除后端可共享平台删除证据。

已补自动化：[擦除恢复页面测试](../test/app/wipe_restart_flow_test.dart) 覆盖故障显示、错误确认不执行、重新倒计时后成功及实际进入首次设置。正常锁定时恢复入口不可绕过隐藏手势；跨重启保护与平台验收边界同 V04。

## V06：真实生命周期、解锁归属与敏感活动中断

已有 [后台锁定 widget 测试](../test/app/background_lock_cleanup_test.dart)、[解锁旧结果测试](../test/features/auth/presentation/unlock_cubit_test.dart#L100)、[生物解锁旧结果测试](../test/features/auth/presentation/biometric_unlock_cubit_test.dart#L68) 与 [会话活动测试](../test/features/auth/domain/session_controller_test.dart#L210)。它们使用模拟生命周期事件、可控 Future 和替身；[#52](https://github.com/CCreative-Od1L/project_sw/issues/52#issuecomment-5392062696) 明确保留真机验收。

- [x] 旧密码/生物解锁结果隔离、step-up lease、改密/恢复/CRUD 提交前 guard、活动锁定中断、idle timer 恢复，已有可控 Future、时钟和仓库断言。
- [ ] 在 Android 上驱动真实后台/前台切换与系统生物提示，核对实际 `inactive`/`paused` 事件组合和生产 adapter 接线：系统提示不应被错误当成后台，真正后台返回须保持锁定，重新解锁流程正常。
- [ ] 将上述真实生命周期场景与已接入的高敏页面做联调；只记录实际覆盖的操作。迁移相关场景须待 V08 的实现/整合缺口解决后执行。

精确延迟和旧 Future 返回顺序由确定性自动化验证，不要求在真机上手动重复所有 KDF/CRUD 时序。提交保护的边界是锁定在敏感提交前生效时取消旧操作；已经耐久提交的结果不因随后页面退出而承诺回滚。

## V07：页面与应用内复制状态清理

已有 [跨页面清理 widget 测试](../test/app/cross_entry_sensitive_cleanup_test.dart#L23)、[详情与输入框相关 widget 测试](../test/widget_test.dart)、[详情读取中断测试](../test/features/vault/presentation/vault_entries_cubit_test.dart#L16) 与 [应用内复制状态单测](../test/core/data_hygiene/sensitive_clipboard_test.dart#L104)。后续生命周期回归只验收应用自身可控的状态，不要求系统剪贴板清除成功。

- [x] 详情/改密/认证擦除/step-up 弹窗清理、控制器文本归空、生成器结果清空，以及复制明文/计时器/反馈与在途/排队操作失效，已有 widget/单元断言。
- [ ] 与 V06 共用一次真实后台/路由联调，确认页面和弹窗关闭、返回锁定态，重新进入不恢复旧输入；生成器锁定态仍可使用。这验证生产接线与可见行为，不重复宣称内部对象此前未验证。

自动化补证：新建条目表单有清理实现，但本轮未找到单独断言“输入中锁定后控制器清空”的 widget 测试。应补充该断言或提供现有证据，不以手动观察页面关闭代替。

内存范围遵循 [ADR-0002](adr/0002-sensitive-data-types.md)：密钥缓冲区显式清零、用户字段使用 `String`。既有缓冲区/控制器断言和真机目视均不能证明 Dart/输入法/系统中的全部物理副本被擦除；全物理副本擦除不属于此清单验收目标。

## V08：双设备扫码与迁移闭环

当前本地只有协议/仓库/TCP 底层。PR #64 的候选代码已有发送/接收页、`MobileScanner`、二维码、相机权限与 `NetworkMigrationFlow`。候选的 [页面测试](https://github.com/CCreative-Od1L/project_sw/blob/b2c9a793a0e04a52247b4e22187fbf88c1287480/test/app/migration_page_test.dart#L13) 使用 `FakeMigrationFlow`，只驱动发送页展示和取消；底层 loopback socket 测试不能代替两台设备联网。

开发/整合前提：PR #64 当前尚未接入迁移主密码 step-up，且使用已被当前版本替换的 idle suppression 接口；必须先补接强认证、activity lease/guard、生产装配及单条选择，详见下文缺口。这些属于代码工作，不能描述为“已全部实现，只等两台手机验收”。

前提完成后，剩余的平台验收为：

- [ ] 两台 Android 真机在同一局域网完成相机授权、扫码、配对与真实条目迁移；分别检查权限拒绝、无效/过期二维码、取消及地址不可达。
- [ ] 分别验证全库与单条选择，确认未选择条目不外传；迁移后解锁读取完整条目，检查 `updated_at` 冲突覆盖/跳过、版本与字段保留；生物设置不随迁移转移。
- [ ] 在连接/传输阶段断网、取消或将任一设备切后台；确认不会提交部分导入，旧库仍可读取，会话策略恢复。

验收缺口的直接来源是 [#50 的人工验收要求](https://github.com/CCreative-Od1L/project_sw/issues/50#issuecomment-5226920912)。

## V09：正式 Android 发布与 tag 重建

当前本地已整合 metadata preflight、签名校验/准备脚本、AAB 构建、artifact 汇总及 `gh release create`。已有脚本测试与 [workflow 合同测试](../test/tool/github_release_workflow_test.dart#L6)，后者检查 YAML 文本，没有实际创建 Release。[#53 最新记录](https://github.com/CCreative-Od1L/project_sw/issues/53#issuecomment-5403771353) 证明临时签名 AAB 构建成功，正式签名环境和 tag 演练仍待验收。

- [x] Metadata 正/负路径、签名材料准备、构建脚本、发布 workflow 合同，以及临时签名 AAB 构建已有验证记录。
- [ ] 建立并核验正式 `release` environment、所需 Android signing 配置及主干合并门禁，按 [发布运行手册](RELEASE_RUNBOOK.md) 执行真实 annotated tag 流程。2026-10-23 API 列出的环境为空，`master` 无经典保护且 rulesets 为空，详见 [发布前置](WORK_ITEMS.md#w08w12发布前置与最终证据)。
- [ ] 确认 metadata、Android、publish 三个 job 成功；GitHub Release 的版本说明、`release-metadata.txt` 与 `app-release.aab` 对应同一 tag/commit，并记录 AAB SHA-256。
- [ ] 在干净环境检出该 tag，使用锁定 SDK/依赖重新构建并核对版本、commit、工具链与产物可用性；不能仅凭 metadata 文件存在认定已完成重建，也不默认要求两次 AAB 字节完全相同。

旧发布候选已随 PR #99 交付主干，相关旧 PR 已收敛；正式签名环境和真实发布演练仍待验收。当前 metadata 中的 SHA-256 对象是 `pubspec.lock`；workflow 尚未自动生成 AAB checksum 附件，AAB SHA-256 目前按运行手册人工记录，不能宣称已有自动附件能力。

## 实现/整合缺口（先解决，再验收）

### 迁移主密码门控与会话接口尚未接入

PR #64 的 [发送/接收入口](https://github.com/CCreative-Od1L/project_sw/blob/b2c9a793a0e04a52247b4e22187fbf88c1287480/lib/app/pages/migration_page.dart#L93) 直接调用 flow，没有主密码 challenge；[旧 flow](https://github.com/CCreative-Od1L/project_sw/blob/b2c9a793a0e04a52247b4e22187fbf88c1287480/lib/features/migration/data/migration_flow.dart#L187) 调用 `beginIdleTimeoutSuppression/endIdleTimeoutSuppression`。当前会话 API 已改为 [beginActivity 返回 lease](../lib/features/auth/domain/session/session_controller.dart#L365)，候选旧方法在当前类中不存在。迁移页面、生产装配、step-up 和中断 guard 需要实际更新后，才能验证整合版本。

### 擦除跨进程保护已实现，待真实平台验收

[`FileVaultWipeProgressStore`](../lib/features/auth/data/file_vault_wipe_progress_store.dart) 以独立 marker 的存在表示未完成擦除，包括空文件或中断写入；删除密钥/文件前先写入并 flush，全部目标验证删除后才清除。marker 不属于擦除目标列表。标记写入失败不开始删除，清除失败继续保留擦除锁。

生产启动优先检查 marker，即使主库已删也进入 `Locked(wipeStarted)`；恢复页面不展示密码或生物解锁，只提供明确确认后的继续删除。共用的擦除协调器合并并发请求，界面可观察既有操作而不重复开始删除。

[文件/启动测试](../test/features/auth/data/file_vault_wipe_progress_store_test.dart) 与 [实际路由测试](../test/app/wipe_restart_flow_test.dart) 已覆盖这些路径。真实 Android OS 进程重启及 Keystore 删除仍归 V04/V05，不把重建 store/生产依赖对象等同于设备验收。

### 单条迁移选择未实现

[迁移规格 §1](specs/lan_migration.md#1-安全要求) 要求可选择全库或单条迁移。当前 [`MigrationVaultPort`](../lib/features/migration/domain/migration_transfer.dart#L53) 只有带 guard 的全量导出接口，[仓库导出](../lib/features/auth/data/encrypted_vault_repository.dart#L464) 遍历整个目录，旧候选页面也没有条目选择。该项属于实现缺口，补齐范围选择与导出约束后再验证选择结果，不能将现有全量传输测试视为单条能力证据。

## 已有验收与平台边界

- v0.5 Android MVP 已由负责人确认通过，见 [#36 验收记录](https://github.com/CCreative-Od1L/project_sw/issues/36#issuecomment-5219235132)，不列为首次待验收。
- 生物解锁主路径 #48 已关闭；PR #56 的生物集合失效回退、生物设置 step-up、错误/正确主密码和重新配置已有 [Android P0 真机通过记录](https://github.com/CCreative-Od1L/project_sw/issues/49#issuecomment-5226602271)。V06 要求的是后续活动 guard、竞态与整合版本回归。
- 系统剪贴板可靠清除已确认为平台能力限制，不再重复安排清除效果验收；PR #83 后续回归仅检查应用内复制状态与锁定不受平台失败影响，归 V07。
- iOS 已有原生实现和无签名构建成功记录；#48 的关闭评论未列明 iOS 设备和用例，现有证据不足以推定 iOS 全流程已完成真机验收。iOS 软件发布不在 V1.0 范围内，其平台验证记录单独补充，不纳入 Android 发布门禁。
- 超时参数可配置、CBOR、桌面/Web、商店分发和固定时限剪贴板清除属于后续范围，未作为“已开发待验证”功能列入。

## 验收记录方式

当前本地可先完成 V01–V07 中明确列出的平台联调和自动化补证；V08 先解决迁移实现/整合缺口；V09 的源码已在本地，真实发布取决于正式环境及交付流程就绪。擦除跨重启已有实现，仍须验证真实 OS 重启，不能以一次正常擦除成功替代。

每项通过时记录代码 commit/分支、设备型号/OS、场景、预期与实际结果、日期和证据链接；自动化运行同时记录 run URL。对象重建测试、模拟器集成、真实进程重启和物理设备生物认证分别记录，避免互相代替。早期清单复核只修订文档；本次擦除源码与自动化已更新，迁移缺口继续保留；后续分支整理对同一源码基线重新运行的自动化结果见 [分支整理验证](BRANCH_ORGANIZATION.md#本次验证)，未执行真机操作或发布。
