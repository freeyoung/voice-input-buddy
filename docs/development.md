# macOS 开发与驱动

SwiftPM 主执行目标为 VoiceInputBuddy。采用公开源码的默认构建，不接受上游私有包环境变量。构建时使用 --disable-keychain，避免公开二进制依赖扫描登录钥匙串。

开发 App：运行 scripts/build-app.sh，输出 dist/Voice Input Buddy.app。首次设置会请求需要的权限，蓝牙权限描述位于 Resources/Info.plist。应用身份为 com.zfdang.voice-input-buddy，设置和系统权限与原产品独立。

虚拟麦克风：scripts/build-driver.sh 固定 BlackHole v0.7.1 的 e2b22aaaba4e507a097131704bf96dabc004d9cf，应用 USB transport 补丁，使用独立工厂 UUID、Bundle ID 和 BuddyMic UID，避免替换 BlackHole 或原 MiRemoteV 驱动。输出 VoiceInputBuddyMic.driver。scripts/build-driver-package.sh 创建系统 HAL 目录安装包，安装需用户明确授权；安装后脚本重启 Core Audio 以重新枚举设备，会短暂中断播放和录音；若失败则提示重启系统。驱动编译禁用 BlackHole 的通道名称格式，确保实际 UID 为 BuddyMic2ch_UID。

应用不会自动修改系统默认音频设备。遥控器断开、应用停止、退出、音频配置失败及重连时，只释放或重新绑定应用自身的音频输出；系统默认输入、输出及系统提示音设备保持由用户或系统管理。应将 App 音频输出与第三方工具麦克风选择设为同一个回环设备。目标语音快捷键需要用户根据工具设置选择；wizard 和权限检查必须保留。

当前发行使用 ad-hoc App 签名和未签名的 PKG，不具备 Apple Developer ID，也未公证。更新包使用本项目的 Sparkle Ed25519 密钥签名；push main 自动发布。若以后取得 Developer ID，应加入 Application / Installer 签名和公证。驱动安装卸载仍需真机回归。不会沿用原作者更新密钥、会员后端或发布服务。

当前保留实验性 Apple 遥控器底层辅助代码与公开兼容类型；上游私有扩展接入分支、历史采集、录音归档与 MCP 已移除。不应将本次构建成功等同于 Mac App Store 审核通过。

## 本地开发

需要完整 Xcode 和 Swift 6.2 或更新版本。首次构建会下载 Sparkle 2.9.4。若当前选择 Command Line Tools，可使用 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```bash
swift build --disable-keychain
swift test --disable-keychain
./scripts/build-app.sh
./scripts/build-driver.sh
```

开发 App 位于 `dist/Voice Input Buddy.app`，驱动位于 `dist/VoiceInputBuddyMic.driver`。App 构建按架构使用独立的 `.build/app-arm64` 与 `.build/app-x86_64` 目录，避免 SwiftPM 缓存混用。Release 与一体安装包的复现步骤见 [发布流程](releases.md)。

本地 `scripts/build-app.sh` 与发布 workflow 共用 Git 版本计算：最近提交在 Asia/Singapore 的日期与完整历史提交数生成 `vYY-MM-DD.NNN`。设置页显示该标记；macOS 的数字版本及构建号分别写入 `CFBundleShortVersionString` 与 `CFBundleVersion`。本地源码有未提交修改时，版本仍对应当前 HEAD，不能把它当作正式发布源码标识。

可选的本地完整源码归档脚本（不作为 Release 附件上传）要求工作区干净（包括暂存、未暂存和未跟踪文件），以保证 HEAD 源码与构建输入一致。忽略目录中的开发输出不会纳入源码包。

测试需要完整 Xcode 提供的 Swift Testing；如遇 `No such module Testing`，设置上面的 `DEVELOPER_DIR`。仅当受限执行环境报 `sandbox-exec: sandbox_apply: Operation not permitted` 时，可在该环境中使用 `swift build --disable-keychain --disable-sandbox`；正常本地与 CI 构建不需要关闭 SwiftPM 沙箱。

