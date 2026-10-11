# macOS 自动发布

`.github/workflows/release.yml` 在 main 收到提交时运行，包括人工合并 PR。PR 本身也会测试、构建安装包供检查，但不会创建 Release。流程不会合并任何 PR。

## 版本

版本为 `v26-10-11.001`。日期来自发布提交的 committer 时间，使用 Asia/Singapore 时区；序号为 `git rev-list --count HEAD`，包括可达的合并提交，按三位补零。例如 1、11、113 分别得到 001、011、113。不是每日重置计数。同一提交重跑得到同一版本；已存在 Release 不覆盖。历史必须完整，因此 checkout 使用 fetch-depth: 0。超过 999 会停止发布，不截断或回绕，需要届时明确扩展版本规则。

App 的 CFBundleShortVersionString 为数字日期（例如 26.10.11），CFBundleVersion 为提交总数；安装包内部使用数字日期加提交总数。Git tag、Release 标题与下载文件采用完整 `vYY-MM-DD.NNN` 格式。

## 安装包与源码

- `Voice_Input_Buddy_vYY-MM-DD.NNN_macOS_universal.pkg`：App 与驱动的一体安装包。
- `Voice_Input_Buddy_vYY-MM-DD.NNN_sources.tar.gz`：发布提交的完整源码、构建脚本，以及实际使用的 patched BlackHole v0.7.1、Sparkle 源码和许可证。
- `SHA256SUMS.txt`：文件校验值。

安装包同时支持 arm64 和 x86_64，要求 macOS 14 或更新版本。App 安装在 `/Applications/Voice Input Buddy.app`，驱动安装在 `/Library/Audio/Plug-Ins/HAL/BuddyMic2ch.driver`。程序展示名称仍为 Voice Input Buddy；发布文件名使用下划线，App 目录保留空格，内部可执行文件为 VoiceInputBuddy。安装需要管理员授权；驱动装好后刷新 Core Audio，会短暂中断播放和录音。安装包不自动开启任何系统隐私授权，也不自动启动 App。

旧开发版本若放在其他目录，应退出旧版并改用 `/Applications/Voice Input Buddy.app`，避免同时运行两个副本。首次安装和更新后请核对系统权限。

当前自动发布使用临时 ad-hoc App/驱动签名，PKG 未经 Developer ID Installer 签名和 Apple 公证。Release 说明会如实标注，系统可能阻止安装，更新也可能使输入监控与辅助功能授权失效。此流程没有关闭 Gatekeeper、修改系统安全策略或复用上游发布密钥。正式签名与公证需要后续配置本项目自己的凭据。

## 本地复现

使用完整 Xcode（Swift 6.2 或更新版本）并先提交发布源码，确保源码归档与二进制一致：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
set -a
source <(scripts/release-metadata.sh)
set +a
swift test --disable-keychain
BUILD_ARCHS="arm64 x86_64" scripts/build-app.sh
scripts/build-driver.sh
scripts/build-release-package.sh
scripts/build-release-sources.sh
```

本地 App 构建默认仅构建宿主架构；Release workflow 明确构建两种架构并验证。GitHub runner 固定 macos-15 和 Xcode 26.2。构建/测试任务仅有读取权限；只有 main 的发布任务拥有创建 Release 所需的 contents: write。
