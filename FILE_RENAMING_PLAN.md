# 文件与职责命名整理计划

日期：2026-10-18（Asia/Singapore）。基线：`0e0a0e681fe53a2c3da4aa15c12694e9aefc98c5`。

状态：**已完成 N-01～N-08 直接重命名与 S-01～S-05 结构职责拆分**。配套缺陷核验见 [REVIEW_FIX_PLAN.md](REVIEW_FIX_PLAN.md)。

## 1. 检查范围与命名准则

检查了 Sources、Tests、scripts、docs 的文件目录和主要声明，重点追踪品牌名称、协议型号、过时职责名及同一文件中混合的功能。下面将“名称确实误导”和“名称不算错误但值得拆分”分开处理，不为整齐而批量改名。

- 多品牌共用的连接、型号、设备和能力类型使用中性名称。
- 型号专用协议保留型号名称；改名不能代替新设备支持。
- 文件尽量对应一个主要类型或明确的职责组；跨域混合时先拆分，再给文件命名。
- 改 Swift 类型和源文件，不顺手更改用户数据 raw value、驱动 UID、bundle ID、协议 UUID、更新 URL、快捷键值或本地化 key。
- 当前开发阶段不保留旧类名 typealias、空壳转发类或退役接口。真正活跃的系统版本兼容、语音会话恢复、更新识别等行为必须保留。
- 命名提交与行为修复提交分开。此前有意取消的独立源码包发布行为不在本计划中调整。

下文路径省略 `Sources/VoiceInputBuddy/`，测试路径另注明。建议名字以避免歧义为目标，实施时应先检查同名冲突。

## 2. 已确认值得直接整理的项目

| 编号 | 当前文件/符号 | 实际职责与证据 | 建议目标 | 同步范围 |
| --- | --- | --- | --- | --- |
| N-01 | `Devices/XiaomiBluetoothBridge.swift`、`XiaomiBluetoothBridge` | 同时处理小米和 Google G9N9N：BLE 发现、连接、DIS、电量、ATVV 控制与语音接收。`:707` 有 Google 发现路径，`:1858` 有 Google 型号确认。已超出“小米桥”。 | `Devices/BluetoothRemoteBridge.swift`、`BluetoothRemoteBridge` | 同步 delegate 为 `BluetoothRemoteBridgeDelegate`，私有代理为 `BluetoothRemotePeripheralDelegateProxy`；registry、model 扩展、voice session runtime、测试和当前架构文档引用同步。已有通用 `BluetoothBridgeState` 不必为改而改。 |
| N-02 | `Devices/RemoteDeviceProfile.swift` 内 `XiaomiRemoteModel` | 枚举除了 rc001/rc003，还含 Apple A2854/A2540、Chromecast 和 unknown，是整个产品的型号类型。 | 提取 `Devices/RemoteModel.swift`，类型名 `RemoteModel` | profile、设置、导入导出、onboarding、图示布局、HID/蓝牙、诊断与测试。原文件继续保留 `RemoteDeviceProfile`、档案及映射模型。只改 Swift 类型名，保持已在使用的 raw values。 |
| N-03 | `Audio/DoubaoAudioDevice.swift`、`DoubaoAudioDevicePolicy` | 返回固定 BuddyMic UID/name，供所有输入工具、设置、向导、诊断和音频准备使用，没有豆包专用逻辑。`AppSettings.selectedAudioDeviceUID` 也引用它。 | `Audio/BuddyMicrophoneDevice.swift`、`BuddyMicrophoneDevicePolicy` | 所有 UID/status 引用；`doubaoAudioStatus` 若仍有消费者，改为 `buddyMicrophoneStatus`。若最终确认只是无人消费的发布状态则单独删除，不靠改名保留死代码。`BuddyMic2ch_UID` 与显示名称保持不变。 |
| N-04 | `Devices/PlannedRemoteDevice.swift`、`PlannedRemoteDevice` | 包含已支持设备和暂不能完成设置的设备，是向导的产品选项，不只代表未来计划。文件开头也明确产品范围与适配就绪是两回事。 | `Devices/RemoteSetupDevice.swift`、`RemoteSetupDevice` | 设备选择、onboarding settings、截图 fixture、测试。保留现有 case raw values 与 `remote.catalog.*` key；选择和 Continue 校验不变。 |
| N-05 | `App/Coordination/BridgeConnectionTypes.swift` | 当前文件只定义 `VoiceKeyCompatibilityWarning`，内容是 Karabiner/输入工具影响语音键的警告，不是连接类型集合。 | `Input/VoiceKeyCompatibilityWarning.swift`，类型名保持 | 仅文件移动及文档路径，现有类型引用无需改名；同时去掉移动后确实不需要的 import。 |
| N-06 | `Input/RemoteVoiceFunctionMapper.swift` 与相关 policy/service | 实际写 IOHID usage mapping：语音键 Fn 映射或置空，也处理电源键到 F20 的系统休眠抑制及原映射恢复。不是仅做 Voice→Function。 | `Input/RemoteHIDKeyMapper.swift`、`RemoteHIDKeyMapper`；policy 改 `RemoteHIDKeyMappingPolicy`，service 改 `RemoteHIDMappingService` | model 的映射对象、HID 应用/清理路径、恢复测试。检查每键所有权与恢复语义，不改映射值或扩大接管范围。 |
| N-07 | `Input/VoiceFunctionKeyLatch.swift`、`VoiceFunctionKeyLatch`、`VoiceFunctionKeyTransition` | latch 管理多 owner 的语音键持有状态；`Audio/BridgeAppModel.VoiceDelivery.swift:154` 按 `VoiceKeyMode` 发 Fn、Command 或 Option，不限 Function key。 | `Input/VoiceKeyLatch.swift`、`VoiceKeyLatch`、`VoiceKeyTransition` | voice delivery、pending activation/release、ownership tests。保持最后 owner 释放、失败 rollback 和重试语义。 |
| N-08 | `Tests/VoiceInputBuddyTests/RebindingTelemetryTests.swift`、`transferRemoteTelemetry()` | 内容是更换设备档案时转移电池电量和供电状态，不采集使用统计。“telemetry”容易被理解为产品遥测。 | `RemoteRebindingDeviceStatusTests.swift`、`RemoteRebindingDeviceStatusTests`；方法 `transferRemoteDeviceStatus()` | `Devices/BridgeAppModel.RemoteRebinding.swift`、测试 suite 标题与 fixture 前缀。保持状态去重、未知值失效和档案所有权行为。 |

