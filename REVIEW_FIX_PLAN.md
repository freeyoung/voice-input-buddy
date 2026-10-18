# Review 核验结果与修复计划

日期：2026-10-18（Asia/Singapore）。状态：**仅核验和规划，尚未实施本计划中的代码修改**。

核验基线：`main` 的 `0e0a0e681fe53a2c3da4aa15c12694e9aefc98c5`，提交计数 393。输入为本次用户提供的五个领域 review，共 22 项风险/缺陷。下述路径及行号以此基线为准；应用代码路径省略 `Sources/VoiceInputBuddy/` 前缀。“确认”表示代码路径可以证明事实，不代表已经在真实遥控器、输入法或辅助功能上复现全部后果。

文件和类型的命名问题另见根目录 [FILE_RENAMING_PLAN.md](FILE_RENAMING_PLAN.md)。本计划不自动授权后续实施，也不改变产品的权限、驱动、真实语音验证、隐私和发布约束。

## 1. 分级与处理原则

- P1：核心功能或发布完整性的明确缺口，优先实施。
- P2：有范围限制的行为缺陷、可确认的防御缺口，或需要先验证方案的改进。
- P3：可选维护或尚无实际影响证据的调查。
- 不修：报告结论不成立、已有实现，或建议改变了已明确的产品交互。

不沿用报告中的“致命”“高危”标签。需要区分源码事实、可推断的风险和必须通过硬件才能确认的结果。尤其不能把未知型号放宽准入、无差别重试控制指令、修改滤波器或绕过验证，当作默认修复。

## 2. 逐项核验

### 音频与虚拟麦克风

**AUD-01：未监听设备自身的静音和音量——部分成立，P1。**

- 证据：`Audio/BridgeAppModel.AudioRouting.swift:336` 的 `startObservingAudioHardware()` 只在系统对象监听设备列表和三个默认设备属性；`Audio/AudioRuntime.swift` 的移除逻辑也仅记录系统属性地址。
- 设备级 mute/volume 变化确实没有独立监听，健康状态又使用缓存，运行中的外部修改可能未及时触发恢复。
- 但“自愈机制彻底失效”不成立：`Audio/AudioOutput.swift:810` 每次配置设备时仍调用 `ensureVirtualAudioDeviceAudible()`，配置变化时也会读取设备音量快照。
- 修复目标：补齐正在使用的 BuddyMic 的属性观察与缓存失效，不修改系统默认设备或用户其他麦克风。

**AUD-02：GY3LE 被 G9N9N 校验拒绝——产品入口与适配范围不一致成立，P1；“任何连接都必然走到指定报错”不成立。**

- `Devices/PlannedRemoteDevice.swift:16,45` 为 GY3LE 提供可开始设置的入口，并将其归入 Chromecast 来源。
- `Devices/G9N9NProtocol.swift:17` 只接受 G9N9N；候选名称、VID/PID、HID 报告和能力验证也都是 G9N9N 专用。`Tests/VoiceInputBuddyTests/G9N9NProtocolTests.swift` 明确测试拒绝 GY3LE。
- GY3LE 可能在发现阶段就被排除；若进入 Google 型号确认分支，也会被拒绝。因此当前代码不能兑现该设备的完整连接流程，但这不是漏加一个字符串即可修好的问题。
- 修复目标：取得 GY3LE 的公开协议依据和真实设备证据，再实现独立识别及必要的协议差异；保留未知型号拒绝策略。遵守用户关于网页四款设备支持表述的要求，不在本次计划中擅自将其改成“即将支持”。

**AUD-03：去直流与软限幅名不副实——数学事实成立，错误承诺与实际音质损害未确认，P3 调查。**

- `Devices/ATVVProtocol.swift:135` 明确注释为 causal binomial FIR，没有声称实现 DC blocker 或 soft limiter。已有测试名为 `postprocessorAppliesSmoothingAndClampedGain()`。
- FIR 系数 `[1,2,1]/4` 的 DC 增益为 1、Nyquist 增益为 0：这是低通滤波器，**不是全通滤波器**，也不去直流。最终 Int16 限幅确实是硬削顶。
- +24 dB 对应约 15.85 倍幅度；没有硬件 DC 偏置测量或识别率对比，不能直接证明报告所称的严重后果。
- 处理：先测 DC、峰值和削顶比例；确认需要后再选择 DC blocker/限幅方案，不直接改当前解码输出。

