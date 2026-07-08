# CryptoService 接口:纯密码学原语 + AadBuilder 工具

CryptoService 仅提供 KDF/AEAD/CSPRNG 纯密码学原语,不耦合 vault 格式语义;三层 AAD 绑定逻辑集中在独立的 `AadBuilder` 纯函数工具类中。

## 考虑过的替代方案

- **路径 A(纯通用 AEAD,AAD 调用方组装)**:接口最小化,但 AAD 组装逻辑分散在 data 层各 repository,三层 AAD 的正确性是安全核心,分散增加出错风险。
- **路径 B(语义化包裹方法,AAD 内部组装)**:AAD 集中且调用方不可能漏绑,但 CryptoService 耦合 vault 格式语义(VaultHeaderParams、entryId、seq),且这些参数类型是 domain 实体——core 层依赖 domain 参数类型是反向依赖,违反 Clean Architecture 依赖方向。

## 选定理由

1. CryptoService 保持纯密码学原语定位(KDF/AEAD/CSPRNG),不依赖 vault 语义,与 ARCHITECTURE.md"加密方案与实现解耦"原则一致。
2. AadBuilder 集中安全最关键的 AAD 绑定逻辑,纯函数可独立单测,避免 AAD 分散出错。
3. 新增包裹关系(如 K_bio 包裹 MVK)只需在 AadBuilder 加方法,不改 CryptoService 接口——扩展性好。
4. CryptoService 的 mock/fake 更简单——测试只 mock 原语,不 mock 语义。

## 接口形状

```dart
abstract class CryptoService {
  Future<Uint8List> deriveKek(String password, Uint8List salt, {int m, int t, int p});
  Uint8List generateKey();
  Uint8List randombytes(int length);
  ({Uint8List nonce, Uint8List ciphertext}) encryptWithAead(Uint8List key, Uint8List plaintext, Uint8List aad);
  Uint8List decryptWithAead(Uint8List key, Uint8List nonce, Uint8List ciphertext, Uint8List aad);
}
```

```dart
class AadBuilder {
  static Uint8List forWrapMvk(Uint8List magic, int formatVersion, int kdfAlgorithmId, Uint8List kdfParams, Uint8List kdfSalt);
  static Uint8List forWrapDek(Uint8List magic, int formatVersion, int aeadAlgorithmId, Uint8List entryId);
  static Uint8List forEncryptEntry(Uint8List magic, int formatVersion, int aeadAlgorithmId, Uint8List entryId, int seq);
}
```

## 同步/异步边界

- `deriveKek`: `Future<Uint8List>`——由调用方在主 isolate 发起,实际后台执行机制遵循 ADR-0003 的分级策略(首选 `Isolate.run()`,次选长驻 crypto worker isolate,最后才是主 isolate fallback)。
- `encryptWithAead` / `decryptWithAead` / `generateKey` / `randombytes`: 同步——单条操作在主 isolate 直接执行;若调用方选择在后台机制内批量解密,则在该后台执行上下文中同步调用这些原语。

## 调用模式

data 层 repository 编排包裹/解包时,两步调用:
```dart
final aad = AadBuilder.forWrapDek(magic, formatVersion, aeadAlgorithmId, entryId);
final (nonce, ciphertext) = cryptoService.encryptWithAead(mvk, dek, aad);
```
