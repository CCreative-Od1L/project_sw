# 构建路线图 · PROJECT_SW

> 本文档定义从空仓库到生产级产品的分阶段构建路径。每个版本定义目标、前置依赖、交付物与验收标准。
> v0.1(tracer bullet)展开到任务级,v0.5 与 v1.0 保持里程碑级(在 v0.1 验证通过后细化)。

## 版本概览

| 版本 | 定位 | 核心交付 |
|------|------|---------|
| v0.1 | tracer bullet | crypto + vault_file + auth(主密码)+ vault CRUD 端到端切片 |
| v0.5 | 可用 MVP | 完整 UI、密码生成器、本地搜索、锁定/超时/数据卫生、i18n |
| v1.0 | 完整版 | 生物解锁、局域网迁移、忘码恢复/死锁擦除、设置页、CI/CD 全流程 |

---

## v0.1 — Tracer Bullet(端到端骨架)

**目标**:验证加密架构可行性的最小闭环——建库 → 解锁 → 加一条目 → 锁定 → 重解锁。无生物、无迁移、无搜索。最简 UI(输入框 + 按钮)。

**前置依赖**:无(空仓库起点)。

### Phase 0:项目骨架

- `fvm flutter create . --org <org> --platforms=ios,android`
- 按 ARCHITECTURE.md §5 建立目录骨架:`lib/features/{auth,vault,generator,search,migration,settings}`、`lib/core/{crypto,vault_file,observability,config}`、`lib/shared/{entities,value_objects,errors}`、`lib/app/`
- `pubspec.yaml` 应用骨架依赖:`get_it`、`go_router`、`flutter_bloc`、`intl`、`path_provider`、`test`、`sodium`;`sodium` 是 libsodium 的 Dart/Flutter 绑定,原生库由 Flutter build hooks 处理
- `analysis_options.yaml`(严格档,DEVELOPMENT.md §4)
- LICENSE(MIT)

**验收**:目录结构存在,`fvm flutter pub get` 通过,`fvm dart analyze` 零 warning。

### Phase 1:基础设施(core 层,无业务逻辑)

