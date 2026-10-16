# 产品范围和架构

Voice Input Buddy 是硬件到语音输入工具的桥接应用，首先实现 macOS，随后适配 Windows。它本身不是 IME，也不在本次移植中实现语音识别模型。

```text
遥控器按下 / 松开 → 蓝牙或 HID → 语音会话 → 目标工具的快捷键
遥控器麦克风 → ATVV → ADPCM 解码 → PCM → 虚拟麦克风 → IME / 听写工具
```

保留设备状态管理、音频路由、权限、首次设置向导和按键映射主体。语音键不等待普通按键的长按阈值；会话在输入法激活及快捷键提交成功后开始，激活期间暂存音频，提前松开或失败则取消。输入工具可配置按住或点按开始／结束行为。普通按键按映射配置操作，目标工具通过向导配置并实际验证。

音频固定送往 Voice Input Buddy Mic（UID `BuddyMic2ch_UID`），不提供输出设备选择或其他设备回退，也不修改 macOS 默认输入、输出设备。每台遥控器分别保存增益和按键映射。当前连接入口为小米 RC001／RC003 和 G9N9N；适配器实现与真机验收状态见 [README](../README.md#支持哪些设备)。

不纳入统计、回眸、音频归档、MCP 历史访问或统计上传。退休的适配器与空实现已移除；计划设备只保留目录展示。iOS、Watch 和 Web 产品不属于本项目范围。

此前反馈中的实时预览、识别尾部延迟和语义整理涉及识别引擎。如果将来增加自有识别后端，应分开测量识别、整理和交付阶段；桥接第三方软件时无法保证这些体验。专用 USB / 蓝牙按钮和脚踏设备可作为后续触发源，不应将其标为当前已验证设备。

Windows 尚未迁入源码，不具备可发布能力。后续需要独立实现系统权限、BLE、音频回环与键盘注入，并进行真实设备测试。

### Runtime ownership

`BridgeAppModel` publishes UI state and coordinates input, connections and audio.
Its main-queue runtime state has three explicit owners:

- `BluetoothConnectionRegistry` owns configured/discovery bridges and their ready states; `stopAll()` stops and removes the whole connection set.
- `VoiceSessionRuntime` owns the active voice device, pending start, command pre-roll and diagnostics; `end()` clears device ownership and buffered work together.
- `AudioRuntime` owns the output, preparation queue, generation tokens, recovery task and HAL registrations. Shutdown invalidates every audio completion token; destruction cancels recovery and removes the exact registered listener block synchronously.

Engine operations and HAL callbacks retain their dedicated queues. Their callbacks
return to the main queue before mutating application state. The UI model does not
own HAL registrations or perform asynchronous teardown from its destructor.
