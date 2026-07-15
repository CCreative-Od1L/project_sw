# PROJECT_SW 密码管理器

一个本地优先、零云依赖的开源密码管理器。所有加解密在设备本地完成,密码库不离开设备(局域网迁移除外)。本文档定义项目领域语言,供工程 skills 在 issue 标题、重构提案、测试命名等输出中统一使用。

## Language

### 密钥层级

**主密码 (Master Password)**:
用户记忆的唯一不存储的秘密,经 Argon2id 派生 KEK。
_Avoid_: 密码(泛指), passphrase, user password

**KEK (Key Encryption Key)**:
由主密码经 Argon2id 派生的 256-bit 密钥,仅存在于解锁后内存,从不落盘。用于包裹 Master Vault Key。
_Avoid_: 派生密钥, derived key

**Master Vault Key (MVK)**:
随机生成的 256-bit 库主密钥,密文存于 vault header。用于包裹每条 DEK。换主密码只需用新 KEK 重新包裹 MVK,无需重加密条目。
_Avoid_: master key, vault key, 主密钥

**DEK (Data Encryption Key)**:
每条目独立随机生成的 256-bit 密钥,密文(dek_wrapped)随条目 Entry Block 存储。用于加密单条条目明文。
_Avoid_: entry key, per-entry key

**K_bio**:
硬件密钥库生成的、生物识别门控的密钥,用于包裹 MVK 实现生物解锁。绑定当前生物特征集,变更后失效。
_Avoid_: biometric key, 生物密钥

### 密码学操作

**信封加密 (Envelope Encryption)**:
每条目独立 DEK 加密明文,MVK 包裹 DEK,KEK(或 K_bio)包裹 MVK 的三层包裹架构。支持局部更新、单条迁移、换主密码不改密文。
_Avoid_: 层级加密, hierarchical encryption

**包裹 (Wrap)**:
用上层密钥经 AEAD 加密下层密钥,产生 nonce + ciphertext + tag 的密文形式(wrapped key)。
_Avoid_: encrypt(泛指), seal

**解包 (Unwrap)**:
包裹的逆操作,用上层密钥经 AEAD 解密还原下层密钥明文。
_Avoid_: decrypt(泛指), unseal

**重包裹 (Re-wrap)**:
迁移场景中,发送端用自身 MVK 解包 DEK 得明文,经会话加密传输,接收端用自身 MVK 重新包裹 DEK 的过程。
_Avoid_: re-encrypt, 重新加密

**AAD (Additional Authenticated Data)**:
AEAD 操作中绑入认证但不加密的上下文数据,用于将身份与版本绑入密文,防篡改、换槽、回放。三层各有不同 AAD 绑定(见 vault_format.md §5)。
_Avoid_: associated data, 认证数据

**Argon2id 基准测试 (KDF Benchmark)**:
首次建库时在目标设备上测多组 Argon2id 参数,在设定延迟上限内选取最高档参数并持久化到 vault header 的自适应过程。
_Avoid_: 参数调优, parameter tuning

### Vault 文件结构

**Vault**:
设备的本地加密密码库文件,自定义二进制外壳 + JSON 内层。
_Avoid_: 密码库(泛指), database, store

**File Header**:
Vault 文件的定长头部,含 magic、format_version、KDF 参数/盐、wrapped MVK、flags、directory 指针、entry_count、free_list_head、sequence_counter、journal 槽。
_Avoid_: header(泛指), 文件头

**Directory**:
Vault 文件中 EntryRecord 的定长数组,由 File Header 的 active_directory_offset 指向。支持双目录 COW(写时复制)实现原子切换。
_Avoid_: 目录(泛指), index, 索引

**EntryRecord**:
Directory 中每条目的一份定长 48B 记录,含 entry_id、block_offset、block_length、block_capacity、plaintext_format_id、seq。
_Avoid_: 条目记录, record, metadata entry

