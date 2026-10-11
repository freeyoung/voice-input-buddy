# macOS 开发与驱动

SwiftPM 主执行目标为 VoiceInputBuddy。采用公开源码的默认构建，不接受上游私有包环境变量。构建时使用 --disable-keychain，避免公开二进制依赖扫描登录钥匙串。

开发 App：运行 scripts/build-app.sh，输出 dist/Voice Input Buddy.app。首次设置会请求需要的权限，蓝牙权限描述位于 Resources/Info.plist。应用身份为 com.zfdang.voice-input-buddy，设置和系统权限与原产品独立。

虚拟麦克风：scripts/build-driver.sh 固定 BlackHole v0.7.1 的 e2b22aaaba4e507a097131704bf96dabc004d9cf，应用 USB transport 补丁，使用独立工厂 UUID、Bundle ID 和 BuddyMic UID，避免替换 BlackHole 或原 MiRemoteV 驱动。输出 BuddyMic2ch.driver。scripts/build-driver-package.sh 创建系统 HAL 目录安装包，安装需用户明确授权；安装后脚本重启 Core Audio 以重新枚举设备，会短暂中断播放和录音；若失败则提示重启系统。驱动编译禁用 BlackHole 的通道名称格式，确保实际 UID 为 BuddyMic2ch_UID。

应用不会自动修改系统默认音频设备。应将 App 音频输出与第三方工具麦克风选择设为同一个回环设备。目标语音快捷键需要用户根据工具设置选择；wizard 和权限检查必须保留。

构建脚本默认仅做开发签名。正式发行前需要本项目自己的 Developer ID Application / Installer 签名、公证、驱动安装卸载回归与独立更新方案。不会沿用原作者更新密钥、会员后端或发布服务。

当前迁入仍包含上游禁用 Apple 扩展的辅助代码与历史兼容类型；不启用私有协议设备支持。不应将本次构建成功等同于 Mac App Store 审核通过。

## 本地开发

需要完整 Xcode 和 Swift 6.2 或更新版本。首次构建会下载 Sparkle 2.9.4。若当前选择 Command Line Tools，可使用 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```bash
swift build --disable-keychain
swift test --disable-keychain
./scripts/build-app.sh
./scripts/build-driver.sh
```

开发 App 位于 `dist/Voice Input Buddy.app`，驱动位于 `dist/BuddyMic2ch.driver`。App 构建按架构使用独立的 `.build/app-arm64` 与 `.build/app-x86_64` 目录，避免 SwiftPM 缓存混用。Release 与一体安装包的复现步骤见 [发布流程](releases.md)。

本地 `scripts/build-app.sh` 与发布 workflow 共用 Git 版本计算：最近提交在 Asia/Singapore 的日期与完整历史提交数生成 `vYY-MM-DD.NNN`。设置页显示该标记；macOS 的数字版本及构建号分别写入 `CFBundleShortVersionString` 与 `CFBundleVersion`。本地源码有未提交修改时，版本仍对应当前 HEAD，不能把它当作正式发布源码标识。
