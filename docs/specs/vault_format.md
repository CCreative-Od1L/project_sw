# Vault 文件格式规格 · PROJECT_SW

> 格式概述见 [SECURITY.md §5](../SECURITY.md)；密码学细节以 [SECURITY.md](../SECURITY.md) 为准。

密码库为单个本地文件。序列化格式**已定**:自定义二进制外壳 + JSON 内层条目明文,支持逐条 O(1) 局部更新与格式版本迁移。

## 1. 两层序列化

序列化横跨两层,各自独立选型:

| 层 | 对象 | 是否密文 | 选型 |
|----|------|----------|------|
| **外壳层** | 整个 vault 文件(header + 目录 + 条目块) | 大部分已是密文 blob | **自定义二进制** |
| **内层** | 单条目明文 `{name,url,username,password,notes}`(加密前输入,字段规格见 [VaultEntry 规格](vault_entry.md)) | 明文,加密后变 blob | **JSON**(`plaintext_format_id` 逐条标识) |

- 外壳把 `entry_ciphertext` 视为不透明 blob(nonce24 + ct + tag),不解析其内部;内层选型不进入外壳布局。
- 内层明文直接喂给 AEAD 为裸字节;字段演进见 [vault_entry.md §4](vault_entry.md)。

## 2. 外壳文件布局

```
┌─ File Header(定长)
├─ Directory(EntryRecord[] 定长,如每条 48B)
└─ Entry Block Region(变长槽:nonce24+ct+tag,外壳视为不透明)
     ├─ 活跃槽 ─┬─ 空闲槽(free list 节点)─┬─ 活跃槽 ─┤
```

三个区域:定长 header + 定长目录记录 + 变长条目块。改一条只动「该条目块 + 目录中该条 48B 记录」,header 与其余条目不碰。

## 3. 外壳字段规范

### File Header(定长)

| 偏移 | 长度 | 字段 | 说明 |
|------|------|------|------|
| 0 | 4 | magic `PSWV` | 文件识别 |
| 4 | 2 | `format_version` | 外壳版本,前缀式派发入口 |
| 6 | 1 | `kdf_algorithm_id` | enum:1=argon2id |
| 7 | 1 | `aead_algorithm_id` | enum:1=xchacha20-poly1305 |
| 8 | 12 | `kdf_params{m,t,p}` | uint32×3 |
| 20 | 16 | `kdf_salt` | 每库唯一,CSPRNG |
| 36 | 72 | `wrapped_master_vault_key` | nonce24+ct32+tag16,被 KEK 包裹 |
| 108 | 1 | `flags` | bit0=has_biometric |
| 109 | 72 | `biometric_wrapped_mvk`(=biometric_wrapped_master_vault_key) | 同形,被硬件密钥包裹(可选) |
| … | 8 | `active_directory_offset` | 指向当前活跃目录;支持双目录/COW |
| … | 8 | `entry_count` | 活跃条目数 |
| … | 8 | `free_list_head` | 首个空闲槽偏移,0=无 |
| … | 8 | `sequence_counter` | 全局序号,供 AAD/重放防护 |
| … | ~32 | `journal` 槽 | 单槽意图日志,崩溃安全(见 §5) |
| … | — | reserved(零填充至定长) | 预留未来字段 |

### Directory EntryRecord(定长 48B,每条目一份)

| 偏移 | 长度 | 字段 | 说明 |
|------|------|------|------|
| 0 | 16 | `entry_id` | UUID/CSPRNG |
| 16 | 8 | `block_offset` | 条目块在文件中的偏移 |
| 24 | 4 | `block_length` | 实际密文长度(双段总长) |
| 28 | 4 | `block_capacity` | 槽容量(≥ length,用于就地改写判断) |
| 32 | 1 | `plaintext_format_id` | 内层前缀派发:1=json,2=cbor |
| 33 | 1 | `flags` | 预留 |
| 34 | 8 | `seq` | 该条版本号,绑入 AAD |
| 42 | 6 | reserved | — |

### Entry Block(双段,外壳不透明)

`dek_wrapped(定长 72B: nonce24 + ct32 + tag16) ‖ entry_ciphertext(变长: nonce24 + ct(|明文|) + tag16)`

