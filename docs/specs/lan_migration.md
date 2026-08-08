# 局域网迁移协议规格 · PROJECT_SW

> 安全要求概述见 [SECURITY.md §8](../SECURITY.md)。

## 1. 安全要求

迁移是唯一跨设备的数据流动,要求:

1. **设备发现与认证**:双方须显式配对确认(二维码),防中间人。
2. **传输加密**:基于配对派生的临时会话密钥(NaCl `crypto_kx` / X25519 + XChaCha20-Poly1305)端到端加密。
3. **完整性**:传输整体 MAC 校验,防篡改。
4. **最小化**:可选择全库或单条迁移;发送端解包 DEK 后,传 entry_ciphertext + DEK 明文(会话加密),由对端 MVK 重包裹。
5. **无云中转**:纯 P2P,数据不经任何第三方。
6. **迁移后建议**:目标端导入后,源端可选删除(用户确认),并提示更新相关条目。

## 2. 握手协议约束(已定)

下列握手细节已定(迁移握手协议在设计层面闭合;实现期细节如二维码载荷编码、消息类型见编码阶段):

- **设备发现与配对认证(方案 C 二维码全通道)**:无 mDNS/自动发现。发起方生成二维码,编码 `{role, IP:port, pk_发起}`;接收方扫码即获得连接信息与发起方公钥(经视觉带外传递,中间人无法在网络层替换)。接收方直连 `IP:port`,在通道内回送自身公钥;双方以 `crypto_kx` 派生会话密钥。发起方公钥带外 → 防中间人冒充发起方;接收方公钥经通道传递,若被替换则双方派生密钥不一致,AEAD 解密失败可检出——无静默中间人。选用理由:规避 mDNS 在 iOS multicast entitlement / 企业网 / AP 隔离下的脆弱性(禁云中转,发现失败即迁移失败、无兜底),并少一项 mDNS 依赖。
- **密钥协商**:双方各生成一次性 X25519 临时密钥对(不持久化、不复用),NaCl `crypto_kx` 派生双向会话密钥;公钥经上述二维码配对带外绑定,防 MITM。
- **版本/算法匹配检测(约束兼容)**:迁移传输前,双方须在已建立的加密通道内交换并比对 `format_version`、`aead_algorithm_id` 及双方支持的 `plaintext_format_id` 取值范围,一致方可进入传输;不一致则拒绝迁移并提示用户先升级至同一版本/算法/内层格式。
- **重包裹(发送端解包 → 接收端重包裹)**:
  - **发送端**:用自身 MVK 解包 dek_wrapped 得 DEK 明文;经会话 AEAD 加密传输 `{entry_id, seq, plaintext_format_id, entry_ciphertext, DEK 明文}`(DEK 明文走会话加密,不裸传;不传 dek_wrapped 原文,因接收端无发送端 MVK 无法解开)。
  - **接收端**:用自身 MVK 重包裹 DEK 明文 → 新 dek_wrapped(AAD = 接收端 header 值 + 迁入 entry_id);`entry_ciphertext` 原样写入新 Entry Block 的 entry 段,不重加密。
  - **seq 透传(C1)**:接收端 EntryRecord.seq 取发送端原值(因 entry_ciphertext 的 AAD 含发送端 seq),不从自身 sequence_counter 重新分配;否则 AAD 重建失败、迁入条目无法解密。该 seq 此后随接收端对该条的修改正常递增。
