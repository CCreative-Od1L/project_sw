# CI/CD 设计规格 · PROJECT_SW

> 概述见 [DEVELOPMENT.md §8](../DEVELOPMENT.md);触发点与分支保护见 [GIT_WORKFLOW.md](../GIT_WORKFLOW.md)。
> 本规格为 CI/CD 的**设计依据**。PR/主干质量门禁已开始落地到
> `.github/workflows/ci.yml`;移动端集成测试由 `integration.yml` 的 Android
> 模拟器承载。构建与定期维护工作流也已落地,签名发布继续按 §12 分批实现。

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
| **`build.yml`(产物构建)** | `push` 到 `master`、`workflow_dispatch` | 构建 debug 产物并上传 artifact;签名 release 产物由 `release.yml` 负责 | 不阻断主干,但 artifact 缺失可被发版流程检出 |
| **`release.yml`(发版)** | `push` tag `v*.*.*` | 构建各平台 release 分发包、签名、创建 GitHub Release | 发版失败,不打 tag 不发版 |
| **`scheduled.yml`(定期维护)** | `schedule`(每周)、`workflow_dispatch` | 依赖过期检查、pub 安全公告解析、锁定 SDK 工具链记录 | 生成报告 artifact,由 Dependabot PR 跟踪可用更新 |

> 触发器与 [GIT_WORKFLOW.md §1.1/§4.2](../GIT_WORKFLOW.md) 对齐:PR 必过 `ci.yml`,tag 触发 `release.yml`。

## 3. Job 矩阵(`ci.yml`)

| 维度 | 取值 | 说明 |
|------|------|------|
| OS | `ubuntu-latest` | 单元/widget/集成测试跑 Linux runner(成本低);平台真机签名在 `release.yml` 各自 OS runner 跑 |
| Flutter 通道 | `stable` | 单通道;必须由 `.fvmrc` 锁定具体版本，开发与 CI 一律通过 `fvm flutter` / `fvm dart` 调用(见 [DEVELOPMENT.md §1.1](../DEVELOPMENT.md)) |
| Dart SDK | 随 Flutter | 不单独约束 |
| 测试目标 | `fvm flutter test`(unit+widget)+ `integration_test` | 集成测试在 Linux 模拟器或 `integration_test` 桌面回退跑 |

> 集成测试跑模拟器成本高且易抖动;若 Linux runner 跑移动端模拟器不稳,回退方案:集成测试在 `integration_test` 桌面宿主跑(平台无关逻辑),平台特异性集成(生物/Keychain/迁移)留作本地手动 + 发版前冒烟。**回退决策留待实现期**,本规格锁定"集成测试须在 CI 跑"的硬要求,具体承载实现期定。

## 4. 检查项与执行顺序(`ci.yml`)

按"快失败在前"排序,任一失败即终止后续:

1. **checkout + setup**(GitHub Action 直接读取入库 `.fvmrc`,安装其中锁定的 Flutter SDK)
2. **依赖缓存**(`pub-cache` 缓存,见 §5)
3. **`fvm flutter pub get`**(基于入库的 `pubspec.lock`,可重放)
4. **`fvm dart format --set-exit-if-changed .`**(格式化把关)
5. **`fvm dart analyze`**(静态分析,严格档 [DEVELOPMENT.md §4](../DEVELOPMENT.md))
6. **`fvm flutter test`**(单元 + widget)
7. **`fvm flutter test integration_test/`**(由独立 Android 模拟器 job 执行)

> 顺序与 [GIT_WORKFLOW.md §3.3](../GIT_WORKFLOW.md) 提交前本地检查一致。CI
> 直接调用由 `.fvmrc` 锁定并安装的 SDK;本地仍通过 FVM 调用同一版本。

## 5. 缓存策略

缓存 = 跨 workflow run 复用的文件存档(依赖包 / 编译中间件),让第二次及之后的构建跳过"装依赖 / 编译"的几分钟。**只缓存重建成本高且随 lockfile 变的工具产物;不缓存源码、不缓存 `build/`、不缓存随机输出。**

### 5.1 执行机制(一次缓存的生命周期)

`actions/cache` 在一次 job 中分两段执行:

```
job 启动
 ├─ uses: actions/cache@v4          ← restore 阶段(步骤执行时)
 │    ├─ 用 key 查缓存服务
 │    ├─ 命中 → 下载解压到 path,设 cache-hit=true
 │    └─ 未命中 → 留空,后续步骤正常装依赖
 ├─ fvm flutter pub get / fvm flutter test …   ← 正常构建(复用缓存或新装)
 └─ job 结束自动 save(post-run)      ← 由 cache action 自动追加
      ├─ key 命中过 → 不重存
      └─ key 未命中 → 打包(tar+zstd)上传,记为 key
```

要点:
- **save 是自动的**:写一次 `actions/cache`,它在 job 末尾自动保存,无需显式 save 步骤。
- **命中不重存**:精确命中时 post-run 不重复上传(省时省带宽)。
- **未命中才存**:key 变了(依赖更新)才存新缓存。
- 仍可显式用分离的 `actions/cache/restore` + `actions/cache/save` 实现"只读恢复"或"集中写"模式(见 §5.6 防投毒)。