**AUD-04：ARN9 格式读取晚于开流——时序缺口成立，具体破音待硬件复现，P2。**

- `Devices/XiaomiBluetoothBridge.swift:1206` 对非 Google 设备的 ready 判定只依赖 capabilities，没有等待 DIS 型号读取。
- `:1869` 在异步 DIS 回调中设置 nibble 顺序；默认 high-first。`Audio/BluetoothAudioPipeline.swift` 将配置和解码排入串行队列，可以保证已入队工作的顺序，却不能让较晚收到的型号信息回溯纠正此前数据。
- ARN9 未在已验证型号目录中，但连接名称和解码分支仍保留相关路径。不能据此宣称所有小米遥控器都会破音。
- 修复目标：在格式未确定时不投递可能错误解码的 PCM，同时为不提供 DIS 的已验证型号制定明确失败或有证据的默认策略，避免无限等待。

### 蓝牙与按键输入

**BT-01：全局重置未清理 repeatTokens——不成立，不修。**

- `Devices/HIDRemoteMonitor.swift:1413`、`:1443` 都已调用 `repeatTokens.removeAll()`，分别位于 `cancelPendingButtonActions()` 与 `resetInputState()`。
- 已有取消、释放、断连和旧 timer 回调测试。本项不能再增加一套冗余清理逻辑。

**BT-02：关麦入队失败仍清除本地开麦状态——成立，P1。**

- `FlowControlledBluetoothWriteQueue.enqueue()` 和 `AcknowledgedBluetoothWriteQueue.enqueue()` 均有 32 项容量限制，满载返回 false。
- `XiaomiBluetoothBridge.requestMicrophoneClose():592–608` 在 `write()` 返回 false 后仍设置 `microphoneOpened = false`；若还未 streaming，后续 close 会直接返回 true。`write()` 的成功也只表示队列接受，不表示物理关麦已确认。
- 无响应队列堵塞已有 5 秒超时重连；长录音流程另有 close timeout，因此“必定永久常开耗电”超出了证据。但丢失关麦意图和错误报告本地状态是真实缺陷。
- 修复目标：明确 requested/open/closing/closed 的状态与关闭意图，保证关闭命令有界送达或连接恢复；不能仅把 Bool 赋值挪到 enqueue 成功之后就宣称物理已关闭。

**BT-03：响应写入失败没有瞬态重试——现状成立，RF 因果链与统一重试建议不成立，P2 调查。**

- `AcknowledgedBluetoothWriteQueue.acknowledge(success: false)` 立即 reset 和 failure；bridge failure 回调停止流并重连，没有错误分类。
- 但 BLE 底层本来有链路重传，ATT 错误不等同于“一次 RF 丢包”；认证、无效句柄、断连、资源不足也不能同样处理。重发 open/extend 等控制命令还可能重复执行。
- 处理：先保留实际错误信息、区分可恢复类型和命令幂等性，再决定有限重试；维持认证修复、断连恢复和超时兜底。

**BT-04：600 毫秒稳定释放窗口吞掉连续点按——成立但范围受限，P2。**

- `HIDRemoteScheduler.swift:20` 定义 600 ms；`HIDRemoteMonitor.scheduleNonRepeatableRelease():1100` 在释放后延迟清除 pressed 状态。
- 对未启用持续连发、未启用“允许连续快速按”、且走 raw 路径的按键，下一次 press 在窗口内被 `shouldAcceptRawPress()` 拒绝，并取消尚未完成的释放计时。当前默认不连发的 Back 可以走此路径。
- 双击/独立长按识别、显式快速点按配置和连发路径不能一概而论。
- 修复目标：真正释放后的独立点按应及时响应；按住时的重复 HID 报告仍不能冒充多次点按，缺失 release 的恢复继续有效。

**BT-05：缺少 35 ms 物理防抖——未证实硬件问题，P3，先调查。**

- `RemoteButtonGestureRecognizer` 没有 timestamp 防抖窗口，但上游已经依据 HID usage 集合提取 press/release 边沿，持续重复相同报告不会直接成为双击。
- 没有真实的 press→release→press 抖动样本，不能假设遥控器固件没有防抖。直接加 35 ms 会影响快速点按及双击。
- 处理：有实际边沿证据再加设备级过滤；不先在通用手势状态机硬编码新窗口。

### AX、剪贴板与单实例

