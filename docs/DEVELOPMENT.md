# 开发指南 · PROJECT_SW

> 本文档规定 PROJECT_SW 的开发环境、代码规范、测试体系、可观测性、版本与发布流程。
> 架构见 [ARCHITECTURE.md](./ARCHITECTURE.md),安全见 [SECURITY.md](./SECURITY.md)。

## 1. 环境准备

### 1.1 基础工具
- **Flutter**:稳定通道(stable),保持团队约定版本(见 `flutter --version`,建议用 fvm 锁定)。
- **Dart**:随 Flutter 附带。
- **Git**:项目初始化后启用(当前尚未 `git init`,为首个开发任务)。

### 1.2 原生构建依赖(libsodium)
本项目使用 `sodium_libs`(libsodium 的 Flutter 绑定,采用 Flutter build hooks 自动处理各平台二进制)。需准备的本地工具:
- macOS / Linux:`make`、基础编译工具链
- Android 交叉编译(尤其 Windows 主机):参见 `sodium_libs` 文档的跨编译说明
- iOS:通过 Swift Package 静态链接(由 build hooks 处理)

> 若原生构建成为负担,可临时降级为纯 Dart 方案 `cryptography_plus`(信封架构与具体库解耦,迁移成本可控,见 ARCHITECTURE.md §设计原则 5)。

## 2. 项目初始化步骤(首个开发任务)

1. `git init`,配置 `.gitignore`(Flutter 标准模板 + 本地密码库文件、密钥、日志输出)。
2. `flutter create . --org <org> --platforms=ios,android`(按需扩展桌面/web)。
3. 按 [ARCHITECTURE.md §5](./ARCHITECTURE.md) 建立目录骨架:顶层 `lib/features/`(6 条业务线,每条内含 `presentation/`/`domain/`/`data/`)、`lib/core/`、`lib/shared/`、`lib/app/`;顶层 `test/features/`、`test/core/`、`integration_test/`。
4. 引入依赖:`sodium_libs`、`flutter_bloc`(含 Cubit)、`intl`、测试与可观测性依赖(见 §6)。
5. 配置 `analysis_options.yaml`(lint 严格档,见 §4)。
6. 添加 LICENSE(MIT)。

## 3. 代码规范

- **语言**:Dart,遵循官方风格指南 + `flutter_lints`(严格档)。
- **架构纪律**:
  - domain 层零 Flutter/平台导入,纯 Dart,可独立单测。
  - 依赖方向单向向内;外层依赖内层接口,禁止反向。
  - 加解密一律经 `CryptoService` 抽象,禁止在 presentation/domain 直接调用 libsodium。
  - 敏感数据(密码、密钥)不得进入全局可观察状态或日志。
- **命名**:文件 `snake_case`,类 `PascalCase`,变量/函数 `camelCase`;接口不加 `I` 前缀,实现可加 `Impl` 后缀。
- **不可变**:State、Entity 值对象使用不可变类 + `copyWith`;使用 `const` 构造。
- **错误处理**:domain 抛领域异常,presentation 负责用户可见映射;禁止吞异常。
- **注释**:公共 API 用 `///` 文档注释;复杂密码学/安全逻辑必须注释理由(引用 SECURITY.md 小节)。

## 4. 静态分析与格式化

```yaml
# analysis_options.yaml(示意)
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  exclude: [build/**, .dart_tool/**]
linter:
  rules:
    prefer_const_constructors: true
    avoid_print: true            # 日志走 observability,禁止裸 print
    public_member_api_docs: true
    # ... 按需追加
```
- 格式化:`dart format`(提交前)。
- 提交前本地:`dart analyze` + `dart test` 必须通过。

## 5. 测试体系

对应需求"功能测试 / 集成测试 / widget 测试等":