### 5.2 key 匹配规则

`actions/cache` 用 `key`(主键,精确匹配)+ `restore-keys`(回退键,前缀匹配)两级:

1. 当前分支找 `key` **精确匹配** → 命中,`cache-hit=true`。
2. 未命中 → `restore-keys` **按顺序前缀匹配**(最具体到最宽泛),取**最近创建**那条,`cache-hit=false`。
3. 当前分支都没有 → 去**默认分支**重复 1、2。
4. 都没有 → 完全 miss,空起步,job 结束存新缓存。

**`restore-keys` 的真实角色**:部分恢复——给一份旧缓存作底,工具自己补差异。用 restore-keys 后**仍要跑 `fvm flutter pub get`**,它复用已存在的、补下新增的,而非全量重下。

### 5.3 key 设计(本项目)

```yaml
# pub 依赖
key: ${{ runner.os }}-pub-${{ hashFiles('pubspec.lock') }}-flutter${{ env.FLUTTER_VERSION }}
restore-keys: |
  ${{ runner.os }}-pub-
# Gradle(Android 发版)
key: ${{ runner.os }}-gradle-${{ hashFiles('android/**/*.gradle*', 'android/**/gradle-wrapper.properties') }}
restore-keys: |
  ${{ runner.os }}-gradle-
# CocoaPods(iOS 发版)
key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}
restore-keys: |
  ${{ runner.os }}-pods-
```

- `key` 含 lockfile hash + OS + Flutter 版本:**lockfile 没变就精确命中**,直接复用。
- `restore-keys` 留宽前缀:lockfile 变了时取回上次缓存,`pub get` 增量补差异。
- Flutter 版本进 key:`subosito/flutter-action` 钉死的版本一旦升,缓存自动失效重建,避免新旧 SDK 产物混用。

### 5.4 cache-hit 语义与步骤跳过

精确命中(`cache-hit == 'true'`)可跳过依赖安装;用 restore-keys 部分命中时仍需安装:

```yaml
- uses: actions/cache@v4
  id: pub-cache
  with:
    path: ~/.pub-cache
    key: ${{ runner.os }}-pub-${{ hashFiles('pubspec.lock') }}-flutter${{ env.FLUTTER_VERSION }}
    restore-keys: ${{ runner.os }}-pub-
- if: steps.pub-cache.outputs.cache-hit != 'true'   # 仅未命中时装
  run: fvm flutter pub get
```

> `subosito/flutter-action` 自带 Flutter SDK 缓存,无需另写 cache step;版本经 `flutter-version: ${{ env.FLUTTER_VERSION }}` 钉死,与 pub-cache key 里的版本同源(共用 `env.FLUTTER_VERSION`)。

### 5.5 作用域与分支隔离

缓存按分支隔离,这是**最关键也最反直觉**的规则:

- 一个 run 能读:**当前分支** + **默认分支**(`master`)的缓存。
- 一个 run **不能读**其他非默认分支的缓存。
- PR 分支**能读默认分支缓存,但不能写**默认分支缓存(防投毒护栏)。
- **fork PR 只读不写**:来自 fork 的 PR 无权写 base 仓库缓存,天然防外部贡献者投毒。

```
            ┌──────────────────────┐
feature-a   │ 自己的缓存(可读写)  │── 读 ──┐
            └──────────────────────┘       │
                                           ▼
            ┌──────────────────────┐
master(默认)│ 默认分支缓存(全局可读) │
            └──────────────────────┘
                                           ▲
            ┌──────────────────────┐       │ 读
feature-b   │ 自己的缓存(可读写)  │── 读 ──┘   ← feature-b 读不到 feature-a
            └──────────────────────┘
```

> 含义:feature 分支首次跑常从 `master` 继承缓存,之后在该分支形成自己的缓存血脉。key 设计的"同分支复用为主"前提即此。

### 5.6 缓存安全:防投毒(发版管线必读)

`actions/cache` 有一个绕过 `permissions:` 的安全盲区(见 TanStack 等真实事件):save 发生在 post-run,**不受 job 的 `permissions:` 块约束**;若用 `pull_request_target` 跑外部代码,fork PR 能写 base 仓库缓存,可投毒——在缓存里塞恶意文件,下游流水线恢复后执行,污染发版产物。

本项目硬约束:
1. **`release.yml` 不复用 PR 路径产生的缓存**:用独立 key 前缀(如 `release-` 前缀)或发版前强制重算,确保发版缓存只由受控的 tag 触发产生。
2. **不用 `pull_request_target` 跑外部代码**:PR 检查用普通 `pull_request`,fork PR 天然只读不写 base 缓存。
3. **缓存只存工具产物,不存可执行脚本**:即使被投毒,影响面限于依赖目录,不直接导致代码执行。
4. **`release.yml` 用 `environment: release` 隔离**(已定于 §7),叠加本条缓存隔离,双重防 PR 污染发版。

### 5.7 容量与驱逐

