# 第五轮审查逐项复核

复核基线：`eaca892`（main，PR #20）。以下编号对应本地第五轮报告。结论依据调用链、资源所有权、公开 API 说明及回归测试；报告中的推测不直接作为缺陷结论。

## 核心发现

| 编号 | 判断与证据 | 处理 |
| --- | --- | --- |
| 1 | 部分成立。Fn key-up 失败后，权限恢复本身不会触发重试，HID 重配回调可以持续等待。但等待真实释放是必要的安全门，不能超时假装成功。 | 每秒单任务重试；成功后才执行等待回调；旧 Fn 未释放时拒绝新的按键注入。测试覆盖失败、恢复、只完成一次。 |
| 2 | 部分成立。缺少销毁释放属实；过期 generation 的回调退出通常伴随取消和清理，不能据此认定原有流程必然卡住。 | 销毁取消任务并尝试抬键；tap 结果以一次性回调收尾，取消/过期返回失败，调用方仍检查 generation。 |
| 3 | 部分成立。Open 失败分支缺显式 Close/回调注销；“整个 manager 必然泄漏”未证实，Swift 管理的 CF 局部引用仍会释放。 | 失败分支注销三个回调、Close、Unschedule，避免留下部分初始化状态。 |
| 4 | 成立。非重复按键丢失释放事件时会持续锁定。 | 8 秒失联释放兜底，清除对应 active usage 和锁定；正常释放、停止、重置取消计时器。它不是重复动作计时器，超时本身不执行用户动作。 |
| 5 | 不成立。设备匹配枚举不要求先 Open。只读本机探针在不 Open 时枚举到 **20 个设备**；CF manager 由 ARC 管理。 | 保留只读枚举，避免为了取名开启 HID 监听或触发额外授权。 |
| 6 | 成立。profileRequired 原分支未释放授权及本进程创建的临时规则。 | 使用现有串行队列 stopOnQueue，统一更新 generation、断开 XPC、释放 AuthorizationRef 和自建规则，再发送 profileRequired。 |
| 7 | 成立。PKLG residual、ACL continuation 无界增长。 | PKLG 单条上限 65,548 字节，输入分块解析；ACL 严格检查声明长度、L2CAP 总长、最多 32 个待组装连接；越界丢弃。测试含 2 MiB 无效头、恢复解析、超长 continuation 和合法分片。 |
| 8 | 成立。清理范围包含上游日志前缀。 | 仅清理本项目日志；测试明确保留上游前缀文件。 |
| 9 | 配置事实成立，不能直接等同并发缺陷。Swift 5 模式关闭部分编译期强并发检查；但报告没有提供实际跨队列无同步访问证据。PacketLogger 的状态、授权完成及 XPC 数据处理返回 stateQueue。 | 保留当前语言模式；不把整个包迁移到 Swift 6 当作未经验证的运行时修复。该迁移应独立检查所有 actor/队列接口。 |
| 10 | 部分成立。helper 名与客户端预期不一致，且不存在 PCM 管线却报告 ready。未打包 helper 是当前仅支持小米遥控器的产品范围，不是已支持 Siri Remote 的发布失败。 | 对齐可执行 target 名和 CI 编译命令；未实现管线明确返回 unavailable，拒绝 start。继续不打包、不启用 Siri Remote。 |
| 11 | 成立。两个迁移标记冗余，单有 Sparkle 启动/历史 build 不足以证明已配置。 | 保留一个迁移标记，仅真实持久化应用配置可以迁移为已完成；首次启动和配置过的旧安装分别测试。已有向导状态不会被覆盖。 |
| 12 | 部分成立。同值赋值和重复图片读取可避免；“必然整个 SwiftUI 树重建”未经性能实测。 | 状态变化才赋值；图片按资源 URL 缓存，最多 16 张、32 MiB 成本预算，由 NSCache 驱逐。保留检测权限恢复的轮询。 |

