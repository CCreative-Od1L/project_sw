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

- `flutter create . --org <org> --platforms=ios,android`
- 按 ARCHITECTURE.md §5 建立目录骨架:`lib/features/{auth,vault,generator,search,migration,settings}`、`lib/core/{crypto,vault_file,observability,config}`、`lib/shared/{entities,value_objects,errors}`、`lib/app/`
- `pubspec.yaml` 依赖:`sodium_libs`、`get_it`、`go_router`、`flutter_bloc`、`intl`、`path_provider`、`test`
- `analysis_options.yaml`(严格档,DEVELOPMENT.md §4)
- LICENSE(MIT)

**验收**:目录结构存在,`flutter pub get` 通过,`dart analyze` 零 warning。

### Phase 1:基础设施(core 层,无业务逻辑)

- **1a. shared/errors**:领域异常体系——`VaultException` 基类 + `VaultLockedException`、`DecryptionFailureException`、`VaultCorruptedException`、`KdfParameterException`
- **1b. core/observability**:`Logger`/`EventTracker`/`MetricsRecorder` 接口 + 便利方法 + `RedactionFilter` + 文件日志实现(路径、滚动、生产/开发切换,见 [observability.md](observability.md))
- **1c. core/config**:最小 config 抽象——固定默认值 readonly(Argon2id 参数、超时值、日志路径)
- **1d. core/crypto**:`CryptoService` 接口(`deriveKek`、`aeadEncrypt`、`aeadDecrypt`、`randombytes`、`wrapKey`、`unwrapKey`)+ `SodiumCryptoService` 适配实现;`deriveKek` 经 `Isolate.run` offload(见 [ADR-0003](../adr/0003-isolate-offload-for-cpu-intensive-operations.md))
 - **1d-spike(sodium isolate 验证)**:**Phase 1d 第一步**。在 `Isolate.run` 内调用 `SodiumLib.init()` + `randombytes` 验证 sodium_libs 跨 isolate 可用性并测量 init 开销。结果三分支: ① init <50ms → 每次 Isolate.run re-init,ADR-0003 不变; ② init 显著(>200ms)→ 改用长驻 isolate(app 启动时 spawn 一次 + init 一次 + 持久复用),触发 ADR-0003 修订; ③ 不可用 → 回退主 isolate 执行 + `await Future.delayed` 让 UI 渲染一次解锁动画再跑 Argon2id,触发 ADR-0003 修订。spike 结果决定后续 1d 实现路径
  - **CryptoService 错误处理**:混合模式——可恢复错误返回 Result 类型,不可恢复错误直接抛异常。
    - **可恢复错误**(返回 Result):AEAD 认证失败(用户输入错误主密码 → 预期业务路径,调用方优雅处理"密码错误"提示)、随机数生成失败(罕见但可重试)。
    - **不可恢复错误**(直接抛异常):参数非法(salt 长度不是 16 字节 → 编程错误,应让开发者修复)、系统熵不足(OS 环境问题,上层决定是否重试或终止)。
    - Result 类型需定义(Dart 标准库无内置,可引入 `result_dart` 或手写 sealed class)。
 - **1e. app/**:DI 容器初始化(get_it 全局单例容器 + 构造函数注入混合)+ GoRouter 路由骨架(redirect 守卫,状态机映射见 [ADR-0004](../adr/0004-routing-with-gorouter.md))
   - **DI 模式**:全局单例容器(`GetIt.instance`)+ 构造函数注入。实现类通过构造函数接收依赖实例,保持模块边界清晰;但实现类本身从容器获取。测试时每个用例开头 `GetIt.instance.reset()` + 注册测试替身保证隔离。

**验收**:core 层单元测试通过(crypto 往返 encrypt→decrypt、RedactionFilter 脱敏、DI 容器解析全部注册项)。

### Phase 2:vault 文件层(依赖 1d)

- **2a.** `core/vault_file` FileHeader 序列化/反序列化(magic `PSWV`、format_version、kdf_algorithm_id、aead_algorithm_id、kdf_params、kdf_salt、wrapped_master_vault_key、flags、active_directory_offset、entry_count、free_list_head、sequence_counter、**committed_seq**、journal 槽)
- **2b.** Directory + EntryRecord 序列化/反序列化(entry_id、block_offset、block_length、block_capacity、plaintext_format_id、flags、seq)
- **2c.** Entry Block 双段读写(dek_wrapped 定长 72B + entry_ciphertext 变长,外壳不透明)
- **2d.** free list 分配/释放(自链节点、capacity 匹配、分裂、append EOF)
- **2e.** journal 机制(单条更新意图 + 目录切换意图;LSN(seq)+ CRC 校验 + 单扇区原子写;committed_seq 作为完成信号;journal 永不主动清零,下次操作覆写;打开时 seq > committed_seq 且 CRC 通过 → 幂等重放或回滚)
- **2f.** 完整文件读写 API(`readHeader`、`readDirectory`、`readEntryBlock`、`writeEntryBlock`、`updateDirectory`、`commitOperation`(写 committed_seq + sequence_counter++ 单扇区原子写 + fsync)、`openVaultFile` 含 journal 恢复逻辑(幂等重放/回滚/.bak 回退))
 - **vault 文件存储位置**:经 `path_provider` 的 `getApplicationSupportDirectory()` 获取路径,vault 文件存于 `<appSupport>/vault.psw`(iOS `NSApplicationSupportDirectory` / Android app files 子目录)。选 applicationSupportDirectory 而非 applicationDocumentsDirectory 的理由:iOS 上默认不被 iCloud 备份,与零云依赖原则一致,无需额外设置 `NSURLIsExcludedFromBackupKey`。
 - **File I/O 策略**:使用同步 `RandomAccessFile`(Dart 标准库 `File.openSync`)。选择理由:① journal 流程是严格"写意图 → fsync → 写数据 → fsync → 写 committed_seq → fsync"同步序列,同步 API 直接表达此顺序;② vault 文件通常几 KB~几 MB,单次 I/O 操作耗时微秒~毫秒级,同步阻塞对 UI 影响可忽略;③ 跨平台一致性(Dart 标准库在 iOS/Android/Linux 行为一致)。
   - **性能风险**:同步 I/O 阻塞主 isolate 事件循环。若 vault 文件规模显著增大(数千条目、目录区达数百 KB),连续 fsync 的累计耗时可能在低端设备上产生感知卡顿。届时需评估:① 减少 fsync 频率(合并多个写入后再 flush,但需重新论证 journal 安全性);② 将文件 I/O 也 offload 到 isolate(与 ADR-0003 一致,但增加复杂度)。当前个人库规模下不触发。

**验收**:vault_file 单元测试通过(序列化往返、free list 分配/释放/分裂、journal 写入/幂等重放/回滚/committed_seq 判断/CRC 损坏检测→.bak 回退、逐字段损坏验证 AEAD tag 失败、File Header 写入对齐到扇区边界)。

### Phase 3:auth 业务线(依赖 1d, 2a)

- **3a. features/auth/domain**:`VaultHeader` 实体;`CreateVault`、`UnlockVault`、`LockVault` use cases;`VaultRepository` 接口(读 header、批量解密条目、锁定清零)
  - **Argon2id 自适应基准测试协议**:首次建库时在目标设备运行基准测试,在目标延迟内选取最高安全档位。
    - **参数档位**(从低到高):最低档 m=19MiB/t=2/p=1(预估~50ms)、低档 m=32MiB/t=2/p=1(~100ms)、中档 m=48MiB/t=3/p=1(~200ms)、高档 m=64MiB/t=3/p=1(~300ms)、最高档 m=96MiB/t=4/p=1(~500ms)
    - **测试协议**:从最低档开始,每组跑 3 次取中位数(避免单次抖动);如果中位数 ≤ 目标延迟(默认 1s),尝试下一档;如果中位数 > 目标延迟,停止并选用上一档;如果最低档也超时,使用最低档并警告用户"设备性能不足,解锁可能较慢"
    - **UI 状态**:建库时显示"正在优化安全参数..."进度提示;基准测试期间禁用"取消"按钮(避免中断导致部分写入);完成后显示实际选用的参数档位
    - **设计假设**:预估耗时基于中端移动设备经验估算,v0.1 实测校准阶段需用真实设备验证各档位耗时,必要时调整档位参数或目标延迟阈值
- **3b. features/auth/data**:`EncryptedVaultDataSource` 实现(调用 vault_file API + CryptoService);`VaultRepository` 实现(编排:读 header → `Isolate.run(deriveKek)` → 解包 MVK → `Isolate.run(批量解密条目)`)
  - **批量解密数据流(路径 A)**:主 isolate 预读全部 Entry Block 原始字节 + MVK + header 参数传入 `Isolate.run`,isolate 内做 AAD 组装 + 解包 DEK + 解密明文 + JSON 反序列化,返回 `List<VaultEntry>`。isolate 内不碰文件 I/O,纯计算。
  - **性能风险**:全部密文字节经 message port 深拷贝(主 isolate → isolate),双份内存占用。个人库规模(几百条 × ~1KB ≈ 几百 KB)下可接受;若库规模显著增大(数千条或单条明文很大),深拷贝开销和内存峰值可能成为瓶颈,届时需评估分批 isolate 或长驻 isolate 逐条返回。
- **3c. features/auth/presentation**:`AuthCubit`(状态用 sealed class:`Uninitialized` / `Locked` / `Unlocked`,后续版本扩展子类)+ 最简解锁页 UI(主密码输入 + 解锁按钮 + 建库引导)

**验收**:auth 单元测试通过(`CreateVault` 生成合法 header、`UnlockVault` 正确密码解锁/错误密码失败、`LockVault` 清零 KEK/MVK/DEK);集成测试可驱动 AuthCubit 状态转换。

### Phase 4:vault 业务线(依赖 2f, 3b)

- **4a. features/vault/domain**:`VaultEntry` 实体(entry_id、name、url、username、password、notes、created_at、updated_at、favorite、custom_fields);`EntryId` 值对象
- **4b. features/vault/domain**:`AddEntry`、`UpdateEntry`、`DeleteEntry`、`GetAllEntries` use cases;`EntryRepository` 接口
- **4c. features/vault/data**:`EntryRepository` 实现(编排:生成 DEK → AEAD 加密条目明文 → MVK 包裹 DEK → 写 Entry Block 双段 → 更新 Directory → `commitOperation`(写 committed_seq + sequence_counter++ 单扇区原子写 + fsync);seq 递增从 header sequence_counter 取值)
- **4d. features/vault/presentation**:`VaultCubit`(条目列表 state)+ 最简 UI(条目列表 + 添加条目表单 + 条目详情)

**验收**:vault 单元测试通过(AddEntry 写入后 GetAllEntries 读回一致、UpdateEntry seq 递增、DeleteEntry 槽入 free list);信封加密往返(明文→加密→落盘→读取→解密→明文一致)。

### Phase 5:端到端集成测试(依赖全部)

- **5a.** 集成测试:建库(输入主密码 + Argon2id 基准)→ 解锁(主密码)→ 加一条目 → 锁定 → 重解锁 → 验证条目存在且明文一致
- **5b.** 单元测试补全:crypto 往返(已知向量 + 随机往返)、vault_file 边界(空库、单条、多条、capacity 溢出分配新槽)、journal 崩溃场景(各阶段崩溃 → openVaultFile 幂等重放/回滚;committed_seq 原子写中断 → 重放不丢数据;CRC 撕裂 → .bak 回退;stale journal seq <= committed_seq → 正确忽略)
- **5c.** 验收清单全绿:`dart format --set-exit-if-changed .` + `dart analyze` + `flutter test` + `flutter test integration_test/`

**v0.1 整体验收标准**:
1. 端到端流程可运行:建库 → 解锁 → CRUD → 锁定 → 重解锁,明文一致
2. 密钥材料(KEK/MVK/DEK)为 `Uint8List`,使用后显式清零(ADR-0002)
3. Argon2id 派生与批量解密经 `Isolate.run` offload,UI 不阻塞(ADR-0003)
4. 全部日志经 observability 管道,无裸 `print`,敏感字段被 RedactionFilter 脱敏
5. 路由守卫正确:未建库 → `/setup`,锁定 → `/unlock`,解锁 → `/home`
6. journal 崩溃恢复:模拟 seq > committed_seq 且 CRC 通过 → 幂等重放;CRC 失败 → .bak 回退;committed_seq 写入中断 → 重放不丢数据
7. `dart analyze` 零 warning,`flutter test` 全绿

> **v0.1 不含**:生物解锁、SecureStorageDataSource、局域网迁移、本地搜索、密码生成器 UI、忘码恢复、死锁擦除、i18n、设置页、CI/CD workflow 文件。

> **v0.1 实测校准**:Argon2id m=64MiB/t=3 在目标设备(或模拟器)上的真实耗时须在此阶段测量,据实测数据校准 SECURITY.md §3 的 250–400ms 假设与自适应基准的默认延迟上限(当前 1s)。
> **v0.1 已知风险**:sodium_libs 跨 isolate 可用性未验证(Phase 1d-spike)。若不可用或 init 开销显著,ADR-0003 的 Isolate.run 方案需修订(改长驻 isolate 或回退主 isolate)。spike 结果在 Phase 1d 第一步产出,决定后续实现路径。

---

## v0.5 — 可用 MVP

**目标**:在 v0.1 骨架上补全面向用户的功能,使产品可日常使用。仅主密码路径,无生物、无迁移。

**前置依赖**:v0.1 全部验收标准通过。

### 里程碑

- **完整 UI 体系**:正式主题(深色/浅色)、组件规范(按钮、列表项、对话框、表单)、导航结构(底部导航栏 + ShellRoute 嵌套);UI 设计 token 定义
- **i18n 挂载**:ARB 骨架(`app_en.arb` / `app_zh.arb`)+ `flutter gen-l10n` 配置 + key 命名规范;所有 UI 文字走 l10n key
- **密码生成器**:`features/generator` 全链——`GenerationProfile` 实体、`GeneratePassword` use case(随机/可发音模式、字符集、无偏抽样、理论熵估算)、生成器 UI(模式切换、长度滑块、字符集 toggle、强度指示器);锁定态可独立使用;生成输出走剪贴板 20s 清除
- **本地搜索**:`features/search` 全链——`SearchEntries` use case(解锁后内存内线性检索、子串+大小写不敏感、字段卫生)、搜索 UI(搜索栏 + 结果列表精简展示)
- **锁定与超时**:`features/auth` 扩展——空闲超时 5min、切后台立即锁、主动锁定;`WidgetsBindingObserver` 生命周期监听;超时计时器;锁定时清零全部内存明文与密钥
- **数据卫生**:`core/observability` 扩展——剪贴板 20s 自动清除 + 倒计时提示 + iOS Handoff 禁用;内存清零策略落地
- **设置页(只读)**:`features/settings` 最小版——超时参数、剪贴板超时、Argon2id 参数展示(只读,标注"未来可配置")

**验收标准**:
1. 用户可完成完整日常流程:解锁 → 搜索/浏览条目 → 添加条目(含生成密码)→ 复制密码(20s 自动清除)→ 锁定
2. 切后台立即锁,回前台须重新解锁
3. 中英文切换正确
4. 密码生成器在锁定态可独立使用,输出复制走 20s 清除
5. 搜索结果不暴露 password / secret 字段
6. `dart analyze` 零 warning,`flutter test` + 集成测试全绿

> v0.5 任务级分解在 v0.1 验收通过后细化。

---

## v1.0 — 完整版

**目标**:README 承诺的完整功能集 + 工程化闭环。

**前置依赖**:v0.5 全部验收标准通过。

### 里程碑

- **生物解锁**:`SecureStorageDataSource` 实现(Keychain/Keystore);K_bio 生成与门控;biometric_wrapped_mvk 存取;生物解锁/失效/重设全链;认证强度策略(冷启动强制主密码、高敏操作枚举、便捷档/强制档);平台权限管理(`USE_BIOMETRIC`、`NSFaceIDUsageDescription`)
- **局域网迁移**:`features/migration` 全链——二维码配对、crypto_kx 握手、版本/算法匹配、逐条重包裹、seq 透传、entry_id 冲突覆盖、transcript MAC、目录双写原子提交;平台权限(`CAMERA`、`NSCameraUsageDescription`、`NSLocalNetworkUsageDescription`);迁移期间超时抑制
- **忘码恢复与死锁擦除**:忘码恢复通道(改密码错 ≥3 次浮现、一周冷却、二次生物确认、salt 重生);死锁擦除(特定手势浮现、四重摩擦、延迟倒计时);擦除覆盖(库文件、.bak、journal、日志、Keychain/Keystore)
- **完整状态机**:lock_and_recovery.md §5 的 12 状态全部实现,含 S5 生物失效、S6/S7 冷却期、S9/S10 迁移状态、S11 擦除
- **设置页(可配置预留)**:超时参数、剪贴板超时当前固定值展示(标注"未来可配置")
- **CI/CD 落地**:按 [ci_cd.md §12](ci_cd.md) 里程碑——`ci.yml`(PR 检查)、`build.yml`(产物)、`release.yml`(签名发版)、`scheduled.yml`(依赖审计);`scripts/build_android.sh`、`scripts/build_ios.sh`;master 分支保护配置;签名 secret 配置
- **CHANGELOG.md**:初始化,记录 v1.0 用户可见变化

**验收标准**:
1. 生物解锁全路径可用(设置、解锁、失效回退、高敏强制主密码)
2. 两台设备间可完成局域网迁移,迁移后条目明文一致,entry_id 冲突按 updated_at 覆盖
3. 忘码恢复通道四重门槛正确,冷却期生效
4. 死锁擦除四重摩擦正确,擦除后 Keychain 清除验证
5. CI:PR 必过 `ci.yml`,tag 触发 `release.yml` 构建签名产物并创建 GitHub Release
6. `dart analyze` 零 warning,`flutter test` + 集成测试全绿
7. 任一历史 tag 可重新构建

> v1.0 任务级分解在 v0.5 验收通过后细化。

---

## 后续版本(v1.1+,预留)

- 超时参数用户可配置(空闲 1/5/15/30min、切后台延迟档)
- 剪贴板清除超时可配置(10/20/30/60s)
- CBOR 内层格式(plaintext_format_id=2)
- 桌面/Web 平台扩展
- 分发渠道接入(Firebase App Distribution / TestFlight / 商店)

## 假设与约束

- 路线图基于当前文档体系(ARCHITECTURE/SECURITY/DEVELOPMENT + specs + ADR-0001~0004),新决策产生新 ADR 时路线图相应调整
- v0.1 的 Argon2id 耗时为待实测假设(SECURITY.md §3),实测结果可能触发参数或默认延迟上限调整
- v0.5 与 v1.0 的里程碑级描述保留弹性,任务级分解在对应前置版本验收通过后进行,避免过早规划未验证的假设
> Infra 组件(DI、observability、路由、错误体系)在 v0.1 Phase 0-1 就位,作为后续所有版本的地基
