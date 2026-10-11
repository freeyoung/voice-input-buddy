# 虚拟麦克风设置

Voice Input Buddy 使用基于 BlackHole 的独立双声道回环驱动，设备名称为 **Voice Input Buddy**，UID 为 `BuddyMic2ch_UID`。它不会替换 BlackHole 或上游产品的驱动。

首次移植提供本地开发构建。运行 `scripts/build-driver.sh` 构建驱动，再运行 `scripts/build-driver-package.sh` 生成 `dist/VoiceInputBuddy-Microphone.pkg`。目前没有公开签名安装包或 DMG。

自行安装本地 PKG 时，macOS 安装器需要管理员授权。安装包只安装 `/Library/Audio/Plug-Ins/HAL/BuddyMic2ch.driver`，不会自动启动 App；安装后会重启 Core Audio 以加载设备，会短暂中断播放和录音。如果刷新失败，请重启 Mac。

在 wizard 中刷新音频设备，选择 Voice Input Buddy 作为输出；在目标语音工具中选择 Voice Input Buddy 作为麦克风，并配置匹配的语音快捷键。已有 BlackHole 2ch 也可选择。

验证时，在 QuickTime Player 的“新建音频录制”中选择回环麦克风，按住遥控器语音键说话，确认输入电平变化；随后在有焦点的文本框中测试目标输入工具。构建成功不等于硬件验收完成。

首次版本尚无卸载安装包。卸载时退出 App，经管理员授权后只移除 HAL 目录中的 BuddyMic2ch.driver，再重启 Mac；不要移除其他音频设备。

驱动使用固定版本 BlackHole v0.7.1 的 GPL 源码，未来公开发行二进制时必须同时提供匹配源码和补丁。