N-01、N-02、N-03 是首批优先项。其余直接整理可随后进行，避免所有大范围符号替换和功能修复挤在同一提交。

## 3. 应拆分职责，不宜只给整个文件换个名字

### S-01：`Devices/ChromecastTypes.swift`

- `ChromecastDeclaredCapabilities:29` 的注释和消费端 `Integrations/VoiceInputCapabilityMatrix.swift` 表明它是多适配器共用的能力词汇，包含 touch surface 等能力。
- 提取为 `Devices/RemoteDeclaredCapabilities.swift`，类型 `RemoteDeclaredCapabilities`，保留 OptionSet 位值。
- `ChromecastVoiceMode` 的当前使用确实限定在 Chromecast 设置/向导；`ChromecastRemoteControl` 定义该遥控器的物理按键，名称仍准确。不把它们机械改成通用类型。
- 可分别放入 `ChromecastVoiceMode.swift` 与 `ChromecastRemoteControl.swift`；如果暂不拆完，原文件仍保留 Chromecast 专用声明。

### S-02：`Audio/AudioOutput.swift`

文件有约 1600 行，核心类是 `VirtualAudioOutput:613`，同时还包含 CoreAudio 枚举、设备电平数据、健康/恢复策略和播放队列容量。`AudioOutput` 太笼统，但直接更名仍未解决查找职责的问题。

建议分步提取：

1. `Audio/VirtualAudioOutput.swift`：播放引擎、排队、drain、输出状态，保留类名。
2. `Audio/CoreAudioDeviceCatalog.swift`：`AudioDeviceInfo` 和 `CoreAudioDeviceCatalog`，设备枚举及 HAL 属性读取。
3. `Audio/VirtualAudioDeviceLevels.swift`：电平 observation/snapshot/repair result/policy；修复算法本身继续放现有 `VirtualAudioAudibilityRepair.swift`，不重复。
4. `Audio/VirtualAudioPolicies.swift`：健康、恢复、配置变化的纯策略；系统挂起类型并入现有 `SystemAudioLifecycle.swift` 时再检查依赖。
5. `Audio/VoicePlaybackQueueCapacity.swift`：队列容量预算。PCMNormalization/安全封装依据实际调用单独归位，不强求一类型一文件。