- 外壳只认 `block_length` / `block_capacity`(覆盖双段总长),不解析内部
- 前 72B 约定为 dek 段(DEK 明文恒 256-bit=32B,故 dek_wrapped 定长 72B)
- dek 段定长的意义:改 DEK 时可原地覆写前 72B,entry 段与 block 偏移不动
- dek_wrapped 由 MVK 包裹,entry_ciphertext 由 DEK 加密,两段各自独立 AEAD

## 4. free list 与崩溃安全

- **free list**:空闲槽自链(`next_free_offset(8B) + capacity(4B) + ...`),header 的 `free_list_head` 指向首节点。分配取 `capacity ≥ 需求` 的槽(可分裂),否则 append 到 EOF;释放将旧槽 push 到链头。碎片由周期性 compaction(锁定时空闲时整体重写,O(N) 离线维护,非热路径)回收。
- **崩溃安全 journal**:header 内单槽意图日志,覆盖两类中途崩溃:
  - **单条更新**(新增/改/删):`journal{op, entry_id, new_offset, new_length, seq, checksum}`,完成块+目录写入后清零;打开时非空且校验通过 → 重放或回滚,校验失败 → 判损坏/回退 .bak。
  - **目录切换**(批量导入/compaction):`journal{op=DIR_SWITCH, new_directory_offset, checksum}`,新目录与块就位后写此 journal,原子切换 `active_directory_offset` 后清零;打开时非空且校验通过 → 切换至新目录或回滚,校验失败 → 回退 .bak。

> 单槽 journal 经"目录切换"单步意图即可支撑批量原子提交:多记录操作先把所有块与新目录写好(中途崩溃不影响旧 active 目录),最后以单步 journal 记录"切换"动作,从而把 N 条原子性收敛为 1 步原子切换。

## 5. AAD 绑定

AEAD 操作将身份与版本绑入认证数据:

| AEAD 操作 | 绑定 AAD |
|-----------|----------|
| DEK 加密条目明文 | `magic ‖ format_version ‖ aead_algorithm_id ‖ entry_id ‖ seq` |
| MVK 包裹 DEK | `magic ‖ format_version ‖ aead_algorithm_id ‖ entry_id` |
| KEK 包裹 MVK | `magic ‖ format_version ‖ kdf_algorithm_id ‖ kdf_params ‖ kdf_salt` |

> 三层包裹逐层绑 AAD:`DEK 加密明文`绑 `seq`(防条目版本回放)、`MVK 包裹 DEK`绑 `entry_id`(防 DEK 在条目间互换的混淆篡改)、`KEK 包裹 MVK`绑 KDF 参数(防参数降级)。`MVK 包裹 DEK` 不绑 `seq`:DEK 的包裹关系随条目版本变化由"换 DEK"体现,包裹本身无需 seq 认证。

## 6. 更新语义(O(1))

Entry Block 为 dek 段(定长 72B)+ entry 段(变长)双段。按"改明文"与"改 DEK"区分:

| 操作 | 动作 | 写入量 |
|------|------|--------|
| 新增 | 分配槽(free list 或 EOF)→ 写双段块 → 追加 EntryRecord → `entry_count++` | 1 块(72B+entry) + 48B |
| 改明文(≤capacity) | 生成新 DEK → 重包裹 dek_wrapped(原地覆写 dek 段 72B)→ 重加密覆写 entry 段 → seq++ | 双段原地 + 48B |
| 改明文(>capacity) | 生成新 DEK → 分配新槽写双段块 → 旧槽入 free list → 更新 EntryRecord | 1 块 + 48B(+旧槽标记) |
| 仅改 DEK(密钥轮换) | 重包裹 dek_wrapped → 原地覆写 dek 段 72B → seq++ | 72B + 48B(entry 段不动) |
| 删一条 | 块入 free list → 置空/标记 EntryRecord → `entry_count--` | 48B(+链头) |

> 改明文必然伴随换 DEK,故"改明文"两行均含 dek 段重包裹。seq 递增从 header `sequence_counter` 取新值并回写。

## 7. 不变约束

- 每次加密均使用全新随机 24 字节 nonce(CSPRNG)。
- Poly1305 标签 16 字节,解密时强制校验,失败即判篡改/损坏。
- 条目明文中的元数据(name/url)同样进入 `entry_ciphertext`,不单独明文暴露。
