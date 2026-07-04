# JSON 序列化策略:手写 toJson/fromFrom

**日期**:2026-07-05
**状态**:已接受

## 背景

VaultEntry、VaultHeader、GenerationProfile、CustomField 等实体需要 JSON 序列化支持(vault_entry.md §4)。Dart/Flutter 生态提供多种选择。

## 考虑过的选项

### 选项 A:手写 toJson() / fromJson()
- 零依赖,完全控制,编译时无开销
- 字段多时容易出错,新增字段需同步更新序列化代码
- 宽容解析需手写逻辑(忽略未知字段,缺失字段取默认值)

### 选项 B:代码生成(json_serializable + build_runner)
- 类型安全,自动处理嵌套对象
- 引入 build_runner 构建链,生成文件需管理(.gitignore 或入库)
- 每次修改实体需跑 build_runner

### 选项 C:运行时反射(dart:mirrors)
- Flutter 不支持(AOT 编译限制),直接排除

### 选项 D:第三方序列化库(freezed)
- 同样需要 build_runner,生成代码量大

## 决定

选择选项 A:手写 toJson() / fromJson()

理由:
1. 最小依赖原则:与 ADR-0001 拒绝 injectable 一致
2. VaultEntry 字段简单:10 个固定字段 + custom_fields 列表,手写工作量可控
3. 宽容解析需求:vault_entry.md §4 要求忽略未知字段、缺失字段取默认值,手写 fromJson() 可精确控制
4. 避免 build_runner 复杂度:开发体验和 CI 步骤更简单
5. 一致性:所有实体统一手写,不引入 codegen 链条

## 实施

- Phase 4a 定义 VaultEntry 实体时手写 toJson() 和 fromJson()
- fromJson() 实现宽容解析:忽略未知字段,缺失字段取类型默认值
- 后续实体同样手写序列化

## 相关文件

- docs/specs/vault_entry.md §4
- docs/adr/0001-dependency-injection-with-get-it.md
