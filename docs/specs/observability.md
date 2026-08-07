# 可观测性规格 · PROJECT_SW

> 行为规范见 [DEVELOPMENT.md §6](../DEVELOPMENT.md);本文定义 `core/observability` 的接口形状、事件清单、脱敏机制与日志存储策略。
> 架构定位见 [ARCHITECTURE.md §3](../ARCHITECTURE.md) `core/observability` 模块。
> 错误分层遵循 [ADR-0009](../adr/0009-error-model-and-result-boundary.md):业务失败与系统故障分别记录,不得混淆。

## 1. 接口定义

三个抽象接口,均定义在 `core/observability`,由 data 层或 core 层提供实现,presentation/domain 经 DI(get_it,见 [ADR-0001](../adr/0001-dependency-injection-with-get-it.md))注入。

### 1.1 Logger

```dart
enum LogLevel { verbose, info, warning, error }

abstract class Logger {
  void verbose(String tag, String message, {Map<String, dynamic>? context});
  void info(String tag, String message, {Map<String, dynamic>? context});
  void warning(String tag, String message, {Map<String, dynamic>? context});
  void error(String tag, String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace});
}
```

- `tag`:模块标识(如 `"auth"`、`"vault_file"`、`"crypto"`),用于日志过滤。
- `context`:结构化附加字段(如 `{"entryId": "...", "durationMs": 320}`),已由调用方提供非敏感值;管道式脱敏过滤器再兜底(见 §3)。
- `error`/`stackTrace`:`error` 级别专用,传入异常对象与堆栈供诊断。
- 便利方法封装统一入口 `void log(LogLevel level, String tag, String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace})`,内部转发。
- 记录原则:
  - 进入 use case `Result` failure 的**业务失败**默认不记 `error`,优先 `info` / `warning`
  - 未被 use case 吸收、继续上抛的**系统故障**记录 `error`

### 1.2 EventTracker

```dart
abstract class EventTracker {
  void track(String event, {Map<String, dynamic>? params});
}
```

- `event`:字符串,取值见 §2 事件清单。用字符串而非枚举,避免跨模块枚举耦合;事件清单常量集中定义在 `core/observability/events.dart`。
- `params`:事件附加参数(已脱敏),如 `{"method": "biometric", "durationMs": 120}`。

### 1.3 MetricsRecorder

```dart
abstract class MetricsRecorder {
  void recordTiming(String name, Duration duration);
  void recordCounter(String name, {int increment = 1});
}
```

- `recordTiming`:耗时分布(KDF 派生耗时、解锁总耗时、加解密耗时、基准测试单组耗时)。
- `recordCounter`:计数(解锁成功/失败次数、错误次数、条目操作次数)。
- 指标名同样用字符串,常量集中定义在 `core/observability/metrics.dart`。

## 2. 事件清单

完整埋点事件,按业务线分组。事件名常量定义在 `core/observability/events.dart`。

### auth(认证)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `vault_created` | 首次建库完成 | `{kdfParams, benchmarkDurationMs}` |
| `unlock_succeeded` | 解锁成功 | `{method: "password"\|"biometric", durationMs}` |
| `unlock_failed` | 解锁失败 | `{method, reason: "wrong_password"\|"biometric_failed"\|"decrypt_error"}` |
| `lock_triggered` | 锁定触发 | `{reason: "timeout"\|"background"\|"manual"}` |
| `master_password_required` | 强制主密码触发 | `{trigger: "high_sensitive"\|"biometric_invalid"}` |
| `biometric_setup` | 设置生物解锁 | — |
| `biometric_unlock_succeeded` | 生物解锁成功 | `{durationMs}` |
| `biometric_unlock_failed` | 生物解锁失败 | `{reason}` |
| `biometric_invalidated` | 生物变更检测 | — |
| `master_password_changed` | 主密码修改完成 | `{via: "normal"\|"recovery"}` |
| `recovery_initiated` | 忘码恢复入口浮现 | — |
| `recovery_succeeded` | 忘码恢复成功 | — |
| `deadlock_wipe_triggered` | 死锁擦除触发 | — |
| `wipe_completed` | 擦除完成 | `{via: "normal"\|"deadlock"}` |

### vault(密码库)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `entry_created` | 新增条目 | `{entryId}` |
| `entry_updated` | 修改条目 | `{entryId}` |
| `entry_deleted` | 删除条目 | `{entryId}` |

### generator(密码生成)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `password_generated` | 生成密码 | `{mode, length, entropyBits}` |

### search(搜索)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `search_executed` | 执行搜索 | `{resultCount, durationMs}` |

### migration(迁移)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `migration_initiated` | 发起迁移 | `{role: "sender"\|"receiver"}` |
| `migration_completed` | 迁移完成 | `{entryCount, durationMs}` |
| `migration_aborted` | 迁移中断 | `{reason}` |