App 打包先在临时目录组装全新的 bundle，资源检查和签名成功后再替换 `dist` 中的 App。重复构建不会保留已移除的资源或框架；打包失败时保留上一份 App。可运行 `python3 scripts/test-app-bundle.py` 验证这两条行为。

配置导入保留本机已有的设备档案映射。跨 Mac 导入时，导出文件中当前选中设备的按键映射会应用到本机当前选中设备；尚未配对时作为默认映射保存。其他无法对应到本机设备的映射会显示导入提示，不会悄悄接受后失效。旧版格式 2 文件只有一个设备档案时可自动对应；多个未知档案且没有选择信息时不猜测。

已删除停用的上游硬件公告数据层、占位服务地址和空面板；新增设备支持通过本项目的发行说明公布。

实验性 Apple 遥控器音频辅助进程的每次启动令牌通过匿名 stdin 管道传递，不放在命令行参数或环境变量中。启动时只接受固定长度的 UUID 及换行，缺失、截断或无效令牌会在创建 IPC 服务前退出。该辅助进程仍不纳入当前发行 App。

SwiftPM 使用 Swift 6.2 工具链，语言模式暂为 Swift 5。这是现有并发边界的迁移状态，并不代表已经通过 Swift 6 严格并发检查。切换语言模式需要单独审查事件 tap、蓝牙回调、音频队列和 MainActor 的隔离，不能以一次 manifest 修改代替并发验证。PacketLogger 库与音频捕获执行目标使用独立源码目录，测试显式声明导入的模块；CI 显式编译两个历史 helper，但不安装或以 root 执行它们。

HID 原始映射在改写前一次性原子写入 `~/Library/Application Support/VoiceInputBuddy/HIDMappingRecovery.json`。记录绑定本机启动会话；UUID 不可用时用系统启动时间识别，同样无法识别或写入失败时拒绝改写 HID。离线或恢复失败时保留记录，下次重连/启动继续恢复；不恢复到用户后来主动更改的映射。

Fn 释放失败时不会调用“清理完成”回调或立即重入映射，需要恢复权限后重试释放。旧音频的隔离状态与 Fn 清理完成分离，避免用户切换模式时等待一个尚未到来的遥控器停止通知。音频排空取消、停止及销毁都会回答等待方一次；Apple 音频排空上限为两秒。

事件 tap 的非独占降级模式无法可靠区分相同键码的设备。为避免遥控器快速点击在 HID 释放后才送达的原生 down 造成两次动作，保留 180 毫秒的待匹配 down/up；这也存在同窗口内误吞物理键盘同键码的取舍。不能单用 held 计数过滤，否则会恢复快速点击重复动作的问题。残留 held 状态设置 30 秒上限；独占 HID 路径优先，降级路径仍需实际设备验收。

蓝牙 `.withResponse` 命令采用有界串行队列，成功 ACK 才发下一条；错误或五秒超时清队列并重连。入队成功只表示接受命令，ATVV 通知才确认实际音频流。实验性 Apple helper 只接受每次启动的第一条有效 READY，回调绑定具体进程与连接，旧实例不能影响新实例。

共享日志器不再创建持久化的公开诊断上传队列；没有配置上传服务。既有加密本地故障日志的轮转策略不变。常用语 JSON 由 `scripts/generate-common-phrases.py` 从 Markdown 编辑源生成，打包测试校验生成资源确实存在。

向导第六步的每种输入工具包含五个设置步骤，第三个为输入工具自身的麦克风选择；确认后才进入第七步的实际语音测试。第七步仅根据按键、声音和文字结果判断通过，不再重复询问设置。豆包设置及豆包、微信麦克风浅色截图于 2026-10-12 从本机安装版本截取，原始截图随资源保存，显示时聚焦相关区域。既有深色截图保持不变；新增截图只有真实浅色版本时，深色界面使用浅色截图回退。无法重新捕获的系统菜单、微信 App 快捷键及未安装工具的截图保留原素材。
