# 错误模型与 Result 边界

**日期**: 2026-07-12
**状态**: 已接受

## 背景

当前文档体系已经分别明确了:

- `CryptoService` 保持纯密码学原语定位,不吸收 vault 业务语义(见 [ADR-0005](0005-cryptoservice-interface-and-aad-builder.md))
- `core/vault_file` 是底层单文件存储引擎,负责持久化与恢复语义(见 [ADR-0008](0008-vault-persistence-runtime-model.md))
- v0.1 路线图中已经出现“混合模式——可恢复错误返回 Result,不可恢复错误抛异常”的方向,但边界尚未定稿(见 [build_roadmap.md](../specs/build_roadmap.md))

如果不把错误模型正式收口,实现期很容易出现以下漂移:

- 把 `Result` 扩散成跨层统一返回形状,导致 repository、use case、Cubit 全面套壳;
- 让 `CryptoService` 或 `vault_file` 直接暴露“主密码错误”等产品语义,侵蚀分层;
- repository / use case 直接泄漏第三方异常或原始 `FileSystemException`,把外部依赖细节带到上层;
- presentation 为了“好处理”吞掉系统故障,把真实损坏伪装成普通交互失败;
- 可预期业务失败与真实故障在日志里混为一谈,降低排障信噪比。

本 ADR 用于明确:

- 项目的错误分类标准;
- `Result` 的使用范围;
- 异常翻译与收束应发生在哪一层;
- presentation 与 observability 对错误的处理边界;
- 首批 use case 的具体映射表。

## 目标与非目标

### 目标

- 让“预期业务失败”和“系统故障”在接口、状态与日志上清晰分离。
- 保持 core/data/domain/presentation 的语义边界清晰。
- 用最小的 `Result` 能力承载少量交互型失败,而不是把项目改造成全面函数式错误风格。

### 非目标

- 不在本 ADR 中穷举所有未来异常类的最终代码实现。
- 不把每个 use case 都改成 `Result<T, F>`。
- 不引入第三方 `Result` 库或一整套 monad 风格 API。

## 考虑过的选项

### 选项 A:全面 `Result`

- repository、use case、Cubit 等公开接口统一返回 `Result<T, E>`
- 异常仅作为极少数兜底

优点:
- 表面上错误流统一;
- 调用点看起来“不需要 try/catch”。

缺点:
- 会把大量本应视为故障的路径伪装成普通返回值;
- `Result` 在所有层蔓延,接口噪音大;
- 很难保持 use case failure 与底层技术异常的边界。

### 选项 B:全面异常

- 所有失败都通过抛异常传播
- presentation 自行区分哪些是普通失败,哪些是系统故障

优点:
- 接口最简;
- 与 Dart 默认风格一致。

缺点:
- “主密码错误”这类预期业务失败没有显式契约;
- presentation 容易开始猜异常来源;
- UI 测试与状态建模会变脏。

### 选项 C:混合模型

- 少量预期、可恢复、交互型失败使用 `Result`
- repository 主要抛项目内领域异常
- use case 再把其中一小部分稳定映射成专属 failure 类型

优点:
- 兼顾显式业务失败与异常语义;
- 不强迫所有层全面 `Result`;
- 能守住 core 不感知产品语义、presentation 不猜底层细节的边界。

缺点:
- 需要额外写清分类标准与映射表;
- repository / use case 需承担明确的异常收束职责。

## 决定

选择选项 C:采用**混合错误模型**。

### 1. 错误分类标准

只有同时满足以下两个条件,失败才允许建模为 `Result` failure:

1. 这是**正常产品流程中预期会发生**的分支;
2. 调用方对它有**明确、稳定、非异常式**的处理动作。

不满足这两个条件的失败,一律视为异常路径,通过抛异常传播。

因此:

- `Result` 面向**预期业务失败**
- 异常面向**非预期失败、不可恢复失败、系统故障、状态违例、数据损坏**

### 2. `Result` 不是跨层统一返回形状

- 项目**不**采用“所有接口统一返回 `Result<T, E>`”的错误风格。
- 默认接口形态仍然是:
  - 成功返回值
  - 故障抛异常
- 只有显式声明为“交互型预期失败”的 use case 才返回 `Result`。

### 3. 技术现象按产品语义解释

