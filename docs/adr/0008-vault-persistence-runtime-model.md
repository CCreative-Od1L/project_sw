# Vault 持久化运行模型: 单文件存储引擎

**日期**: 2026-07-08
**状态**: 已接受

## 背景

当前项目已对 vault 文件格式做了较细的规格化约束,包括:

- 定长 `File Header`
- `Directory` / `EntryRecord`
- `Entry Block` 双段布局
- `free list`
- `journal`
- `committed_seq`
- `.bak` 回退

这些内容已经超出“普通文件读写 + 若干安全细节”的范畴,实际构成了一个**单文件存储引擎**。如果不将其作为独立运行模型正式收口,实现期容易出现以下漂移:

- 把 journal、`.bak`、目录切换视为互不相关的技巧而非统一提交/恢复协议;
- 让 `core/vault_file` 同时承担底层块管理和高层条目 CRUD 语义,侵蚀分层;
- 在 I/O 模型、恢复优先级、compaction 职责上由实现者临时发挥。

本 ADR 用于明确:

- `vault` 持久化层的运行时定位;
- 正式事务边界;
- 提交与恢复协议的主次关系;
- 当前正式 I/O 模型;
- `core/vault_file` 对上层暴露的接口层级。

## 考虑过的选项

### 选项 A:把 vault 视为普通文件格式

- `core/vault_file` 仅被视为序列化/反序列化工具;
- journal、`.bak`、目录切换等细节留给实现期自行编排;
- I/O 模型和恢复协议主要由 repository 层掌控。

优点:
- ADR 更短;
- 表面上给实现保留更多自由度。

缺点:
- 会把真正高风险的持久化语义留给实现者临时决定;
- 难以稳定约束恢复协议与提交顺序;
- 容易让底层引擎边界膨胀或塌陷。

### 选项 B:把 vault 明确建模成单文件存储引擎

- `core/vault_file` 被定义为单文件存储引擎;
- 明确事务边界、恢复协议、I/O 立场、离线维护职责;
- repository/data 层基于引擎 API 编排条目语义。

优点:
- 持久化正确性与恢复语义有单一权威来源;
- 便于把格式、提交、恢复、维护职责收束到一致模型;
- 能稳定约束后续实现与文档同步。

缺点:
- ADR 需要承载更多运行时细节;
- 后续若运行模型调整,需要以新 ADR 明确修订。

## 决定

选择选项 B: 将 `vault` 持久化层明确建模成**单文件存储引擎**。

### 1. 运行时定位

- `core/vault_file` 是 vault 的**底层单文件存储引擎**,不是普通文件工具集。
- 该引擎负责:
  - `File Header`
  - `Directory`
  - `Entry Block`
  - `free list`
  - `journal`
  - `committed_seq`
  - `.bak` 快照回退
  这一整套单文件持久化运行模型。
- 条目 CRUD、密钥编排、AAD 组装、业务级错误映射仍留在 repository/data 层,不下沉到引擎层。

### 2. 事务边界

引擎正式承诺的事务边界只有两类:

1. **单条更新事务**
   - 覆盖新增 / 修改 / 删除单条 Entry 的提交。
2. **目录切换事务**
   - 覆盖 compaction、批量导入、迁移接收端提交等需要切换 `active_directory_offset` 的提交。

除此之外,ADR 不承诺更细或更粗的事务语义:

- 不把“单字段修改”进一步下沉成独立事务类型;
- 不把任意多条业务操作组合成通用大事务。

### 3. 恢复协议分层

- **一线恢复协议**: `journal + committed_seq`
- **二线回退机制**: `.bak`

具体立场:

- `journal` 与 `committed_seq` 构成正式提交/恢复协议;
- `.bak` 不是与 `journal` 对等的常规恢复路径;
- `.bak` 只在 `header` / `journal` 本身发生异常、撕裂、CRC 校验失败、或无法可信重放时作为最后快照回退使用。

### 4. 两类事务与恢复协议的绑定

两类事务必须与各自的恢复协议责任显式绑定:

#### 单条更新事务

协议顺序:

1. 写 `journal` 意图并 `fsync`
2. 写新的 `Entry Block` 并 `fsync`
3. 更新 `Directory` 并 `fsync`
4. 写 `committed_seq = seq` 且递增 `sequence_counter` 并 `fsync`

恢复责任:

- 打开 vault 时,若 `journal.seq > committed_seq` 且 CRC 有效,按单条更新事务进行幂等重放或回滚;
- 若 `journal.seq <= committed_seq`,视为已完成或过期 journal,忽略;
- 若 `journal` 自身校验失败,进入 `.bak` 回退路径。

#### 目录切换事务

协议顺序:

1. 写 `journal{op=DIR_SWITCH,...}` 意图并 `fsync`
2. 先将新目录与相关新块全部写到位
3. 原子切换 `active_directory_offset`,同时写 `committed_seq = seq` 且递增 `sequence_counter`,再 `fsync`

