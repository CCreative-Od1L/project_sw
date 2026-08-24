# 全局会话真相源与强认证升级运行模型

**日期**: 2026-07-14
**状态**: 已接受

## 背景

当前文档体系已经分别明确了多组规则:

- [lock_and_recovery.md](../specs/lock_and_recovery.md) 定义了锁定、超时、恢复、擦除与 12 状态状态机
- [biometric_auth.md](../specs/biometric_auth.md) 定义了生物解锁、冷启动生物便捷路径与高敏操作强制主密码
- [ADR-0004](0004-routing-with-gorouter.md) 将状态机映射为 GoRouter redirect 路由守卫
- [ADR-0007](0007-unlocked-residency-and-summary-detail-split.md) 要求锁定或切后台时清除摘要与详情明文
- [ADR-0009](0009-error-model-and-result-boundary.md) 已明确 use case / presentation 的错误边界

这些规则已经足够定义“项目应当如何锁定、何时允许生物、何时需要主密码升级”,但仍缺少一个正式的**运行时会话模型**来回答:

- 谁是唯一的会话真相源;
- 锁定原因与认证强度如何建模;
- 生命周期事件如何进入状态机;
- 高敏操作触发的主密码要求是“重新锁定”,还是“解锁态内 step-up challenge”;
- idle timer、background lock、迁移/恢复期超时抑制由谁统一管理;
- `AuthCubit`、GoRouter redirect、页面局部状态谁是权威、谁只是投影。

如果不正式收口,实现期很容易出现以下漂移:

- `AuthCubit`、GoRouter、页面局部状态各自维护一份“当前是否已解锁/是否允许生物/是否已升级主密码”的半真相;
- 高敏操作在页面层各自判断,出现漏判或标准不一致;
- 生命周期和 idle timer 逻辑分散到多个页面或 Cubit,导致锁定副作用不一致;
- 背景锁定与恢复续接各自“顺手停 timer”,没有统一的白名单抑制机制;
- redirect 再解释一遍状态机,与真正会话状态机脱节。

本 ADR 用于明确:

- 全局会话真相源;
- 会话状态模型;
- 强认证升级(step-up)的运行语义;
- 生命周期与锁定事件的统一入口;
- `AuthCubit`、GoRouter、高敏操作对会话状态的消费边界。

## 目标与非目标

### 目标

- 为“锁定 / 解锁 / 强认证升级 / 生命周期事件 / 路由守卫”提供单一运行时权威来源。
- 将现有状态机与认证强度策略落成可实现的会话控制模型。
- 统一锁定副作用、idle timer 与超时抑制的所有权。

### 非目标

- 不在本 ADR 中重写生物解锁的密码学细节。
- 不在本 ADR 中重写忘码恢复或擦除的产品摩擦细节。
- 不把所有 UI 状态都塞进会话真相源。
- 不设计一次性授权 token 子系统。

## 考虑过的选项

### 选项 A:以 `AuthCubit` 作为状态机本体

- `AuthCubit` 自己维护锁定/解锁/强度/计时器
- GoRouter 与页面都订阅它

优点:
- 看起来实现直接;
- 少一个额外协调器对象。

缺点:
- Cubit 同时承担 UI 投影与运行时权威,职责过重;
- 很容易把 Flutter 生命周期、路由与高敏策略耦到 presentation;
- 测试时难以脱离 UI 层验证会话状态机。

### 选项 B:路由、页面、Cubit 分散判定

- GoRouter 自己看 auth 状态做 redirect
- 页面自己决定何时 step-up
- 各页各自 reset idle timer

优点:
- 每个局部看起来都能“独立完成任务”。

缺点:
- 会立即形成多份半真相;
- 策略一致性最差;
- 后续演进成本最高。

### 选项 C:独立全局会话真相源

- 用 `SessionController` / `SessionCoordinator` 一类全局对象持有会话状态机
- `AuthCubit`、GoRouter、高敏流程都只消费其只读派生结果

优点:
- 规则有单一权威来源;
- 方便统一管理生命周期、timer、副作用与 step-up;
- presentation 只做投影,边界清晰。

