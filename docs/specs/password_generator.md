# 密码生成器规格 · PROJECT_SW

> 规格概述见 [ARCHITECTURE.md §3](../ARCHITECTURE.md);安全约束(随机源)见本文档 §1。

对应核心功能"密码生成"。规格定义 `GenerationProfile` 实体与 `GeneratePassword` use case 的参数空间。

### 1. 随机源(安全根基)

- 生成器随机源**与加密用 CSPRNG 同源**:使用 `sodium` 的 `randombytes`(经审计,与盐/nonce/MVK/DEK 同源),**禁止**用 `dart:math.Random()`(伪随机)或未审计的第三方随机源(见本文档 §1)。
- 抽样采用**无偏等概率**方式:使用 `sodium` 的 `randombytes_uniform(charset.length)`(内部已实现无偏选择,经密码学社区审计),避免字符集大小非 2 的幂时的模偏置。不使用手写拒绝采样或 `dart:math.Random.nextInt`(伪随机,已在 §1 禁用)。

### 2. 生成模式与字符集

**pronounceable 模式字符集**:默认仅使用字母(辅音+元音交替,基于固定音节表),与 §3 `charsets` 的 digits/symbols 开关独立;若需在音节间插入数字/符号,实现期可扩展。

| 模式 | 说明 | 默认 |
|------|------|------|
| **随机字符串**(random) | 从启用的字符集均匀抽取 N 字符 | ✓ 默认模式 |
| **可发音**(pronounceable) | 按音节结构(辅音/元音交替)生成类词字符串,可读性介于随机串与 passphrase 之间 | 可选 |

> 不提供 passphrase(多词拼接)模式:依赖外部词库资产,与最小依赖原则冲突;可发音模式已覆盖"可读性"诉求。

### 3. 字符集(随机字符串模式)

| 字符集 | 范围 | 默认启用 |
|--------|------|----------|
| 小写字母 | `a-z` | ✓ |
| 大写字母 | `A-Z` | ✓ |
| 数字 | `0-9` | ✓ |
| 符号 | 可配置子集(默认 ASCII 符号集,排除影响表单/URL 的字符如空格、`/`、`"`、`'`) | ✓ |

- **可读性选项(排除易混字符)**:可选排除易混集 `O 0 I 1 l |`(及按需 `B 8`、`S 5`、`G 6` 等),减少人工辨识错误;默认**关闭**(保留熵),用户可开。
- 至少启用一个字符集;若启用集并集为空,生成拒绝。

### 4. 长度

| 项 | 值 |
|----|----|
| 默认长度 | **20 字符**(全面字符集下理论熵 ≈ 131 bit) |
| 最小长度 | 8 |
| 最大长度 | 128(避免 UI/存储边界问题) |
| 可发音模式长度 | 按音节数控制,默认映射到等价熵 |

### 5. 强度评估(口径已定)

- 采用**理论熵估算**:`entropy ≈ length × log2(启用字符集并集大小)`,映射到标签:
  - `< 50 bit`:弱
  - `50–80 bit`:中
  - `80–120 bit`:强
  - `> 120 bit`:极强
- **不引入字典/模式评估**(如 zxcvbn):避免重依赖与词库,与最小依赖原则一致。代价:不识别弱模式(如重复/键盘序列)——以"随机源无偏 + 用户可调长度"兜底,UI 提示理论熵为估算值。
- 可发音模式按音节熵折算:`entropy ≈ syllable_count × log2(音节表大小)`,音节表为固定辅音×元音组合集合;折算后套用同一标签阈值。
- **pronounceable 模式字符集**:默认仅使用字母(辅音+元音,约 26 个大写/小写字符的固定音节表);`charsets` 中的 digits/symbols 开关在 pronounceable 模式下**是否生效待定**,默认关闭(纯字母发音串)。若需在音节间插入数字/符号,实现期可扩展。

### 6. GenerationProfile 实体字段(目标)

```dart
GenerationProfile {
  mode: { random | pronounceable }       // 默认 random
  length: int                             // 默认 20,范围 [8, 128]
  charsets: { lowercase, uppercase, digits, symbols }  // 各 bool,默认全 true
  excludeAmbiguous: bool                  // 默认 false
  symbolSubset: Set<String>               // 可配置符号子集
}
```

`GeneratePassword(profile) → String` 为纯函数(domain 层),随机源经抽象注入便于单测(测试注入固定随机源以可复现)。**生成器输出流向**:生成器输出经用户确认后填入 VaultEntry.password 或 custom_fields.value(见 [vault_entry.md](vault_entry.md)),随条目走 [vault_format.md §3](vault_format.md) 信封加密;输出未存入 vault 前为短暂 UI 态,按 [data_hygiene.md §1](data_hygiene.md) 内存卫生持有与清零。**生成器可在锁定态独立使用**(不依赖 vault/MVK),此时输出复制应同样走 [data_hygiene.md §2](data_hygiene.md) 剪贴板 20s 清除。