提取前检查 file-private/private 的可见性变化；不为拆分把内部实现无差别暴露。保留 engineQueue、playbackLock、异常保护和所有 drain 生命周期语义。可在 AUD-01 行为修复前后独立完成，不能在同一提交混淆修改。

### S-03：`Devices/RemoteButtons.swift`

文件除了物理按键和 HID report，还定义 `CustomKeyboardShortcut`、`ConfiguredButtonAction`、应用启动/聚焦配置、preset application 和 action 分类，名称不足以说明这些跨域内容。

建议保留 `RemoteButtons.swift` 的 `RemoteButton` 与对应原生事件；依职责提取：

- `Input/CustomKeyboardShortcut.swift`：键盘快捷键值及修饰符表示。
- `Input/ConfiguredButtonAction.swift`：触发种类、配置动作和 action 分类，必要时再拆具体 ButtonAction。
- `Input/ApplicationActionProfile.swift`：自定义应用、聚焦策略和 AX 目标描述。
- `Devices/RemoteHIDReportParser.swift`：report parser；权限门禁归入现有 HID 权限模块或独立 `HIDPermissionGate.swift`。

这是职责归位，不改快捷键编码、动作 raw values、导入校验和每键的单击/双击/长按行为。

### S-04：`Onboarding/OnboardingFlow.swift`

文件同时含 step/purpose、输入工具定义、工具绑定模型与 adapter profile、能力快照、恢复/验证策略和 AI 帮助文案。文件名未完全错误，但“Flow”不能帮助定位已被常规设置使用的工具模型。

建议保留实际 `OnboardingFlowPolicy` 与流程类型；提取共用的 `VoiceToolUserBinding`、`VoiceToolAdapterProfile`、状态枚举到 `Integrations/VoiceToolBindings.swift` 和 `Integrations/VoiceToolAdapterProfile.swift`。向导专用提示文案放 `OnboardingPrompts.swift`。步骤与 purpose 可放 `OnboardingSteps.swift`，其余向导验证策略按现有职责集中。

先厘清共同持久化模型与纯向导数据；不用此次整理改变初次安装、添加设备、输入工具重配或真实转写验证。

### S-05：`Diagnostics/FirstUseDiagnostics.swift` 与 `Audio/VoiceAudioDiagnostics.swift`

- `FirstUseDiagnostics.swift` 的前半包含虚拟音频播放 counters、输出快照和 delivery policy，它们不只用于首次使用；后半的 FirstUseFailureReason 和向导诊断仍符合原名。
- 将通用音频诊断类型提取为 `Diagnostics/VoiceAudioDeliveryDiagnostics.swift`，保留真正 first-use 的部分。
- `VoiceAudioDiagnostics.swift` 当前还包含 `CommandVoiceActivationAudioBuffer`（预滚/等待缓存）和 `AudioRecoveryCoalescingState`（恢复事件合并），这两者不是诊断。分别移到 `Audio/CommandVoiceActivationAudioBuffer.swift` 与恢复策略模块；剩余蓝牙尾音指标可命名 `BluetoothVoiceTailDiagnostics.swift`。
- 保持仅内存音频处理和本地诊断，不新增音频档案、转写历史或统计上报。

这五项都是第二阶段的可选结构整理，不阻塞明确缺陷修复。

## 4. 保留原名及条件性改名

