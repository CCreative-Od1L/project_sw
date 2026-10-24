# 依赖 CI 维护记录

> 记录日期：2026-10-23（America/Los_Angeles；远端运行发生在 2026-10-24 UTC）。按用户确认的顺序逐项处理，任务只基于已合并的共同主干。

## 修复与交付

| PR | 处置 | 直接证据 |
|---|---|---|
| [#106 cupertino_icons](https://github.com/CCreative-Od1L/project_sw/pull/106) | 升至 2.0.0，移除旁系锁文件升级；已合并为 `7ba884f` | 仅两个依赖文件变化；严格锁文件、格式、分析、283 项测试及五项远端检查通过 |
| [#107 get_it](https://github.com/CCreative-Od1L/project_sw/pull/107) | 从 #106 已交付主干独立升至 9.3.0；已合并为 `bae324d` | 仅目标包版本/校验和与 manifest 变化；同样通过 283 项测试和五项远端检查 |
| [#104 AGP / Gradle](https://github.com/CCreative-Od1L/project_sw/pull/104) | 已合并为 `60bec47`：AGP 9.4.1、最低 Gradle 9.6.0，并校验官方分发包 SHA-256 | 本地格式、分析、283 项测试、实际 APK 构建，以及五项远端检查全部通过 |

#106/#107 的原失败发生在锁文件校验：机器人同时升级了 intl、test 等 Flutter 固定的旁系包。使用当前 FVM SDK 从主干锁文件重新解析后，各自只改变目标包；这不是目标包本身不兼容的证据。

#104 原本只更新 AGP，缺少 [AGP 9.4 要求的 Gradle 9.6.0](https://developer.android.com/build/releases/agp-9-4-0-release-notes#compatibility)。实际加载核验确认 Kotlin 插件仍为 2.3.20；项目保持 `android.builtInKotlin=false` 和 `android.newDsl=false`。此组合超出 [Kotlin 官方 fully supported 表](https://kotlinlang.org/docs/gradle-configure-project.html#apply-the-plugin)列出的范围，官方允许使用更新版本但可能存在弃用或新功能限制；本次验证仅说明项目现有构建/回归结果，不声明 Flutter/Kotlin 对该组合的全面支持。

## SDK 约束项

以下候选在临时目录使用当前项目 manifest/lock 和 Flutter 3.44.7 / Dart 3.12.2 分别执行 `flutter pub get`，均以依赖解析失败退出。没有通过降低检查要求或绕过锁文件采用这些版本。

| PR | 已复现的原因 | 处置 |
|---|---|---|
| [#105 test 1.31.1](https://github.com/CCreative-Od1L/project_sw/pull/105) | flutter_test 固定 test_api 0.7.11，候选要求 0.7.12 | 暂缓；由 SDK 升级任务 #114 接续 |
| [#109 intl 0.20.3](https://github.com/CCreative-Od1L/project_sw/pull/109) | flutter_localizations 固定 intl 0.20.2 | 暂缓；由 #114 接续 |
| [#108 sodium 4.1.2](https://github.com/CCreative-Od1L/project_sw/pull/108) | sodium >=4.1.0 要求 Dart >=3.13.0，当前为 3.12.2 | 暂缓；由 #114 接续 |

[SDK 升级任务 #114](https://github.com/CCreative-Od1L/project_sw/issues/114) 记录目标组合选择、SDK/CI 一致性、Android 工具链与原生 crypto 回归要求。旧候选按暂缓处置关闭；升级任务继续开放。

Dependabot 配置使用明确版本名单：`test 1.31.1/1.31.2/1.32.0/1.33.0`、`intl 0.20.3`、`sodium 4.1.0/4.1.2`。官方 registry 核验确认这些 test 版本分别固定 test_api 0.7.12–0.7.15，两个 sodium 版本均要求 Dart 3.13；这样避免关闭旧候选后立即生成另一个已知不兼容版本。没有使用包级通配符或忽略未来所有版本。目标 SDK 能解析兼容组合后，在 #114 中移除对应规则并提交新升级 PR。原有三个生态的更新计划与 PR 数量限制不变，其他版本仍接受正常审核。

## 分支与验证边界

- #106、#107、#104 分别使用独立 worktree，并只从已合并主干创建或同步；本维护文档/配置也是独立交付，不把未合并迁移 #113 当作前置。
- 原始来源与修复提交分别保存在 `.git/branch-backups/2026-10-23/` 的 bundle 中，删除来源分支前核对完整 head，使用 SHA 租约。
- 维护交付后，仍活动的迁移分支只从最新主干同步，再运行格式、分析、全量测试和远端检查。
- [迁移 #113](https://github.com/CCreative-Od1L/project_sw/pull/113) 仍需双 Android 真机验收，旧 #64 保留作对照；设备恢复/擦除和正式发布验收也继续开放。
- #101、#102、#103、#110 是独立可选维护；现有绿色检查不表示这些更新已经合并，也不表示多个工具链升级的组合已验证。
