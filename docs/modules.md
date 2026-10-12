# 模块清单

第三方项目及历史技术参考列在 [README References](../README.md#references)，版权、许可证与固定版本记录见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。实际构建目标以 [Package.swift](../Package.swift) 为准。

## SwiftPM 模块

| 模块 | 作用 |
| --- | --- |
| VoiceInputBuddy | 主 App、设备会话、设置、权限、音频路由与按键映射 |
| BuddyRemoteCore | 公开设备兼容接口 |
| BuddyRemoteUI | 公开兼容 UI |
| AudioExceptionGuard | 音频异常保护的 Objective-C 边界 |
| AppleRemoteSupport | 保留的 Apple 遥控器底层辅助代码 |
| AppleRemoteAudioCore | 历史 Apple 遥控器音频处理代码 |
| AppleRemoteHCIProtocol | 历史 HCI 辅助协议与消息类型 |
| AppleRemotePacketLogger | 历史 PacketLogger 客户端 |
| AppleRemoteHCIService | 单独声明的辅助执行目标，不随当前 PKG 分发 |
| AppleRemoteAudioCapture | 单独声明的音频捕获目标，不随当前 PKG 分发 |
| VoiceInputBuddyTests | 协议、生命周期与产品边界测试 |
| Sparkle | 第三方 macOS 更新框架 |

内部兼容代码保留不等于设备已启用；当前公开使用流程只提供小米遥控器。私有扩展包不参与构建。

## 驱动

VoiceInputBuddyMic.driver 基于固定版本 BlackHole 源码构建，使用独立 Bundle ID、设备 UID 与工厂 UUID。其对应固定版本源码、补丁与许可证通过 Release 的源码链接提供，见 [source-code.md](source-code.md)。

## macOS 系统模块

使用 AppKit、SwiftUI、Foundation、Combine、CoreBluetooth、IOBluetooth、CoreAudio、AudioToolbox、AVFoundation、CoreFoundation、CoreGraphics、CoreImage、ApplicationServices、Carbon、IOKit、Network、Security、CryptoKit、OSLog、ServiceManagement、UniformTypeIdentifiers、Charts、Accelerate 及 Darwin 系统接口。系统框架由 macOS 提供，不作为第三方二进制随 PKG 重新分发。

历史记录存储、录音归档、MCP 授权与客户端配置代码已移除；应用不会读写 AI 工具的 MCP 配置。上游私有扩展的条件编译分支已移除，公开兼容接口与未支持设备的 UI 类型仍保留。

## 暂时保留的手机 / Web Remote 与 Membership 脚手架

本轮保留这些类型作为后续解耦的过渡层：`BridgeAppModel`、设置和向导状态、公开兼容 UI 仍引用它们。删除需要同步整理状态与存储设置，不在端口校验和链接命名修复中一并进行。它们不是当前产品支持的功能，也没有恢复上游会员或授权服务的计划。

`MembershipFeatureIntegration` 是禁用的本地空桩：会员入口和环境设置不显示，手机连接与 Web Remote 授权能力为 false，创建远程会话授权固定返回 unavailable，诊断上传接口不提供记录。当前设置页不使用手机连接面板，向导不提供手机 / Web Remote 选择。不得仅通过显示入口或修改这些开关来宣称支持；若以后实现，需要独立设计公开服务、隐私边界与端到端测试。

未来移除时，应一并清理客户端、UI、状态和设置迁移，并保留小米遥控器连接、按键映射与语音输入的回归验证。`references/` 是忽略的本地研究笔记目录，正式参考链接列在 README；`dist/` 是忽略的本地构建输出，不属于版本库源码。
