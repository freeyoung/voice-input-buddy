# macOS 自动发布

`.github/workflows/release.yml` 在 main 收到提交时运行，包括人工合并 PR。PR 本身也会测试、构建安装包供检查，但不会创建 Release。流程不会合并任何 PR。

## 版本

版本为 `v26-10-11.001`。日期来自发布提交的 committer 时间，使用 Asia/Singapore 时区；序号为 `git rev-list --count HEAD`，包括可达的合并提交，按三位补零。例如 1、11、113 分别得到 001、011、113。不是每日重置计数。同一提交重跑得到同一版本；已存在 Release 不覆盖。历史必须完整，因此 checkout 使用 fetch-depth: 0。超过 999 会停止发布，不截断或回绕，需要届时明确扩展版本规则。

App 的 CFBundleShortVersionString 为数字日期（例如 26.10.11），CFBundleVersion 为提交总数；安装包内部使用数字日期加提交总数。Git tag、Release 标题与下载文件采用完整 `vYY-MM-DD.NNN` 格式。

## 安装包与源码

- `Voice_Input_Buddy_vYY-MM-DD.NNN_macOS_arm64.pkg` / `*_macOS_intel.pkg`：App 与驱动的一体安装包。
- `Voice_Input_Buddy_Uninstaller_vYY-MM-DD.NNN_macOS_universal.pkg`：Apple Silicon / Intel 共用的脚本卸载包。

Release 只附这三个 PKG，不额外上传 SHA 文件、TXT 更新摘要、appcast XML 或源码压缩包。源码使用对应 Git tag；第三方固定版本源码及构建说明见 [source-code.md](source-code.md)。

安装包按 arm64 和 x86_64（文件名 intel）分别提供，要求 macOS 14 或更新版本。App 安装在 `/Applications/Voice Input Buddy.app`，驱动安装在 `/Library/Audio/Plug-Ins/HAL/VoiceInputBuddyMic.driver`。程序展示名称仍为 Voice Input Buddy；发布文件名使用下划线，App 目录保留空格，内部可执行文件为 VoiceInputBuddy。安装需要管理员授权；驱动装好后刷新 Core Audio，会短暂中断播放和录音。安装包不自动开启任何系统隐私授权，也不自动启动 App。

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
export BUILD_ARCH=arm64 # Intel: x86_64
scripts/build-app.sh
scripts/build-driver.sh
scripts/build-uninstaller.sh
scripts/build-release-package.sh
scripts/verify-release-package.sh
```

本地 App 构建默认仅构建宿主架构；Release workflow 以 matrix 分别构建两种架构并验证。GitHub runner 固定 macos-15 和 Xcode 26.2。构建/测试任务仅有读取权限；只有 main 的发布任务拥有创建 Release 所需的 contents: write。

## 应用内更新

Sparkle 从 `https://voice.zfdang.com/appcast-arm64.xml` 或 `appcast-intel.xml` 检查正式版本。应用内置
`SUPublicEDKey`，下载的 PKG 必须通过对应 Ed25519 公钥验证，才会开始安装。
通过菜单或设置中的“检查更新”可以手动触发；默认也进行后台检查。
版本比较使用递增的 CFBundleVersion（完整 Git 提交计数），显示采用完整发布标签。

main 的发布构建从仓库 Actions Secret `SPARKLE_PRIVATE_KEY` 读取签名私钥，
仓库 Variable `SPARKLE_PUBLIC_KEY` 必须与内置公钥完全一致。私钥只通过标准输入
传递给 Sparkle sign_update；不会写入源码、日志、发布资产或 PR 构建。
签名后使用 CryptoKit 与应用公钥独立验证，再生成对应架构的 appcast XML。更新源上传到 Actions 的 `website-update-feeds` 产物，不作为 Release 下载附件。
PR 构建只测试和打包，不接触签名私钥、不部署更新源。

Release 成功后 Pages workflow 从该次发布的 Actions 产物部署两份 appcast XML。单独更新网页或重复执行已发布版本时，读取网站上已发布的更新源，并验证版本和包地址仍匹配最新 Release。旧 Actions 产物过期不影响单独更新网页；验证失败时停止部署，保留线上站点。PKG 地址指向
GitHub Releases；安装同时更新 App 和驱动，需要管理员授权，并可能短暂重启音频。
这不是静默安装，也不代替 Apple Developer ID 签名和公证。

已有未配置更新源的版本需手动安装一次带更新源与公钥的新 PKG。
开发目录中的 ad-hoc App 无法代表完整安装流程，验收应从 `/Applications` 中
通过 PKG 安装的版本升级到后续版本。发布前必须实测管理员授权、升级后重启、
驱动可用性和系统权限；不得仅凭构建通过宣称完整升级已验证。

尚未发布预览通道；启用预览检查时，缺失预览源会回退到正式更新源。
不要随意更换密钥。PKG 更新无法通过普通更新自动轮换遗失的签名密钥，
必须安全备份，并在确需更换时安排用户重新安装。

通用卸载包以 `Voice_Input_Buddy_Uninstaller_vYY-MM-DD.NNN_macOS_universal.pkg` 发布，只有脚本而没有安装载荷。Release matrix 只在 arm64 任务中生成它，避免两份同名产物。

新 App 使用各自的更新源，开发阶段不维护旧 universal feed。arm64 feed 标注 Sparkle 的 [arm64 硬件要求](https://sparkle-project.org/documentation/api-reference/Classes/SUAppcastItem.html)，Intel feed 指向 Intel 包。

应用的更新摘要直接读取 appcast 中的说明，不再生成或下载独立的 `.en.txt` / `.zh.txt` 文件。