| 层级 | 目标 | 工具 | 覆盖重点 |
|------|------|------|----------|
| 单元测试 | domain use case、纯函数、密码生成器(模式覆盖、字符集并集、长度边界、排除易混、**无偏抽样**、**理论熵估算校验**)、加密信封编解码 | `package:test` | 业务逻辑与密码学正确性(含 KDF/AEAD 向量、信封包裹/解包、错误路径);生成器随机源须用同源 CSPRNG(见 [SECURITY.md §15](./SECURITY.md)) |
| Widget 测试 | 单个组件/页面在给定 State 下的渲染与交互 | `flutter_test` | UI 状态映射、事件上报、错误展示 |
| 集成测试 | 端到端关键流(首次建库→解锁→增删改查→锁定→生物解锁→迁移);**迁移细节**(发送端解包 DEK 会话加密传输、接收端 seq 透传不改写、entry_id 冲突整条覆盖、目录双写原子切换/中途崩溃回滚);**认证强度策略路径**(冷启动强制主密码、高敏操作强制主密码、超时后仍允许生物);**超时锁定**(当前固定:空闲 5min、切后台立即锁、切后台锁不可禁用;设置中可见);**剪贴板**(敏感字段复制后 20s 自动清除、倒计时提示、iOS 禁用 Handoff);**忘主密码边界**(已设生物+生物未变仍可访问、生物失效后不可恢复、正常擦除须主密码、**死锁擦除**:特定手势浮现+四重摩擦+不要求主密码);**忘码恢复通道**(改密码连续错 ≥3 次浮现入口、一周冷却、二次生物确认、强告知接管风险) | `integration_test` | 跨层协作、真实存储、超时锁定(参数见 [SECURITY.md §10.1](./SECURITY.md))、剪贴板卫生(见 [§7.1](./SECURITY.md))、忘主密码(见 [§10.2](./SECURITY.md))、迁移(见 [§8.1](./SECURITY.md))、强度档位切换 |
| 加密专项 | 解密失败/篡改/nonce/参数升级等安全路径;**外壳解析与完整性**(逐字段损坏验证检测、free list/journal 重放与回滚、AAD 绑定校验、序列化往返一致性);**Entry Block 双段**(dek 段定长 72B 原地覆写、改 DEK 不动 entry 段、双段往返一致) | `package:test` | 见 SECURITY.md §威胁模型、§5 |

要求:
- domain 与 crypto 层单元测试覆盖率目标 ≥ 90%;关键安全路径 100%。
- 密码学测试使用已知向量与往返(encrypt→decrypt)一致性校验。
- 集成测试在 CI 的移动端模拟器上运行。
- 禁止在测试中输出真实敏感数据;使用固定测试向量。

## 6. 可观测性(日志 / 埋点 / 监控)

对应需求"日志系统、埋点以及监控":
- **统一入口**:`core/observability` 提供日志、埋点、监控抽象,各层通过它上报,禁止裸 `print`/`debugPrint`。
- **脱敏**:所有日志/埋点经脱敏过滤器,禁止记录明文密码、密钥、条目内容(见 SECURITY.md §7)。只可记录条目 id、操作类型、耗时、错误码、KDF 耗时(用于自适应调参)等。
- **日志**:分级(verbose/info/warning/error);开发期可写控制台,生产期可写**本地滚动明文文件**并受容量上限(加密决策见下条)。
- **埋点**:关键业务事件(建库、解锁成功/失败、迁移完成、锁定触发、强制主密码触发、忘码恢复触发/成功、死锁擦除触发);本地计数,不上报外部。
- **监控**:本地健康指标(解锁耗时分布、加解密耗时、错误率),用于自适应调参与异常发现;**本地为主,无外传**。
- **本地日志不加密(已定)**:日志文件保持**脱敏后明文滚动存储**,不加密。理由:① 日志第一职责是诊断(解锁失败、启动错误、崩溃等),而这些事件恰恰发生在 MVK 不可用的未解锁/锁定态——用 Master Vault Key 派生子密钥加密日志会使最该被记录的诊断事件在加密形态下写不进去,自废诊断职责;② 独立 Keychain 密钥方案要么不生物门控(强度≈设备本身,对能读日志的攻击者无防护收益)要么门控(回退自废诊断),均不可取;③ 脱敏后日志无明文敏感字段,残余的行为元数据(entry id 为随机 UUID、操作类型、耗时)信息量有限且需结合"这是谁的设备"才有效用,而能读日志者大概率已物理接触设备、落在 [SECURITY.md §13](./SECURITY.md) 声明不防御的范围内。综合可诊断性与复杂度,脱敏明文为最终方案。

