# DI 方案:get_it

选用 `get_it`(service locator 模式)作为依赖注入容器,在 `app/` 层的 composition root 一次性注册所有 interface→implementation 绑定。

## 考虑过的替代方案

- **riverpod**:功能更强且编译安全,但与已定的 Cubit/Bloc 状态管理形成两套范式,概念重叠,增加认知负担。
- **provider**:轻量但作者已推荐迁移至 riverpod,长期方向不明。
- **injectable + get_it**:注解驱动 codegen 自动生成注册代码,但引入 `build_runner` 构建链,对个人项目属过度工程。
- **手写 Service Locator**:零依赖但等于重新发明 get_it,且缺乏测试替身支持。

## 选定理由

1. 与 Cubit/Bloc 正交——Bloc 管状态,get_it 管依赖解析,职责不重叠。
2. 最小依赖原则——纯 Dart 包,无平台依赖,无 codegen,无 build_runner。
3. Clean Architecture composition root 模式天然映射到 `registerLazySingleton`。
4. 测试友好——支持运行时替换注册,便于注入 mock/fake;集成测试用 reset + 重新注册隔离。
5. 解决跨业务线注入:`features/search` 定义 `EntryQueryPort` 接口,`features/vault` data 层实现,在 `app/` 注册绑定,search 不 import vault 包——满足"业务线间零直接依赖"约束。
