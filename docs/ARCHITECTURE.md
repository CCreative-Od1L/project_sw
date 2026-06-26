# 架构设计文档 · PROJECT_SW

> 本文档描述 PROJECT_SW 的系统架构。密码学细节以 [SECURITY.md](./SECURITY.md) 为准,本文只引用其结论。

## 1. 设计原则

1. **Clean Architecture** —— 依赖方向单向向内:presentation → domain ← data。内层(domain)不依赖任何外层框架。
2. **本地优先** —— 所有持久化与加解密在设备本地完成,无网络依赖(局域网迁移为唯一例外,且作为独立 data source 隔离)。
3. **可测试性** —— domain 层为纯 Dart,可脱离 Flutter/平台 SDK 单测;data 层通过接口注入便于 mock。
4. **响应式状态** —— 表现层使用 Cubit/Bloc + State + Pure Signal,UI 为状态的纯函数。
5. **加密方案与实现解耦** —— 密码学操作收敛到一个 `CryptoService` 抽象,底层可替换(`sodium_libs` ↔ 纯 Dart),信封架构不绑死具体库。

## 2. 分层结构

```
┌─────────────────────────────────────────────────────────┐
│  Presentation (表现层)                                   │
│  Widgets · Pages · Cubit/Bloc · State · Pure Signal      │
└──────────────────────────┬──────────────────────────────┘
                           │ 依赖倒置(调用 use case)
┌──────────────────────────▼──────────────────────────────┐
│  Domain (领域层)  —— 纯 Dart,无 Flutter/平台依赖          │
│  Entities · Use Cases · Repository Interfaces            │
└──────────────────────────┬──────────────────────────────┘
                           │ 依赖倒置(实现接口)
┌──────────────────────────▼──────────────────────────────┐
│  Data (数据层)                                            │
│  Repository Implementations · DataSources                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐ │
│  │ EncryptedVault│ │ SecureStorage │ │ LanMigrationDS  │ │
│  │ DataSource    │ │ DataSource    │ │ (网络/传输)      │ │
│  │ (本地加密库)   │ │ (Keychain/    │ │                 │ │
│  │               │ │  Keystore)    │ │                 │ │
│  └──────────────┘ └──────────────┘ └──────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 2.1 Presentation 层
- **Widgets/Pages**:仅负责渲染与事件上报,不持有业务逻辑。
- **Cubit/Bloc**:承接 UI 事件,调用 domain use case,产出 State。
- **State**:不可变值对象,描述某一时刻的界面。
- **Pure Signal**:用于跨组件、跨 Bloc 的细粒度响应式信号(如解锁状态、搜索关键词),避免不必要的重建。

### 2.2 Domain 层
- **Entities**:`VaultEntry`、`VaultMeta`、`VaultHeader`、`GenerationProfile` 等纯数据模型。
- **Use Cases**:`UnlockVault`、`LockVault`、`AddEntry`、`UpdateEntry`、`SearchEntries`、`GeneratePassword`、`MigrateOverLan` 等,封装单一业务用例。
- **Repository Interfaces**:`VaultRepository`、`SecureKeyRepository`、`MigrationRepository` 等抽象,由 data 层实现。

### 2.3 Data 层
- **Repository 实现**:组合多个 DataSource 实现 domain 接口,负责加解密编排。
- **EncryptedVaultDataSource**:负责密码库文件的读写(密文)、序列化格式、版本/头信息管理。
- **SecureStorageDataSource**:封装系统 Keychain/Keystore,存放包裹后的库主密钥(生物解锁路径)。
- **LanMigrationDataSource**:局域网设备发现、握手、传输,独立隔离,默认不启用网络栈。

## 3. 核心模块

| 模块 | 职责 | 关键依赖 |
|------|------|----------|
| `crypto` | KDF(Aargon2id)、AEAD(XChaCha20-Poly1305)、信封加解密、随机数 | `sodium_libs` |
| `vault` | 密码库结构、条目 CRUD、密钥层级包裹/解包 | `crypto`, `data` |
| `biometric` | 生物识别授权、硬件密钥释放 | 平台生物识别 API, `SecureStorageDataSource` |
| `migration` | LAN 设备发现、安全握手、库传输 | 平台网络 API |
| `search` | 本地检索(对加密元数据/索引的安全处理) | `vault` |
| `generator` | 密码生成(规则、强度评估) | 纯 Dart + CSPRNG |
| `i18n` | 中英文资源加载 | `intl` + ARB |
| `observability` | 日志、埋点、监控(见 DEVELOPMENT.md) | 跨层 hook |

## 4. 密钥层级与数据流

完整密码学设计见 [SECURITY.md §密钥层级](./SECURITY.md)。架构层面只强调:加解密编排集中在 data 层的 repository,`CryptoService` 为唯一入口,domain 层只处理明文实体,绝不接触密钥或密文。

**解锁数据流**:

```
用户输入主密码 ──Argon2id──▶ KEK(256-bit,仅内存)
                                │ 解密 vault header
                                ▼
                     Master Vault Key(随机 256-bit)
                                │ 解密每条 DEK
                                ▼
                       DEK_i(随机 256-bit)
                                │ XChaCha20-Poly1305 解密
                                ▼
                        明文 VaultEntry(domain 实体)
```

**生物解锁路径**:首次主密码解锁后,Master Vault Key 经硬件密钥包裹存入 Keychain/Keystore;后续生物识别通过后,由 OS 释放该密钥,跳过 Argon2id 派生环节(详见 SECURITY.md)。

## 5. 项目结构(目标)

```
lib/
  main.dart
  app/                      # 应用入口、路由、主题、i18n 装配
  presentation/
    pages/                  # 各页面
    widgets/                # 可复用组件
    cubits/  blocs/         # 状态管理
    states/  signals/       # State 与 Pure Signal
  domain/
    entities/
    usecases/
    repositories/           # 接口
  data/
    repositories/           # 接口实现
    datasources/
      encrypted_vault/      # 本地加密库读写
      secure_storage/       # Keychain/Keystore 封装
      lan_migration/        # 局域网迁移
    crypto/                 # CryptoService 实现(信封加解密)
  core/
    crypto/                 # CryptoService 抽象 + sodium 适配
    observability/          # 日志/埋点/监控
    i18n/
    config/
test/                       # 单元测试
  domain/ data/ presentation/
integration_test/           # 集成测试
```

## 6. 状态管理约定

- 一个业务域一个 Cubit/Bloc,粒度以"页面或功能域"为单位,避免巨型 Bloc。
- State 为不可变类,变更经 `copyWith`。
- 跨 Bloc 共享状态(如全局解锁态、当前搜索词)走 Pure Signal 订阅,避免层层透传。
- 敏感状态(明文密码、密钥)禁止进入全局可观察状态,仅在受控作用域内短生命周期持有。

## 7. 错误与可观测性

- 错误分层:domain 抛领域异常(`VaultLockedException`、`DecryptionFailureException`),presentation 负责映射为用户可见提示。
- 日志/埋点 hook 集中在 `core/observability`,禁止在 domain 层直接打印明文敏感字段(详见 SECURITY.md §内存与日志卫生)。

## 8. 待决与演进

- 局域网迁移协议细节(设备发现、握手认证)—— 见 SECURITY.md §局域网迁移。
- 本地搜索是否建立加密元数据索引及性能权衡 —— 见 SECURITY.md §本地搜索。
- 密码库文件格式(版本化头 + 条目集合)具体序列化方案待定(JSON/CBOR/自定义二进制),要求支持格式版本迁移。