- 错误分类不能只看底层技术现象,必须结合调用语境解释产品语义。
- 同一种技术失败在不同语境下可以落入不同类别。

例如:

- `decryptWithAead` 失败发生在 `UnlockVault` 的 header/MVK 解包语境中,可以解释为“主密码错误”;
- 同样的 AEAD 失败若发生在 `GetEntryDetail` 或 journal 恢复路径中,更接近库损坏、篡改或实现故障,不得解释成“密码错误”。

### 4. 分层责任

#### `core/crypto`

- 只暴露密码学原语语义;
- 不产生“主密码错误”“生物拒绝”之类产品语义;
- 可抛 core/适配层异常,但不得把业务 failure 直接编码到接口里。

#### `core/vault_file`

- 只暴露存储引擎、提交、恢复、损坏语义;
- 不把恢复失败伪装成普通业务失败;
- 不感知 UI 交互语义。

#### repository(data)

- repository 是**技术异常到项目内领域异常**的第一层收束点;
- repository 公开边界以**项目内领域异常**为主,而不是以 `Result` 为主;
- repository 不负责把所有失败都转换为交互型 failure。

#### use case(domain)

- use case 负责识别“哪些领域异常属于本用例的预期业务失败”;
- 只有 use case 才能把这类异常吸收到专属 `Failure` 类型并放入 `Result`;
- 其余异常继续上抛。

#### presentation

- presentation 正常消费 use case 的 `Result` failure;
- 对未被 use case 吸收的异常,只做有限边界处理:
  - 进入故障态 / 错误页 / 全局错误边界
  - 或触发状态修正/路由回退
- presentation 不自行猜测底层异常含义。

### 5. repository 公开边界禁止泄漏第三方/底层异常

repository / use case 的公开边界上,禁止直接泄漏:

- `sodium_libs` 或其他第三方密码学库异常
- 原始 `FileSystemException`
- 任意底层平台/系统异常

这些异常必须在 core 适配层或 repository 中被收束成项目自有异常族。

首批命名方向包括但不限于:

- `InvalidMasterPasswordException`
- `VaultLockedException`
- `VaultCorruptedException`
- `VaultIoException`
- `CryptoInitializationException`
- `EntropyUnavailableException`
- `InvalidArgumentException`

未来可按同一原则补充:

- `BiometricAuthDeclinedException`
- `BiometricUnavailableException`
- `MigrationProtocolException`

### 6. `Result` 的实现约束

- 不引入第三方 `Result` 库;
- 项目内定义最小 sealed `Result<T, F>` 抽象即可;
- 只承载预期业务失败;
- 不在本项目内扩展为全面函数式链式编程范式。

### 7. `Result` 的失败侧不用异常对象

- use case 返回的 `Result` failure 必须是**use case 专属 failure 类型**
- 不直接把异常对象塞进 `Failure`

例如:

- `UnlockVault` 返回 `Result<UnlockedVault, UnlockFailure>`
- `UnlockFailure` 可包含 `invalidMasterPassword`
- 而不是把 `InvalidMasterPasswordException` 直接暴露给 UI

这保证 presentation 消费的是稳定的产品语义,而不是内部控制流细节。

### 8. `Result` 的适用范围

当前明确采用 `Result` 的 use case 范围应当保持很窄。

首批推荐范围:

- `UnlockVault`
- 未来的 `UnlockVaultWithBiometric`
- 未来的 `EnableBiometricUnlock`
- 未来其他少数“用户主动触发且失败需当场正常反馈”的交互型用例

当前明确**不**采用 `Result` 的 use case:

- `CreateVault`
- `LockVault`
- `AddEntry`
- `UpdateEntry`
- `DeleteEntry`
- `GetAllEntriesSummary`
- `GetEntryDetail`

这些用例默认采用:

- 成功返回值
- 故障抛异常

### 9. presentation 不吞掉系统故障

- `UnlockFailure.invalidMasterPassword` 这类显式业务失败,由 UI 作为普通反馈处理;
- `VaultCorruptedException`、`VaultIoException`、`CryptoInitializationException` 等故障不得在 presentation 被伪装成普通业务失败;
- `VaultLockedException` 等状态违例应触发状态修正或路由修正,而不是被降格成表单提示。

### 10. observability 分层

错误与日志必须分成两档:

#### 业务失败