**SEC-01：短语剪贴板缺少特殊数据标记——成立，P2 隐私加固。**

- `CommonPhrases/CommonPhraseClipboardPaste.swift:176` 当前只用 `.string` 写入短语，没有 generated/transient/concealed 标记。
- 应加入符合语义的标记，让遵循约定的剪贴板历史工具选择不收录。标记不是访问控制，不能保证任意监听程序不会读取。
- 成功提交当前允许慢速目标读取，采用显式恢复。不能为添加标记而改成定时恢复，或提前写出一个未标记的明文版本。

**SYS-01：锁文件不包含 PID——事实成立，P3 可选诊断。**

- `App/ApplicationInstanceGuard.swift:52–68` 使用 flock，成功后没有写 PID。锁功能不依赖文件内容，因此不是单实例失效。
- 若实施，仅在持锁期间写入诊断信息；PID 陈旧或被复用不能成为删除锁、强杀进程或绕过 flock 的依据。

**AX-01：微信坐标点击应降级——优先顺序问题成立，P2。**

- `Input/KeyboardInjector.swift:884` 第一次尝试会优先执行 `focusWeChatComposer()`，早于通用 AX composer 搜索。
- `KeyboardInjector.Accessibility.swift:152` 用窗口宽高的 0.68 / 0.85 比例点选，依赖窗口标题和最小尺寸；不能识别内部面板布局。当前发送点击后就返回 true，没有证明输入焦点落到 composer。
- 微信具体版本、联系人面板和宽屏失败仍需公开 UI 验证。修复目标：优先可靠 AX 目标，坐标仅作受约束的最后备用手段，并验证点选后的实际焦点。

### SwiftUI 与体验

**UX-01：快捷键选择器 5 处裸 Text key 必然导致切换语言失效——结论不成立，开发资源路径不一致成立，P2 整理。**

- 五处位置属实：`Input/KeyboardShortcutPicker.swift:413,442,444,565,567`。
- `Settings/SettingsView.swift:106` 已注入 `.environment(\.locale, localization.locale)`。SwiftUI 的本地化 Text 会使用环境 locale，不能仅凭未调用 LocalizationStore 断言正式 .app 切换语言无效。
- 真正的差异是 `LocalizationStore` 支持 `VoiceInputBuddyResourceBundle.mainOrDevelopment`，裸 Text 默认找 main bundle；SwiftPM 裸二进制没有同样的资源回退。
- 处理：统一走现有 LocalizationStore；验证正式包与开发预览、原地切换中英语言，而非引入第二套本地化机制。

**UX-02：偏好设置裸写中文——成立，P3。**

- `Settings/SettingsView.Preferences.swift:315` 的“测试长时间语音功能”没有英文本地化；仅在 RC003 延长语音实验启用时显示，不是所有用户都会看到。
- 修复：增加中英资源 key，复用现有文案读取方式。

**UX-03：持续连发不能再点取消——不按此提议改；选中无障碍属性缺失成立，P2。**

- `SettingsView.MappingEditor.swift:23` 是“长按动作值”的单选按钮，不是第四个独立开关。这符合用户已明确的三种配置：单击、双击、长按；长按值是一个普通动作或持续连发。
- 编辑页已有“清除设置”，选择其他动作也能替换持续连发，因此并非不能关闭。重复选择同一值保持选中是合理单选行为。
- 该按钮仅用视觉 checkmark 和 identifier 表达选中，未添加 `.isSelected`。计划补齐可访问的当前值和单选语义，不改成互相叠加的 Toggle。

**UX-04：状态栏 Control-click 与 VoiceOver 菜单入口——部分成立，P2。**

- `App/VoiceInputBuddyApp.swift:850` 只显式判断 `.rightMouseUp`；其他事件都打开设置，没有 control modifier 分支。
- 某些系统派发方式可能将 Control-click 处理成上下文点击，仍需实际验证；没有显式 VoiceOver 菜单操作也是改进点，但不能只从源码断定所有 VoiceOver 菜单入口都失效。
- 修复目标：左键仍打开设置，右键和 Control-click 打开菜单，并为辅助功能提供可发现的菜单入口；实际用 VoiceOver 验收日志、退出等菜单操作。

**UX-05：HID 绑定 Sheet 没有最大高度——代码事实成立，溢出未复现，P3。**