缺点:
- 需要额外定义运行时状态与事件模型;
- 需要更明确的副作用边界。

## 决定

选择选项 C:采用**独立全局会话真相源**。

### 1. 单一会话真相源

项目必须存在一个全局 `SessionController` / `SessionCoordinator` 一类对象,作为唯一会话真相源。

- 它持有会话状态机;
- `AuthCubit` 只订阅并投影为 UI 状态;
- GoRouter redirect 只读取它的派生路由态;
- 高敏操作只向它请求“是否需要主密码 step-up”,不自行缓存认证强度。

因此:

- 页面不是会话权威;
- `AuthCubit` 不是会话状态机本体;
- redirect 不是会话状态解释器。

### 2. 会话状态模型

会话状态不能只建模成简单的 `locked/unlocked` 布尔值,至少必须同时承载三类信息:

#### 可访问性

- `Locked`
- `Unlocked`

#### 锁定原因

- `cold_start`
- `background_or_timeout`
- `manual_lock`
- `biometric_invalidated`
- 未来可扩展恢复/擦除等其他状态原因

#### 当前认证强度

- `none`
- `biometric`
- `master_password`

因此推荐的最小状态形状为:

- `Locked(reason: ...)`
- `Unlocked(authStrength: ...)`

### 3. 强认证升级不是重新锁定

高敏操作要求的主密码验证,建模为**解锁态内部的 step-up challenge**,而不是将全局会话重新打回锁定态。

语义如下:

- 若当前已是 `Unlocked(authStrength: master_password)`,高敏操作可直接继续;
- 若当前是 `Unlocked(authStrength: biometric)`,由会话真相源发起主密码 step-up challenge;
- challenge 必须绑定唯一 session lease;认证升级没有绕过 lease 的公开入口;任一锁定事件立即使其失效,旧异步结果不得作用于后续重新解锁的会话;
- 挑战成功后,会话保持 `Unlocked`,但 `authStrength` 升级为 `master_password`;
- 失败则当前操作不放行,但不因此自动转入锁定态。

### 4. step-up 成功后的强度保持

step-up 成功后,当前会话的 `authStrength` 升级为 `master_password`,并保持到下一次锁定为止。

会话升级后的失效条件:

- `manual_lock`
- `appBackgrounded` 导致的立即锁定
- `idle_timeout`
- 进程终止 / 冷启动
- `biometric_invalidated`
- `wipe_started`

项目**不**引入“一次性高敏操作授权 token”子系统。

### 5. 高敏操作触发权与责任分层

高敏操作的认证门槛不由页面自行判断。

责任分层如下:

- use case / 业务入口声明操作需要 `master_password` 强度;
- 会话真相源统一判断当前 `authStrength` 是否满足;
- 若不满足,由会话真相源发起 step-up challenge;
- 页面仅负责呈现 challenge UI,不拥有高敏策略判定权。

### 6. 所有锁定事件统一先进入会话真相源

以下事件都必须先进入会话真相源,再由它统一执行状态迁移与副作用:

- `manual_lock`
- `appBackgrounded`
- `idle_timeout`
- `biometric_invalidated`
- `wipe_started`
- 未来其他需要强制锁定的系统事件

锁定副作用由会话真相源统一分发,至少包括:

- 清除 KEK / MVK / DEK
- 清除摘要模型与详情明文
- 停止或重置 idle timer
- 发出会话状态变化供 GoRouter redirect
- 记录锁定埋点
- 作废未完成的高敏 challenge

状态变化按顺序发布。锁定开始后到 `Locked(...)` 发布完成前,会话真相源拒绝重入解锁、step-up challenge 或新 activity。每个敏感数据清理器独立按 best-effort 执行:单个清理器异常不得跳过后续清理,也不得阻止最终锁定;会话真相源在解锁态被销毁时同样触发清理。

### 7. 生命周期事件先适配为项目内领域事件

业务层不直接依赖 Flutter `AppLifecycleState` 作为会话状态机输入。

需显式区分两层:

