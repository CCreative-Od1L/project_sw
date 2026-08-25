# Android 发布运行手册

本手册对应 V1.0 的 Android-only 软件发布范围。iOS 无签名构建仍可由 CI/开发流程验证，但 iOS 软件版本不进入发布、GitHub Release、TestFlight 或 App Store 流程。

## 发布流水线

向远端推送符合 `v<MAJOR>.<MINOR>.<PATCH>` 的 annotated tag 后，`.github/workflows/release.yml` 按以下顺序运行：

1. 校验 tag、`pubspec.yaml` 版本、`CHANGELOG.md` 段落、annotated tag、Flutter 版本和 `pubspec.lock` checksum。
2. 在 `release` environment 中构建 signed Android AAB。
3. 将非敏感 metadata、AAB 和对应的 CHANGELOG 段落汇总到 GitHub Release。

任一步骤失败都会阻止后续步骤；workflow 不会回退到 debug signing。

## 一次性配置 release environment

在 GitHub repository settings 创建名为 `release` 的 Environment，并按组织策略配置 required reviewer。只在该 Environment 中配置以下四个 Actions Secrets：

| Secret | 用途 |
|--------|------|
| `ANDROID_KEYSTORE_BASE64` | keystore 的 base64 内容 |
| `ANDROID_KEY_ALIAS` | keystore alias |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码 |

`ANDROID_KEYSTORE_PATH` 不需要配置。workflow 会把 keystore 解码到 runner 的临时目录，构建完成后删除；该文件不会进入仓库、artifact 或日志。

生成和提交 `ANDROID_KEYSTORE_BASE64` 时，源 keystore 和中间 base64 文件必须位于仓库目录之外。示例（Linux）：

```bash
release_tmp="$(mktemp -d)"
base64 --wrap=0 /absolute/path/to/release.keystore > "${release_tmp}/release.keystore.b64"
gh secret set ANDROID_KEYSTORE_BASE64 --env release < "${release_tmp}/release.keystore.b64"
```

alias 和密码通过 `gh secret set ... --env release` 交互式输入或由受控的 secret manager 注入；不要把它们写入仓库文件、shell 脚本或命令历史。完成后安全删除临时 base64 文件。

## 发布前检查

在创建 tag 前，确认：

- `pubspec.yaml` 的版本与目标 tag 一致；
- `CHANGELOG.md` 有对应的 `## [X.Y.Z]` 段落；
- 工作区清洁，且 `master` 已包含准备发布的提交；
- 本地格式检查、静态分析、全量测试和 Android debug 构建通过；
- release environment 中四个 secret 均已配置，且没有在日志中打印 secret。

建议先在本地执行非敏感门禁：

```bash
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze --no-pub
fvm flutter test --no-pub
FLUTTER_COMMAND='fvm flutter' bash scripts/build_android.sh debug-apk
```

## Tag 演练

确认上述条件后，创建并推送 annotated tag：

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

在 GitHub Actions 中核对 `Release preflight and Android signed build` 的 metadata、Android 和 publish jobs 均成功。GitHub Release 应包含：

- 对应 CHANGELOG 段落；
- `release-metadata.txt`；
- `app-release.aab`。

记录以下非敏感证据即可完成发布演练：tag、commit SHA、workflow run URL、GitHub Release URL、AAB SHA-256 和各 job 结果。不得记录 keystore、alias、密码或其内容。

## 失败处理

- metadata preflight 失败：修正版本/tag/CHANGELOG 后重新创建唯一 tag。
- 缺少签名 secret 或 keystore：workflow 应在 signing seam 失败，不会生成未签名冒充的 release AAB。
- Android 构建失败：检查 runner 日志中的非敏感错误和依赖版本，不上传临时签名材料。
- publish 失败：先保留 workflow artifact 和日志，修复原因后使用新的版本 tag；不要强制改写已发布 tag。
