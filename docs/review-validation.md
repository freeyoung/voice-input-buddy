# 输入与运行时审查核验

核验范围为 C-02、C-03、H-01 至 H-12、M-01 至 M-14、L-01 至 L-08，共 36 项。原始代码基线为 `999e17e`。结论区分源码事实、可复现的行为和需要真机确认的推测；原始严重级别不代表已经复现故障。H-08 按维护者要求保留，不调整版本规则。

## 覆盖率实测

使用完整 Xcode，在隔离目录从基线源码执行 `swift test --disable-keychain --enable-code-coverage`，原有 319 项测试通过。SwiftPM 的 LLVM 行覆盖率为：

| 文件 | 基线行覆盖率 | 本次测试后的行覆盖率 |
| --- | ---: | ---: |
| RemoteButtonGestureRecognizer.swift | 37.1% | 100% |
| AudioOutput.swift | 38.7% | 42.6% |
| AppLogger.swift | 84.7% | 84.1% |
| 新提取的 VirtualAudioAudibilityRepair.swift | 不适用 | 100% |

基线的手势覆盖来自集成测试，因此“没有专门的单元测试”成立，“零测试覆盖”不成立。`AudioOutput` 的“<5%”同样不成立。本次提取了部分逻辑，不宜将修改前后的文件覆盖率差值直接解释为测试质量提升。上述数字来自本地测试运行，不代表 HAL、遥控器或第三方输入工具已通过真机验收。

## 关键与高优先级发现

| 编号 | 准确性 | 证据与处理 |
| --- | --- | --- |
| C-02 | 部分成立，已补测 | 基线没有 `RemoteButtonGestureRecognizerTests.swift`，但有 37.1% 间接覆盖。新增专门测试，使用统一的 `ControlledTestScheduler` 验证 300ms 双击窗口、550ms 长按阈值、单击、双击、第二次按下的长按、重复按下、取消、重置和多按钮隔离。还修复了重复长按超时可重复触发动作的问题。 |
| C-03 | 策略分歧成立，已修复 | `OnboardingView.Readiness` 曾直接以 `onboardingDevice != nil` 覆盖策略结果。现在由 `OnboardingFlowPolicy.canContinue(selectedDevice:)` 统一判断，测试逐一比较所有设备的策略与 UI。原报告对诊断的描述过强：基线 `FirstUseDiagnosticContext.failureReason` 在设备选择页本来就返回 nil。计划设备仍可点击 Continue 查看提示，但不会通过未开放适配器的连接步骤。 |
| H-01 | 接口风险成立，当前后台回调场景不成立，已移除实现 | 三个类确实使用 `@unchecked Sendable` 并公开可变闭包；实际方法只是返回 unavailable 的占位实现，没有外设后台回调。移除三个传输类、无效授权类型、实例与回调接线，保留活跃设备和音频路径。 |
| H-02 | 不成立，原有保护有效 | `VoiceInputDestinationCoordinator` 在转换前已经检查 `CFGetTypeID(value) == AXUIElementGetTypeID()`。不重复添加同一检查。 |
| H-03 | 每条记录的额外 I/O 成立，已优化 | 基线日志本来就在后台串行队列写入，但每条记录仍重新打开目录锁、查询文件大小并重新打开日志。改为持有会话文件描述符并累计实际写入字节数，只在创建、轮转和清理归档时获取目录锁。保留文件大小上限、私有权限、符号链接保护和活动会话锁。原报告所称每秒调用量没有性能采样支持。 |
| H-04 | 缺少 flags 的推断不成立，应用丢事件待真机确认 | `ShortcutEventSequence.emit` 已对每个事件设置 `event.flags = synthetic.union(hardwareFlags())`，现有测试覆盖组合修饰键、物理按键保留和失败释放。没有以未经复现的 Electron 行为为由加入固定阻塞延迟。 |
| H-05 | 不成立，返回值由 ARC 持有 | 查找结果是受 Swift 管理的 `TISInputSource`，而非裸指针或 Unmanaged。用相同查找与桥接逻辑检查优化后的 SIL，函数签名返回 `@owned Optional<TISInputSource>`，数组迭代对象的所有权被管理。数组离开作用域不使返回值悬空；额外手动 retain 会泄漏。 |
| H-06 | onCapture 问题成立，已修复 | Monitor 原来捕获初始化时的 onCapture，更新 Coordinator 不会更新该副本。共享组件现在使用弱引用转发至当前回调，测试验证更新回调与 Coordinator 释放。onFailure 原来就通过 weak self 查询当前值，并不存在相同的旧闭包问题。 |
| H-07 | 重复成立，已合并 | 两份 NSViewRepresentable 结构近乎相同，但捕获写法略有差别，不能称为逐字 100% 相同。统一到 `Input/ShortcutCaptureView.swift`，删除向导副本。 |
| H-08 | 成立，按要求保留 | `release-metadata.sh` 确实拒绝超过 999 次提交；appcast、release notes 和版本解析也有三位数约束。本次不修改任何版本格式或断言。 |
| H-09 | 覆盖率和模块描述不准确，已加强真实逻辑测试 | 基线 AudioOutput 行覆盖率为 38.7%。当前使用 AVAudioEngine/AVAudioPlayerNode，不含报告所称的自实现环形缓冲区；ADPCM 解码及 PCM 后处理在设备协议模块，原有 ATVV/G9N9N 测试已覆盖。新增设备级音频写入边界、静音/音量阈值、双 scope 修复、写入失败和实际读回验证。设备输出与系统采样率转换仍需真机验收。 |
| H-10 | 固定等待事实成立，已替换 | 两个文件中的固定 Task.sleep 已移除。排队任务使用可控的 DispatchWorkItem 执行入口，drain 截止时间注入虚拟调度器；同步析构直接验证释放。没有以更长的 sleep 掩盖调度问题。 |
| H-11 | 成立，已统一 | RecoveryScheduler、LifecycleClock、OperationScheduler 和原 ControlledTestScheduler 的独立实现合并。共享替身支持到期步进、下一任务、周期任务、取消和强制送达失效回调，保留原有生命周期回归场景。 |
| H-12 | 源码扫描事实成立，已替换并强化边界 | 删除运行时正则扫描。所有设备静音/音量写入改经 `CoreAudioDevicePropertyWriter`，拒绝 system/unknown 对象及非静音/音量 selector；注入 writer 的行为测试确认拒绝发生在 HAL 调用之前。 |

