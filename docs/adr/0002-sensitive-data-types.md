# 敏感数据类型:密钥材料用 Uint8List,用户字段用 String

密钥材料(KEK、MVK、DEK、K_bio)使用 `Uint8List` 且使用后显式 `fillRange(0)` 清零;用户敏感字段(`VaultEntry.password`、`CustomField.value`)保持 `String`。

## 考虑过的替代方案

- **路径 A(全 String)**:密钥材料也用 String,边界处转换。简单但密钥材料无法主动清零,高价值长生命周期数据残留风险不可接受。
- **路径 B(全 SecureString)**:domain 层全部用自定义 `SecureString` 包装 `Uint8List`。最严格但 Dart GC 语言中 wrapper 对象的 GC 时机仍不可控,安全性提升有限;且无成熟生态实现,自研贯穿 domain 层的维护负担和错误来源显著。

## 选定理由

1. 密钥材料是高价值、长生命周期(解锁期间常驻内存)的字节数据,`Uint8List` + 显式清零无额外成本且可控擦除。
2. 用户密码字段是低价值(单条)、短生命周期(展示后即丢)、文本性质的数据,`String` 的残余风险落在 SECURITY.md §13 声明的"不防御运行时内存被恶意进程读取"边界内。
3. `String` 与 JSON 序列化、UI 展示天然兼容,无需自定义 codec,domain 层不被污染。
4. 路径 C 与现有文档改动最小——`VaultEntry.password: String` 不变,仅明确密钥材料的类型约束。