## 7. 版本管理

> 完整的 Git 工作流规范(分支模型、提交格式、PR 生命周期、标签与发布)见 [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)。

- **Git 分支策略**:简洁主干开发 + 功能分支;`main` 始终可发布。
- **提交规范**:Conventional Commits(`feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:` / `security:`)。
- **语义化版本**:SemVer `MAJOR.MINOR.PATCH`;移动端构建号 `+N` 递增。
- **CHANGELOG.md**:随版本更新,记录用户可见变化。
- **依赖锁定**:`pubspec.lock` 入库;定期检查依赖安全更新。

## 8. 脚本化打包与 CI/CD

对应需求"脚本化打包流程、CI/CD 流程":

### 8.1 打包脚本
- 统一打包脚本(`scripts/`),参数化平台与环境(dev/staging/release):
  - `scripts/build_android.sh` —— APK/AAB,签名配置经环境变量注入,禁止入库密钥库。
  - `scripts/build_ios.sh` —— IPA,经 fastlane gym,签名经 match/ci。
- 签名密钥、证书、密钥库**绝不入库**,通过 CI secrets / 本地环境变量提供。

### 8.2 CI(GitHub Actions,示意)
- **PR 检查**:`dart analyze` + `dart format --set-exit-if-changed` + `flutter test` + 集成测试(模拟器)。
- **主分支**:同上 + 构建 release 产物 + 上传为 artifact。
- **发布**:打 tag 触发 release 流水线,构建各平台分发包并发布。
- 安全:CI 中禁用打印 secrets;依赖固定版本与 hash 校验。

### 8.3 CD / 分发
- Android:内测经 Firebase App Distribution 或自建渠道;正式经商店(可选)。
- iOS:内测经 TestFlight;正式经 App Store(可选)。
- 作为个人项目,分发渠道可简化,但流程脚本化、可重放是目标。

## 9. 发布 → 维护闭环

对应需求"走通开发 - 分发 - 维护的软件工程实践流程":
1. **开发**:功能分支 → PR → CI 全绿 → 合并。
2. **发布**:更新版本号与 CHANGELOG → 打 tag → CI 构建分发包 → 分发。
3. **维护**:依赖与安全更新定期处理;安全问题经 `security:` 提交并优先发版;用户反馈经 issue 跟踪。
4. **可重放**:任何历史版本可由 tag 重新构建。

## 10. 依赖策略

- 最小化依赖,优先官方/高维护状态包;新增依赖需评估维护状态、许可证、安全记录。
- 核心安全依赖(`sodium_libs`)锁定具体版本并追踪上游安全公告。
- 禁止引入任何会上报外部/联网分析的"分析"类依赖(与本地优先原则冲突)。

## 11. 待补全

- [ ] `pubspec.yaml` 依赖清单(含 dev 依赖)
- [ ] `analysis_options.yaml` 最终 lint 规则集
- [ ] CI workflow 文件(.github/workflows/)
- [ ] 打包脚本与签名流程细则
- [x] ~~本地日志加密方案决策~~ → 已定:不加密,脱敏后明文滚动存储(见 §6,理由:诊断职责冲突 + 残余威胁落在 [SECURITY.md §13](./SECURITY.md) 不防御范围)