**Entry Block**:
Vault 文件中单条目密文的存储单元,双段结构:前 72B dek_wrapped(定长)+ 后变长 entry_ciphertext。外壳视为不透明 blob。
_Avoid_: block(泛指), 数据块

**dek_wrapped**:
Entry Block 的前 72B 段,MVK 包裹 DEK 的密文(nonce24 + ct32 + tag16)。定长,支持改 DEK 时原地覆写。
_Avoid_: wrapped DEK, DEK 密文

**entry_ciphertext**:
Entry Block 的后变长段,DEK 加密条目明文的密文(nonce24 + ct + tag16)。迁移时原样传输不重加密。
_Avoid_: 条目密文, encrypted entry

**free list**:
Vault 文件中空闲槽的自链表,header 的 free_list_head 指向首节点。分配取 capacity 匹配的槽(可分裂),释放将旧槽 push 到链头。
_Avoid_: 空闲链表, free space list, 空闲空间

**journal**:
File Header 内的单槽意图日志,覆盖单条更新与目录切换两类操作。完成后清零,打开时非空则重放或回滚,校验失败则回退 .bak。
_Avoid_: WAL, write-ahead log, 日志(泛指)

**seq**:
EntryRecord 中该条目的版本号,绑入 AAD 防条目版本回放。每次修改递增,从 header sequence_counter 取值。
_Avoid_: sequence, 版本号, version

### 条目模型

**VaultEntry**:
单条密码条目的**完整明文实体**,经 DEK 加密后存入 entry_ciphertext。含 name、url、username、password、notes、created_at、updated_at、favorite、custom_fields。根据 ADR-0007,`VaultEntry` 不作为解锁态全局常驻工作集,仅在解锁提取摘要或详情页按需解密时短生命周期存在。
_Avoid_: entry(泛指), 条目(泛指), credential, item

**EntrySummary**:
解锁后保留在全局内存中的**常驻摘要模型**,仅含 `entry_id`、`name`、`url`、`username`、`favorite`、`created_at`、`updated_at`。用于列表、排序、过滤、常规搜索;不含 `password`、`notes` 或任何 `custom_fields`。
_Avoid_: preview entry, lightweight entry, list item, summary record

**EntryDetail**:
详情页按需解密得到的**单条完整详情对象**。字段形状可与 `VaultEntry` 等价,但只允许存在于详情页局部作用域,退出详情页或锁定后即清理,不得回填全局常驻状态。
_Avoid_: full entry cache, hydrated entry, detail cache

**CustomField**:
VaultEntry 中的自定义键值对,带 secret 标记。secret=true 按 password 级卫生处理(不入搜、不入列表展示);secret=false 语义上是非敏感扩展字段,但按 ADR-0007 同样不入常规搜索、不入列表展示,仅详情页按需解密展示。
_Avoid_: 自定义字段, extra field, attribute

**GenerationProfile**:
密码生成器的配置实体,含 mode(random/pronounceable)、length、charsets、excludeAmbiguous、symbolSubset。
_Avoid_: 生成配置, generator config, profile

### 认证与状态

**生物解锁 (Biometric Unlock)**:
指纹/面容授权 OS 释放 K_bio,解包 biometric_wrapped_mvk 得 MVK,跳过 Argon2id 的便捷解锁路径。安全强度归 OS/硬件,非密码学。
_Avoid_: biometric auth, 指纹解锁(泛指)

**会话真相源 (Session Source of Truth)**:
全局唯一的会话状态机与协调器,负责持有 `Locked/Unlocked`、锁定原因、认证强度、idle timer、step-up challenge 与路由态派生。`AuthCubit`、GoRouter、页面局部状态都只能订阅它,不能各自维护独立真相(见 ADR-0010)。
_Avoid_: auth cubit 真相源, router state authority, page-owned session

