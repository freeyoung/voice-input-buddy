# 审查问题核验与修复执行计划

本计划覆盖所提供 Issue Matrix 的全部 19 个编号，供后续逐项执行。当前阶段只核验、分级和制定计划，未修改产品代码，也未新增修复性测试。核验基线为 main 的 `560995940ce15ee3d23bff49a58c130fcb42ada7`，日期为 2026 年 10 月 17 日；未来执行时须先对照最新代码重新确认。

最先处理的是 G9N9N 连接准入冲突和重复流开始造成的音频状态重置。没有证据支持 Critical／P0 级别。原报告提出的若干修复不能直接照搬：不能在每次 ADPCM reset 时清除设备格式，不能靠跳过驱动或转写检查宣告向导验证成功，也不能只递增一个蓝牙 generation 而不更新其余回调身份。

## 分级和证据标准

- **P0 紧急**：广泛严重故障、可利用的严重安全漏洞或不可逆数据损坏，需要立即止损。本次未确认此类问题。
- **P1 高**：已能从生产调用链确认的核心功能失效，应优先修复；真机仍用于验收实际影响。
- **P2 中**：范围受限的缺陷、恢复体验问题或明确的防御性缺口，按依赖安排。
- **P3 低**：细节体验或可选加固，不阻塞主要功能。
- **不作为缺陷修复**：原结论不成立，或描述的是产品验证要求；保留核验记录，出现新证据再重开。

“成立”表示代码路径支持所述缺陷，不等于已经真机复现。“部分成立”表示事实存在，但触发范围、影响或原建议需要修正。“待复现”项先做限定实验，不能凭猜测改行为。优先级与证据可信度分开记录。

## 全量核验矩阵

| 编号 | 原级别 | 核验结论 | 重新分级 | 实际范围与下一步 |
| --- | --- | --- | --- | --- |
| BT-01 | Critical | 成立，源码路径确认 | P1 | 发现阶段允许部分 Chromecast 名称，didConnect 再无条件拒绝相同名称。不是所有 G9N9N 名称都会命中，也没有安全漏洞证据。 |
| BT-02 | High | 部分成立，格式保留已实验确认 | P2 | nibble 顺序确实未随外设重置；常规一设备一桥不支持报告所称任意换设备串扰。重点检查未绑定发现桥失败后换候选、同身份固件变化。 |
| BT-03 | High | 成立，源码路径确认 | P1 | 已开始流后再次 startStreaming 仍先 reset。属于串行回调先后顺序错误，不是两个线程同时解码的数据竞争。 |
| UX-01 | High | 部分成立，交互行为确认 | P2 | Siri 可选择、Continue 可点，点击显示提示并不前进；可重新选择其他设备，不是不可退出的死锁。 |
| UX-02 | High | 部分成立，验证门槛与恢复缺口并存 | P2 | 驱动未就绪确实不能前进，但已有刷新、安装说明和返回。改善恢复与暂停设置，不跳过验证并标记成功。 |
| UX-03 | High | 行为属实，作为缺陷不成立 | 不修复原提议 | 实际语音转写是既定验收条件，物理打字不能冒充语音成功；无网影响取决于选用工具。 |
| LAY-01 | High | 部分成立，滚轮拦截待交互复现 | P2，复现主要操作不可达则升 P1 | 小窗口确实有外层及左右内层滚动；现有程序化滚动可以到达底部，不能据此断言滚轮始终被拦截。 |
| LOC-01 | High | 部分成立，裸二进制资源问题已预览复现 | P2 | `.app` 中中英文本均能解析裸 key；页面已注入 locale。“必然破坏应用内切换”不成立，原地切换需专门回归。 |
| INP-01 | Medium | 成立，源码提取探针复现 | P2 | Command key-up 返回 false 后保留 active 却无自动重试；Tab 失败时的回滚也需纳入同一所有权。 |
| INP-02 | Medium | 检查缺口成立，安全后果未证实 | P2 防御加固 | 普通映射 send 没有 Secure Input 门禁。不能据此声称已绕过系统安全机制或已泄露密码；先明确各类动作策略。 |
| SYS-01 | Medium | 成立，常量差异确认 | P2 | fallback 与 Info.plist 不仅大小写不同，连字符也不同；共享文件锁仍有效，影响第二实例的激活目标。 |
| SYS-02 | Medium | 编译期隔离缺口成立 | P2 架构改进 | 无类级 MainActor，但已有主队列回调和局部隔离；尚未确认实际后台发布或崩溃。 |
| BT-04 | Medium | 部分成立，旧回调误收待复现 | P2 调查后修复 | 快速恢复复用 generation；现有 central、peripheral、phase 检查可挡部分事件，同一 peripheral 对象跨尝试的旧回调仍需验证。 |
| BT-05 | Medium | 成立，缓存与去重链确认 | P2 | 新 profile 缓存被删后未迁入原 profile；重新读相同值又被桥去重，可能显示缺失或原设备旧值。 |
| UX-04 | Medium | 部分成立，初次设置缺少显式暂停 | P2 | 初次设置不能 dismiss，但窗口可关闭、菜单可退出；不是进程死胡同。不得绕过所需权限继续验证。 |
| A11Y-01 | Medium | 局部设置成立，实际焦点可见性待验收 | P3 | focusEffectDisabled 仅应用于向导返回按钮，不能推导所有 Tab 导航失效。 |
| A11Y-02 | Medium | 显式快捷键缺失成立，默认系统行为待验收 | P2 | 两个绑定弹窗无 cancelAction/defaultAction 声明；需检查 Esc、Return、列表焦点及禁用状态。 |
| SYS-03 | Low | 原“音频不完成导致无限等待”结论不成立 | 不修复原提议；可选 P3 回归 | 音频排空和 Fn 会话都有截止兜底，key-up 失败有有界重试及失败完成通知。没有主线程被底层调用永久阻塞的复现。 |
| LAY-02 | Low | 成立，位置覆盖调用确认 | P3 | 设置 autosave 名称后无条件 center；还需显式区分恢复成功与首次打开。 |