| 文件/符号 | 结论 |
| --- | --- |
| `Devices/G9N9NProtocol.swift`、`G9N9NReadiness`、`G9N9NMappingLayout` | 当前只验证 G9N9N，名称准确，保留。完成 GY3LE 事实核验后才可提取真正共用的 Google 协议/布局层；型号专用事实仍保留在各自模块。 |
| `XiaomiVoiceRemoteNameMatcher`、`RemoteHIDIdentity.xiaomi`、RC001/RC003、`XiaomiHIDBindingTests.swift` | 明确表示小米名称/VID/PID/硬件事实和测试范围，保留，不全库替换 Xiaomi 字样。 |
| `VoiceRemoteCatalog` | 当前 entries 只含 rc001/rc003，Google 识别在另一个模块。名称有“全产品统一目录”的暗示，注释也过度承诺唯一事实源。随 N-02 提取为 `Devices/XiaomiRemoteCatalog.swift` / `XiaomiRemoteCatalog`，明确其当前小米验证范围；若后续设备适配真正统一目录，则采用通用目录名，不能并存两个声称权威的目录。 |
| `usesPrivateAdapter` | 当前实现仅返回 `isAppleSiriRemote`，私有适配包已不存在，命名会误导。逐个核验调用门禁后使用现有 `isAppleSiriRemote` 表达实际型号排除；若语义是可处理性则引入准确的能力策略。不要重建退役私有适配接口。 |
| `ChromecastVoiceMode` | 当前属性、snapshot、向导配对计划都限定 Chromecast；保留品牌范围及持久化 key，除非将来职责确实扩展。 |
| `VoiceFnTapSessionController.swift`、`BluetoothPendingAudioStart.swift` | 前者确实转换 Fn 点按，后者确实管理待开始音频状态，名称准确，保留。 |
| `SettingsCompatibilityViews.swift` | 主要是 macOS 26 glass 与旧系统样式的活跃适配，不是旧数据兼容层，保留。这与删除废弃 API 的要求不冲突。 |
| `MobileRemoteButtonObservation` | 本次检索只找到声明，没有找到消费者；不把无人使用的类型改名后继续保留。后续代码清理时核对后删除，单独提交。 |
| `scripts/build-driver.sh`、`build-release-sources.sh`、`generate-website-screenshots.py` | 名称与行为相符，保留。是否启用脚本、使用正式应用截图还是 fixture，是运行方式和产品流程问题，不靠改文件名解决。 |

与上述文件相关的旧注释已同步核对并更新：`BluetoothLifecycle.swift` 移除“私有 Chromecast 适配包/宿主 Xiaomi 桥”及不存在的类型引用；`AppSettings.swift` 移除已删除设置的孤立注释；`RemoteButtons.swift` 澄清 Chromecast 专属按键在专属 HID 报告中读取；`ChromecastRemoteControl.swift` 移除未定义的画布类型引用；`VoiceKeyLatch` 明确蓝牙与 Chromecast 语音键通道。不再指向不存在的外部包或类型。

## 5. 实施顺序、依赖和验证

1. **建立引用清单**：对每个旧类型/文件名搜索生产、测试、脚本、CI、资源说明和当前文档；记录 Codable raw values、UserDefaults key、反射类型名是否参与存储。检查所有修改是否纯命名。
2. **首批中性化**：先 N-01、N-02、N-03。每项独立提交；N-02 同时澄清当前小米专用 catalog。对目录统一和 GY3LE 支持另作行为设计，不夹带到改名。
3. **其余直接改名**：N-04～N-08。使用文件移动保持历史可追溯，类型引用同步，不保留旧名 alias。`usesPrivateAdapter` 的替换先逐个核验实际条件。
4. **后续职责拆分**：S-01～S-05 仅在相关功能验证稳定时实施，避免多个大文件同时移动。首批改名不是实施所有拆分的前置授权。
5. **静态核验**：确认没有意外修改资源 key、驱动 UID、bundle ID、签名配置、协议数据和导出字段。旧符号在活跃代码中清零；专用小米符号和历史审查记录允许保留。
6. **功能验证**：运行 `swift build --disable-keychain`、`swift test --disable-keychain`；涉及源码路径的 Python 测试运行对应脚本。比较配置导入导出、向导选择、连接注册/释放、每键映射和音频路由的行为。
7. **界面和硬件验收**：中英文设置与向导截图不应因纯命名变化而改变；遥控器按键、语音、断连/睡眠恢复及停止清理仍需真实设备验收，不能用编译通过代替。
8. **交付**：命名提交与缺陷提交分离，更新当前架构/模块文档；不更改发布产物名字，不触发品牌支持文案的重新定义。保持人类合并 PR 的工作流程。

验收标准：代码搜索能按职责找到入口，通用类型不再误带单一品牌，真正型号专用模块继续清晰可辨；用户可见行为和持久化值在纯改名阶段保持一致。
