# Git Workflow · PROJECT_SW

> 本文档定义 PROJECT_SW 的 Git 工作流全生命周期规范。
> 高层约定(分支策略 / 提交格式 / 版本号)见 [DEVELOPMENT.md §7](./DEVELOPMENT.md)。

## 1. 分支模型

### 1.1 主干

- **`main`**(`master` 的别名,同分支):唯一长期分支,**始终可发布**。
- `main` 上的每个提交都必须通过 CI(分析 + 格式化 + 单元测试 + 集成测试),无例外。

### 1.2 功能分支

- 命名规范:`<type>/<short-description>`,type 与 [Conventional Commits](./DEVELOPMENT.md) type 对齐。
  - `feat/<name>` — 新功能
  - `fix/<name>` — 缺陷修复
  - `docs/<name>` — 文档变更
  - `refactor/<name>` — 重构(无行为变化)
  - `test/<name>` — 测试补充
  - `chore/<name>` — 构建 / 工具 / 依赖
  - `security/<name>` — 安全补丁

- 示例:
  ```
  feat/password-generator
  fix/clipboard-clear-on-suspend
  docs/git-workflow
  security/update-sodium
  ```

### 1.3 发布分支(临时)

- 仅在需要**冻结特性**时创建(如 RC 阶段):`release/v<MAJOR>.<MINOR>.0`。
- 从 `main` 切出,仅接受缺陷修复;发布后合并回 `main` 并打 tag,**分支随即删除**。

### 1.4 热修复分支(临时)

- 当 `main` 上的最新 tag 存在必须立即修复的缺陷时,从该 tag 切出 `hotfix/<description>`。
- 修复后合并回 `main` 并打新 tag,**分支随即删除**。

## 2. 提交规范(Conventional Commits)

### 2.1 消息格式

```
<type>[(scope)]: <description>

[body]

[footer(s)]
```

- **type**(必填):`feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `security`
- **scope**(可选):被影响的模块/域(如 `crypto`、`vault`、`migration`、`search`、`generator`、`ui`)
- **description**(必填):≤72 字符,英文小写开头,不加句号
- **body**(可选):详细描述,每行 ≤100 字符,说明 **what** 和 **why**(非 how)
- **footer**(可选):`BREAKING CHANGE:` 或关联 issue 引用(`Refs: #NN` / `Closes: #NN`)

### 2.2 示例

```
feat(crypto): add envelope encryption for per-entry DEK

Implement XChaCha20-Poly1305 based envelope encryption:
- Each VaultEntry gets its own random DEK (256-bit)
- DEK is wrapped by Master Vault Key (AEAD, AAD = entry_id)
- Entry plaintext is encrypted by DEK (AEAD, AAD = entry_id + seq)
- Enables per-entry O(1) update and single-entry LAN migration

Refs: SECURITY.md §4, specs/vault_format.md §5
```

```
docs(clipboard): document platform cleanup boundaries

Native clipboard APIs can clear the current primary clip,
but cannot guarantee removal from vendor clipboard history,
already-read copies, or an app process that has been suspended.

Keep fixed-time clipboard cleanup out of the product security
boundary until a platform-specific design is verified.

Refs: docs/specs/data_hygiene.md, ADR-0011
```

```
docs: add git workflow specification

Covers branch model, commit format, PR lifecycle,
release tagging, and enforcement tooling.

Refs: DEVELOPMENT.md §7
```

```
security(deps): bump sodium to 4.0.3

Addresses CVE-2026-XXXXX (side-channel in XChaCha20
implementation on ARMv7).

BREAKING CHANGE: minimum Flutter SDK bumped to 3.27.0
to support updated sodium build hooks.
```

### 2.3 提交粒度

- **一个提交做一件事**:逻辑独立的变更不混在同一提交。
- 文档与对应代码的变更可在同一提交(如 `feat(crypto): ...` 含对应 `SECURITY.md` 更新)。
- **WIP 提交不入 `main`**:在功能分支上可多次提交,合入 `main` 前经 squash/rebase 整理为干净历史。

## 3. 功能分支生命周期

### 3.1 创建

```bash
git checkout main
git pull --rebase origin main
git checkout -b feat/my-feature
```

### 3.2 开发

- 在功能分支上以 Conventional Commits 格式提交。
- 定期将 `main` 合并到功能分支以保持同步:

```bash
# 在功能分支上
git fetch origin
git rebase origin/main
```

- **禁止**直接向 `main` 推送。

### 3.3 提交前检查

每个提交前本地必须通过:

```bash
fvm dart format --set-exit-if-changed .
fvm dart analyze
fvm flutter test
```

CI 上将运行相同检查 + 集成测试。任何失败将阻止合并。

### 3.4 推送与 PR

```bash
git push -u origin feat/my-feature
```