按主要处理级别统计：2 项 P1、13 项 P2（包含先调查再决定修复的条目）、2 项 P3、2 项不采纳原缺陷修复提议。SYS-03 的补充回归属于可选加固，不计作已确认缺陷。

## 逐项证据与实施任务

以下条目均为未来任务。只有进入实施阶段后，才能勾选完成；无缺陷及待复现项允许以证据归档结案，无须制造代码变更。

### BT-01 统一发现与连接阶段的设备准入

**证据。** [VoiceRemoteAdmission.decide](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/BluetoothLifecycle.swift#L103) 在 allowsG9N9N 为 true 时优先采纳候选名称，而 [didConnect](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1425) 无条件执行 ForeignVoiceRemoteProduct 检查。两者交集包含 `Chromecast`、`Chromecast Remote`、`Chromecast 遥控器`。名称为 `G9N9N` 或 `Chromecast Voice Remote` 并不命中同一拒绝表，因此不能说所有真机必然失败。拒绝 UUID 集合属于桥实例生命周期，不是写入磁盘的永久黑名单。

**实施。** 将连接后校验纳入统一准入策略，先验证回调属于当前 central／peripheral／phase，再判定设备。放行候选名称仍需 G9N9N 型号、codec 与准备状态握手，不能将蓝牙名字当成正品认证；保留不支持的 G10 等设备拒绝。同步纠正“私有 Chromecast 适配器接管”的过时注释。

**验收。** 覆盖所有交集名称、其他 G9N9N 名称、改名后的保存身份、非 Google 模式、非目标 UUID、伪装名称但错误型号、失败握手，以及旧连接 didConnect。增加完整“发现→连接后校验→DIS／capabilities→ready”测试，避免仅纯 admission 测试通过而实际仍拒绝。用实际 G9N9N 验收配对、重连和语音。

### BT-02 把 ADPCM 格式绑定到外设而非音频帧重置

**证据。** [IMAADPCMDecoder.reset](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/ATVVProtocol.swift#L98) 保留 lowNibbleFirst；[型号处理](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1847) 只有置 true 的分支；[resetPeripheral](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L766) 未恢复格式。源码提取实验确认 true 在 reset 后保留，字节 `12 34 56` 得到 `[3,4,11,18,31,49]`，高半字节优先为 `[1,4,8,15,27,47]`。这证明状态与结果不同，不能证明真机必然出现“刺耳爆音”。

[一设备一桥与发现桥提升](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/BridgeAppModel.BluetoothConnections.swift#L14) 和 bindVerifiedIdentity 会固定已确认 UUID，降低了报告所称跨任意设备换连的触发范围。ARN9 连续会话需要保留其格式；帧同步也会调用 decoder.reset，故原建议在所有 reset 中置 false 会直接引入回归。

**实施。** 区分设备格式配置和预测器／累加器／滤波器状态。在外设边界恢复默认格式；读取型号时明确赋值两种格式，Google 分支同样由设备配置确定。流开始／停止和同步帧只重置音频状态，保留已识别格式。

**验收。** 高／低半字节已知向量，ARN9 连续两次录音及中途同步后格式不变；未绑定发现桥先收到 ARN9 型号再初始化失败，随后采纳高半字节设备时不继承格式；同 UUID 重连和读取型号失败的默认策略。缺少 ARN9 真机时只标记算法与状态测试通过，不宣称完成听感验收。

### BT-03 让重复流开始对解码状态幂等

**证据。** [startStreaming](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1218) 在 `guard !streaming` 前执行 audioDecoder.reset。[handleAudio](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1255) 可隐式开始流，迟到的 0x04 控制包再次进入同一函数。累加器、预测器及 FIR 历史会被重置。实际吞字或爆音幅度仍需音频向量和硬件确认。

**实施。** 将“一次流的新建”与“迟到控制包补全 session metadata”分开；对同一活动流的重复开始不重置。保留收到停止后真正新流的重置，以及错误 codec／取消开麦的拒绝逻辑。新 session ID 与重复通知须明确区分，不把所有后续 0x04 一概吞掉。

**验收。** 比较音频先到、控制先到、重复控制和分片跨越控制包四种序列，PCM 与无重复开始的参考流一致；覆盖真正新 session、停止后残包、取消开麦与不同 codec。使用可注入传输或事件入口驱动生产处理路径，不能只验证复制出来的状态机。

### UX-01 让计划设备的设置状态在选择时可见

**证据。** [canContinue](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingFlow.swift#L779) 只要求 selectedDevice 非空；[continueFlow](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.Navigation.swift#L164) 会拦截 canStartSetup 为 false 的设备并显示提示；[设备定义](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/PlannedRemoteDevice.swift#L13) 中 Siri 无 onboardingSource。用户可重新选择设备。目录还明确区分“允许开始设置”和“已验证适配器”，不能顺带把其他计划型号的可选策略改掉。

**实施。** 保留查看计划设备的能力，选择后立即在主交互区说明暂不支持；Continue 的状态与能否开始设置保持一致，必要时以说明动作代替继续。调整既有刻意允许点击后解释的策略测试和文案，而非将旧测试当成实现缺陷。

**验收。** Siri 无须先点 Continue 才知道不可设置；可以通过鼠标、键盘、VoiceOver 返回可支持设备；小米与 G9N9N 的选择流程不回退，其他型号仅按其现有产品定义处理。

### UX-02 改善驱动失败时的恢复而保留音频验证

**证据。** [音频页面](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.AudioRoute.swift#L15) 已有刷新和安装说明，[底部导航](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.Navigation.swift#L121) 在 audio 阶段隐藏 Continue；自动前进要求驱动与输出均 ready。驱动未加载时无法继续是预期门槛，但长时间等待和退出恢复可更明确。

**实施。** 显示等待、缺驱动、驱动存在但输出失败等状态，提供重试、说明及“退出并稍后继续设置”。超时只触发解释与恢复入口，不把超时当成功。若产品未来需要跳过，只能进入明确“未完成／不可录音”的状态，不能写入完成标记或验证绑定；本计划默认不新增绕过门槛。

**验收。** 缺驱动、初始化失败、设备恢复、重试中离开页面和迟到回调都可处理；不就绪时不会标记音频已验证，恢复后只前进一次，保留固定虚拟麦克风路由。

### UX-03 保留真实语音验证并说明失败原因

**证据。** [语音继续条件](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingFlow.swift#L792) 要求开始、采样、结束、转写且无人工键盘输入；[Readiness](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.Readiness.swift#L52) 还验证转写与目标工具运行态。物理打字可以发生，但不会被计作语音测试通过。静音、离线和外部工具故障无法建立语音可用的证据。

**处理。** 不按原建议放行打字或空转写。核对失败文案与重试／稍后继续入口；如需改善，作为 UX-02／UX-04 的暂停恢复体验，保持独立测试证明“暂停≠完成”。只有维护者明确改变产品验收定义时才另立需求。

**验收。** 人工打字、没有采样、没有结束或转写来自错误目标时均不能完成验证；有效语音转写仍可完成；离线型工具不被额外加入网络前置条件。

### LAY-01 先验证嵌套滚动再固定关键导航

**证据。** [最小画布与外层滚动](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/SettingsWindowLayout.swift#L8) 为 980×732；[左栏](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.Navigation.swift#L65) 和右栏各有内层 ScrollView。Continue 在左栏内部 ScrollView 外、外层 ScrollView 内。之前的程序化滚动预览能显示 Continue，但没有覆盖鼠标悬停内层时滚轮／触控板事件的分配，因此原报告的“根本无法触及”尚未确认。

**先复现。** 在 720×500、1020×680、1020×732 和正常窗口下，分别将指针置于左栏内容、右栏内容、边缘及滚动条；测试滚轮、触控板、拖动滚动条、Tab 到主按钮。覆盖内容有／无内层溢出的步骤。如果主要输入方式无法到达 Continue，升级 P1 并优先修复。

**实施。** 向导主导航固定在实际视口中，正文在可用空间内滚动；宽度不足时保留可到达的横向内容，不能靠强制缩小字号。设置页按实际存在的固定操作区域分别调整，不能假设所有设置页都有同一底栏。确认问题范围后再决定是否删除外层双轴滚动或只取消竖向最小高度，避免替换一个裁切问题。

**验收。** 主按钮不依赖滚动即在可视区内；左右正文均可滚到末尾，焦点跳转不将按钮移出视口；正常尺寸、长英文、高对比度与重新打开窗口通过交互验收。截图证明布局，可控 UI 交互才证明滚动可达。

### LOC-01 统一开发资源解析并回归应用内语言切换

**证据。** [权限页](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/SettingsView.Permissions.swift#L13) 等处有裸 LocalizedStringKey；[SettingsView](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/SettingsView.swift#L100) 和 [OnboardingView](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.swift#L104) 已注入 localization.locale，[LocalizationStore.select](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Support/Localization.swift#L160) 发布 locale。实际 `.app` 权限页的中英预览均能翻译这些 key；同源码裸二进制预览会显示 `settings.permissions.introduction` 等原 key。已确认的是资源查找路径不统一，而非所有裸 key 都不支持动态 locale。

**实施。** 以 LocalizationStore／LocalizationSnapshot 的资源解析为统一入口，逐页处理需要开发资源回退的 Text、Button、Label 与 accessibility 文本。可使用显式 bundle 的统一 helper 或已翻译的 String，但须保留插值、复数、格式与可访问性语义。设备名、用户输入和符号文字使用原文；不能机械替换每个 Text，也不能靠给整棵视图换 identity 来刷新语言并丢失向导状态。

**验收。** 同一个已打开窗口中切换中文→英文→系统，正文、按钮、菜单、弹窗和无障碍标签同步更新；步骤、输入、列表选择与正在编辑的快捷键保留。分别验收真实 `.app` 与裸二进制开发预览；检查 key 缺失和英文回退。广泛 High 的原结论降为 P2。

### INP-01 对 App Switcher 的 Command 释放建立恢复所有权

**证据。** [releaseCommandKey](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/KeyboardInjector.swift#L130) 清除 releaseTask 后只尝试一次 key-up，失败保留 isActive；[trigger](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/KeyboardInjector.swift#L81) 在 Command-down 成功、Tab 失败时也只有一次回滚，且尚未设 active。底层 [postMarkedKeyState](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/KeyboardInjector.Events.swift#L53) 返回的是事件构造／提交结果，不是目标应用已接收的确认；原报告关于“辅助功能 IPC 轻微阻塞”的原因未经证实。

**实验。** 使用生产 AppSwitcherSession 类型正文及可控调度器，注入 Command key-up 返回 false；触发临时切换并运行所有任务后，`isActive == true` 且自动重试任务为 0。实验不向系统发送按键，也不证明系统接收了任何事件。

**实施。** Command-down 成功即建立释放义务，覆盖正常确认、取消和 Tab 失败回滚。注入调度器，对构造／提交失败进行有界重试并维持 busy／cleanup 状态；旧 generation 不能释放新会话。达到上限需明确保留失败状态与可再次恢复入口，不能保证三次重试就“必然抬起”，也不能无限轮询。

**验收。** 失败两次后成功、持续失败、重复 trigger、旧计时回调、取消顺序、Tab 失败回滚；只释放本程序持有的修饰键，不改变物理按键状态，不产生重试风暴。实际目标系统接收和权限撤销仍需人工验收。

### INP-02 明确 Secure Input 下普通映射的动作策略

**证据。** [KeyboardInjector.send](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/KeyboardInjector.swift#L296) 的普通复制、粘贴、剪切与自定义快捷键分支没有 SecureInputMonitor 检查；[外部动作调用方](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/BridgeAppModel.ButtonActions.swift#L9) 只检查系统暂停。语音键与常用语路径已有自己的检查。这是策略不一致，不能由缺少 guard 推导出成功绕过 Secure Input 或复制出了密码。

**实施。** 建立显式动作分类，默认阻止程序新增的文本／剪贴板动作；确认自定义快捷键应整体阻止还是按明确类型限制，不能靠猜某个 keyCode 就判定安全。媒体／音量、应用切换及普通导航按产品定义决定。安全门禁必须允许已有按键的 key-up 和清理，不能在 Secure Input 打开时遗留修饰键。将状态检查注入便于测试；异步目标切换完成后、真正提交前重新检查。

**验收。** Secure Input 开／关与动作分类矩阵，延迟聚焦期间状态变化，物理按键保留，以及禁止新 key-down 仍允许释放。只用事件提交替身验证策略；在真实密码框中验收需要时使用无敏感内容的测试剪贴板，不读取或保存其他应用私有数据。

### SYS-01 统一单实例的标准身份

**证据。** [fallback 常量](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/App/ApplicationInstanceGuard.swift#L57) 为 `com.zfdang.VoiceInputBuddy`，Info.plist 为 `com.zfdang.voice-input-buddy`；[入口](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/App/VoiceInputBuddyApp.swift#L153) 在共享文件锁失败后按该 ID 查询已有进程。锁文件路径不依赖 Bundle ID，故主要缺陷是无 Bundle 的第二实例可能查不到已运行的 `.app`，不是锁失效或允许双实例。

**实施。** 对齐本项目标准 ID，增加针对实际 Info.plist 的一致性检查，保留锁和激活行为。若两个裸二进制实例没有可查询的 Bundle 身份，单独记录该限制，不能承诺只改常量便解决所有激活情况。

**验收。** `.app`→`.app`、`.app` 已运行后启动裸二进制、锁被持有但没有可激活目标、启动尚未结束、锁获取异常；第二实例不会启动硬件或形成双实例，能识别的既有窗口正确激活。

### SYS-02 为 UI 模型建立编译期并发约束

**证据。** [BridgeAppModel](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/App/Coordination/BridgeAppModel.swift#L8) 与 [AppSettings](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/AppSettings.swift#L4) 无类级 MainActor；蓝牙使用主队列，异步音频和部分服务已有回主队列的安排，LocalizationStore 已有 MainActor。不能仅凭缺少注解宣称当前已发生线程安全故障。

**实施。** 先列出所有 delegate、publisher、通知、析构及测试入口，再隔离 UI 模型与其扩展；跨隔离的音频／HID／BLE 边界传不可变快照或显式回主 actor。审查 await 前后状态变化，保留已存在的 generation 和取消保护。不能把整个音频引擎搬到主线程，不能用大面积 unchecked Sendable 或无前提 assumeIsolated 消除编译报错。

**验收。** 构建和测试通过，目标代码在完整并发检查下无新增警告；测试后台服务回调回到主 actor、析构资源释放、会话取消和重入。在线程检查与真实输入／音频压力场景下验证无行为回退。这是较高改动风险的架构任务，排在局部功能修复之后。

### BT-04 分清连接周期和连接尝试的旧回调

**证据。** [快速唤醒恢复](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L472) 在 scanning／waitingReconnect 中复用 generation；[代理回调](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L39) 携带 generation，而 [特征值入口](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1761) 只校验当前 peripheral 对象与 generation。现有 lifecycle 阶段、central 对象与 current peripheral 检查会挡掉不少旧事件；若同一 CBPeripheral 对象在新尝试中复用，不能只靠对象相等区分旧代理。尚未实际送达并观察到此类旧事件污染。

**先复现。** 保留旧代理／已排队计时回调，执行相同设备快速唤醒恢复，再分别送达旧的发现、通知、音频、写入应答和断开事件；区分旧 central、新 central、同 peripheral 对象及新对象。现有测试中只验证 monitor 自身取消不足以覆盖整条链。

**实施。** 实验成立后为每次连接尝试建立独立身份，或复用已有 fresh connection cycle 使 central 与 generation 一起更换。必须同步处理 centralGeneration、代理、连接超时、初始化超时、写队列和 keepalive。单独 `generationCounter += 1` 会让仍持旧代号的合法 central 回调也被拒绝，不采纳该简化修复。

**验收。** 旧事件不得改变新尝试 ready／streaming 状态或完成新写入；合法新事件仍可握手。保留精确 UUID 唤醒、HID 活动恢复及系统连接轮询的速度，避免引入额外完整退避。未复现则记录已覆盖边界后结案，不无条件重写连接状态机。

### BT-05 重新绑定时迁移当前连接的遥测快照

**证据。** [rebindRemote](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/BridgeAppModel.RemoteRebinding.swift#L24) 删除 replacementProfileID 的电量和电源缓存，未复制到保留的 profileID；[桥的电量／充电回调](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Devices/XiaomiBluetoothBridge.swift#L1810) 对相同值去重。显式 refresh 只重新读取，不清除去重状态；因此同值不会重新发布，保留 profile 可能没有值或仍显示旧设备值。

**实施。** 在更改 profile 所有权前取出当前连接已知的有效电量／电源快照，成功绑定后迁入保留 profile，并处理确实未知时旧值的失效。也可由桥提供显式快照重放，选一种清晰的所有权实现；避免关闭全局遥测去重或仅增加轮询。保留原 profile 的映射、增益与 HID 身份。

**验收。** 电量值相同、充电状态相同、未知值、原 profile 带旧缓存、绑定失败无副作用；重新读取相同值也不能让新卡片空白或显示旧值。验证源 profile 删除后不再拥有任何遥测 UI 状态。

### UX-04 提供可恢复的初次设置退出

**证据。** [canDismissOnboarding](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/AppSettings.Onboarding.swift#L30) 仅允许从已完成配置重返的流程 dismiss；初次权限未满足时 Continue 禁用。应用窗口可关闭，应用菜单有退出，因此不是无法退出进程。企业策略限制权限是真实无法满足的前置条件，应解释而不是绕过。

**实施。** 与 UX-02 共用“暂停设置，之后继续”的产品状态，但保持两个独立问题的提交。明确关闭窗口／退出应用后保存到哪一步、如何重开、未就绪能力如何显示；不写 completedVersion，不授予未经验证的功能。权限不可用时可阅读帮助，但不得启动受限的注入或硬件流程。

**验收。** 初次拒绝任一权限、之后恢复权限、企业限制、关闭／重开、已有完成配置返回设置等场景；暂停不丢配置，也不被误认作首次设置已完成。

### A11Y-01 验证并恢复返回按钮的可见键盘焦点

**证据。** [返回按钮](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/OnboardingView.Navigation.swift#L60) 应用 focusEffectDisabled，范围仅为该控件。需要结合 `.plain` 样式及系统键盘导航设置确认是否仍有其他足够明显的焦点状态，不能推断 Tab 已失效。

**实施与验收。** 先在全键盘导航启用状态验证 Tab／Shift-Tab 与 VoiceOver；若无可见焦点，去掉抑制或提供等效清晰样式。高对比度、深浅主题均须分辨焦点、选中和禁用状态，鼠标样式不应破坏键盘导航。

### A11Y-02 为绑定弹窗定义明确的键盘动作

**证据。** [RemoteHIDBindingPicker](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Onboarding/RemoteHIDBindingPicker.swift#L25) 和 [RemoteRebindingPicker](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Settings/RemoteRebindingPicker.swift#L29) 未声明 `.cancelAction`／`.defaultAction`。未声明不等于已经实测所有 Esc／Return 都无效，不能仅由源码宣称违反某条 HIG。

**实施与验收。** 明确绑定取消和确认快捷键；Esc 关闭且无持久化，Return 仅在有效候选且无会话冲突时确认。检查 List 获焦、没有候选、候选消失、正在录音、失败提示及 VoiceOver 的焦点顺序；不能让 Return 绕过 disabled 或触发两个动作。

### SYS-03 归档无限排空推断并保留有界退出回归

**证据。** [applicationShouldTerminate](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/App/VoiceInputBuddyApp.swift#L328) 等待 Fn cleanup，cleanup 最终无论 success 与否都会 reply true。[音频排空](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Audio/AudioOutput.swift#L1134) 有截止回调；[Fn beginDrain](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/Input/VoiceFnTapSessionController.swift#L333) 另有 `max(2, pendingPlaybackDuration + 1.5)` 的兜底；按键释放失败达到上限会完成清理回调。因此“只要底层不返回排空就无限等待”的推断不成立。

**实验。** 源码提取探针直接运行生产 Fn 控制器正文，排空回调永不应答：普通清理在虚拟时间 2,390ms 完成一次；停止时 key-up 持续失败则在 9,390ms 完成一次且结果为 false。应用的退出闭包忽略此 Bool 并回复允许退出。这验证了该状态机的有界完成，不等同于实际系统声卡故障下的整进程退出验收。

**处理与验收。** 不为此直接增加强制退出或删除清理等待。后续可用可控调度器验证：排空永不应答、正在开始／停止、key-up 持续失败、重复退出、迟到排空回调时，退出完成只触发一次。若主线程被某个同步系统调用真实卡住，记录具体阻塞栈后重新分级；主线程上的另一个计时器本身无法解决该类阻塞。

### LAY-02 只在无有效保存位置时居中

**证据。** [makeSettingsWindowController](https://github.com/zfdang/voice-input-buddy/blob/560995940ce15ee3d23bff49a58c130fcb42ada7/Sources/VoiceInputBuddy/App/VoiceInputBuddyApp.swift#L917) 在 setFrameAutosaveName 后无条件 center。显式恢复是否成功还应通过 setFrameUsingName 的返回值来区分，不能把设置 autosave 名称等同于已经正确恢复。

**实施。** 恢复保存 frame，成功则保留位置；无保存值或无有效屏幕时才使用默认位置。保留 fitSettingsWindowToScreen，让移除显示器或可用区域变小时仍可到达窗口。避免把保存的合法小尺寸强制改回默认值。

**验收。** 首次打开、移动缩放后重开、主副屏切换、负坐标屏幕、显示器移除、Dock／菜单栏可用区域变化。合法保存位置不居中，失效位置能落入可视区域。

## 后续执行批次与提交安排

实施阶段默认每个独立缺陷一个 Conventional Commit，测试与该缺陷一起提交；同一批执行复用一个 PR。调研结论不成立时直接更新核验记录，不为凑提交制造修复。任何一项在执行前发现代码已变化或已被其他 PR 修复，先更新本计划状态。

| 批次 | 顺序 | 编号 | 建议提交主题或产物 | 依赖及放行条件 |
| --- | --- | --- | --- | --- |
| A 核心功能 | 1 | BT-01 | `fix(bluetooth): align g9n9n connection admission` | 无；完整连接链测试及真实 G9N9N 验收。 |
| A 核心功能 | 2 | BT-03 | `fix(audio): preserve active decoding on late stream starts` | 不依赖 BT-02；同桥事件序列和 PCM 对比测试。 |
| A 核心功能 | 3 | BT-02 | `fix(audio): scope nibble order to peripheral configuration` | BT-03 后检查所有 reset，避免互相覆盖。 |
| A 核心功能 | 4 | INP-01 | `fix(input): recover failed app switcher key releases` | 先定义失败清理状态，测试不能依赖真实键盘注入。 |
| B 连接恢复 | 5 | BT-04 | 旧回调实验；成立时 `fix(bluetooth): isolate reconnect attempt callbacks` | 先有复现，保持唤醒延迟与准确 UUID 路由。 |
| B 连接恢复 | 6 | BT-05 | `fix(devices): preserve telemetry across remote rebinding` | BT-01 使 G9N9N 连接测试可用；两类遥控器均覆盖。 |
| B 输入与进程 | 7 | INP-02 | `fix(input): apply secure input policy to configured actions` | 明确动作分类，清理键释放不得被门禁阻断。 |
| B 输入与进程 | 8 | SYS-01 | `fix(app): align fallback instance identity` | 与实际 Info.plist 一致，保留共享锁。 |
| C 向导体验 | 9 | LAY-01 | 滚轮交互实验；成立时 `fix(onboarding): keep navigation within the viewport` | 复现不可达则提前到批次 A；先固定布局再做焦点验收。 |
| C 向导体验 | 10 | UX-01 | `fix(onboarding): explain unsupported device setup` | 不扩大适配器范围，更新既有目录策略测试。 |
| C 向导体验 | 11 | UX-02 | `fix(onboarding): provide recoverable driver checks` | 驱动验证不被绕过；定义暂停恢复语义。 |
| C 向导体验 | 12 | UX-04 | `fix(onboarding): allow resumable exit from permission setup` | 复用 UX-02 的暂停语义，独立提交。 |
| C 向导体验 | 13 | UX-03 | 维持真实语音验收；核对失败提示并归档 | 不新增跳过转写或人工输入成功路径。 |
| D 一致性与无障碍 | 14 | LOC-01 | `fix(localization): unify development resource lookup` | 覆盖上面新增文案；原地切换保留 UI 状态。 |
| D 一致性与无障碍 | 15 | A11Y-01 | 焦点实验；必要时 `fix(a11y): restore onboarding keyboard focus` | LAY-01 后复验，按实际影响决定是否改代码。 |
| D 一致性与无障碍 | 16 | A11Y-02 | `fix(a11y): add keyboard actions to binding sheets` | LOC-01 后验收两种语言；disabled 规则保留。 |
| D 一致性与无障碍 | 17 | LAY-02 | `fix(ui): restore saved settings window positions` | 保留现有屏幕裁切策略，覆盖多显示器。 |
| E 架构与回归 | 18 | SYS-02 | `refactor(concurrency): isolate ui model mutations` | 放在局部修复后，避免混淆功能与大规模隔离变更。 |
| E 架构与回归 | 19 | SYS-03 | 可选退出回归测试与结案证据 | 不按未复现假设强制退出；若出现新阻塞栈则另行分级。 |

P2 里的“调查”可提前执行，其结果决定排期；上述顺序不是要求等待低风险实验完成后才修复 P1。没有测量支持的工期暂不估算，执行前按测试替身与真实硬件可用性拆解。

## 已执行的核验与可复用命令

本次基线完整测试为 **405 项、67 个 suite，全部通过**；debug `.app` 装配通过。现有测试通过只建立回归基线，并不证明上表新发现不存在。ADPCM 源码提取探针确认 reset 保留格式及两种顺序的输出差异；AppSwitcher 探针复现释放失败后无重试，Fn 控制器探针确认排空不应答及停止键释放失败仍会有界完成。提取探针保留被测生产类型正文，只替换键盘提交、排空回调和调度；不是新增到仓库的测试，也不替代真实硬件验收。用同一基线实际 `.app` 生成中英文权限页，再用裸二进制生成英文权限页，确认资源模式的区别；未将独立进程的两次预览当作“同一窗口原地切换”的完整证明。

在仓库根目录执行：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build --disable-keychain
swift test --disable-keychain
CONFIGURATION=debug scripts/build-app.sh

VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR=/tmp/buddy-review-en \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_SECTION=permissions \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_LANGUAGE=en \
'dist/Voice Input Buddy.app/Contents/MacOS/VoiceInputBuddy'

VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR=/tmp/buddy-review-zh \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_SECTION=permissions \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_LANGUAGE=zh-Hans \
'dist/Voice Input Buddy.app/Contents/MacOS/VoiceInputBuddy'

VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR=/tmp/buddy-review-bare \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_SECTION=permissions \
VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_LANGUAGE=en \
.build/debug/VoiceInputBuddy

VOICE_INPUT_BUDDY_ONBOARDING_SCREENSHOT_DIR=/tmp/buddy-review-compact \
VOICE_INPUT_BUDDY_ONBOARDING_SCREENSHOT_SIZE=720x500 \
'dist/Voice Input Buddy.app/Contents/MacOS/VoiceInputBuddy'
```

上述截图使用隔离 fixture，不启动遥控器或音频硬件。`VOICE_INPUT_BUDDY_SCREENSHOT_SCROLL_TO_END=1` 可另测程序化滚动末端，但不能替代滚轮、触控板及 Tab 的交互测试。后续实施时应优先使用已有 ControlledTestScheduler、事件提交替身与协议纯逻辑；只对确有行为变化的边界补有意义的测试，不把扫描源码字符串当作行为验收。

## 实施阶段的统一验收边界

- 自动化验证：新增缺陷回归、相关既有测试、完整 build／test、diff 检查；涉及资源、签名或打包时再跑对应脚本。一次缺陷的测试及文档与修复同 commit。
- 真机验证：小米 RC001／RC003 与可用的 G9N9N 分别验收首次连接、断开重连、休眠唤醒、按下／松开、短句句首和句尾、虚拟麦克风路由与实际输入工具。ARN9 缺机则记录未验收，不以生成音频替代真机。
- UI 验证：1280×800 和 1366×768 所对应的实际 visibleFrame、小窗口、多屏、双语原地切换、全键盘导航、VoiceOver、高对比度和深浅主题。暗黑常用语指示盘在原报告没有具体缺陷与复现，暂列此验收项目，不另造已确认问题。
- 产品约束：保留真实权限、驱动、语音转写及完成更新检测；不把“稍后设置”标成设置成功。保留输入清理和原有映射／增益；不增加遥测、转写历史或音频落盘。
- 发布约束：不改变 main 自动发布、项目 Sparkle 签名、生产固定自签名证书及本地 ad-hoc 默认值，不改证书信任；安装包仍未签名、未公证，GPL 和第三方通知继续保留。

报告中的“锁绝不死锁”“绝无音频落盘”“零遥测”“完全合规”等总体正面评价不等于本次完成了新的安全或许可证审计，不能由 19 项核验推导为全工程保证。

## 执行状态

当前均为计划状态，文档审核通过也不代表已开始修复。

- [ ] BT-01 完成准入修复和验收。
- [ ] BT-02 完成设备格式边界修复和验收。
- [ ] BT-03 完成重复开始的音频状态保护和验收。
- [ ] UX-01 完成计划设备说明与继续状态统一。
- [ ] UX-02 完成驱动失败恢复体验，保留验证。
- [ ] UX-03 确认维持验证要求，记录必要文案回归后结案。
- [ ] LAY-01 完成实际滚动复现，按证据修复或结案。
- [ ] LOC-01 完成资源入口统一与原地语言切换回归。
- [ ] INP-01 完成修饰键清理恢复和验收。
- [ ] INP-02 完成 Secure Input 动作策略与验收。
- [ ] SYS-01 完成进程身份一致性修复和验收。
- [ ] SYS-02 完成 UI 模型并发隔离及边界回归。
- [ ] BT-04 完成旧回调实验，按证据修复或结案。
- [ ] BT-05 完成重新绑定遥测迁移和验收。
- [ ] UX-04 完成初次设置暂停恢复体验。
- [ ] A11Y-01 完成返回按钮焦点验收，按证据修复或结案。
- [ ] A11Y-02 完成两种绑定弹窗键盘动作验收。
- [ ] SYS-03 记录有界退出回归证据，出现真实阻塞则重开。
- [ ] LAY-02 完成窗口位置恢复和屏幕变更验收。