- **Lifecycle adapter**
  - 例如 `WidgetsBindingObserver`
- **Session event model**
  - 例如:
    - `appForegrounded`
    - `appBackgrounded`
    - `userInteractionObserved`
    - `idleTimeoutElapsed`
    - `biometricInvalidated`

会话真相源只消费项目内事件模型,不直接消费 Flutter 平台枚举。

### 8. 切后台立即锁定的运行时语义

收到 `appBackgrounded` 事件时:

- 若当前处于任一 `Unlocked(...)` 会话
- 会话真相源必须**立即**迁移到 `Locked(reason: background_or_timeout)`

该迁移:

- 不等待 idle timer
- 不等待路由完成
- 不等待页面 `dispose`

这条规则是状态机级即时迁移,不是 UI 层顺手执行的清理动作。

### 9. idle timer 归会话真相源所有

idle timer 是会话系统的一部分,由会话真相源统一启动、重置、暂停、销毁。

规则如下:

- 仅在 `Unlocked(...)` 状态下运行;
- 页面只上报 `userInteractionObserved`;
- 收到 `userInteractionObserved` 时,由会话真相源决定是否重置;
- 收到 `appBackgrounded` / `manual_lock` / `biometric_invalidated` / `wipe_started` 时,清理 timer;
- 锁定态不运行 idle timer。

### 10. 显式 Session Activity 与受控 lock suppression

会话真相源在 `Unlocked(...)` 中显式发布 `SessionActivity`,而不是另存一份页面不可见的 timer 标志。当前活动至少包括:

- `none`
- `migration_sending`
- `migration_receiving`
- `password_recovery`
- `password_change`
- `biometric_configuration`

迁移协调器、忘码恢复、主密码变更、生物配置与认证擦除入口必须通过会话真相源取得唯一 guard;已满足主密码强度时使用 activity lease,生物会话的主密码变更复用 step-up challenge。认证擦除在验证当前主密码前取得 lease,并在开始不可逆销毁前再次检查;锁定后的旧验证结果不得启动擦除。页面不得自行维护并行流程标志。活动完成或传输中断后回到 `none`,锁定会使 guard 失效并触发挂起 I/O 取消或敏感提交检查;stale completion 不得重新解锁、写入新 header 或结束后续同类活动。

非 `none` 活动提供一个极窄的受控 `lockSuppression` 效果。

首批仅允许以下流程申请:

- `migration_sending` / `migration_receiving`
- `password_recovery`
- `password_change`
- `biometric_configuration`

其效果只限于:

- 抑制 **idle timeout**

明确**不**抑制:

- `appBackgrounded` 立即锁定
- `manual_lock`
- `biometric_invalidated`
- `wipe_started`

因此,`lockSuppression` 是白名单式的、只影响 idle timeout 的运行时机制,不是“流程期间不锁”的泛化后门。

### 11. `AuthCubit` 只是 UI 投影

`AuthCubit` 不是会话状态机本体,而是会话真相源的 UI 投影层。

它可以把底层会话状态投影为更适合渲染的状态,例如:

- `locked(canUseBiometric: false, reason: coldStart)`
- `locked(canUseBiometric: true, reason: timeoutOrBackground)`
- `unlocked`
- `stepUpRequired`
- `fault`

但它不得:

- 维护独立 idle timer
- 再维护另一套 lock reason
- 自行推导 auth strength

### 12. GoRouter redirect 只消费派生路由态

redirect 不直接拼接多份信号解释当前会话。

GoRouter redirect 只读取会话真相源提供的单一派生路由态,例如:

- `/setup`
- `/unlock`
- `/home`
- `/migration/sender`
- `/migration/receiver`
- `/wiping`

或等价的 `SessionRouteState` 抽象。

因此:

- redirect 不是策略判断中心;
- 它只消费会话真相源已经派生好的可访问路由态。

## 选定理由