- 在 GitHub 上创建 Pull Request,目标分支 `main`。
- PR 标题使用 Conventional Commits 格式。
- PR body 须包含:变更摘要、关联 issue、测试证据(截图/日志链接)。
- 至少一个审查者批准后方可合并(个人项目阶段可为自审,但 PR 流程保留)。

### 3.5 合并

- **优先使用 rebase + fast-forward merge**,保持 `main` 历史线性。
- 若功能分支包含多个 WIP 提交,**squash merge** 为单个干净提交(使用 PR 标题作为 squashed commit 的 message)。
- 功能分支合并后**立即删除**(GitHub PR 可自动删除分支)。

### 3.6 分支删除

```bash
# 本地
git branch -d feat/my-feature

# 远程(自动或手动)
git push origin --delete feat/my-feature
```

## 4. 标签与发布

### 4.1 版本号

遵循 [SemVer](https://semver.org/),格式:`v<MAJOR>.<MINOR>.<PATCH>`。移动端构建号以 `+N` 后缀递增。

### 4.2 打标签

```bash
# 确保在 main 上且工作区干净
git checkout main
git pull --rebase origin main
git tag -a v1.0.0 -m "v1.0.0: Initial release"
git push origin v1.0.0
```

- **annotated tag**(`-a`)必用——包含作者、日期、message。
- 发布 tag 由 CI 触发构建流程,产出各平台分发包。

### 4.3 发布流程

1. 更新 `CHANGELOG.md`(记录用户可见变化)
2. 提交 `chore(release): bump version to v1.0.0`
3. 打 annotated tag
4. 推送 tag 触发 CI release 流水线
5. 创建 GitHub Release(附构建产物的下载链接与 `CHANGELOG.md` 摘要)

## 5. 分支保护规则(GitHub Settings)

`main` 分支应配置:

| 规则 | 值 |
|------|----|
| 要求 PR 才能合并 | ✓ |
| 要求状态检查通过 | ✓(CI 全部绿) |
| 要求分支最新(`main` 无新提交) | ✓ |
| 要求对话解决 | ✓ |
| 限制推送权限 | ✓(仅仓库管理员) |
| 删除分支保护 | ✓ |
| 禁止强制推送 | ✓ |

## 6. 安全实践

### 6.1 签名

- **建议启用提交签名**(GPG / SSH):
  ```bash
  git config commit.gpgsign true
  git config user.signingkey <KEY_ID>
  ```

### 6.2 密钥与机密

- **签名密钥、证书、密钥库绝不入库**(已约定于 [DEVELOPMENT.md §8.1](./DEVELOPMENT.md))。
- `.gitignore` 排除:
  ```gitignore
  # 本地密码库文件(测试/开发期)
  *.vault
  *.vault.bak

  # 签名密钥与证书
  *.keystore
  *.jks
  *.p12
  *.p8
  *.mobileprovision

  # 环境变量与本地配置
  .env
  .env.*
  ```

### 6.3 依赖审计

- `pubspec.lock` 入库(已约定)。
- 定期运行 `fvm dart pub outdated` + 安全审计。
- 安全补丁优先通过 `security:` 提交处理并优先发版。

## 7. 常见场景速查

### 7.1 新功能

```bash
git checkout main && git pull --rebase
git checkout -b feat/my-feature
# 开发 + 多次提交...
fvm dart format --set-exit-if-changed . && fvm dart analyze && fvm flutter test
git push -u origin feat/my-feature
# 创建 PR → 审查 → squash merge → 删除分支
```

### 7.2 热修复

```bash
git checkout v1.0.0 -b hotfix/critical-bug
# 修复 + 提交...
git push -u origin hotfix/critical-bug
# PR → merge to main → tag v1.0.1 → 删除分支
```

### 7.3 同步功能分支

```bash
git checkout feat/my-feature
git fetch origin
git rebase origin/main
# 若冲突:解决 → git add → git rebase --continue
git push --force-with-lease origin feat/my-feature
```

### 7.4 撤消最后一次提交(未推送)

```bash
git reset --soft HEAD~1   # 保留变更在暂存区
git reset --hard HEAD~1   # 完全丢弃
```

### 7.5 修改最后一次提交的 message

```bash
git commit --amend -m "new message"
# 若已推送:
git push --force-with-lease origin feat/my-feature
```

## 8. 演进与定制

本文档初始版基于主流 trunk-based development 实践制定。当项目进入活跃开发后,可根据实际摩擦(如 PR 审查人数不足、CI 耗时过长)调整规则——调整须经 PR 流程在本文档上体现,与代码变更同等对待。具体规则变更的批准门槛由项目维护者决定。

## 参考

- [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
- [Semantic Versioning 2.0.0](https://semver.org/)
- [Trunk Based Development](https://trunkbaseddevelopment.com/)
- PROJECT_SW 内部约定:[DEVELOPMENT.md §7](./DEVELOPMENT.md)、[DEVELOPMENT.md §8](./DEVELOPMENT.md)
