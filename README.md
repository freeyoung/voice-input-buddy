# Voice Input Buddy

Voice Input Buddy（语音搭子）把遥控器等硬件的按键和麦克风连接到语音输入法与听写工具。当前首次移植聚焦 **macOS 14 及以上**；Windows 属于后续平台计划，尚未提供实现或安装包。

这是基于 [remote-mic-app](https://github.com/HD838A/remote-mic-app) 的独立 GPL-3.0-only 衍生项目，与 SayAll 原产品、小米和第三方输入软件不存在官方合作或背书关系。

## 保留的能力

- 小米遥控器 BLE 连接、ATVV 音频协议与 ADPCM 解码。
- 音频设备选择和虚拟麦克风路由。
- 按下开始、松开结束的语音键，以及普通按键映射。
- 蓝牙、输入监控、辅助功能权限检查和首次设置 wizard。
- 自定义应用快捷键、常用语和本机设置导入导出。
- 基于 BlackHole 固定源码构建的独立 `BuddyMic2ch.driver`。

本项目不提供使用统计、回眸文本采集、录音归档或日志上传，也不包含上游私有会员、AI、手机或 Web 服务。部分内部历史数据类型暂时保留，以便完成主体移植；采集执行路径已禁用，相关页面不进入导航，MCP 可执行程序不构建。

## 本地开发

需要 Xcode 和 Swift 6.2。运行测试需选择完整 Xcode 开发环境；若当前选择 Command Line Tools，可在命令前加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。首次构建会下载 Sparkle 2.9.4。

```bash
swift build --disable-keychain
swift test --disable-keychain
./scripts/build-app.sh
./scripts/build-driver.sh
./scripts/build-driver-package.sh
```

`dist/Voice Input Buddy.app` 和驱动 PKG 目前是本地开发产物，未经发布公证，不能视为正式发行版本。首次运行请按 wizard 授权并选择回环设备；在目标输入法或 VoiceCursor 中选择同一设备，并配置相匹配的语音快捷键。第三方语音工具的识别、整理与延迟由第三方控制。

## 文档

- [产品范围和架构](docs/architecture.md)
- [界面与使用流程](docs/interface.md)
- [macOS 开发与驱动](docs/development.md)
- [移植来源和许可](docs/provenance.md)
- [隐私边界与验证](docs/privacy-and-testing.md)

## 许可

软件代码和本项目原创图标采用 **GPL-3.0-only**，见 [LICENSE](LICENSE)。保留上游和其他贡献者版权；第三方组件按其各自许可证使用，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。原产品的专有 Logo 和来源不明确的产品照片未迁入。
