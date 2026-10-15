# 运行时边界问题二次核验

核验基线：`0113871`（main）。编号对应提交的问题清单。每个已修复的独立问题使用一个 commit；第 13 项涉及两个独立资源所有者，分别提交。所有改动在同一个 PR。

| 编号 | 结论 | 代码证据与处理 |
| --- | --- | --- |
| 1 | 成立，已修复 | `AudioOutput.swift` 原先在 Obj-C 保护外执行 connect、prepare、start。新增 `AudioEngineSafety.perform` 同时处理 NSException 与 Swift Error；失败后的 engine stop 也有异常边界。测试实际抛出 NSException 和 Swift Error，验证两者均被转换为可处理失败。 |
| 2 | 不成立 | Apple SDK 的 `AXUIElement.h` 对 `AXUIElementSetMessagingTimeout` 明确说明：传入 system-wide 对象会设置本进程全局默认值，传入其他对象才只影响该实例。当前 `AccessibilityMessaging.prepareQueries()` 的一次性设置符合这个规则，无需给所有 application element 再设置一次。API 失败已有日志。不能据此推导真实查询仍使用 6 秒默认值。 |
| 3 | 同步 AX 查询成立，已修复 | `KeyboardInjector.Events.frontmostWindowFrame()` 原先先查询 focused window，再回退 WindowServer。滚轮路径改为直接使用 `CGWindowListCopyWindowInfo`，不向前台 App 发送 AX IPC。测试验证前台进程普通窗口筛选和鼠标位置回退。第 2 项的“固定阻塞 6 秒”推导不成立，WindowServer 调用本身也不承诺固定毫秒耗时。 |
| 4 | 成立，已修复 | `VirtualAudioOutput.enqueue` 原先只累计 pending 样本，没有容量门限。现按 mono 16 kHz 的 8,000 样本限制排队长度，包括尚未在 engine queue 上执行的任务；在同一 playbackLock 下检查并记账。满队列拒绝新批次，返回 false 并沿用现有拒绝日志与调用方失败计数；不停止引擎。超大批次同样拒绝。播放完成、flush、stop 仍沿用原有扣减与 generation 机制。容量测试覆盖边界、溢出和重新获得空间。过载时会丢弃音频，这是一项明确的有界延迟取舍，并非时钟重采样方案。 |
| 5 | 部分成立，已修复确定的清理缺口 | `releaseVoiceKeyIfNeeded` 原先在释放失败时保留 latch，但不安排重试。现每秒最多安排一个自动重试，直到释放成功；generation 阻止旧回调释放后续会话，新按下会等待遗留清理。测试模拟两次失败后成功，无需新的遥控器事件即可解除 latch，并检查过期回调。BLE 断连通知到达前的监督延迟仍由系统/设备决定；未加入会截断合法长录音的固定最长按压限制。另一个 ordered-Fn 通道原先已有独立释放重试，不能笼统说所有 Fn 路径都无恢复。 |
| 6 | 成立，已修复睡眠清理缺口 | `handleSystemAudioLifecycle` 原先对所有 suspend 事件都允许活动语音推迟释放。现在 systemWillSleep 在 startup-pending 判断前终止活动会话、取消待启动/重启、释放键并停止输出；使旧音频配置回调失效。睡眠中的 startup 枚举完成也不配置引擎。仅熄屏仍允许活动录音继续。测试覆盖启动期间睡眠、活动会话清理、排队缓冲清理，以及仅熄屏时保留会话。是否出现特定 HAL“僵尸化”还需要实机复现，不能仅凭分支断言。 |
| 7 | 未证实内存缺陷，未修改 | `accessibilityTextCandidates` 已由 `AccessibilityTraversalBudget` 同时限制 5,000 节点和 1 秒耗时；CF Copy 返回值受 Swift ARC 管理。visitedElements、stack、candidates 中保留的对象不会因为加入 autoreleasepool 就提前释放。现无分配曲线或泄漏证据支持“数百 MB”和“重试风暴”的结论，不为未证实的性能推测增加循环包装。若出现实测峰值，再依据 Instruments 分配轨迹处理。 |
| 8 | 成立，已修复 | filter 原先直到最终 stop 才清除 isRunning。现在收到 disabled 通知立即清除可用状态；实际 isRunning 还检查 tapIsEnabled，重启期间不创建第二个端口，只有恢复启用成功后才重新可用。HIDRemoteMonitor 原有动态 mappingDeliveryIsSafe 检查因此会暂停自定义注入。现有 filter 丢失、重复/长按、权限撤销和延迟恢复测试通过。 |
| 9 | root 执行的说法不成立，签名检查已补齐 | `uninstall-user.sh` 在任何准备步骤之前拒绝 uid 0；系统卸载脚本与用户准备分开。此前确实只核对 bundle ID，现额外运行 codesign --verify --deep --strict；签名损坏时跳过执行并继续卸载。测试在临时 app 上使用真实 ad-hoc 签名，篡改可执行文件后确认跳过。此检查验证完整性，不代表 Apple 公证或开发者身份信任，也不抵御攻击者替换后重新签名的所有情况。 |
| 10 | 成立，已修复 | cleanup helper 缺少参数契约；虽然调用方有 set -u，空字符串仍可能进入。现在要求存在的绝对目录，拒绝 home 本身为符号链接；物理路径规范化后再拒绝根目录（含 /// 等拼写）。测试覆盖空、相对、根、缺失和符号链接路径，并保留仅删除产品文件的测试。 |
| 11 | 成立，已修复 | preinstall 的 bundle 检查在旧 Info.plist 缺失/损坏时失败。新增仅供安装的检查，允许固定安装目的目录的损坏元数据被修复；可读且属于其他产品的 bundle、符号链接和普通文件继续拒绝。卸载删除仍要求肯定的 bundle ID，不放宽删除验证。测试覆盖损坏修复、外来产品拒绝和符号链接拒绝。 |
| 12 | 缺少标注属实，但未确认运行时 bug，未修改 | 三个类型目前没有 @MainActor，项目使用现有主队列派发约定；ObservableObject 本身并不要求 actor 标注。仅缺少标注不能证明已有数据竞态，也不能证明所有方法都适合整体隔离。Swift 6 严格并发迁移需要同时检查协议代理、后台查询、同步存储 API 和调用方，不在本次修复中用三个宏替代完整迁移。 |
| 13 | 资源释放兜底缺口成立，分别修复 | XiaomiBluetoothBridge 析构时现在取消工作项/watchdog、撤销 shared scanner 订阅、解除 delegate 并取消外设连接。取消订阅在主线程执行，异步路径只捕获 token。SiriRemoteCursorFeedbackController 析构时取消隐藏任务并隐藏 panel；非主线程析构只把 panel 交给主队列，不捕获正在析构的 self。未直接调用会发送状态回调或异步 weak-self 清理的 stop。 |

## 验证边界

- `swift build --disable-keychain` 成功。
- `swift test --disable-keychain`：349 项测试通过，涵盖 50 个 suite。
- 安装测试仅操作临时 bundle/目录，签名用临时 ad-hoc fixture；daemon 命令被替身替换，不卸载或重启真实音频服务。
- 软件测试不能替代真实蓝牙断电、长时间录音漂移、系统合盖/唤醒和目标 App 卡顿的硬件验收。