## 中优先级发现

| 编号 | 准确性 | 证据与处理 |
| --- | --- | --- |
| M-01 | 成立，已解耦 | UpdateInformationStore 原来依赖 VoiceFnTapSessionController.Scheduler。将取消任务和调度函数类型提取到 `Support/ScheduledOperation.swift`，更新、输入目标及语音状态机共用独立类型。 |
| M-02 | 维护性问题成立，已按职责拆分文件 | 基线 KeyboardInjector 超过 2100 行。保留编排入口，将辅助功能查找/聚焦和事件合成分别提取至 `KeyboardInjector.Accessibility.swift`、`KeyboardInjector.Events.swift`。保留现有类型接口，跨文件使用的辅助函数才扩为 internal；没有以重构为由替换已验证行为。 |
| M-03 | 编译选项缺口成立，泄漏未复现，已加固 | Objective-C 异常边界原来未显式启用 ARC 异常清理。为单独的 AudioExceptionGuard target 添加 `-fobjc-arc` 与 `-fobjc-arc-exceptions`。已有测试验证 NSException 转为失败结果；不能据此声称已复现原报告假设的内存泄漏。 |
| M-04 | 防御性缺口，已加固 | sysctl 缓冲区原来只有查询长度。新增一字节的预置零终止空间，避免 C-string 初始化依赖提供方返回终止符。没有复现 macOS 的 kern.bootsessionuuid 返回未终止字符串。 |
| M-05 | 语法事实成立，性能结论未证实，保留有界下载 | 当前上限为 1 MiB，并非报告中的 262K。AsyncBytes 的逐字节迭代不等于每个字节一次任务调度；现有 URLProtocol 测试验证恰好上限、超大响应头、超大响应体和 HTTP 错误。直接改为 data(for:) 再检查大小会失去接收过程的大小限制，因此保留当前实现。 |
| M-06 | 隔离缺口成立，已修复 | LocalizationStore 及 UI 文本辅助函数现在由 @MainActor 隔离，系统 locale 通知显式切回主 actor。非 UI 查询使用不可变 LocalizationSnapshot；回归测试验证旧快照不会随 UI 语言切换而变化。原报告没有提供实际并发写入的复现。 |
| M-07 | 不成立 | Swift 6.2 于 2025-09-15 正式发布，核验时不是预发布工具链。项目和 CI 使用 6.2，保留 tools version，不为错误前提降级。 |
| M-08 | 私有 SPI 判断不成立 | 所用 IOHIDEventSystemClientCreateSimpleClient、CopyServices 与 IOHIDServiceClient 属性函数来自 macOS SDK 的公开 hidsystem 头文件；CreateSimpleClient 还有 Apple 公开文档。没有私有符号声明或动态加载，不添加无意义的 dlsym 分支。既有 ServiceProvider 已提供可注入测试边界。 |
| M-09 | 硬编码事实成立，“上游仓库”不成立 | appcast URL 中的 zfdang/voice-input-buddy 与当前 origin 完全一致，是本项目更新源。没有复制上游仓库地址；保留固定发布目标，不将可配置性建议当作产品缺陷。 |
| M-10 | 状态较多属维护性事实，阻塞推断不成立，已减少轮询 | 原循环是可取消的异步 Task.sleep，权限就绪后 5 秒轮询，否则 1 秒，并不持续阻塞主线程。将语音工具运行态改为工作区应用启动/退出通知。权限与 Secure Input 没有可完全替代轮询的公开通知，继续保留低频检查；没有整体迁移 SwiftUI 状态所有权，以免改变向导 view identity。 |
| M-11 | 成立，已移出主线程 | 设置页延迟三秒后曾在主线程执行同步 AX 查询。现在经现有串行 focusQueue 查询，再回主线程保存结果与更新 UI。该入口的查询并非报告描述的整个 composer 一秒扫描，但仍可能等待跨进程 AX 消息。 |
| M-12 | 成立，已复用缓存 | RemoteCatalogPhoto 曾在 body 中直接创建 NSImage。改用已有 OnboardingImageCache，复用数量和成本受限的 NSCache。首次加载仍为本地资源解码。 |
| M-13 | 成立，已减少重复持久化 | resetBindings 的多次字段写入会级联更新并序列化设备 profile，setBaseBinding 也曾分别发布 remove/append。重置期间批量合并 profile 与统一绑定保存，单条绑定在局部副本完成修改后只赋值一次。回归测试验证重启后的完整映射和其他设备映射保留。 |
| M-14 | 成立，已统一语言来源 | Picker 的原生 Text/Button 字面量没有显式使用应用内语言选择。改经 localization.text，保持候选设备名原样显示。 |