枚举依据：[Apple IOHIDManagerSetDeviceMatching 文档](https://developer.apple.com/cn/documentation/iokit/1438371-iohidmanagersetdevicematching)、[IOHIDManagerCopyDevices](https://developer.apple.com/documentation/iokit/1438391-iohidmanagercopydevices)。NULL 匹配条件枚举全部设备；Open 用于打开通信，不是此读取的前置条件。

## 第 13 项的十个子项

| 子项 | 判断与处理 |
| --- | --- |
| LoginItemService.refresh | 成立。前台刷新不再清掉操作失败提示；实际重试成功才清除，有测试。 |
| CommonPhrase 失败浮层 | 成立。创建新浮层前关闭旧浮层；独立反馈 generation 防止旧计时器关闭新窗口。 |
| 无 pending 的目的地保护 | 部分成立。直接语音输入不应沿用自动切换的全部限制，否则用户主动输入搜索框也被拒绝。现在直接路径拒绝 AX protected/secure 及敏感语义字段；允许显式搜索和自定义编辑器。测试区分这两种情况。无法从 AX 取到字段信息时，不声称能识别所有敏感目标。 |
| 更新检查卡 checking | 成立。启动失败返回 false，调用方停止后续检查；信息检查设 30 秒兜底，终态取消旧计时器。测试确认超时不会覆盖已完成结果。 |
| 蓝牙恢复标志过早消费 | 成立。先检查运行状态/连接状态，再消费恢复请求，保留暂不能执行的请求。 |
| 初始化失败被 reconnecting 覆盖 | 成立。等待重连期间保留 failed 原因，实际下一次连接阶段更新状态。 |
| stop 等断连回调释放 | 成立。停止时同步结束 session 和 attempt，清除外设、delegate、characteristic 和 central，不依赖系统断连回调。 |
| Apple Remote 语音结束未释放输出 | 成立。没有后续待启动设备时调用 releaseVirtualAudioOutputIfUnused，仍尊重其他活动音频源。 |
| pendingBluetoothVoiceStart 弱引用 | 部分成立。self 销毁也会销毁其拥有的 pending 状态，并非残留；bridge 消失而 self 存活的路径需要清理。补该路径清理及统一 cancel()，仍按 identifier 隔离不同请求。 |
| 隐式本地化 | 不成立。SettingsView 和 OnboardingView 根视图均设置 `.environment(\.locale, localization.locale)`，这些子视图继承应用语言。无需重复替换 Text。 |

## 第 14 项及隐私结论

| 子项 | 判断与处理 |
| --- | --- |
| migrateLegacyMacroBindings | 无调用属实，删除孤立迁移方法。 |
| pendingOnboardingVoiceKeyMigration | 从未非 nil 属实，删除未使用状态、读取入口和整条未展示提示。 |
| applyChromecastModeIfNeeded | 空操作属实，删除方法及调用。没有因此启用 Chromecast 支持。 |
| AppSharing.swift | 无外部调用属实，删除文件。显式复制时 clearContents 本身不能视为缺陷；它与临时为文本插入借用剪贴板的恢复策略不同。 |
| C/ObjC 模块无调用 | 不成立。AudioOutput 调用 VoiceInputBuddyTryPlayAudioPlayerNode；AppleSiriRemoteAdapter 调用 SAYAppleRemoteTouchSession 的创建/启动/停止/销毁及触摸源函数。保留模块。 |
| 缺 AppIcons 目录 | 目录缺失属实，“导致主图标缺失”不成立。catalog 退回 NSApplication.applicationIconImage，程序有独立 icns；facetedDuck 仍用于设置迁移。补上游 logo 许可文档范围说明，保留原许可文字。 |
| 第 15 项隐私 | 复核未新增遥测、原始语音留存或转写归档。诊断日志仍为用户可读取的本地文本。 |
| 第 16 项剔除结论 | 本地化 key 存在；generation 抢占已有失败回调和 owner 清理。没有因这些误报改动对应有效机制。 |

## 验证范围

- `swift test --disable-keychain`：124 项、17 个测试套件通过（原 114 项及新增 10 项），含原有生命周期、音频、目标等待和更新界面测试。
- `swift build --disable-keychain -c release` 通过。
- 7 组 Python 脚本检查通过：app bundle、发布元数据、对应源码、安装/卸载动作、appcast、Pages feed、更新签名。
- 本次没有操作实体遥控器、系统授权数据库或卸载/重装驱动；以上不能替代实体设备验收。
