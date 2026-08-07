# 路由方案:GoRouter

选用 GoRouter(flutter.dev 官方维护)作为声明式路由,通过 redirect 守卫将 lock_and_recovery.md §5 的 12 状态状态机映射为路由访问控制。运行时会话真相源与路由消费边界见 [ADR-0010](0010-global-session-source-of-truth-and-step-up-auth.md)。

## 考虑过的替代方案

- **auto_route**:注解驱动 codegen 生成路由,类型安全(编译期检查参数)。但需要 build_runner,与最小依赖、避免 codegen 原则有张力。
- **Navigator 2.0 裸用**:Flutter 原生 API,完全可控但样板量极大(手写 Navigator + Pages + RouterDelegate),个人项目不划算。

## 选定理由

1. flutter.dev 官方维护,长期稳定性最高,与 Flutter 生态方向一致。
2. 声明式 `redirect` 守卫天然映射状态机:根据当前 auth 状态(未建库/锁定/解锁)重定向到对应页面,一个 redirect 函数处理所有状态守卫。
3. 不需要 build_runner,无 codegen 依赖,与 ADR-0001 的最小依赖原则一致。
4. ShellRoute 支持解锁后主界面的底部导航栏嵌套子路由结构。

## 状态机 → 路由映射

| 状态机状态 | 路由 | 说明 |
|---|---|---|
| S0 未建库 | `/setup` | 首次建库引导 |
| S1 已建库·锁定(冷启动) | `/unlock` | 已配置生物时允许生物,否则使用主密码 |
| S2 已建库·锁定(超时/切后台) | `/unlock` | 允许生物 |
| S3 解锁·主密码路径 | `/home` | 主界面 |
| S4 解锁·生物路径 | `/home` | 与 S3 同路由 |
| S5 生物失效 | `/unlock` | 回退主密码,提示重设生物 |
| S6 冷却期·忘码入口隐藏 | `/home` 或 `/unlock` | 取决于当前是否在解锁态 |
| S7 冷却期外·忘码入口可浮现 | `/home`(改密码流程中) | 入口在改密码页面内浮现 |
| S8 忘码恢复成功 | `/home` | 新密码生效 |
| S9 迁移发送中 | `/migration/sender` | 迁移流程页 |
| S10 迁移接收中 | `/migration/receiver` | 迁移流程页 |
| S11 擦除中 | `/wiping` | 擦除进度页(不可返回) |

redirect 守卫不自行解释多份会话信号,而是只消费全局会话真相源派生出的单一路由态。`AuthCubit` 仍可作为 UI 投影层对外发布易渲染状态,但 redirect 不以其为运行时权威;迁移与擦除状态也应经会话真相源或等价协调器派生到路由态后再进入独立路由。