- `Onboarding/RemoteHIDBindingPicker.swift:23,37` 只有 List 的最小高度和 Sheet 宽度，没有显式高度上限。
- List 本身可滚动，多设备不等于必然无限增高。需要先用小屏、长名称和大量候选验证导航按钮是否可见，再决定合理的默认尺寸与上限。

### 发布、依赖与许可证

**REL-01：没有将独立源码包接入生产发布——事实属实，但属于用户明确保留的设计，不处理。**

- `.github/workflows/release.yml` 没有调用 `scripts/build-release-sources.sh`；publish 明确只上传三种 PKG。
- 本次读取正式 Release `v26-10-18.393`，附件确实只有 arm64、intel 与 uninstaller 三个包，没有独立源码 tarball。GitHub 自动仓库归档不等于包含修改版驱动及依赖的配套源码包。
- `docs/source-code.md` 已明确：使用对应 Git tag 的项目源码、固定 revision 的 BlackHole/Sparkle 源码和本仓库 patch/构建脚本；合并源码脚本仅供可选本地归档。`docs/releases.md` 同样说明不附独立源码包。原 review 忽略了已有的源码提供设计。
- 用户在本次核验中明确说明，这是此前特意调整的发布设计，不需要增加源码附件。本计划据此排除此项，不接入打包脚本、不增加发布门禁、不补传历史附件。
- GPL 允许不止一种源码提供方式，不能只根据“没有独立 tarball”认定违法。本次不对完整法律合规作结论，也不因原 review 的标签而改变发布行为。

**REL-02：BlackHole 版权和许可证遗漏——部分成立，P2。**

- `THIRD_PARTY_NOTICES.md:215` 的 BlackHole 小节只有项目、revision 和 GPL 标识，缺少明确的上游作者版权声明及随包许可证位置。
- 但“发行包没有 GPL 正文”不成立：`scripts/build-driver.sh` 已将上游完整 LICENSE 拷入驱动 `Contents/Resources/BlackHole-LICENSE`；`build-app.sh:37` 也将项目 LICENSE 和 notices 拷入 app。
- 固定 revision 的 `BlackHole.c` 声明 `Copyright (C) 2019 Existential Audio Inc.`，LICENSE 首部也有 Existential Audio 的声明。不能凭报告添加未在该 revision 找到的 Clifton Norrie 署名。
- 修复目标：补准确版权与许可证指引，保留上游完整 LICENSE，验证最终包可找到；不必在 notices 中重复整篇 GPL。

**REL-03：第 1000 次提交触发版本上限——成立，P2，须提前发布修复。**

- `scripts/release-metadata.sh:7` 主动拒绝大于 999；`generate-appcast.py:13`、`generate-release-notes.py:9` 和 `Updates/UpdateInformationStore.swift:161` 均限定恰好三位计数。
- `docs/releases.md` 已明示这个已知格式上限及扩展需求；它是主动格式保护，不是突然引入的恶意或未知“熔断炸弹”。本计划将其作为提前安排的格式扩展。
- 只删除 shell 上限仍会让 feed、release notes 或已安装客户端解析失败。当前基线计数是 393，并非报告的 392。
- 修复目标：保留日期和提交计数语义，前三位只是最小补零宽度，接受增长后的计数；在达到 1000 之前交付能识别新 tag 的客户端。

**REL-04：Xcode 26.2 不存在，是 16.2 笔误——不成立，不修该建议。**

