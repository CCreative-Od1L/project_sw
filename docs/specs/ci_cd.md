# CI/CD 设计规格 · PROJECT_SW

> 概述见 [DEVELOPMENT.md §8](../DEVELOPMENT.md);触发点与分支保护见 [GIT_WORKFLOW.md](../GIT_WORKFLOW.md)。
> 本规格为 CI/CD 的**设计依据**,代码就绪后据此落地 `.github/workflows/` 与 `scripts/`。当前项目处于设计阶段(无 `pubspec.yaml` / `.github/` / `scripts/`),本规格不假设任何已存在代码。

## 1. 目标与定位

- **目标**:把"开发 → 分发 → 维护"闭环中可自动化的部分固化为可重放的流水线:PR 把关、主干守稳、tag 发版、产物可追溯。
- **定位**:个人项目,流程脚本化、可重放优先;分发渠道可简化,但 CI 把关不省。
- **平台范围**:与 [ARCHITECTURE.md](../ARCHITECTURE.md) 一致,移动端优先(iOS / Android);桌面/Web 若后续纳入,CI 矩阵相应扩展。
- **CI 平台**:GitHub Actions(与远端 `origin` 一致,免额外基础设施)。

## 2. 流水线分层与触发器

四条独立 workflow,触发器分离,职责不混。

| Workflow | 触发器 | 职责 | 失败后果 |
|----------|--------|------|----------|
| **`ci.yml`(PR/主干检查)** | `pull_request`(目标 `master`)、`push`(到 `master`) | 静态分析 + 格式化 + 单元/widget 测试 + 集成测试 | 阻止 PR 合并(分支保护要求状态检查通过) |
| **`build.yml`(产物构建)** | `push` 到 `master`、`workflow_dispatch` | 构建 debug/release 产物并上传 artifact | 不阻断主干,但 artifact 缺失可被发版流程检出 |
| **`release.yml`(发版)** | `push` tag `v*.*.*` | 构建各平台 release 分发包、签名、创建 GitHub Release | 发版失败,不打 tag 不发版 |
| **`scheduled.yml`(定期维护)** | `schedule`(每周)、`workflow_dispatch` | 依赖过期检查(`dart pub outdated`)、安全审计、SDK 上限漂移检测 | 仅报告,开 issue 跟踪 |

> 触发器与 [GIT_WORKFLOW.md §1.1/§4.2](../GIT_WORKFLOW.md) 对齐:PR 必过 `ci.yml`,tag 触发 `release.yml`。

## 3. Job 矩阵(`ci.yml`)

| 维度 | 取值 | 说明 |
|------|------|------|
| OS | `ubuntu-latest` | 单元/widget/集成测试跑 Linux runner(成本低);平台真机签名在 `release.yml` 各自 OS runner 跑 |
| Flutter 通道 | `stable` | 单通道;用 fvm 锁定具体版本(见 [DEVELOPMENT.md §1.1](../DEVELOPMENT.md)) |
| Dart SDK | 随 Flutter | 不单独约束 |
| 测试目标 | `flutter test`(unit+widget)+ `integration_test` | 集成测试在 Linux 模拟器或 `integration_test` 桌面回退跑 |

> 集成测试跑模拟器成本高且易抖动;若 Linux runner 跑移动端模拟器不稳,回退方案:集成测试在 `integration_test` 桌面宿主跑(平台无关逻辑),平台特异性集成(生物/Keychain/迁移)留作本地手动 + 发版前冒烟。**回退决策留待实现期**,本规格锁定"集成测试须在 CI 跑"的硬要求,具体承载实现期定。

## 4. 检查项与执行顺序(`ci.yml`)

按"快失败在前"排序,任一失败即终止后续:

1. **checkout + setup**(Flutter via `subosito/flutter-action`,锁定版本)
2. **依赖缓存**(`pub-cache` 缓存,见 §5)
3. **`dart pub get`**(基于入库的 `pubspec.lock`,可重放)
4. **`dart format --set-exit-if-changed .`**(格式化把关)
5. **`dart analyze`**(静态分析,严格档 [DEVELOPMENT.md §4](../DEVELOPMENT.md))
6. **`flutter test`**(单元 + widget)
7. **`flutter test integration_test/`**(集成测试)

> 顺序与 [GIT_WORKFLOW.md §3.3](../GIT_WORKFLOW.md) 提交前本地检查一致,CI 是同一套的强制重放。

## 5. 缓存策略

- **`pub-cache`**:key 含 `pubspec.lock` hash + OS + Flutter 版本;命中跳过依赖下载。
- **Flutter SDK**:由 `subosito/flutter-action` 内部缓存,版本钉死。
- **Gradle / CocoaPods**(发版构建):各自缓存,key 含 lockfile hash。
- 不缓存 `build/`、`.dart_tool/`(产物缓存易脏,重建成本低)。

## 6. Runner 选型

- `ci.yml` / `build.yml`(debug):`ubuntu-latest`(免费额度足够,个人项目)。
- `release.yml`:按平台分 job——Android 构建用 `ubuntu-latest`,iOS 构建/签名用 `macos-latest`(Xcode 仅 macOS)。各 job 并行,产物统一上传后由一个汇总 job 创建 Release。
- 不使用自托管 runner(个人项目无必要,且引入维护面)。

## 7. 签名与机密注入