**认证强度 (Auth Strength)**:
当前解锁会话满足的认证级别,至少区分 `none`、`biometric`、`master_password`。它与“是否已解锁”不同:两个 unlocked 会话可能强度不同,从而决定是否允许高敏操作。
_Avoid_: 登录态强度, unlock level

**Step-up Challenge**:
已解锁会话内为高敏操作补充主密码验证的一次强认证升级。它不是重新锁定,成功后会把当前会话的 `authStrength` 升级为 `master_password` 直到下一次锁定。
_Avoid_: re-login, forced relock, one-shot token

**Lock Suppression**:
会话真相源对白名单流程提供的窄范围 idle timeout 抑制机制。首批仅用于迁移中与忘码恢复中,且不抑制切后台立即锁、手动锁或生物失效。
_Avoid_: no-lock mode, background unlock bypass

**Session Route State**:
由会话真相源派生出的单一路由可访问状态,供 GoRouter redirect 消费。redirect 不自己拼多份会话信号,只读取这份派生结果。
_Avoid_: router-owned auth logic, redirect inference

**Result**:
用于承载**预期业务失败**的最小密封返回抽象,只在少量交互型 use case 上使用。不是跨层统一返回形状,不用于承载系统故障或内部异常对象(见 ADR-0009)。
_Avoid_: 通用错误容器, monad result, 全面函数式返回

**领域异常收束 (Domain Exception Normalization)**:
repository 作为第一层边界,将第三方或底层异常收束为项目内异常族,禁止把 `sodium_libs` 异常、`FileSystemException` 等直接泄漏到 use case / presentation。
_Avoid_: 透传底层异常, raw exception passthrough

**业务失败 (Business Failure)**:
正常产品流程中预期发生,且调用方有稳定处理动作的失败分支。典型例子是错误主密码;在本项目中应由 use case 专属 failure 类型承载,默认低噪声记录。
_Avoid_: 普通异常, expected exception

**系统故障 (System Fault)**:
未被 use case 吸收的异常路径,包括文件损坏、I/O 失败、crypto 初始化失败、状态违例等。presentation 不应将其伪装成普通业务失败,observability 按 error/fault 路径记录。
_Avoid_: 普通错误提示, recoverable failure

**忘码恢复 (Master Password Recovery)**:
已设生物且生物未变时,经生物协助重置主密码的隐式应急通道。带四重门槛(隐式入口、错三次触发、一周冷却、二次生物确认)。
_Avoid_: password reset, 密码重置, 找回密码

**死锁擦除 (Deadlock Wipe)**:
主密码与生物均不可用时的最后逃生手段,不要求主密码,带四重摩擦(隐式入口、强告知、二次确认、延迟倒计时)。擦除而非窃取,残余风险与生物冒用同量级。
_Avoid_: 强制擦除, emergency wipe, panic wipe

### 迁移

**二维码配对 (QR Pairing)**:
局域网迁移的设备发现与认证方式:发起方生成二维码编码 {role, IP:port, pk_发起},接收方扫码获带外公钥,防中间人。
_Avoid_: QR 认证, 扫码配对

**crypto_kx 握手**:
双方各生成一次性 X25519 临时密钥对,经 NaCl crypto_kx 派生双向会话密钥的密钥协商过程。公钥经二维码配对带外绑定。
_Avoid_: key exchange, 密钥交换, 握手(泛指)

**transcript MAC**:
迁移会话中累积的完整性校验:运行中 H.update(session_seq ‖ ct ‖ tag),TRANSFER_END 时校验,防丢包/乱序/重放。
_Avoid_: 会话校验, session hash, 传输校验

**目录双写原子切换 (Directory COW Switch)**:
迁移接收端先将全部新 Entry Block 与新 Directory 写入空闲区,就位后经 journal 记录单步意图,原子切换 active_directory_offset 指向新目录。切换前崩溃则旧目录仍有效,整体回滚。
_Avoid_: 双写切换, atomic directory swap, COW commit