- 官方 `actions/runner-images` 的 macOS 15 清单列出 `/Applications/Xcode_26.2.app`；该路径是有效安装路径。
- 基线对应发布构建 [39086520298](https://github.com/zfdang/voice-input-buddy/actions/runs/39086520298) 成功。当前 Package 使用 tools 6.2，UI 还包含 macOS 26 SDK API，不能盲目降到 Xcode 16.2。
- 未来 runner 移除某版本是正常维护事项，可增加工具链可用性诊断，但不作为本次已确认构建故障。

**REL-05：驱动构建非原子、依赖联网——部分成立，P3。**

- `scripts/build-driver.sh` 在固定 `.build/buddy-driver` 工作目录和最终 dist bundle 中写入，缺少隔离 staging；并发调用或中途失败可能留下部分产物。
- 网络仅在依赖 Git 目录不存在的首次准备阶段使用，并非每次构建都会 fetch。已有固定 commit、checkout 和 patch 校验，正常冷构建需要联网不算单独缺陷。
- 修复目标：依赖准备可恢复、并发可控，最终产物经验证与签名后才替换；在已有源码缓存时支持不联网构建。无需承诺首次运行天然离线。

## 3. 分批修复计划与验收

### 第一批：关麦可靠性与音频恢复（BT-02、AUD-01、AUD-04）

1. 先增加确定性回归场景：32 项满队列、暂停发送、关麦 enqueue 失败、关闭前尚未收到 stream start、迟到的 stop/start、断连及重连后的旧回调。
2. 为 close 建立可观察的 pending/closing 意图和有界完成路径；根据 ATVV 版本判断何种事件可确认结束。关闭控制可保留发送空间或有明确优先级，但不能让排队的旧 open 在 close 之后重新开麦。发送失败/超时必须保留关闭需求或升级为可见的连接恢复。
3. 有响应命令区分“已入队”“ATT 已确认”和“会话已关闭”；无响应发送不能被记录成硬件确认。所有 timer/重试绑定连接及会话身份，旧会话不得关闭新会话。
4. 对选定 BuddyMic 注册支持且存在的 input/output mute、volume 属性监听，必要时覆盖驱动实际暴露的 channel element。记录 object ID、address、queue、listener 身份，以便同样参数移除。
5. 设备替换、驱动重启、休眠及停止时撤销旧监听；在非实时队列合并通知、更新健康状态并使用现有修复策略，避免自身写属性形成恢复循环。首次语音准备时也检查过期缓存。
6. 将解码格式确定纳入 ready 门槛；型号读取失败/缺失须有有界结果，不能静默用错误 nibble 顺序输出。保持 disconnect reset 与 session reset 的不同语义。

验收：受控 scheduler/模拟 HAL 测试通过；真实遥控器关闭后停止流；音频 MIDI 修改 BuddyMic 静音与音量后可恢复；其他麦克风和系统默认路由不变；小米 RC001/RC003 的首次语音、断连、睡眠恢复不退化。ARN9 的具体顺序和缺失 DIS 行为另做设备验收，不能用模拟测试代替。

### 第二批：许可证说明和版本边界（REL-02、REL-03）

1. 补齐 notices 的上游版权与包内许可证位置，测试真实解包结果；不复制商标或私有凭据。
2. 在所有 tag 生产和消费处统一放宽提交计数位数：metadata、appcast、release notes、客户端版本识别及相关测试/文档。保持计数为正整数、格式严格校验及 Sparkle 数值排序。
3. 增加 998/999/1000/1001 及更大值、日期切换、浅 clone 拒绝、异常 tag、旧三位 tag 的测试。保留对仍在发布使用的旧版本格式读取，这属于活跃更新行为，不增加旧 API 兼容壳。

验收：最终包保留正确上游版权及许可证；999→1000 的 feed 与客户端可读；生产签名要求及未公证说明保持不变。

保留当前不附独立源码包的发布设计、双架构 PKG、卸载器及 main 自动发布行为，不调整历史 Release。

### 第三批：设备适配与用户输入（AUD-02、BT-04、AX-01）

1. GY3LE 先采集用户可见设备信息、DIS、PnP、服务和控制能力，依据公开资料验证与 G9N9N 的相同及不同部分。未取得证据前，不直接复用 VID/PID、帧长、codec 或 HID usage。
2. 建立明确型号选择和身份表，使设备选择、连接、映射图、会话就绪都使用实际型号；确有共用事实才抽取 GoogleRemote 公共部分。名称不能替代身份校验。
3. 先重现 Back 快速点按的 raw 路径，再将“真实释放后的新按下”和“无释放的重复报告”分离。不能简单将全部 600 ms 换成另一常量；保留每键快速点按设置的可理解语义、双击 300 ms、长按 550 ms、连发 350 ms 及断连清理。
4. 微信优先 AX 查询和确认 composer；只有公开 AX 失效且目标应用/窗口/安全状态均验证后才执行最后备用点击。点击后重新检查实际焦点；目标无法确认时报告失败。

验收：新旧 Google 型号正反例与未知设备拒绝；真实 GY3LE 普通键和语音完整向导；Back 100/200/400 ms 间隔独立点按、无释放报告、双击、长按与 mapping reset；微信多种窗口大小/布局、焦点变化、安全控件和无权限路径。GY3LE 实机不可用时该项保持待验收，不声称实现完成。

### 第四批：隐私、辅助功能与本地化（SEC-01、UX-01～UX-05）

1. 使用同一个 NSPasteboardItem 写入短语和合适的 Transient/AutoGenerated/Concealed 标记，尽量避免明文先于标记可见；快照保留原剪贴板所有类型。
2. NSPasteboard 多步写入后重新审视 changeCount 租约，保证写入失败回滚、用户复制新内容、连续短语插入和手动恢复均正确；保留当前无定时覆盖的恢复模型。
3. 给持续连发选项补充选中语义、可访问名称和可达的“清除设置”；保留长按动作单选，不增加第四个开关。
4. 状态栏补 Control-click 与辅助功能菜单操作；保留普通左击设置入口，测试空事件和键盘辅助调用。
5. 五处快捷键 key 及实验功能中文统一使用现有 LocalizationStore；验证正式 .app 与 SwiftPM 预览的中英切换。
6. 先确认 HID picker 的小屏布局，必要时限制 sheet 内容高度并维持 List 滚动，让取消/刷新/保存始终可达。

验收：剪贴板测试检查同一 item 的类型、租约和恢复，不读取第三方剪贴板工具数据库；可通过工具的公开 UI 核实其遵循标记，但不承诺屏蔽任意监听。VoiceOver 可读当前长按值并关闭连发、打开状态栏菜单；中英文截图及小屏多候选界面检查通过。

### 第五批：有证据再做的优化（AUD-03、BT-03、BT-05、SYS-01、REL-05）

- DSP：以合成 DC/正弦/脉冲、不同增益和跨帧数据评价 DC、频响、峰值、延迟和会话 reset；真实输入仅做用户授权的现场比较，不默认落盘音频。确认收益后才引入高通/限幅，另定验收阈值。
- ATT 重试：用错误分类和幂等矩阵设计一次有界重试；认证失败、旧 generation、断连与未知完成结果不能盲目重发。重试前后会话顺序和原重连兜底必须可验证。
- 防抖：仅在采集到实际错误边沿后处理，证明不会吞掉用户双击或快速点按。
- PID：若增加，验证持锁写入、错误路径、权限、符号链接拒绝及退出释放；不更改 flock 判据。
- 驱动构建：引入独立 staging、缓存准备的原子完成/锁定和最终替换；测试首次中断、损坏 checkout、已有 patch、缓存离线、并发启动、编译或签名失败后旧 bundle 仍可用。

## 4. 基线验证与实施门槛

- 本次已运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-keychain`：488 项测试、88 个 suite 全部通过。这是当前基线结果，不表示上述待修路径已经被测试覆盖。
- 本次已运行发布流水线中的 13 项 Python 测试脚本：13/13 通过。源码打包脚本的单元测试通过与是否在生产发布中启用它是两件事；后者继续按用户要求保持不启用。
- 报告中的“全部 Swift 6 语言模式”不准确：Package 的 tools version 是 6.2，`swiftLanguageModes` 当前为 `.v5`。测试采用 Swift Testing 与生产代码语言模式是两回事。
- “完全没有真实休眠”也不准确：`InputLifecycleRegressionTests.swift:456,467` 使用两次 100 ms Task.sleep。受控时钟覆盖很广，不能将其描述为所有测试均无真实等待。
- 每个独立问题使用独立提交；按主题保持同一修复批次 PR。命名整理与行为修复分开，便于定位回归。当前仅文档提交，不提前实施。
- 后续运行 `swift build --disable-keychain`、`swift test --disable-keychain` 及相应 Python 测试；涉及硬件、输入法或 VoiceOver 的事项需保留明确的人工验收记录。

## 5. 外部依据

- [GitHub 官方 macOS 15 runner 清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)：核验 Xcode 26.2 安装路径，清单会随镜像变动。
- [固定 revision 的 BlackHole LICENSE（含 GPL v3 正文）](https://github.com/ExistentialAudio/BlackHole/blob/e2b22aaaba4e507a097131704bf96dabc004d9cf/LICENSE)：核验上游版权、源码对应范围与第 6 条的提供方式。
- [NSPasteboard 特殊数据标记约定](https://nspasteboard.org/)：核验 confidential/generated/transient 标记语义；它是互操作约定，不是系统保密屏障。
- [正式 Release v26-10-18.393](https://github.com/zfdang/voice-input-buddy/releases/tag/v26-10-18.393)：本次读取的公开附件列表。
