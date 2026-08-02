# 并发模型:CPU 密集操作脱离 UI 主执行路径

Argon2id 派生、首次建库基准测试、批量解密所有条目三类 CPU 密集操作**不得阻塞 UI 主执行路径**。已选机制为 `Isolate.run()` 一次性后台执行:在 Redmi Note 9 Pro 上以 30 次短生命周期 isolate 实机验证 `sodium` 初始化与 `randombytes`,全部样本有效且初始化 P95 `≤100ms`。后续 Argon2id 与批量解密沿用此路径;单条 AEAD 加解密(CRUD)仍在主 isolate 直接执行,不做后台调度。

## 考虑过的替代方案

- **纯 async(不 offload)**:用 `Future` 包装但实际在主 isolate 执行。Argon2id 是 CPU 密集型同步操作,async 只让出事件循环,不能消除阻塞,UI 仍卡死。
- **`Isolate.run()` 一次性后台执行**:最简单,与当前一次性派生/批量解密模型贴合。#14 已在 Redmi Note 9 Pro 上完成 30 次实机验证,确认 `sodium` 可在短生命周期 isolate 中稳定初始化且 P95 `≤100ms`。
- **长驻 isolate + SendPort/ReceivePort**:持久 worker 进程模型,适合复用一次初始化后的 sodium 上下文,代价是生命周期管理与消息协议复杂度更高。
- **主 isolate 受限 fallback**:通过先让 UI 渲染等待态,再在主 isolate 上执行 CPU 密集任务作为最后兜底。实现最直接,但只能在 isolate 路线均不可行时使用,因为它会侵蚀交互流畅性。
- **`compute()`**:`Isolate.run` 的高层封装,功能更受限(只能传一个函数 + 一个参数),不如直接控制后台执行机制灵活。

## 选定结论

1. **已定原则**:Argon2id 派生(目标 250–400ms,仍待 Argon2id 专项基准校准)、首次建库基准测试、批量解密都属于 CPU 密集操作,主 isolate 执行会阻塞 UI,因此必须脱离 UI 主执行路径。
2. **已选机制**:`Isolate.run()` 最贴合当前的一次性任务形状,实现和测试成本最低;#14 的 30 次 Redmi Note 9 Pro 实机样本满足初始化 P95 `≤100ms`,因此后续实现采用它。
3. **既定替代**:若未来目标设备或运行时回归使短生命周期 isolate 不再可用或未达到该阈值,长驻 crypto worker isolate 是首选替代,因为它仍守住“重活不进 UI 主路径”这一原则。
4. **兜底机制**:主 isolate fallback 只在前两类机制均不可行时使用。它不是对等选项,而是功能可用性上的最后退路。
5. **不后台化的边界**:单条 AEAD 加解密是微秒~毫秒级,主 isolate 直接执行通常无感知;对这类细粒度操作做后台调度,通信开销往往高于收益。

## 实现路径与替代策略

后续实现使用 `Isolate.run()` + 每次任务独立初始化 `sodium`。#14 的集成测试以 30 个顺序样本记录非敏感环境与初始化统计,并要求全部样本有效、P95 `≤100ms`。[验证实现](../../integration_test/sodium_isolate_probe_test.dart) 仅返回字节长度与耗时,不传回随机字节。

若上述路径在新增目标环境中失效或不达标,按以下顺序切换,并在切换前补充对应验证:

1. 长驻 crypto worker isolate(启动时初始化一次,后续复用)
2. 主 isolate 受限 fallback(先渲染等待态,再执行 CPU 密集任务)

## 实现约束

短生命周期 isolate spike 已完成,不再是实现前置条件。若需要切换执行路径,验证必须重新确认:
- `sodium` 是否可在目标环境的 `Isolate.run()` 所创建的短生命周期 isolate 中稳定初始化并工作;
- 初始化成本是否满足 P95 `≤100ms` 的接受阈值;
- 未达标时是否切换到长驻 crypto worker isolate。

对于所有 isolate 路线,Isolate 间数据传递经 Dart message port 序列化(深拷贝),`Uint8List`(密钥/明文)会被复制一份:
- 传入 isolate 和返回时各存在一份拷贝,生命周期不受控。
- 缓解:isolate 内用完立即清零本地拷贝;主 isolate 拿到返回值后用完清零(遵循 ADR-0002)。
- 残余风险落在 SECURITY.md §13"不防御运行时内存被恶意进程读取"边界内。

若最终落到主 isolate fallback,实现需满足:
- CPU 密集任务开始前先让 UI 渲染明确的等待/进度态;
- 该路径须带可观测性埋点,便于后续确认是否需要继续优化执行模型;
- 不得把主 isolate fallback 描述为与 isolate 路线等价的常规方案。