默认配额(截至 2025-11):
- **10 GB / 仓库**(2025-11 起可付费超额,默认仍 10 GB)。
- **7 天未访问即删除**(retention)。
- **LRU 驱逐**:超 10 GB 按"最久未用"先删;2025-10 起驱逐检查从每 24 小时提至**每小时**,缓存抖动风险上升。
- 缓存条目数无上限,只受总大小约束。

本项目预估:pub-cache 通常 <1 GB,Gradle/CocoaPods 各 <1 GB,合计远低于 10 GB,无虑。仍需:
- **不缓存 `build/`、`.dart_tool/`**(产物易脏、增长快、重建成本低,是缓存膨胀主因)。
- 定期在 Actions 设置页查缓存用量;接近上限先排查是否缓存了不该缓存的目录。

### 5.8 action 版本与供应链

- 用 **`actions/cache@v4`**(2025-02 起的新缓存服务 v2 API,当前稳定版);v5 已发布但需 runner ≥2.327.1,按需评估。
- 按 §9 供应链要求:**action 钉 tag + SHA**(`uses: actions/cache@<tag>` 并注释 SHA),防 action 被篡改。
- self-hosted runner 须 ≥2.331.0 以兼容 v4(本项目不用 self-hosted,无虑)。

### 5.9 各技术栈缓存路径速查

| 技术栈 | path | key 主键依据 |
|--------|------|--------------|
| Dart/Flutter pub | `~/.pub-cache` | `pubspec.lock` |
| Flutter SDK | 由 `subosito/flutter-action` 内部缓存 | `flutter-version` |
| Gradle(Android) | `~/.gradle/caches`、`~/.gradle/wrapper` | `*.gradle*`、`gradle-wrapper.properties` |
| CocoaPods(iOS) | `~/Library/Caches/CocoaPods`、`ios/Pods` | `Podfile.lock` |

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
- Android release 配置不得回退到 debug signing;缺少 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEY_ALIAS`、`ANDROID_KEYSTORE_PASSWORD` 或 `ANDROID_KEY_PASSWORD` 时必须在 Gradle 任务中失败,且不得输出 secret 值。

## 8. 产物与留存

| Workflow | 产物 | 留存 |
|----------|------|------|
| `build.yml` | debug APK(Android)、无签名 debug `.app`(iOS) | GitHub Actions artifact,90 天 |
| `release.yml` | 当前为 tag/version/CHANGELOG 与可重建 metadata preflight;签名 AAB/APK 与 IPA 为后续 lane | metadata artifact;签名产物目标为长期绑定 GitHub Release |

- 产物命名含版本号 + commit short sha + 平台,可追溯到具体提交。
- `build.yml` 的平台构建通过 `scripts/build_android.sh debug-apk` 与
  `scripts/build_ios.sh unsigned-debug` 执行;脚本显式校验产物,避免 workflow
  命令与本地构建语义漂移。
- 当前 `release.yml` 仅上传非敏感的可重建 metadata;签名构建、GitHub Release 汇总与 `CHANGELOG.md` 摘要将在签名 lane 接入后启用。

## 9. 依赖校验与安全

- **`pubspec.lock` 入库**(已约定 [DEVELOPMENT.md §7](../DEVELOPMENT.md)):CI `fvm flutter pub get` 基于锁文件,保证可重放。
- **依赖固定**:Actions 第三方 action 钉 tag + SHA(`uses: <action>@<tag>` 并注释 SHA),防供应链篡改。
- **定期审计**(`scheduled.yml`):`fvm dart pub outdated` + 安全公告扫描;发现高危依赖开 issue,按 `security:` 提交处理并优先发版([GIT_WORKFLOW.md §6.3](../GIT_WORKFLOW.md))。
- CI 中禁用打印 secrets;workflow 不含任何硬编码凭据。

## 10. 发版流水线(`release.yml`,目标设计)

触发:`push` tag `v*.*.*`(annotated tag,[GIT_WORKFLOW.md §4.2](../GIT_WORKFLOW.md))。

当前已落地 tag 格式、版本号、`CHANGELOG.md`、annotated tag、Flutter toolchain 与 lockfile checksum 的 preflight;缺失任一项即失败。

目标签名发版流程为:

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

1. **`fvm flutter create` 后**:落 `ci.yml`(步骤 1–6,集成测试步骤 7 在模拟器方案定后补);同步配置 `master` 分支保护。
2. **首个可运行构建后**:落 `build.yml`(debug 产物 + artifact)。
3. **首次发版前**:已落 `release.yml` 的 tag/version/CHANGELOG/可重建元数据 preflight 与平台构建脚本;仍需接入 iOS 签名 lane、签名 secret 配置与 tag → Release 产物演练。
4. **稳定后**:落 `scheduled.yml`(依赖/安全审计)与 Dependabot 周期更新(已完成)。

## 13. 待决(实现期)

- [ ] 集成测试在 CI 的承载方式(Linux 模拟器 vs `integration_test` 桌面回退 vs 平台特异性本地手动)
- [ ] 分发渠道最终取舍(仅 GitHub Release / 接 Firebase / 接商店)
- [ ] iOS 签名方案确认(fastlane match 仓库选址 vs CI secret)
- [x] Flutter `3.44.7` 已由 `.fvmrc` 锁定
