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
- **1e. app/**:DI 容器初始化(get_it 注册所有接口→实现)+ GoRouter 路由骨架(redirect 守卫,状态机映射见 [ADR-0004](../adr/0004-routing-with-gorouter.md))

**验收**:core 层单元测试通过(crypto 往返 encrypt→decrypt、RedactionFilter 脱敏、DI 容器解析全部注册项)。

### Phase 2:vault 文件层(依赖 1d)

- **2a.** `core/vault_file` FileHeader 序列化/反序列化(magic `PSWV`、format_version、kdf_algorithm_id、aead_algorithm_id、kdf_params、kdf_salt、wrapped_master_vault_key、flags、active_directory_offset、entry_count、free_list_head、sequence_counter、journal 槽)
- **2b.** Directory + EntryRecord 序列化/反序列化(entry_id、block_offset、block_length、block_capacity、plaintext_format_id、flags、seq)
- **2c.** Entry Block 双段读写(dek_wrapped 定长 72B + entry_ciphertext 变长,外壳不透明)
- **2d.** free list 分配/释放(自链节点、capacity 匹配、分裂、append EOF)
- **2e.** journal(单条更新意图 + 目录切换意图,写入后清零、打开时重放/回滚)
- **2f.** 完整文件读写 API(`readHeader`、`readDirectory`、`readEntryBlock`、`writeEntryBlock`、`updateDirectory`、`commitJournal`、`openVaultFile` 含 journal 恢复逻辑)

**验收**:vault_file 单元测试通过(序列化往返、free list 分配/释放/分裂、journal 写入/重放/回滚/损坏检测、逐字段损坏验证 AEAD tag 失败)。

### Phase 3:auth 业务线(依赖 1d, 2a)

- **3a. features/auth/domain**:`VaultHeader` 实体;`CreateVault`、`UnlockVault`、`LockVault` use cases;`VaultRepository` 接口(读 header、批量解密条目、锁定清零)
- **3b. features/auth/data**:`EncryptedVaultDataSource` 实现(调用 vault_file API + CryptoService);`VaultRepository` 实现(编排:读 header → `Isolate.run(deriveKek)` → 解包 MVK → `Isolate.run(批量解密条目)`)
- **3c. features/auth/presentation**:`AuthCubit`(状态用 sealed class:`Uninitialized` / `Locked` / `Unlocked`,后续版本扩展子类)+ 最简解锁页 UI(主密码输入 + 解锁按钮 + 建库引导)

**验收**:auth 单元测试通过(`CreateVault` 生成合法 header、`UnlockVault` 正确密码解锁/错误密码失败、`LockVault` 清零 KEK/MVK/DEK);集成测试可驱动 AuthCubit 状态转换。

### Phase 4:vault 业务线(依赖 2f, 3b)

- **4a. features/vault/domain**:`VaultEntry` 实体(entry_id、name、url、username、password、notes、created_at、updated_at、favorite、custom_fields);`EntryId` 值对象
- **4b. features/vault/domain**:`AddEntry`、`UpdateEntry`、`DeleteEntry`、`GetAllEntries` use cases;`EntryRepository` 接口
- **4c. features/vault/data**:`EntryRepository` 实现(编排:生成 DEK → AEAD 加密条目明文 → MVK 包裹 DEK → 写 Entry Block 双段 → 更新 Directory → commit journal;seq 递增从 header sequence_counter 取值)
- **4d. features/vault/presentation**:`VaultCubit`(条目列表 state)+ 最简 UI(条目列表 + 添加条目表单 + 条目详情)

**验收**:vault 单元测试通过(AddEntry 写入后 GetAllEntries 读回一致、UpdateEntry seq 递增、DeleteEntry 槽入 free list);信封加密往返(明文→加密→落盘→读取→解密→明文一致)。

### Phase 5:端到端集成测试(依赖全部)

- **5a.** 集成测试:建库(输入主密码 + Argon2id 基准)→ 解锁(主密码)→ 加一条目 → 锁定 → 重解锁 → 验证条目存在且明文一致
- **5b.** 单元测试补全:crypto 往返(已知向量 + 随机往返)、vault_file 边界(空库、单条、多条、capacity 溢出分配新槽)、journal 崩溃场景(写入中途模拟损坏 → openVaultFile 恢复)
- **5c.** 验收清单全绿:`dart format --set-exit-if-changed .` + `dart analyze` + `flutter test` + `flutter test integration_test/`

**v0.1 整体验收标准**:
1. 端到端流程可运行:建库 → 解锁 → CRUD → 锁定 → 重解锁,明文一致
2. 密钥材料(KEK/MVK/DEK)为 `Uint8List`,使用后显式清零(ADR-0002)
3. Argon2id 派生与批量解密经 `Isolate.run` offload,UI 不阻塞(ADR-0003)
4. 全部日志经 observability 管道,无裸 `print`,敏感字段被 RedactionFilter 脱敏
5. 路由守卫正确:未建库 → `/setup`,锁定 → `/unlock`,解锁 → `/home`
6. journal 崩溃恢复:模拟中途崩溃,openVaultFile 正确重放或回滚
7. `dart analyze` 零 warning,`flutter test` 全绿

> **v0.1 不含**:生物解锁、SecureStorageDataSource、局域网迁移、本地搜索、密码生成器 UI、忘码恢复、死锁擦除、i18n、设置页、CI/CD workflow 文件。

> **v0.1 实测校准**:Argon2id m=64MiB/t=3 在目标设备(或模拟器)上的真实耗时须在此阶段测量,据实测数据校准 SECURITY.md §3 的 250–400ms 假设与自适应基准的默认延迟上限(当前 1s)。

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