- **1a. shared/errors**:领域异常体系——`VaultException` 基类 + `VaultLockedException`、`InvalidMasterPasswordException`、`VaultCorruptedException`、`VaultIoException`、`CryptoInitializationException`、`EntropyUnavailableException`、`InvalidArgumentException`
- **1b. core/observability**:`Logger`/`EventTracker`/`MetricsRecorder` 接口 + 便利方法 + `RedactionFilter` + 文件日志实现(路径、滚动、生产/开发切换,见 [observability.md](observability.md))
- **1c. core/config**:最小 config 抽象——固定默认值 readonly(Argon2id 参数、超时值、日志路径)
- **1d. core/crypto**:`CryptoService` 接口(`deriveKek`、`generateKey`、`randombytes`、`encryptWithAead`、`decryptWithAead`)+ `SodiumCryptoService` 适配实现;包裹/解包由 data 层通过 `AadBuilder + encryptWithAead/decryptWithAead` 编排(见 [ADR-0005](../adr/0005-cryptoservice-interface-and-aad-builder.md));Argon2id 与批量解密均使用 [ADR-0003](../adr/0003-isolate-offload-for-cpu-intensive-operations.md) 已选定的短生命周期 `Isolate.run()` 路径
 - **1d-spike(已完成)**:#14 已在 Redmi Note 9 Pro 上使用 30 个短生命周期 `Isolate.run()` 样本验证 `sodium` 初始化与 `randombytes`:全部样本有效,初始化 P95 `≤100ms`。因此 `CryptoService` 的 Argon2id 与后续批量解密采用此路径。长驻 crypto worker isolate 与主 isolate 受限 fallback 保留为未达标或不可用时的既定替代策略,不作为当前实现路线。
  - **错误模型**:遵循 [ADR-0009](../adr/0009-error-model-and-result-boundary.md) 的混合模型——repository 公开边界以项目内领域异常为主,use case 仅对少量预期业务失败返回 `Result`。
    - `CryptoService` / `vault_file` 不直接暴露产品语义失败,只抛原语/存储层异常,由 repository 收束。
    - `UnlockVault` 吸收 `InvalidMasterPasswordException` 并返回 `UnlockFailure.invalidMasterPassword`;其余异常继续上抛。
    - 项目内 `Result` 采用自定义最小 sealed 抽象,不引入第三方 Result 库。
 - **1e. app/**:DI 容器初始化(get_it 全局单例容器 + 构造函数注入混合)+ GoRouter 路由骨架(redirect 守卫,状态机映射见 [ADR-0004](../adr/0004-routing-with-gorouter.md));按 [ADR-0010](../adr/0010-global-session-source-of-truth-and-step-up-auth.md) 装配全局 `SessionController` / `SessionCoordinator` 作为会话真相源(实现归属 `features/auth`,`app/` 只负责装配与适配器接线)
   - **DI 模式**:全局单例容器(`GetIt.instance`)+ 构造函数注入。实现类通过构造函数接收依赖实例,保持模块边界清晰;但实现类本身从容器获取。测试时每个用例开头 `GetIt.instance.reset()` + 注册测试替身保证隔离。

**验收**:core 层单元测试通过(crypto 往返 encrypt→decrypt、RedactionFilter 脱敏、DI 容器解析全部注册项)。

### Phase 2:vault 文件层(依赖 1d)

- **2a.** `core/vault_file` 单文件存储引擎 FileHeader 序列化/反序列化(magic `PSWV`、format_version、kdf_algorithm_id、aead_algorithm_id、kdf_params、kdf_salt、wrapped_master_vault_key、flags、active_directory_offset、entry_count、free_list_head、sequence_counter、**committed_seq**、journal 槽)
- **2b.** Directory + EntryRecord 序列化/反序列化(entry_id、block_offset、block_length、block_capacity、plaintext_format_id、flags、seq)
- **2c.** Entry Block 双段读写(dek_wrapped 定长 72B + entry_ciphertext 变长,外壳不透明)
- **2d.** free list 分配/释放(自链节点、capacity 匹配、分裂、append EOF)
- **2e.** journal 机制(单条更新意图 + 目录切换意图;LSN(seq)+ CRC 校验 + 单扇区原子写;committed_seq 作为完成信号;journal 永不主动清零,下次操作覆写;打开时 seq > committed_seq 且 CRC 通过 → 幂等重放或回滚)
- **2f.** 单文件存储引擎 API(`readHeader`、`readDirectory`、`readEntryBlock`、`writeEntryBlock`、`updateDirectory`、`commitOperation`(写 committed_seq + sequence_counter++ 单扇区原子写 + fsync)、`openVaultFile` 含 journal 恢复逻辑(幂等重放/回滚/.bak 回退))
 - **vault 文件存储位置**:经 `path_provider` 的 `getApplicationSupportDirectory()` 获取路径,vault 文件存于 `<appSupport>/vault.psw`(iOS `NSApplicationSupportDirectory` / Android app files 子目录)。选 applicationSupportDirectory 而非 applicationDocumentsDirectory 的理由:iOS 上默认不被 iCloud 备份,与零云依赖原则一致,无需额外设置 `NSURLIsExcludedFromBackupKey`。
 - **File I/O 策略**:使用同步 `RandomAccessFile`(Dart 标准库 `File.openSync`)。选择理由:① journal 流程是严格"写意图 → fsync → 写数据 → fsync → 写 committed_seq → fsync"同步序列,同步 API 直接表达此顺序;② vault 文件通常几 KB~几 MB,单次 I/O 操作耗时微秒~毫秒级,同步阻塞对 UI 影响可忽略;③ 跨平台一致性(Dart 标准库在 iOS/Android/Linux 行为一致)。
   - **性能风险**:同步 I/O 阻塞主 isolate 事件循环。若 vault 文件规模显著增大(数千条目、目录区达数百 KB),连续 fsync 的累计耗时可能在低端设备上产生感知卡顿。届时需评估:① 减少 fsync 频率(合并多个写入后再 flush,但需重新论证 journal 安全性);② 将文件 I/O 也迁到 ADR-0003 所定义的后台执行机制中(优先 isolate 路线,但增加复杂度)。当前个人库规模下不触发。

**验收**:vault_file 单元测试通过(序列化往返、free list 分配/释放/分裂、journal 写入/幂等重放/回滚/committed_seq 判断/CRC 损坏检测→.bak 回退、逐字段损坏验证 AEAD tag 失败、File Header 写入对齐到扇区边界)。

### Phase 3:auth 业务线(依赖 1d, 2a)

- **3a. features/auth/domain**:`VaultHeader` 实体;`CreateVault`、`UnlockVault`、`LockVault` use cases;`VaultRepository` 接口(读 header、批量解密条目并提取摘要、锁定清零)
  - **Argon2id 自适应基准测试协议**:首次建库时在目标设备运行基准测试,在目标延迟内选取最高安全档位。
    - **参数档位**(从低到高):最低档 m=19MiB/t=2/p=1(预估~50ms)、低档 m=32MiB/t=2/p=1(~100ms)、中档 m=48MiB/t=3/p=1(~200ms)、高档 m=64MiB/t=3/p=1(~300ms)、最高档 m=96MiB/t=4/p=1(~500ms)
    - **测试协议**:从最低档开始,每组跑 3 次取中位数(避免单次抖动);如果中位数 ≤ 目标延迟(默认 1s),尝试下一档;如果中位数 > 目标延迟,停止并选用上一档;如果最低档也超时,使用最低档并警告用户"设备性能不足,解锁可能较慢"
    - **UI 状态**:建库时显示"正在优化安全参数..."进度提示;基准测试期间禁用"取消"按钮(避免中断导致部分写入);完成后显示实际选用的参数档位
    - **v0.1 实测校准(已完成)**:Xiaomi M2007J17C(Android 12) 上各档中位数为 19MiB/t=2:65ms、32MiB/t=2:95ms、48MiB/t=3:207ms、64MiB/t=3:280ms、96MiB/t=4:554ms;均在默认 1s 阈值内,选择最高档 96MiB/t=4/p=1。64MiB/t=3 的 280ms 验证 SECURITY.md §3 的 250–400ms 假设。该数据仅为设备基线,首次建库仍执行自适应基准。
- **3b. features/auth/data**:`EncryptedVaultDataSource` 实现(调用 vault_file API + CryptoService);`VaultRepository` 实现(编排:读 header → 通过 ADR-0003 的后台机制执行 `deriveKek` → 解包 MVK → 通过同一后台机制批量解密条目并提取摘要模型)
  - **批量解密数据流(路径 A)**:主 isolate 预读全部 Entry Block 原始字节 + MVK + header 参数,再交给 ADR-0003 选定的后台执行机制;后台上下文内完成 AAD 组装 + 解包 DEK + 解密明文 + JSON 反序列化,随后仅提取 `entry_id/name/url/username/favorite/created_at/updated_at` 摘要字段返回摘要集合。后台执行上下文不碰文件 I/O,只做纯计算;完整 `VaultEntry` 明文不进入解锁态全局常驻内存(见 [ADR-0007](../adr/0007-unlocked-residency-and-summary-detail-split.md))。
  - **性能风险**:若采用 isolate 路线,全部密文字节经 message port 深拷贝(主 isolate → 后台执行上下文),双份内存占用。个人库规模(几百条 × ~1KB ≈ 几百 KB)下可接受;若库规模显著增大(数千条或单条明文很大),深拷贝开销和内存峰值可能成为瓶颈,届时需评估分批处理或长驻 crypto worker isolate 逐条返回。
- **3c. features/auth/presentation**:`AuthCubit` 作为会话真相源的 UI 投影层(不自持状态机规则) + 最简解锁页 UI(主密码输入 + 解锁按钮 + 建库引导)。错误主密码消费 `UnlockFailure.invalidMasterPassword`;库损坏/I/O/crypto 初始化失败进入故障态而非普通表单错误。

**验收**:auth 单元测试通过(`CreateVault` 生成合法 header、`UnlockVault` 正确密码解锁/错误密码失败、`LockVault` 清零 KEK/MVK/DEK);集成测试可驱动 AuthCubit 状态转换。

### Phase 4:vault 业务线(依赖 2f, 3b)

- **4a. features/vault/domain**:`VaultEntry` 实体(entry_id、name、url、username、password、notes、created_at、updated_at、favorite、custom_fields);`EntryId` 值对象;解锁态摘要模型(`EntrySummary` 或等价命名,字段范围见 ADR-0007)
- **4b. features/vault/domain**:`AddEntry`、`UpdateEntry`、`DeleteEntry`、`GetAllEntriesSummary`、`GetEntryDetail` use cases;`EntryRepository` 接口
- **4c. features/vault/data**:`EntryRepository` 实现(编排:生成 DEK → AEAD 加密条目明文 → MVK 包裹 DEK → 写 Entry Block 双段 → 更新 Directory → `commitOperation`(写 committed_seq + sequence_counter++ 单扇区原子写 + fsync);seq 递增从 header sequence_counter 取值)
- **4d. features/vault/presentation**:`VaultCubit`(摘要列表 state) + 最简 UI(条目列表 + 添加条目表单 + 条目详情);条目列表只依赖摘要模型,进入详情页后按需解密单条完整详情对象,退出详情页即清理

**验收**:vault 单元测试通过(AddEntry 写入后 GetAllEntriesSummary 读回摘要一致、GetEntryDetail 可按需解出完整单条详情、UpdateEntry seq 递增、DeleteEntry 槽入 free list);信封加密往返(明文→加密→落盘→读取→解密→明文一致)。

### Phase 5:端到端集成测试(依赖全部)

- **5a.** 集成测试:建库(输入主密码 + Argon2id 基准)→ 解锁(主密码)→ 加一条目 → 锁定 → 重解锁 → 验证条目存在且明文一致
- **5b.** 单元测试补全:crypto 往返(已知向量 + 随机往返)、vault_file 边界(空库、单条、多条、capacity 溢出分配新槽)、journal 崩溃场景(各阶段崩溃 → openVaultFile 幂等重放/回滚;committed_seq 原子写中断 → 重放不丢数据;CRC 撕裂 → .bak 回退;stale journal seq <= committed_seq → 正确忽略)
- **5c.** 验收清单全绿:`fvm dart format --set-exit-if-changed .` + `fvm dart analyze` + `fvm flutter test` + `fvm flutter test integration_test/`

**v0.1 整体验收标准**:
1. 端到端流程可运行:建库 → 解锁 → CRUD → 锁定 → 重解锁,明文一致
2. 密钥材料(KEK/MVK/DEK)为 `Uint8List`,使用后显式清零(ADR-0002)
3. Argon2id 派生与批量解密遵循 ADR-0003 的后台执行策略,不阻塞 UI 主执行路径
4. 全部日志经 observability 管道,无裸 `print`,敏感字段被 RedactionFilter 脱敏
5. 路由守卫正确:未建库 → `/setup`,锁定 → `/unlock`,解锁 → `/home`
6. journal 崩溃恢复:模拟 seq > committed_seq 且 CRC 通过 → 幂等重放;CRC 失败 → .bak 回退;committed_seq 写入中断 → 重放不丢数据
7. `fvm dart analyze` 零 warning,`fvm flutter test` 全绿

> **v0.1 不含**:生物解锁、SecureStorageDataSource、局域网迁移、本地搜索、密码生成器 UI、忘码恢复、死锁擦除、i18n、设置页、CI/CD workflow 文件。

> **v0.1 实测校准(已完成)**:在 Xiaomi M2007J17C(Android 12) 上,Argon2id m=64MiB/t=3 的 3 次中位数为 280ms,验证 SECURITY.md §3 的 250–400ms 假设;全部五档均在 1s 内,选中 96MiB/t=4/p=1。详情见 SECURITY.md §3.1。这项基准独立于 #14 已完成的 `sodium` 短生命周期 isolate 初始化验证。
> **v0.1 已选路径**:#14 已在 Redmi Note 9 Pro 上完成 30 次 `sodium` 短生命周期 isolate 验证,全部样本有效且初始化 P95 `≤100ms`;Argon2id 与批量解密采用 `Isolate.run()`。若未来环境不达标或不可用,按 ADR-0003 切换到长驻 crypto worker isolate,再不行才使用主 isolate 受限 fallback。

---

## v0.5 — 可用 MVP

**目标**:在 v0.1 骨架上补全面向用户的功能,使产品可日常使用。仅主密码路径,无生物、无迁移。

**前置依赖**:v0.1 全部验收标准通过。

### 里程碑

- **完整 UI 体系**:正式主题(深色/浅色)、组件规范(按钮、列表项、对话框、表单)、导航结构(底部导航栏 + ShellRoute 嵌套);UI 设计 token 定义
- **i18n 挂载**:ARB 骨架(`app_en.arb` / `app_zh.arb`)+ `flutter gen-l10n` 配置 + key 命名规范;所有 UI 文字走 l10n key
- **密码生成器**:`features/generator` 全链——`GenerationProfile` 实体、`GeneratePassword` use case(随机/可发音模式、字符集、无偏抽样、理论熵估算)、生成器 UI(模式切换、长度滑块、字符集 toggle、强度指示器);锁定态可独立使用;生成输出可复制到系统剪贴板。应用侧固定时限自动清除暂不纳入 v0.5,待平台专项方案确定后再规划
- **本地搜索**:`features/search` 全链——`SearchEntries` use case(基于解锁态摘要模型的内存内线性检索、子串+大小写不敏感、字段卫生);搜索 UI(搜索栏 + 结果列表精简展示)。常规搜索仅覆盖 `name/url/username` 与 `favorite` 过滤,不搜索 `notes`、`custom_fields`、`password`(见 [ADR-0007](../adr/0007-unlocked-residency-and-summary-detail-split.md))
- **锁定与超时**:`features/auth` 扩展——按 ADR-0010 的会话真相源模型实现空闲超时 5min、切后台立即锁、主动锁定;`WidgetsBindingObserver` 仅作 lifecycle adapter;idle timer 归会话真相源统一管理;锁定时清零全部内存明文与密钥
- **数据卫生**:`core/observability` 扩展——内存清零策略落地,并明确剪贴板的系统平台边界;应用侧固定时限自动清除暂缓
- **设置页(只读)**:`features/settings` 最小版——锁定策略与 Argon2id 参数展示(只读,标注"未来可配置")

**验收标准**:
1. 用户可完成完整日常流程:解锁 → 搜索/浏览摘要条目 → 进入详情页按需查看单条详情 → 添加条目(含生成密码)→ 复制密码→ 锁定
2. 切后台立即锁,回前台须重新解锁
3. 中英文切换正确
4. 密码生成器在锁定态可独立使用,输出可复制到系统剪贴板
5. 搜索结果不暴露 `password` / `notes` / `custom_fields` / `secret` 字段,详情页退出后完整详情对象不残留在全局状态
6. `fvm dart analyze` 零 warning,`fvm flutter test` + 集成测试全绿

> v0.5 任务级分解在 v0.1 验收通过后细化。

---

## v1.0 — 完整版

**目标**:README 承诺的完整功能集 + 工程化闭环。

**前置依赖**:v0.5 全部验收标准通过。

### 里程碑

- **生物解锁**:`SecureStorageDataSource` 实现(Keychain/Keystore);K_bio 生成与门控;biometric_wrapped_mvk 存取;生物解锁/失效/重设全链;认证强度策略(冷启动允许已配置生物并保留主密码回退、高敏操作枚举、便捷档/强制档);高敏操作经会话真相源触发 step-up challenge 并将当前会话升级到 `master_password`;平台权限管理(`USE_BIOMETRIC`、`NSFaceIDUsageDescription`)
- **局域网迁移**:`features/migration` 全链——二维码配对、crypto_kx 握手、版本/算法匹配、逐条重包裹、seq 透传、entry_id 冲突覆盖、transcript MAC、目录双写原子提交;平台权限(`CAMERA`、`NSCameraUsageDescription`、`NSLocalNetworkUsageDescription`);迁移期间超时抑制
- **忘码恢复与死锁擦除**:忘码恢复通道(改密码错 ≥3 次浮现、一周冷却、二次生物确认、salt 重生);死锁擦除(特定手势浮现、四重摩擦、延迟倒计时);擦除覆盖(库文件、.bak、journal、日志、Keychain/Keystore)
- **完整状态机**:lock_and_recovery.md §5 的 12 状态全部实现,由 ADR-0010 所定义的全局会话真相源统一驱动,含 S5 生物失效、S6/S7 冷却期、S9/S10 迁移状态、S11 擦除
- **设置页(可配置预留)**:会话超时参数当前固定值展示(标注"未来可配置");剪贴板自动清除待平台专项方案确定
- **CI/CD 落地**:按 [ci_cd.md §12](ci_cd.md) 里程碑——`ci.yml`(PR 检查)、`build.yml`(产物)、`release.yml`(tag/version/CHANGELOG preflight,后续接签名发版)、`scheduled.yml`(依赖审计);`scripts/build_android.sh`、`scripts/build_ios.sh`;master 分支保护配置;签名 secret 配置
- **CHANGELOG.md**:初始化,记录 v1.0 用户可见变化

**验收标准**:
1. 生物解锁全路径可用(设置、解锁、失效回退、高敏强制主密码)
2. 两台设备间可完成局域网迁移,迁移后条目明文一致,entry_id 冲突按 updated_at 覆盖
3. 忘码恢复通道四重门槛正确,冷却期生效
4. 死锁擦除四重摩擦正确,擦除后 Keychain 清除验证
5. CI:PR 必过 `ci.yml`,tag 触发 `release.yml` 构建签名产物并创建 GitHub Release
6. `fvm dart analyze` 零 warning,`fvm flutter test` + 集成测试全绿
7. 任一历史 tag 可重新构建

> v1.0 任务级分解在 v0.5 验收通过后细化。

---

## 后续版本(v1.1+,预留)

- 超时参数用户可配置(空闲 1/5/15/30min、切后台延迟档)
- 平台原生剪贴板生命周期方案(含清除语义、后台生命周期、各厂商自研剪贴板和第三方输入法剪贴板历史)评估完成后,再决定是否提供应用侧自动清除及其可配置时限
- CBOR 内层格式(plaintext_format_id=2)
- 桌面/Web 平台扩展
- 分发渠道接入(Firebase App Distribution / TestFlight / 商店)

## 假设与约束

- 路线图基于当前文档体系(ARCHITECTURE/SECURITY/DEVELOPMENT + specs + ADR-0001~0004),新决策产生新 ADR 时路线图相应调整
- v0.1 的 Argon2id 耗时已在 Xiaomi M2007J17C(Android 12) 上完成基线实测(SECURITY.md §3.1);其他设备仍由首次建库时的自适应基准选择参数,这不影响已验证的 `sodium` 短生命周期 isolate 执行路径
- v0.5 与 v1.0 的里程碑级描述保留弹性,任务级分解在对应前置版本验收通过后进行,避免过早规划未验证的假设
> Infra 组件(DI、observability、路由、错误体系)在 v0.1 Phase 0-1 就位,作为后续所有版本的地基