- **完整性**:每消息 AEAD tag + 会话级 transcript MAC(运行中 `H.update(session_seq ‖ ct ‖ tag)`,TRANSFER_END 时校验),防丢包/乱序/重放。
- **原子性(目录双写原子切换,C4)**:接收端先在内存缓冲全部迁入条目,transcript MAC 校验通过后,将所有新 Entry Block(双段)与新 Directory 写入文件空闲区,就位后原子切换 `active_directory_offset` 指向新目录;切换前崩溃则 active 仍指旧目录,整体回滚(零落盘至活跃库)。journal 仅记"目录切换"单步意图。MAC 失败则丢弃缓冲,不进入提交。
- **entry_id 冲突策略(C2,整条覆盖)**:迁入条目与接收端已有条目 `entry_id` 冲突时,按 `updated_at` 判定——较新者整条覆盖、丢弃较旧者(不保留旧 `created_at`),较旧则跳过;冲突均须向用户提示。覆盖含所有 VaultEntry 字段(含 `favorite`/`custom_fields`/注释等),非字段级合并。`entry_id` 全局唯一(CSPRNG UUID),正常迁移不应冲突,此策略为兜底。
- **前置约束与超时抑制**:接收端须已建库且处于解锁态(持有自身 MVK);全新设备需先建空库再接收迁移。全库迁移为逐条重包裹的循环,仅数量差异。**迁移进行中临时抑制空闲超时，但不抑制切后台立即锁**(完成/中断后恢复空闲计时);迁移发起前强告知用户"迁移期间请保持应用前台"。
- **生物设置不迁移**:`K_bio` 绑定本设备硬件密钥库,`biometric_wrapped_mvk` 不随迁移传输;接收端须迁移完成后独立设置生物解锁。

## 3. 迁移序列图

```mermaid
sequenceDiagram
    actor UserA as 用户(发送端)
    actor UserB as 用户(接收端)
    participant Send as 发送端(Domain+Vault)
    participant Net as 加密通道(crypto_kx)
    participant Recv as 接收端(Vault+内存缓冲)
    participant RecvV as 接收端 Vault 文件

    Note over UserA,RecvV: ── ① 发现与配对 ──
    UserA->>Send: 发起迁移
    Send->>Send: 生成一次性 X25519 密钥对(pk_发,sk_发)
    Send->>UserA: 显示二维码{role, IP:port, pk_发}
    UserB->>Recv: 扫码 → 获 pk_发(带外,防 MITM)
    Recv->>Recv: 生成一次性 X25519 密钥对(pk_收,sk_收)
    Recv->>Net: TCP 直连,回送 pk_收

    Note over Send,Net: ── ② 密钥协商 ──
    Send->>Send: crypto_kx(pk_收,sk_发) → 会话密钥
    Recv->>Recv: crypto_kx(pk_发,sk_收) → 会话密钥

    Note over Send,Net: ── ③ 版本/算法匹配 ──
    Send->>Net: {format_version, aead_algorithm_id, plaintext_format_id 支持集}
    Recv->>Net: 比对自身 → 一致 ✓

    Note over Send,RecvV: ── ④ 逐条传输 + 重包裹(C1/C3) ──
    loop 每条条目
        Send->>Send: MVK 解包 dek_wrapped → DEK 明文
        Send->>Net: 会话 AEAD: {entry_id, seq(原值), plaintext_format_id, entry_ciphertext(原样), DEK 明文}
        Recv->>Recv: 内存缓冲; 会话 AEAD 解密得各字段
        Recv->>Recv: 自身 MVK 重包裹 DEK 明文 → 新 dek_wrapped(72B)
        Note right of Recv: AAD = 接收端header + 迁入entry_id<br/>seq = 发送端原值(C1)
        Recv->>Recv: 构建新 EntryBlock = 新dek_wrapped ‖ entry_ciphertext(原样)
    end

    Note over Send,RecvV: ── ⑤ TRANSFER_END + transcript MAC ──
    Send->>Net: TRANSFER_END + MAC(tx_key, transcript_hash)
    Recv->>Recv: 校验 transcript MAC → 通过 ✓

    Note over Recv,RecvV: ── ⑥ 目录双写原子提交(C4) ──
    Recv->>RecvV: 全部双段块 + 新 Directory → 写入空闲区
    Recv->>RecvV: journal{op=DIR_SWITCH, new_dir_offset}
    Recv->>RecvV: 原子切换 active_directory_offset
    Recv->>RecvV: journal 清零

    Note over Recv: ── ⑦ 恢复空闲超时 + 提示冷备同步 ──
    Recv-->>UserB: 迁移完成
    Recv->>Recv: 恢复空闲超时抑制
```

> 迁移握手协议在设计层面已闭合。实现期细节(二维码载荷字段编码与纠错级、消息成帧与类型枚举)留待编码阶段,不构成设计决策。