恢复责任:

- 打开 vault 时,若 `journal.seq > committed_seq` 且 CRC 有效,按目录切换事务进行幂等重放或回滚;
- 切换前崩溃时,旧目录仍为有效视图;
- `journal` 校验失败时进入 `.bak` 回退路径。

### 5. I/O 模型

当前正式 I/O 方案为**同步 `RandomAccessFile` I/O**。

接受该方案的前提是:

- 当前项目以**正确性、恢复语义、提交顺序可表达性**优先于极致吞吐;
- 在个人库规模下,同步 I/O 的成本被视为可接受;
- 只有当真实数据证明连续 `fsync` 累积卡顿不可接受时,才开启新的 ADR 讨论后台 I/O。

这意味着:

- 同步 I/O 不是“临时凑合方案”;
- 也不是现在就预设必须迁到后台 I/O;
- 若后续迁移,必须通过显式 ADR 修订而不是在实现中悄然改变提交语义。

### 6. 引擎 API 层级

`core/vault_file` 对上层暴露的是**块/记录级引擎 API**,不是高层条目事务 API。

正式职责边界:

- 引擎层暴露:
  - `readHeader`
  - `readDirectory`
  - `readEntryBlock`
  - `writeEntryBlock`
  - `updateDirectory`
  - `commitOperation`
  - `openVaultFile`
  - `recover`
  - `free list` 分配/释放
  - `journal` 读写
- repository/data 层负责:
  - `AddEntry`
  - `UpdateEntry`
  - `DeleteEntry`
  - 批量导入
  - 迁移接收端条目重建
  - 密钥包裹/解包与条目语义编排

因此:

- `core/vault_file` 不直接变成 `addEntry` / `updateEntry` / `deleteEntry` facade;
- 调用方不能绕过 repository 把业务语义压回引擎层。

### 7. Compaction 职责

- `compaction` 属于**单文件存储引擎职责**
- 但它属于**离线维护路径**,不是热路径提交协议的一部分

具体含义:

- compaction 可重写块区、整理碎片、生成新目录并通过目录切换事务提交;
- 它不应成为每次条目 CRUD 的顺手步骤;
- 它和迁移接收端目录切换共享“目录切换事务”这一恢复协议,但不因此变成热路径常规操作。

## 选定理由

1. 当前文档体系实际上已经描述了一个单文件存储引擎,继续把它叫“文件格式”会弱化实现边界。
2. 将 `journal + committed_seq` 明确为一线恢复协议,可以给提交顺序、恢复流程和测试断言提供稳定基线。
3. 将 `.bak` 降为二线回退而不是对等主机制,能避免恢复语义模糊。
4. 在当前项目阶段,同步 I/O 更直接表达严格提交顺序,实现与审计成本最低。
5. 维持块/记录级引擎 API,能守住 `core/vault_file` 与 repository/data 的分层。
6. 明确 compaction 是离线维护职责,可以避免把碎片整理错误地揉进热路径提交。

## 实施

- `core/vault_file` 实现时按单文件存储引擎建模,而不是零散文件工具函数。
- 单条更新与目录切换分别实现独立的提交协议与恢复路径,共享 `journal + committed_seq` 框架。
- `.bak` 只在异常恢复路径中启用,不作为常规事务提交的主要完成信号。
- 同步 I/O 保持为当前正式实现方案,所有 `fsync` 顺序必须与事务协议一一对应。
- `compaction` 通过目录切换事务提交,且只能在非热路径触发。

## 测试要求

- 单条更新事务:
  - journal 写入后崩溃
  - Entry Block 写入后崩溃
  - Directory 写入后崩溃
  - `committed_seq` 写入中断
  - stale journal 正确忽略
- 目录切换事务:
  - 新目录写好但未切换时崩溃
  - 切换 `active_directory_offset` 前后崩溃
  - 重放幂等性
- 异常恢复:
  - journal CRC 失败触发 `.bak` 回退
  - `.bak` 作为上一个成功提交快照可恢复
- API 边界:
  - repository 层编排条目事务,`core/vault_file` 不暴露高层 CRUD facade

## 影响与后续同步

本 ADR 通过后,以下文档需要同步或以它为权威解释:

- [docs/specs/vault_format.md](../specs/vault_format.md)
  - 保持字段与布局规格,但以本 ADR 作为运行模型与恢复协议的权威来源。
- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
  - auth/vault/migration 的实现路径需引用“单文件存储引擎”而不是笼统文件读写。
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
  - `core/vault_file` 的职责描述可进一步引用本 ADR,强调其是底层引擎而非条目业务层。

## 相关文件

- [docs/specs/vault_format.md](../specs/vault_format.md)
- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- [docs/SECURITY.md](../SECURITY.md)
