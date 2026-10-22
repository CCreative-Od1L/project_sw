# PROJECT_SW

> **代号**:PROJECT_SW(正式名称待定)
> **一句话定位**:一个仅依靠本地能力进行加密的开源密码管理器
> **协议**:MIT · **状态**:v0.1、v0.5 已验收；v1.0 实现与发布验收收尾中，尚未正式发布。详见 [当前进度](docs/PROGRESS.md)。

---

## 项目简介

PROJECT_SW 是一个**本地优先(local-first)、零云依赖**的密码管理器。所有加解密都在设备本地完成,密码库不离开设备(局域网迁移除外)。面向个人自用,作为练手与软件工程化实践项目。

- 🧊 **纯本地加密**:客户端独立完成所有加解密,无后端、无账号体系、无云端密钥托管
- 🔐 **现代密码学**:Argon2id 派生 + XChaCha20-Poly1305 AEAD + 逐条信封加密
- 👆 **生物解锁**:指纹/面容授权释放硬件 Keychain/Keystore 中的密钥
- 🖥️ **局域网迁移**:设备间通过 LAN 安全迁移密码库,无需任何云服务
- 🔍 **本地搜索**:对加密库进行本地检索
- 🌐 **国际化**:中文 + 英文
- 📱 **跨平台**:Flutter,移动端优先

> 以上包含目标功能。当前工作区已有建库、解锁、条目 CRUD、生成器、搜索、生物认证与恢复/擦除流程；局域网迁移底层已实现，二维码/扫码页面仍在未合并的 [PR #64](https://github.com/CCreative-Od1L/project_sw/pull/64)，尚未接入当前工作区。v1.0 仍需整合 PR、完成真机验收和 Android 正式发布演练；iOS 不在本次软件发布范围内。

## 非目标(明确不做)

- ❌ 云同步 / 云备份 / 跨互联网同步
- ❌ 团队/企业共享、账号体系、服务端
- ❌ 浏览器自动填充扩展(初期)

## 技术栈

| 维度 | 选型 |
|------|------|
| 客户端框架 | Flutter(移动端优先) |
| 架构模式 | Clean Architecture(presentation / domain / data) |
| 状态管理 | Cubit/Bloc + State + Pure Signal |
| 密码学库 | `sodium`(libsodium 的 Dart/Flutter 绑定;原生库由 Flutter build hooks 处理) |
| 密钥安全存储 | 系统原生 Keychain(iOS/macOS)/ Keystore(Android),硬件背书 |
| KDF | Argon2id |
| AEAD | XChaCha20-Poly1305 |
| 加密粒度 | 逐条信封加密(envelope encryption),自定义二进制外壳 + JSON 内层 |
| 国际化 | Flutter `intl` + ARB(zh + en) |

> 加密方案的完整设计见 [docs/SECURITY.md](docs/SECURITY.md)。

## 核心功能

1. **密码生成** —— 按可配置规则(模式/长度/字符集/可读性)生成强密码,理论熵强度评估(规格见 [docs/specs/password_generator.md](docs/specs/password_generator.md))
2. **加密存储** —— 本地加密保存密码库,逐条信封加密
3. **生物解锁** —— 指纹/面容解锁应用,硬件密钥保护
4. **局域网迁移** —— 设备间 LAN 传输密码库,带鉴权与传输加密
5. **本地搜索** —— 在加密库中检索条目

## 文档导航

| 文档 | 内容 |
|------|------|
| [docs/PROGRESS.md](docs/PROGRESS.md) | 当前进度、代码与远端分支差异、待验收与发布事项、验证证据 |
| [docs/PENDING_VALIDATION.md](docs/PENDING_VALIDATION.md) | 已开发但待真机/完整链路验证的功能、已有验证边界与验收清单 |
| [docs/BRANCH_ORGANIZATION.md](docs/BRANCH_ORGANIZATION.md) | 共同代码基线、独立任务分支、历史归档与远端 PR 收敛顺序 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 系统架构综述、Clean Architecture 分层、模块划分、数据流、密钥层级 |
| [docs/specs/vault_format.md](docs/specs/vault_format.md) | Vault 文件格式:二进制外壳、Entry Block 双段、free list、journal、AAD |
| [docs/specs/vault_entry.md](docs/specs/vault_entry.md) | VaultEntry 字段规格:固定字段、自定义字段、卫生汇总、条目组织 |
| [docs/specs/biometric_auth.md](docs/specs/biometric_auth.md) | 生物解锁机制、认证强度策略、高敏操作枚举 |
| [docs/specs/lan_migration.md](docs/specs/lan_migration.md) | 局域网迁移协议:二维码配对、crypto_kx 握手、重包裹、原子提交 |
| [docs/specs/local_search.md](docs/specs/local_search.md) | 本地搜索:内存内线性检索基线、字段卫生、不越基线论证 |
| [docs/specs/password_generator.md](docs/specs/password_generator.md) | 密码生成器规格:随机源、生成模式、字符集、强度评估 |
| [docs/specs/lock_and_recovery.md](docs/specs/lock_and_recovery.md) | 锁定、销毁、忘主密码恢复、死锁擦除、状态机 |
| [docs/specs/data_hygiene.md](docs/specs/data_hygiene.md) | 数据卫生:内存/日志脱敏、剪贴板平台边界 |
| [docs/specs/observability.md](docs/specs/observability.md) | 可观测性:Logger/EventTracker/MetricsRecorder 接口、事件清单、脱敏管道、日志存储 |
| [docs/specs/ci_cd.md](docs/specs/ci_cd.md) | CI/CD 设计规格:workflow 分层、job 矩阵、缓存、签名、发版流水线 |
| [docs/specs/build_roadmap.md](docs/specs/build_roadmap.md) | 构建路线图:v0.1 任务级 tracer bullet、v0.5 MVP、v1.0 完整版 |
| [docs/SECURITY.md](docs/SECURITY.md) | 威胁模型、加密方案、密钥层级、生物解锁、迁移与搜索安全 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 开发环境、代码规范、测试体系、可观测性、CI/CD、发布流程 |
| [docs/RELEASE_RUNBOOK.md](docs/RELEASE_RUNBOOK.md) | V1.0 Android-only 发布配置、Tag 演练与非敏感证据记录 |
| [docs/GIT_WORKFLOW.md](docs/GIT_WORKFLOW.md) | Git 工作流:分支模型、提交格式、PR 生命周期、标签与发布 |
| [docs/simple_description.md](docs/simple_description.md) | 项目原始需求描述 |

## 快速开始

> 当前工作区可运行建库 → 解锁 → 条目 CRUD → 锁定/重解锁，以及生成器、搜索和设置流程。v1.0 的分支整合与验收边界见 [当前进度](docs/PROGRESS.md)。

```bash
# 1. 环境准备(详见 docs/DEVELOPMENT.md)
fvm install                # 安装 .fvmrc 锁定的 Flutter stable 版本
fvm flutter --version      # 不直接调用全局 flutter
# `sodium` 的原生库由 Flutter build hooks 处理；macOS/Linux 需 `make` 与基础编译工具链

# 2. 获取依赖
fvm flutter pub get

# 3. 运行
fvm flutter run

# 4. 测试
fvm flutter test               # 单元 + widget 测试
fvm flutter test integration_test  # 集成测试
```

## 软件工程化

本项目有意走通完整的"开发 → 分发 → 维护"工程实践闭环,包含:项目文档与业务设计管理、分层测试(单元/widget/集成)、日志与埋点监控、版本管理与脚本化打包、CI/CD 流水线。详见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 许可证

MIT License — 见 [LICENSE](LICENSE)。