| 平台 | 签名材料 | 注入方式 | 出处 |
|------|----------|----------|------|
| Android | keystore(`.jks`/`.keystore`)、key alias/passwords、play service json(若上架) | GitHub Actions **加密 secret** → 环境变量 → `build.gradle.kts` 读取;CI 临时解码 keystore 到 runner,job 结束随 runner 销毁 | [DEVELOPMENT.md §8.1](../DEVELOPMENT.md)、[GIT_WORKFLOW.md §6.2](../GIT_WORKFLOW.md) |
| iOS | signing certificate(`.p12`)、provisioning profile(`.mobileprovision`)、App Store Connect key | 经 **fastlane match**(机密仓库或 CI secret)拉取;`fastlane gym` 构建 + 签名 | [DEVELOPMENT.md §8.1](../DEVELOPMENT.md) |

**硬约束**([GIT_WORKFLOW.md §6.2](../GIT_WORKFLOW.md)):
- 签名密钥、证书、密钥库**绝不入库**;`.gitignore` 已排除(`*.keystore`、`*.jks`、`*.p12`、`*.p8`、`*.mobileprovision`、`.env*`)。
- CI 日志禁用 `ACTIONS_STEP_DEBUG` 打印 secret;GitHub 自动 mask 注入的 secret 值。
- secret 最小权限:发版 workflow 用 `environment: release`(带必需 reviewer / 分支限定),`ci.yml` 不持有任何签名 secret。

## 8. 产物与留存

| Workflow | 产物 | 留存 |
|----------|------|------|
| `build.yml` | debug APK(Android)、debug IPA(iOS,若有签名) | GitHub Actions artifact,90 天 |
| `release.yml` | signed AAB/APK(Android)、signed IPA(iOS) | 绑定到 GitHub Release,长期 |

- 产物命名含版本号 + commit short sha + 平台,可追溯到具体提交。
- `release.yml` 产物上传后,在 GitHub Release 描述附 `CHANGELOG.md` 对应段落 + commit 范围链接。

## 9. 依赖校验与安全

- **`pubspec.lock` 入库**(已约定 [DEVELOPMENT.md §7](../DEVELOPMENT.md)):CI `dart pub get` 基于锁文件,保证可重放。
- **依赖固定**:Actions 第三方 action 钉 tag + SHA(`uses: <action>@<tag>` 并注释 SHA),防供应链篡改。
- **定期审计**(`scheduled.yml`):`dart pub outdated` + 安全公告扫描;发现高危依赖开 issue,按 `security:` 提交处理并优先发版([GIT_WORKFLOW.md §6.3](../GIT_WORKFLOW.md))。
- CI 中禁用打印 secrets;workflow 不含任何硬编码凭据。

## 10. 发版流水线(`release.yml`)

触发:`push` tag `v*.*.*`(annotated tag,[GIT_WORKFLOW.md §4.2](../GIT_WORKFLOW.md))。

1. 校验 tag 格式 + `CHANGELOG.md` 含对应版本段落(缺失则失败)。
2. 并行构建:Android(`ubuntu-latest`)、iOS(`macos-latest`),各签名。
3. 汇总 job:创建 GitHub Release(tag 对应),上传 signed 产物,附 `CHANGELOG.md` 摘要 + commit 范围。
4. 分发(可选,实现期定):Android → Firebase App Distribution / Play;iOS → TestFlight / App Store。个人项目阶段可仅到"GitHub Release 产物",分发渠道按需接。

> 发版前的版本号/CHANGELOG 提交(`chore(release): bump version to vX.Y.Z`)由人手工做([GIT_WORKFLOW.md §4.3](../GIT_WORKFLOW.md)),CI 只在 tag 触发后接管构建与发布。

## 11. 与分支保护的耦合

`master` 分支保护([GIT_WORKFLOW.md §5](../GIT_WORKFLOW.md))要求:

- 要求 PR + 状态检查通过 → `ci.yml` 的 check 名须与分支保护配置一致。
- 要求分支最新 → PR 须基于最新 `master`,否则 CI 在 stale 分支上跑的结果不计。
- 禁止强制推送 → 历史(含已发版 tag)不可改写,保证"任何历史版本可由 tag 重新构建"([DEVELOPMENT.md §9](../DEVELOPMENT.md))。

> 分支保护规则需在 GitHub Settings 手动配置;CI workflow 落地后同步配置,使 check 名对齐。

## 12. 落地里程碑(代码就绪后)

本规格为设计依据,实际 YAML/脚本在代码骨架就绪后分阶段落:

1. **`flutter create` 后**:落 `ci.yml`(步骤 1–6,集成测试步骤 7 在模拟器方案定后补);同步配置 `master` 分支保护。
2. **首个可运行构建后**:落 `build.yml`(debug 产物 + artifact)。
3. **首次发版前**:落 `release.yml` + `scripts/build_android.sh` / `scripts/build_ios.sh` + 签名 secret 配置;跑通一次 tag → Release。
4. **稳定后**:落 `scheduled.yml`(依赖/安全审计)。

## 13. 待决(实现期)

- [ ] 集成测试在 CI 的承载方式(Linux 模拟器 vs `integration_test` 桌面回退 vs 平台特异性本地手动)
- [ ] 分发渠道最终取舍(仅 GitHub Release / 接 Firebase / 接商店)
- [ ] iOS 签名方案确认(fastlane match 仓库选址 vs CI secret)
- [ ] fvm 锁定的 Flutter 具体版本号