## 低优先级发现

| 编号 | 准确性 | 证据与处理 |
| --- | --- | --- |
| L-01 | 成立，已更新 | 更新窗口两处调用改用 macOS 14 起支持的 NSApp.activate()；项目最低系统版本为 14。 |
| L-02 | 成立，已显式签名 | 移除签名阶段的 --deep。枚举真实 Mach-O 文件与嵌套 bundle，由内向外签名，再签外层；不跟随 framework 符号链接。保留固定证书、可选临时 keychain 和本地 ad-hoc 默认值。fixture 验证顺序与失败传播，实际 App 的递归严格签名验证通过。验证阶段使用 --deep 与签名阶段使用它含义不同。 |
| L-03 | 成立，已修复 | 删除已完成后，coreaudiod 已退出等情况可令 killall 失败。现在保留重启提示但返回成功，不把已完成的卸载报告为失败。fixture 不执行真实系统卸载或重启音频服务。 |
| L-04 | 不成立 | `scripts/build-driver-package.sh` 实际存在，development.md 的链接与脚本匹配，不删除有效说明。 |
| L-05 | 未取消事实成立，失效动作已有部分保护，已改为取消任务 | 原来的两组三个 asyncAfter 有步骤/attempt 检查，但任务未主动取消，其中 transcript 恢复没有终态检查。现在保留可取消句柄，在完成、失败、重试、新会话、切步和离开页面时取消，并将三秒截止任务纳入相同生命周期。 |
| L-06 | 不成立 | ConfigurationFiles.swift 已分别显示不支持版本、语音快捷键忙、无效文件以及读写失败状态；Preferences.swift 会实际呈现 configurationStatus。没有静默吞错。 |
| L-07 | 成立，已加强 | 设备卡片在高对比度下提高边框对比度和线宽，选中卡片添加 isSelected 辅助功能 trait。实际 VoiceOver 播报与高对比度视觉效果仍需交互验收。 |
| L-08 | 成立，已显示两种语言 | 截图说明原来只在英文显示，而中文资源中已有对应文本。移除英文条件，两种语言都通过 LocalizationStore 显示说明。 |

## 验证与边界

本次完整 Xcode 测试为 336 项，全部通过。另验证应用装配、签名 fixture、固定发布证书/keychain 流程、卸载 fixture 和更新签名测试；本地开发 App 使用 ad-hoc 签名。发布仍使用 GitHub Secrets 中固定自签名证书和项目 Sparkle 签名，PKG 仍未签名、未公证，没有修改证书信任或 main 自动发布行为。

可复现命令：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build --disable-keychain
swift test --disable-keychain --enable-code-coverage
python3 scripts/test-app-bundle.py
python3 scripts/test-sign-bundle.py
python3 scripts/test-release-signing.py
python3 scripts/test-installation-actions.py
python3 scripts/test-update-signature.py
CONFIGURATION=debug scripts/build-app.sh
codesign --verify --deep --strict 'dist/Voice Input Buddy.app'
```

真机仍需覆盖遥控器按键/音频、HAL 输出、第三方应用快捷键接收、辅助功能聚焦、休眠唤醒及权限撤销。自动化测试和构建成功不能替代这些验收。

参考：[Swift 6.2 正式发布](https://www.swift.org/blog/swift-6.2-released/)、[Apple IOHIDEventSystemClientCreateSimpleClient](https://developer.apple.com/documentation/iokit/2269514-iohideventsystemclientcreatesimp)、[Clang ARC 异常清理](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions)。
