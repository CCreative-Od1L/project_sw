# 远端分支清理核验与执行记录

> 核验日期：2026-10-23。首次远端快照时间（UTC）：`2026-10-23T13:12:28.807354+00:00`。删除前重新核验于 `2026-10-23T13:26:35.258616+00:00`；执行与事后核验完成于 `2026-10-23T13:28:05.104546+00:00`。已删除 **34** 个旧远端分支。

仓库 `CCreative-Od1L/project_sw` 的远端分支由 **47** 个减为 **13** 个：34 个已核验候选全部删除，其余分支保留。主干仍为 `cf15300f5400fa87054f1d86c8b486926f367004`。

后续已执行 [本地归档清理](2026-10-23-local-cleanup.md)，删除 36 个已交付本地归档分支。本页记录远端删除步骤的核验结果；已删除归档的当前恢复依据为持久 bundle，恢复源引用见本地清理数据。

## 核验口径

- 仅以共同基线 PR #99 已覆盖的旧 PR #65–#98 为候选范围，逐一核对当前远端 head 与原始记录相同。
- 34 个旧 PR 当前均为 CLOSED；开放 PR 的 head/base 均不引用这些分支，且这些分支不受保护、不是默认分支。
- GitHub rebase 已改变提交 SHA；本轮重新验证原始 36 对提交的稳定 patch-id 相等，映射后的提交均可从当前主干到达，不能只依赖 `git branch --merged` 判断。
- 原始归档 ref 与候选 head 一致，并存在于已通过 `git bundle verify` 的持久备份中。
- 删除前已重新核对远端 head、归档/备份、补丁覆盖和开放 PR 引用；34 个候选均满足原核验条件，没有跳过项。

初始核验数据和完整 SHA 见 [候选数据](2026-10-23-remote-cleanup-candidates.json)；执行回执与事后核验见 [删除结果](2026-10-23-remote-cleanup-results.json)；提交覆盖来源见 [共同基线交付记录](2026-10-22-baseline-convergence.json)。

## 已核验并删除的 34 个分支

表中 SHA 为删除前 head 的缩写；执行时使用 JSON 中的完整 SHA。远端删除时，每个已删分支对应的本地归档引用为 `archive/pre-independent-20261022/<完整分支名>`；这些归档随后已按本地清理计划删除，原提交继续由 bundle 保存。

