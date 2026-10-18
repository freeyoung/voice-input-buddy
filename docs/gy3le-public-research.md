# GY3LE 公开资料与适配证据

检索日期：2026-10-18（Asia/Singapore）。本项目目前没有 GY3LE 实物，也没有它在 macOS 上的受控按键或语音抓包。

本文只把来源明确支持的内容记作事实。官方产品功能、其他型号的协议实测、对 GY3LE 的兼容推断及本项目拟实现的策略分开记录。未找到证据不表示某项功能不存在。

## 官方可以确认的内容

| 项目 | 可确认内容 | 依据 |
| --- | --- | --- |
| 产品身份 | GY3LE 是 Google TV Streamer Voice Remote 的产品型号；GRS6B 是 Google TV Streamer (4K) 主机型号，两者不能混用。 | [Google 安全与监管资料](https://support.google.com/product-documentation/answer/4541589?hl=en) 中明确对应型号和产品名称。 |
| 外形与供电 | 遥控器为 137 × 38 × 16 mm；不含电池 40 g，含两节 AAA 电池 63 g。 | [Google 规格表](https://support.google.com/chromecast/answer/3046409?hl=en) 的 **Google TV Streamer Voice Remote** 小节；不能读成前一节主机的规格。 |
| 通信与声音 | 有 Bluetooth、用于电视/音响控制的 IR 和集成语音麦克风。 | 同一份官方遥控器规格表。官方该小节没有给出遥控器 Bluetooth 版本、采样率、编码或 GATT 协议。 |
| 产品兼容性 | 官方列出 Google TV Streamer (4K) 和 Chromecast with Google TV。 | 同上。这是与电视设备的产品兼容声明，不是 macOS、Windows 或 Linux 的功能保证。 |

### 按键布局

[Google 的遥控器介绍](https://support.google.com/googletv/answer/15323195?hl=en) 提供了文字布局，足以独立绘制无品牌示意图：

- 顶部是方向圆盘，中心为 Select。
- 左列由上到下为 Back、Assistant/Mic、Mute、YouTube，底部小键为 Power。
- 右列为 Home、竖向 Volume 摇杆、Netflix，底部小键为可自定义按钮。
- 音量摇杆的上半和下半分别控制音量增减。与旧 Chromecast 遥控器的侧面音量布局不同。
- Assistant/Mic 是按住说话。遥控器背面还有用于 Find My Remote 提示音的声音出口，不能误写成麦克风位置。

按上/下/左/右/Select 和音量加/减分别计数，可数出 14 个非语音物理操作，加一个语音操作。这个计数不代表已经确认了 14 个 HID usage、报告格式或蓝牙事件。

### 星号键与旧款 Input 键

[Google 的自定义按钮说明](https://support.google.com/chromecast/answer/15157668?hl=en) 明确指出星号图标代表可自定义按钮，可在电视端选择 Google Home、某个应用或输入源功能。

这能证明 **GY3LE 底部右键不能在产品 UI 中固定称为旧款 Input 键**。但不能据此推导它的 HID usage、report ID，或认为它必然与 G9N9N 的 Input usage 相同。电视端配置也不能自动当作本应用的按键映射。

### 配对、系统控制和固件

- [Google 初次设置说明](https://support.google.com/chromecast/answer/15157762?hl=en) 指出：需要手动配对时，同时按住 Back 和 Home，直到指示灯开始闪动。该页面针对 Google 主机设置，没有保证相同动作在 Mac 上自动完成所有服务授权。
- [音量、电源和输入控制说明](https://support.google.com/chromecast/answer/10094150?hl=en) 区分对电视/音响和对串流设备的控制。不能假设每种电视端配置都会向 Mac 发送相同的蓝牙键值。
- [Google 的遥控器介绍](https://support.google.com/googletv/answer/15323195?hl=en) 说明，遥控器与 Google TV Streamer 或 Chromecast with Google TV 配对时会应用软件更新。固件差异应进入后续验收记录。
- Find My Remote 是官方产品功能，不代表本项目已知其 BLE 控制命令；这次适配不臆造寻回、蜂鸣或 OTA 指令。

## 开源资料：能参考什么，不能证明什么

### VibeMote：G9N9N 的受控采集，Streamer 未实测

来源：[Tilkmilk/vibe-mote](https://github.com/Tilkmilk/vibe-mote/tree/fb30e479694524962512b5bba6afc76cd0a04778)，检索时固定 commit 为 `fb30e479694524962512b5bba6afc76cd0a04778`。

- [README 的已知设备说明](https://github.com/Tilkmilk/vibe-mote/blob/fb30e479694524962512b5bba6afc76cd0a04778/README.md#L430-L431) 把原装 G9N9N 列为已知可用；提及 Streamer 2024 遥控器时明确写了 **“本项目未实测”**。
- [keys.py 的 usage 表](https://github.com/Tilkmilk/vibe-mote/blob/fb30e479694524962512b5bba6afc76cd0a04778/keys.py#L101-L109) 标注受控采集，包含旧款 Input 及 14 个键。这里没有提供独立的 GY3LE 星号键记录。
- 同文件中出现 `VID 18d1 / PID 9450`；结合其设备说明，不能把它转写成已经验证的 GY3LE 身份。
- [voice.py](https://github.com/Tilkmilk/vibe-mote/blob/fb30e479694524962512b5bba6afc76cd0a04778/voice.py) 研究 ATVV 控制和音频，能作为现有 Google 公共链路的实现参考，不能当成 GY3LE 的独立抓包。
- 该项目还有 Windows 特定的驱动宿主注入路径。本项目不复制这条路径，继续使用公开 CoreBluetooth/IOKit API。

**结论：它提供 G9N9N 的参考事实和对 Streamer 兼容性的推断，不提供 GY3LE 已实测的证据。**

### ATVVoice：ATVV 通用实现，不是 GY3LE 专用规格

来源：[b0o/ATVVoice](https://github.com/b0o/ATVVoice/tree/0e8f6413dc4bad7a04e3c6b648945439d7a22fac)，检索时 commit 为 `0e8f6413dc4bad7a04e3c6b648945439d7a22fac`。

[研究报告](https://github.com/b0o/ATVVoice/blob/0e8f6413dc4bad7a04e3c6b648945439d7a22fac/docs/research/report.md) 的研究对象明确是 **G20S PRO BLE**，不是 GY3LE。报告与协议源码讨论 ATVV 的服务、控制、分帧和 ADPCM。可用于理解已有 ATVV 适配和设计运行时能力校验，但没有在本次核验中找到 GY3LE 的专用 DIS、HID 描述符或会话记录。

**结论：ATVV 适配代码的存在不证明 GY3LE 必然使用某个 ATVV 版本、codec、帧长或 nibble 顺序。**

### BlueZ 讨论：有原始报告，但涉及其他设备

[BlueZ issue #1086](https://github.com/bluez/bluez/issues/1086) 最初讨论的是 UR02 克隆遥控器的麦克风。

- [2026-07-27 的参与者实测报告](https://github.com/bluez/bluez/issues/1086#issuecomment-5089723424) 自述设备为 Chromecast with Google TV 遥控器，列出了 `bluetooth:v18D1p9450d0110`、ATVV v1.0、16 kHz ADPCM、HoldToTalk 及 frame size 160，并报告了可理解的语音和松键停止。
- 这是一手使用者报告，提供了可核查的命令和输出；本项目没有独立复测该硬件。报告没有声明设备为 GY3LE，因此这些值不能作为 GY3LE 参数。
- 同一讨论还引用了一份第三方站点托管的 Google Voice over BLE spec 1.0 PDF。该副本带有 `Google Confidential` 标记，且不是 Google 官方公开发布页面。本次不将其复制进仓库，也不把它视作 GY3LE 的公开设备规格。

### 芯片厂商参考实现：Infineon CYW20829

[Infineon 官方参考工程](https://github.com/Infineon/mtb-example-btstack-freertos-cyw20829-voice-remote/tree/b2b7dcb046ca2be022dcd0dc931699f670a35c98) 的 README 说明其参考硬件可选择 Android TV ADPCM 或 Opus 编码。

它是芯片厂商公开的一手参考设计，但不是 GY3LE 固件，不能据此认定 GY3LE 使用 CYW20829、支持 Opus，或使用其按键表。本次仅记录来源与适用边界，没有复制固件代码。

## 仍然未知的协议事实

| 项目 | 本次证据状态 | 实现时的限制 |
| --- | --- | --- |
| BLE 广播名 | 未找到原装 GY3LE 的受控记录 | 产品名称可用于发现候选，不能替代型号和协议验证。 |
| DIS Model Number（2A24）实际值 | 官方产品型号是 GY3LE，但未找到该特征的实测值 | 接受规范化后的精确型号是准入策略，不能称为真实设备读取结果。 |
| DIS PnP、VID/PID | 未找到独立可靠的 GY3LE 记录 | 不复制 G9N9N 的 18d1:9450；运行时读取并与实际 HID 候选匹配。 |
| HID descriptor、report ID/长度/位序 | 未找到原装 GY3LE 的受控记录 | 不默认沿用 G9N9N 的 report 2 数组格式；优先从实际 HID 描述信息取得事件。 |
| 星号键 usage、按下/松开报告 | 未知 | 不臆定为 G9N9N Input 的 0x0189，也不凭位置推断。 |
| 普通键完整 usage 表 | 未找到独立 GY3LE 采集 | 对已声明的标准 usage 可设计解析，但测试 fixture 必须注明是构造数据。 |
| ATVV 服务及能力响应 | 尚无 GY3LE 抓包 | 只在真实服务/特征和能力响应满足已实现格式时启用该解码链路。 |
| 音频采样率、codec、帧长、nibble 顺序 | 未知 | 不能把 G9N9N 的 16 kHz ADPCM 当作 GY3LE 已证实参数；不支持的格式要明确拒绝。 |
| 关麦/保活/重连行为 | 没有本设备实测 | 复用代码需要带会话身份和超时保护；不能把单元测试通过写成物理关麦验收。 |
| macOS HID 接管、权限、休眠恢复 | 无真机验收 | 自动测试验证程序行为，硬件验收保持待完成。 |

特别注意：官方规格中的 **Bluetooth 5.1 是 Streamer 主机的信息**；旧 Chromecast Voice Remote 的 BLE 4.2 也是另一款设备的信息。本次不为 GY3LE 指定未经确认的 Bluetooth 版本。

## 不采用为协议证据的资料

- 本仓库、个人博客和网站的“支持设备”列表：是产品描述，不是独立的硬件验证。
- 电商“适配 GY3LE”的替换遥控器：兼容商品可能有不同芯片、身份和协议。
- 型号相似的 FCC/检测镜像：检索到 `TX4GY3LE`、申请人 Remote Solution 的认证线索，但未完成原装设备标签和照片的交叉核验；本次尝试访问 FCC 官方附件也未能成功。必须核对申请人、品牌、照片和完整标识，不能只凭文件名含 GY3LE 就认定是 Google 原装。本文没有把它记作原装身份或 BLE VID/PID。
- 搜索结果摘要中的推测、普通用户论坛转述和未经采集的生成代码：只作线索，不作为常量来源。
- 官方宣称可控制 Chromecast：不能进一步推导 VID/PID、按键报告、音频参数全部相同。

## 对后续代码的约束与验收清单

1. 增加独立 GY3LE 型号、布局和星号键概念，保持 G9N9N 的身份与实测协议边界。
2. 公共 BLE 会话、配置和音频调度可以复用；具体设备数据必须从运行时声明或已有可靠采集取得。
3. HID 关联仅绑定与已确认 BLE 设备相匹配的身份及唯一候选，不以“任意蓝牙键盘”兜底，不抢其他键盘。
4. 没有依据的报告常量不写成生产事实。无法识别的按键应保留明确诊断和后续采集入口，不伪造按键验证完成。
5. 自动测试标明构造的型号、PnP、报告与音频能力数据，覆盖 G9N9N 不回归、未知型号拒绝、两种 Google 型号不串档。
6. 有实物后按公开系统界面记录：设备型号/固件、DIS/PnP、HID descriptor、每键 press/release（尤其星号）、ATVV 能力和正常启停；完成 Mac 输入、语音、真实文字上屏及休眠恢复。
7. 除非用户另行要求，不默认保存用户语音、转写内容、蓝牙地址或敏感标识。协议资料与程序测试不等同于产品已真机验收。

本次检索结论：**官方足以确认产品身份、布局和功能；尚不足以确认 GY3LE 的完整线级协议。** 不把这个缺口用 G9N9N 参数或猜测填平。
