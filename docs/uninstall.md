# 卸载 Voice Input Buddy

从 GitHub Releases 下载对应 CPU 的独立卸载 PKG：Apple Silicon 选择 `macOS_arm64.pkg`，Intel 选择 `macOS_intel.pkg`。使用 macOS Installer 打开；个人数据删除选项默认勾选，取消勾选即可保留。系统按钮显示“安装”，此包实际执行卸载。

默认“彻底卸载”会退出应用、注销登录项、移除 `/Applications/Voice Input Buddy.app` 和 `/Library/Audio/Plug-Ins/HAL/VoiceInputBuddyMic.driver`，并删除当前用户的设置、日志、缓存和保存的窗口状态。仅删除这些明确归属于本项目的位置：

- `~/Library/Preferences/com.zfdang.voice-input-buddy.plist`
- `~/Library/Application Support/VoiceInputBuddy`
- `~/Library/Logs/VoiceInputBuddy`
- `~/Library/Caches/com.zfdang.voice-input-buddy`
- `~/Library/Saved Application State/com.zfdang.voice-input-buddy.savedState`

取消勾选个人数据删除选项仅删除 App 和驱动。系统目录删除需要 macOS 管理员认证；取消认证不会删除文件。驱动移除后重启 Core Audio，会短暂中断播放或录音；若无法重启，按错误提示重启 Mac。其他用户的个人数据、原 remote-mic / MiRemoteV 驱动及其他音频驱动不在卸载范围内。

本项目早期本地驱动文件名 `BuddyMic2ch.driver` 也纳入删除范围，但必须匹配本项目的 Bundle ID。卸载器不会删除源码仓库、下载的安装包或开发目录中的 App 副本。系统隐私授权列表可能保留失效条目，可在系统设置中手工移除；不修改系统 TCC 数据库。

开发：`BUILD_ARCH=arm64 scripts/build-uninstaller.sh`；Intel 改为 `x86_64`。两个版本都不需要 Xcode、Python 或原 App 作为运行依赖。卸载 PKG 未签名、未公证，与 App 安装包的发行限制相同。

验证：`python3 scripts/test-installation-actions.py` 使用临时目录测试身份拒绝、符号链接拒绝、重复卸载、旧文件名清理和个人数据删除；不会删除真实安装。可用 `installer -showChoicesXML -pkg <卸载包> -target /` 查看选项，不执行卸载。