1. 现有文档已经定义了足够多的锁定与认证规则,缺的不是“规则本身”,而是运行时权威来源。
2. 将会话状态、生命周期、idle timer、step-up 与 redirect 收束到单一真相源,可以最大程度减少多份半真相。
3. 把强认证升级建模为解锁态内 step-up challenge,比“重新锁定再解锁”更符合产品语义,也更少副作用。
4. 将 step-up 成功后的强度保持到下一次锁定,能避免额外设计一次性 token 子系统,同时仍受 background immediate lock 与 idle lock 约束。
5. 白名单式 `lockSuppression` 能满足迁移与恢复续接需求,同时不破坏切后台立即锁的安全底线。

## 实施

- 全局会话真相源的实现归属 `features/auth`,因为它承载的是认证/锁定/step-up 的业务语义,不是纯 `core` 基础设施。
- `app/` 只负责:
  - 通过 DI 装配全局会话真相源
  - 接入 lifecycle adapter
  - 将 GoRouter redirect 绑定到派生路由态
- 定义项目内 session event model,由 Flutter 生命周期与用户交互适配器统一输入。
- 将 idle timer 所有权下沉到会话真相源。
- 将迁移发送、迁移接收与忘码恢复建模为 `UnlockedSession` 的显式活动,由会话真相源统一发布并管理 idle suppression。
- `AuthCubit` 改为只投影会话状态,不直接拥有状态机规则。
- GoRouter redirect 改为只消费会话真相源派生的路由态。
- 高敏 use case / 操作入口以显式方式声明 `requiresMasterPassword`,交由会话真相源决定是否发起 step-up。

## 测试要求

- 会话状态机测试:
  - `cold_start` 锁定态允许已配置的生物并保留主密码回退
  - `background_or_timeout` 锁定态允许生物
  - `biometric_invalidated` 回退主密码路径
- lifecycle / timer 测试:
  - `appBackgrounded` 立即锁定
  - `Unlocked(...)` 状态下 idle timer 正常触发
  - 锁定态 timer 被销毁
- step-up 测试:
  - 生物解锁会话访问高敏操作时触发主密码 challenge
  - challenge 成功后升级到 `master_password` 并保持到下一次锁定
  - challenge 失败不自动全局锁定
  - challenge 验证挂起时锁定会立即作废,且 stale completion 不会升级新会话或覆盖新 challenge
- suppression 测试:
  - `migration_sending` / `migration_receiving` / `password_recovery` 抑制 idle timeout
  - 但不抑制 `appBackgrounded` 立即锁定
  - 活动完成或中断后回到 `none`,stale completion 不得解除锁定或结束新 lease
  - 锁定会关闭挂起的迁移传输,并阻止忘码恢复继续提交 MVK 重包裹
- redirect / projection 测试:
  - `AuthCubit` 与 GoRouter 只消费会话真相源派生结果,不重复解释状态机

## 影响与后续同步

本 ADR 通过后,以下文档需要同步或以它为权威解释:

- [docs/specs/lock_and_recovery.md](../specs/lock_and_recovery.md)
  - 状态机应明确由全局会话真相源运行,并补充 background lock、idle timer、suppression 的运行语义。
- [docs/specs/biometric_auth.md](../specs/biometric_auth.md)
  - 高敏操作的主密码要求需明确为 step-up challenge,且成功后提升当前会话强度直到下一次锁定。
- [docs/adr/0004-routing-with-gorouter.md](0004-routing-with-gorouter.md)
  - redirect 应改为只消费会话真相源派生的路由态。
- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
  - auth 生命周期、idle timer、会话状态机与 step-up 实现路径需引用本 ADR。
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
  - 需要明确 `SessionController` / `AuthCubit` / GoRouter 的职责分层。
- [CONTEXT.md](../../CONTEXT.md)
  - 需要补充 session、auth strength、step-up、lock suppression 等运行时术语。

## 相关文件

- [docs/specs/lock_and_recovery.md](../specs/lock_and_recovery.md)
- [docs/specs/biometric_auth.md](../specs/biometric_auth.md)
- [docs/adr/0004-routing-with-gorouter.md](0004-routing-with-gorouter.md)
- [docs/specs/build_roadmap.md](../specs/build_roadmap.md)
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- [CONTEXT.md](../../CONTEXT.md)