| 旧 PR | 完整远端分支名 | 删除前 head | 等价主干提交 | 核验结果 |
|-------|----------------|-----------|--------------|----------|
| [#65](https://github.com/CCreative-Od1L/project_sw/pull/65) | `chore/v1-ci-quality-gate` | `d3a5139` | `571e6f3` | 通过，开放 PR 引用为 0 |
| [#66](https://github.com/CCreative-Od1L/project_sw/pull/66) | `chore/v1-platform-builds` | `b5ad7b4` | `325b1c6` | 通过，开放 PR 引用为 0 |
| [#67](https://github.com/CCreative-Od1L/project_sw/pull/67) | `chore/v1-dependency-audit` | `c281b63` | `bf36657` | 通过，开放 PR 引用为 0 |
| [#68](https://github.com/CCreative-Od1L/project_sw/pull/68) | `chore/v1-android-integration-ci` | `7f78db4` | `26a6266` | 通过，开放 PR 引用为 0 |
| [#69](https://github.com/CCreative-Od1L/project_sw/pull/69) | `feat/v1-master-password-change-core` | `64274d7` | `a28ac28` | 通过，开放 PR 引用为 0 |
| [#70](https://github.com/CCreative-Od1L/project_sw/pull/70) | `feat/v1-master-password-change-ui` | `57aeabe` | `eb9f04a` | 通过，开放 PR 引用为 0 |
| [#71](https://github.com/CCreative-Od1L/project_sw/pull/71) | `feat/v1-recovery-gate` | `5bc89a5` | `328e528` | 通过，开放 PR 引用为 0 |
| [#72](https://github.com/CCreative-Od1L/project_sw/pull/72) | `feat/v1-biometric-recovery-core` | `224dade` | `8511203` | 通过，开放 PR 引用为 0 |
| [#73](https://github.com/CCreative-Od1L/project_sw/pull/73) | `feat/v1-biometric-recovery-ui` | `c8ea753` | `4456f3b` | 通过，开放 PR 引用为 0 |
| [#74](https://github.com/CCreative-Od1L/project_sw/pull/74) | `feat/v1-recovery-resume-window` | `244156e` | `c789e52` | 通过，开放 PR 引用为 0 |
| [#75](https://github.com/CCreative-Od1L/project_sw/pull/75) | `feat/v1-deadlock-wipe-core` | `3dbaa70` | `c33a9f5` | 通过，开放 PR 引用为 0 |
| [#76](https://github.com/CCreative-Od1L/project_sw/pull/76) | `feat/v1-deadlock-wipe-ui` | `d34147c` | `ce784b8` | 通过，开放 PR 引用为 0 |
| [#77](https://github.com/CCreative-Od1L/project_sw/pull/77) | `feat/v1-authenticated-wipe-ui` | `133b47d` | `0bbdb38` | 通过，开放 PR 引用为 0 |
| [#78](https://github.com/CCreative-Od1L/project_sw/pull/78) | `feat/v1-session-transition-guards` | `869333c` | `726eb36` | 通过，开放 PR 引用为 0 |
| [#79](https://github.com/CCreative-Od1L/project_sw/pull/79) | `feat/v1-session-activity-state` | `b7311a1` | `584e4ce` | 通过，开放 PR 引用为 0 |
| [#80](https://github.com/CCreative-Od1L/project_sw/pull/80) | `fix/v1-step-up-challenge-lifecycle` | `3950e34` | `4b538fe` | 通过，开放 PR 引用为 0 |
| [#81](https://github.com/CCreative-Od1L/project_sw/pull/81) | `fix/v1-password-change-activity-guard` | `dbb5074` | `97da485` | 通过，开放 PR 引用为 0 |
| [#82](https://github.com/CCreative-Od1L/project_sw/pull/82) | `fix/v1-biometric-configuration-guard` | `8111feb` | `e203cc1` | 通过，开放 PR 引用为 0 |
| [#83](https://github.com/CCreative-Od1L/project_sw/pull/83) | `fix/v1-clipboard-lock-cleanup` | `7b68321` | `597489d` | 通过，开放 PR 引用为 0 |
| [#84](https://github.com/CCreative-Od1L/project_sw/pull/84) | `fix/v1-dialog-secret-cleanup` | `c401baf` | `13b17c2` | 通过，开放 PR 引用为 0 |
| [#85](https://github.com/CCreative-Od1L/project_sw/pull/85) | `fix/v1-authenticated-wipe-guard` | `9991757` | `f58083f` | 通过，开放 PR 引用为 0 |
| [#86](https://github.com/CCreative-Od1L/project_sw/pull/86) | `fix/v1-vault-crud-activity-guard` | `a0c9f7a` | `7645992` | 通过，开放 PR 引用为 0 |
| [#87](https://github.com/CCreative-Od1L/project_sw/pull/87) | `fix/v1-session-state-contract` | `42fc892` | `b4a9b23` | 通过，开放 PR 引用为 0 |
| [#88](https://github.com/CCreative-Od1L/project_sw/pull/88) | `test/v1-cross-entry-sensitive-cleanup` | `551e309` | `a2c9e63` | 通过，开放 PR 引用为 0 |
| [#89](https://github.com/CCreative-Od1L/project_sw/pull/89) | `test/v1-background-lock-cleanup` | `ab04786` | `7d07333` | 通过，开放 PR 引用为 0 |
| [#90](https://github.com/CCreative-Od1L/project_sw/pull/90) | `fix/v1-unlock-attempt-ownership` | `036c428` | `9e8695c` | 通过，开放 PR 引用为 0 |
| [#91](https://github.com/CCreative-Od1L/project_sw/pull/91) | `chore/v1-release-metadata-preflight` | `1929c55` | `61c6b98` | 通过，开放 PR 引用为 0 |
| [#92](https://github.com/CCreative-Od1L/project_sw/pull/92) | `chore/android-release-signing-seam` | `c4bb9b6` | `91afe5f` | 通过，开放 PR 引用为 0 |
| [#93](https://github.com/CCreative-Od1L/project_sw/pull/93) | `chore/platform-build-scripts` | `d6c794f` | `83d4fdd` | 通过，开放 PR 引用为 0 |
| [#94](https://github.com/CCreative-Od1L/project_sw/pull/94) | `chore/android-signed-aab-release` | `b5da96b` | `2e51fae` | 通过，开放 PR 引用为 0 |
| [#95](https://github.com/CCreative-Od1L/project_sw/pull/95) | `chore/github-release-aggregation` | `5d951d4` | `35e25fa` | 通过，开放 PR 引用为 0 |
| [#96](https://github.com/CCreative-Od1L/project_sw/pull/96) | `docs/android-only-release-scope` | `5b764aa` | `7119fd1` | 通过，开放 PR 引用为 0 |
| [#97](https://github.com/CCreative-Od1L/project_sw/pull/97) | `docs/android-release-runbook` | `190f4a9` | `66dc2b5` | 通过，开放 PR 引用为 0 |
| [#98](https://github.com/CCreative-Od1L/project_sw/pull/98) | `fix/android-release-pub-regeneration` | `4fa3c7a` | `cf15300` | 通过，开放 PR 引用为 0 |

## 本轮保留的 13 个分支

| 远端分支名 | 当前 head | 保留原因 |
|------------|-----------|----------|
| `dependabot/github_actions/actions/checkout-7.0.1` | `5d4f307` | 独立依赖维护任务；关联 #101 |
| `dependabot/github_actions/actions/download-artifact-8.0.2` | `d45c5a0` | 独立依赖维护任务；关联 #100 |
| `dependabot/github_actions/actions/upload-artifact-7.0.2` | `c8465b0` | 独立依赖维护任务；关联 #102 |
| `dependabot/gradle/android/com.android.application-9.4.1` | `b3085c4` | 独立依赖维护任务；关联 #104 |
| `dependabot/gradle/android/gradle-wrapper-9.8.2` | `0a2c8a4` | 独立依赖维护任务；关联 #103 |
| `dependabot/gradle/android/org.jetbrains.kotlin.android-2.4.21` | `117a2ba` | 独立依赖维护任务；关联 #110 |
| `dependabot/pub/cupertino_icons-2.0.0` | `9d26a5e` | 独立依赖维护任务；关联 #106 |
| `dependabot/pub/get_it-9.3.0` | `c9785ed` | 独立依赖维护任务；关联 #107 |
| `dependabot/pub/intl-0.20.3` | `d2902da` | 独立依赖维护任务；关联 #109 |
| `dependabot/pub/sodium-4.1.2` | `50b94c3` | 独立依赖维护任务；关联 #108 |
| `dependabot/pub/test-1.31.1` | `a2eafe0` | 独立依赖维护任务；关联 #105 |
| `feat/v1-lan-migration-ui` | `b2c9a79` | 迁移 PR #64 的移植来源，尚未由新迁移方案替代 |
| `master` | `cf15300` | 默认主干 |

## 执行与事后核验

- 使用 `gh` 读取远端分支和 PR；删除使用 `git push --atomic`，为每个待删 ref 指定完整预期 SHA 的 `--force-with-lease`，34 个删除同批成功。
- 已确认这 34 个分支从远端消失，并同步清理本地 `origin/*` 跟踪引用；远端实际只剩上述 13 个保留分支，head 均与删除前相同。
- 开放 PR 仍为 #64 和 #100–#110 共 12 个，head/base 未变化；#65–#98 仍为关闭状态。
- 在此次远端删除步骤中，默认主干、版本标签和本地归档引用均未变化；未操作 Issue，未关闭新 PR。

## 恢复依据与边界

- 持久备份：`.git/branch-backups/2026-10-22/before-baseline-convergence.bundle`，本轮已验证可读且归档引用齐全。
- 备份 SHA-256：`08e077bb0ecf27849f4ef79d83b21acbea44bc8b25e021fe750a1b8c1a19682b`。
- 原始引用清单：[2026-10-22-original-refs.json](2026-10-22-original-refs.json)。
- 版本标签、本地独立任务分支和归档引用均不属于本轮远端清理范围。
- 本轮只删除上述 34 个远端旧分支并同步本地远端跟踪引用；未删除本地归档，也未改变 Issue 的实现或验收状态。
- 本次只涉及 Git/PR 元数据及文档，无应用代码改动；已核对 Git 对象、补丁、备份与文档数据，不需要重复执行 Flutter 功能测试。