### system(系统)

| 事件名 | 触发时机 | params |
--------|---------|--------
| `kdf_benchmark_completed` | 基准测试完成 | `{selectedParams, durationMs}` |
| `params_upgraded` | KDF/AEAD 参数升级 | `{from, to}` |

> 所有 params 中的 `entryId` 为随机 UUID,不含明文;`reason`/`method` 等为枚举字符串,不含敏感数据。

## 2.1 业务失败与系统故障

- **业务失败**:指正常产品流程中预期发生、并已被 use case 显式建模为 `Result` failure 的分支。例如错误主密码、生物认证被用户取消。
- **系统故障**:指未被 use case 吸收、继续上抛的异常。例如 vault 文件损坏、I/O 故障、crypto 初始化失败、状态违例。

记录要求:

- 业务失败:
  - 允许埋点与计数
  - 默认使用 `info` / `warning`
  - 不默认附带异常堆栈
- 系统故障:
  - 使用 `error`
  - 记录异常对象与堆栈
  - 进入诊断与排障路径

## 3. 脱敏管道(管道式)

所有 `Logger` 实现内部经过管道式脱敏过滤器,调用方不需要自觉脱敏,机制兜底:

```dart
class RedactionFilter {
  static const _sensitiveKeys = {
    'password', 'key', 'mvk', 'kek', 'dek', 'k_bio', 'secret',
    'master_password', 'wrapped_key', 'plaintext', 'entry_ciphertext',
  };

  Map<String, dynamic> redact(Map<String, dynamic>? context) {
    if (context == null) return {};
    return context.map((k, v) {
      if (_sensitiveKeys.any((s) => k.toLowerCase().contains(s))) {
        return MapEntry(k, '[REDACTED]');
      }
      return MapEntry(k, v);
    });
  }
}
```

- 过滤器对 context 的 key 做子串匹配(大小写不敏感),命中敏感关键词的 value 替换为 `[REDACTED]`。
- 过滤器位于 `Logger` 实现的输出管道中,所有日志输出前必经此过滤。
- `message` 正文不由过滤器处理——调用方有责任不在 message 中拼接敏感值;过滤器只兜底 `context` map。
- `EventTracker` 和 `MetricsRecorder` 的 params 不过管道——这些接口的 params 由调用方传入结构化数据,设计上不含敏感值(见 §2 表格)。
- 第三方异常原文若包含潜在敏感上下文,在进入 `Logger.error` 前也应先做项目内收束或筛洗,不得直接原样打出。

## 4. 日志文件存储

### 4.1 路径

经 `path_provider` 获取平台目录:
- Android:`getApplicationDocumentsDirectory()` → `/data/data/<package>/files/logs/`
- iOS:`getApplicationDocumentsDirectory()` → `NSDocumentDirectory/logs/`

### 4.2 文件名与滚动

- 当前日志文件:`app.log`
- 滚动策略:按大小滚动,单文件上限 **2 MB**;滚动时重命名为 `app.log.1`、`app.log.2`、`app.log.3`,保留最近 **3 个**备份(共 ~8 MB 上限)。
- 超过 3 个备份时最旧的删除。
- 日志格式:每行一条,`[ISO8601] [LEVEL] [tag] message {context_json}`,便于 `grep` 与日后解析。

### 4.3 生产 vs 开发

- 开发期:同时输出到控制台(`debugPrint` 等效)和文件。
- 生产期:仅输出到文件(禁止控制台输出,避免 logcat/Xcode console 泄露)。
- 切换由编译期常量(`kReleaseMode`)或 `core/config` 控制。

## 5. 监控指标存储

- 指标本地存储,不上报外部(见 [DEVELOPMENT.md §6](../DEVELOPMENT.md))。
- 耗时分布:内存中维护滑动窗口(最近 N 次记录),用于自适应调参(KDF 参数升级时读取 P95 耗时)。
- 计数:内存计数器,app 重启后重置;可选持久化到设置文件(未来版本)。

## 6. 测试可注入性

- `Logger`、`EventTracker`、`MetricsRecorder` 均为抽象接口,测试中可注入 fake/spy。
- `RecordingEventTracker`:test spy 实现,记录所有 `track` 调用供断言(如集成测试断言 `lock_triggered` 事件被触发)。
- `RecordingLogger`:记录所有日志调用供断言(如测试断言 error 级日志未输出明文)。
- 集成测试在 `get_it` 中 override 注册为 recording 实现(见 [ADR-0001](../adr/0001-dependency-injection-with-get-it.md))。
- `RedactionFilter` 可独立单测:构造含敏感 key 的 context,断言输出为 `[REDACTED]`。
