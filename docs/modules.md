# 模块清单

第三方项目及历史技术参考列在 [README References](../README.md#references)，版权、许可证与固定版本记录见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。历史 Apple 音频捕获、PacketLogger 和 HCI helper 的源码与构建目标已删除。实际构建目标以 [Package.swift](../Package.swift) 为准。

## SwiftPM 模块

| 模块 | 作用 |
| --- | --- |
| VoiceInputBuddy | 主 App、设备会话、设置、权限、音频路由与按键映射 |
| BuddyRemoteCore | 公开设备兼容接口 |
| BuddyRemoteUI | 公开兼容 UI |
| AudioExceptionGuard | 音频异常保护的 Objective-C 边界 |
| VoiceInputBuddyTests | 协议、生命周期与产品边界测试 |
| Sparkle | 第三方 macOS 更新框架 |

当前公开使用流程提供小米 RC001／RC003 和 Google G9N9N；G9N9N 的 macOS 真机验收仍待完成。GY3LE 与 Siri Remote 可在设备目录中选择，但不能继续连接。内部兼容类型不代表对应功能已启用；私有扩展包不参与构建。

## 驱动

VoiceInputBuddyMic.driver 基于固定版本 BlackHole 源码构建，使用独立 Bundle ID、设备 UID 与工厂 UUID。其对应固定版本源码、补丁与许可证通过 Release 的源码链接提供，见 [source-code.md](source-code.md)。

## macOS 系统模块

使用 AppKit、SwiftUI、Foundation、Combine、CoreBluetooth、IOBluetooth、CoreAudio、AudioToolbox、AVFoundation、CoreFoundation、CoreGraphics、CoreImage、ApplicationServices、Carbon、IOKit、Network、Security、CryptoKit、OSLog、ServiceManagement、UniformTypeIdentifiers、Accelerate 及 Darwin 系统接口。系统框架由 macOS 提供，不作为第三方二进制随 PKG 重新分发。停用的统计图表 UI 和 Charts 依赖已删除。

历史记录存储、录音归档、MCP 授权与客户端配置代码已移除；应用不会读写 AI 工具的 MCP 配置。上游私有扩展的条件编译分支已移除，公开兼容接口与未支持设备的 UI 类型仍保留。

## 未开放的手机 / Web Remote 兼容层

`BuddyRemoteCore`、`BuddyRemoteUI` 及应用编排中仍有手机 / Web Remote 兼容类型。当前设置页不提供管理面板，向导的可用来源仅为小米和 G9N9N；这些类型不是已开放的产品功能，也不代表有可用的远程授权服务。

`MembershipFeatureIntegration`、会员入口、宏动作及私有功能占位实现已删除。若以后实现手机或 Web Remote，需要独立设计公开服务、隐私边界与端到端测试。

整理兼容层时，应同步清理客户端、UI、状态和停用设置，不为未发布的旧格式增加迁移，并保留当前遥控器连接、按键映射与语音输入的回归验证。`references/` 是忽略的本地研究笔记目录，正式参考链接列在 README；`dist/` 是忽略的本地构建输出，不属于版本库源码。

诊断只写本地日志；上传器、私有上传协议和待上传事件队列已删除。

## G9N9N public adapter

`G9N9NProtocol.swift` identifies candidates, parses report 2 Consumer Control usages, checks ATVV capabilities, and distinguishes pairing errors. `XiaomiBluetoothBridge` now also hosts G9N9N via explicit opt-in, requiring DIS model G9N9N and ATVV v1.0 / 16 kHz before readiness. Audio uses the existing ADPCM decoder and virtual microphone output; driver sources and signing are unchanged. The retired no-op Chromecast package facade has been removed.
