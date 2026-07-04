# 并发模型:CPU 密集操作 isolate offload

Argon2id 派生、首次建库基准测试、批量解密所有条目三类 CPU 密集操作通过 `Isolate.run()` 在后台 isolate 执行;单条 AEAD 加解密(CRUD)在主 isolate 直接执行,不 offload。

## 考虑过的替代方案

- **纯 async(不 offload)**:用 `Future` 包装但实际在主 isolate 执行。Argon2id 是 CPU 密集型同步操作,async 只让出事件循环,不能消除阻塞,UI 仍卡死。
- **长驻 isolate + SendPort/ReceivePort**:持久 isolate 双向通信,适合需多次交互的场景(如批量解密逐条返回进度)。但通信复杂度高,个人库规模(几十~数百条)下一次性批量足够,无需细粒度进度反馈。
- **compute()**:Isolate.run 的高层封装,功能更受限(只能传一个函数 + 一个参数),不如 Isolate.run 灵活。

## 选定理由

1. Argon2id 派生(目标 250–400ms,待实测校准)是 CPU 密集同步操作,主 isolate 执行必然阻塞 UI;Isolate.run 一次性 spawn 跑完即回收,最简单且足够。
2. 首次建库基准测试需测多组参数(累计可能数秒),Isolate.run 在后台跑完返回最优组合,期间 UI 显示等待状态。
3. 批量解密所有条目(解锁时遍历全部 EntryBlock),个人库规模下一次性 Isolate.run 批量返回 List&lt;VaultEntry&gt; 足够;若未来库规模显著增大,再评估分批 + 长驻 isolate。
4. 单条 AEAD 加解密是微秒~毫秒级,主 isolate 直接执行无感知,offload 反而增加通信开销。

## 实现约束

Isolate 间数据传递经 Dart message port 序列化(深拷贝),Uint8List(密钥/明文)会被复制一份:
- 传入 isolate 和返回时各存在一份拷贝,生命周期不受控。
- 缓解:isolate 内用完立即清零本地拷贝;主 isolate 拿到返回值后用完清零(遵循 ADR-0002)。
- 残余风险落在 SECURITY.md §13"不防御运行时内存被恶意进程读取"边界内。