- 指进入 `Result` failure 的预期交互型失败;
- 默认按低噪声处理:
  - 可记 `info` / `warning`
  - 可做计数与埋点
  - 不默认打 `error`

#### 系统故障

- 指未被 use case 吸收、继续上抛的异常;
- 按真正故障处理:
  - 记录 `error` / `fault`
  - 进入诊断与排障路径

两档日志均继续受 observability 与安全文档的脱敏规则约束,不得记录:

- 主密码
- 条目明文
- 密钥材料
- 未筛选的第三方异常敏感上下文

### 11. 首批具体映射表

#### `UnlockVault`

- repository 可抛:
  - `InvalidMasterPasswordException`
  - `VaultCorruptedException`
  - `VaultIoException`
  - `CryptoInitializationException`
  - `EntropyUnavailableException`
- use case 映射:
  - `InvalidMasterPasswordException` → `UnlockFailure.invalidMasterPassword`
- 其余异常:
  - 不进入 `Result`
  - 继续上抛

#### `CreateVault`

- 默认成功返回或异常上抛
- 不返回 `Result`

#### `LockVault`

- 默认成功返回或异常上抛
- 不返回 `Result`

#### `AddEntry` / `UpdateEntry` / `DeleteEntry`

- 默认成功返回或异常上抛
- 不返回 `Result`

#### `GetAllEntriesSummary` / `GetEntryDetail`

- 默认成功返回或异常上抛
- 不返回 `Result`

## 选定理由

1. 混合模型能保留 Dart/Flutter 对异常的自然表达,同时为少数交互型失败提供显式契约。
2. 把异常翻译权放在 repository / use case 边界,能守住 `CryptoService` 与 `vault_file` 的纯底层定位,不违背 ADR-0005 与 ADR-0008 的原意。
3. repository 以领域异常为主、use case 再筛出少量 `Result` failure,比“所有层统一 Result”更稳健。
4. 用 use case 专属 failure 类型替代异常对象,能让 presentation 依赖稳定产品语义而不是内部实现细节。
5. 将业务失败与系统故障在 observability 中分层,能显著提高日志信噪比。

## 实施

- 在 `shared/errors` 中定义项目内异常族,作为 repository / use case 公开边界使用的标准异常。
- 在 `shared/` 或 domain 合适位置定义最小 sealed `Result<T, F>` 抽象,仅承载预期业务失败。
- `UnlockVault` 首先落地 `Result<UnlockedVault, UnlockFailure>` 模式。
- repository 实现中主动收束第三方/底层异常,不将其直接穿透到上层。
- Cubit/Bloc 只消费显式 failure;其余异常进入故障态或全局错误边界。
- observability 对 `unlock_failed` 等业务失败事件维持低噪声记录,对故障异常记录 `error`。

## 测试要求

- repository 测试:
  - 第三方/底层异常被正确收束成项目内异常族
  - 不直接泄漏 `FileSystemException` 或第三方异常
- use case 测试:
  - `UnlockVault` 对错误主密码返回 `UnlockFailure.invalidMasterPassword`
  - `UnlockVault` 对库损坏/I/O/crypto 初始化失败继续上抛异常
- presentation 测试:
  - 普通错误主密码进入业务失败提示
  - 系统故障进入故障态或错误边界,不伪装成密码错误
- observability 测试:
  - 业务失败不默认打 `error`
  - 系统故障记录 `error`
  - 错误上下文不泄漏敏感字段

## 影响与后续同步

本 ADR 通过后,以下文档需要同步或以它为权威解释:

- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
  - `CryptoService` / repository / use case 的错误处理需引用本 ADR 的混合模型,不再保留“Result 是否第三方库”的悬而未决状态。
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
  - 需要明确 use case、repository、presentation 在错误模型上的责任边界。
- [docs/specs/observability.md](../specs/observability.md)
  - 需区分业务失败与系统故障的日志等级与事件记录策略。
- [CONTEXT.md](../../CONTEXT.md)
  - 需补充 `Result`、领域异常收束等运行时术语。

## 相关文件

- [docs/adr/0005-cryptoservice-interface-and-aad-builder.md](0005-cryptoservice-interface-and-aad-builder.md)
- [docs/adr/0008-vault-persistence-runtime-model.md](0008-vault-persistence-runtime-model.md)
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
- [docs/specs/observability.md](../specs/observability.md)
- [CONTEXT.md](../../CONTEXT.md)
