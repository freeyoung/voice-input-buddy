# 遥控器素材与适配准备

设备范围为小米蓝牙遥控器 2／2 Pro、Google G9N9N、Google GY3LE、Apple Siri Remote 四项。小米保留现有能力；四款均可选择。小米和 G9N9N 可继续进入连接页；GY3LE 与 Siri Remote 点击继续时留在第二步，在右侧图片下方显示“现在还不支持，敬请期待。”G9N9N 已有公开音频和按键适配，连接页检查真实连接与按键；真机验收仍待完成。三款新增设备都不能作为已验证连接提供。

## 官方外观资料与应用素材

| 设备 | 官方图片／按键资料 | 应用内素材 |
| --- | --- | --- |
| Chromecast Voice Remote（G9N9N） | [Google 外观与按键图](https://support.google.com/chromecast/answer/10116742?hl=en) | `Resources/ChromecastG9N9NIllustration.png` |
| Google TV Streamer Voice Remote（GY3LE） | [Google 外观与按键图](https://support.google.com/chromecast/answer/15323195?hl=en)、[商品页](https://store.google.com/product/google_tv_streamer_remote?hl=en-US) | `Resources/GoogleStreamerGY3LEIllustration.png` |
| Apple Siri Remote | [Apple 第三代 USB-C 外观图](https://support.apple.com/en-us/111844)、[型号识别](https://support.apple.com/en-au/103233) | `Resources/SiriRemoteA2854Illustration.png` |

官方图片仅作为链接参考，不复制进安装包。新增素材是原创、无品牌标志的透明背景示意图，按项目 GPL-3.0-only 分发；可编辑 SVG 源文件位于 `Resources/RemoteIllustrations/`。示意图不是照片，也不按实际尺寸比例绘制。

Apple 素材以第三代 USB-C A2854 为外观基准（[Apple 官方型号信息](https://www.apple.com/kr-edu/shop/product/mw5g3kh/a/siri-remote)）。它不代表其他 Siri Remote 代际的按键布局或音频协议已得到支持。正式适配前仍需固定实际样机型号。

## 小米硬件型号与支持范围

| 商品名称 | 蓝牙 DIS 硬件型号 | 当前状态 |
| --- | --- | --- |
| 小米蓝牙遥控器 2 | RC001 | 已包含 ATVV 语音和普通按键适配；完整音频验收待完成 |
| 小米蓝牙遥控器 2 Pro | RC003 | 已本地验证连接和按键；音频已由用户确认正常 |

RC001／RC003 是设备型号，不是协议或商品版本号。两款使用同一套普通按键映射与项目示意图，语音键单独处理；实际固件和第三方兼容款仍需分别验证。ATVV 是 Android TV Voice over BLE，不是 Google 原装遥控器独有，小米也使用它。当前小米与 G9N9N 音频均解码为 16kHz PCM，再送入同一个虚拟麦克风；新增遥控器不需要改麦克风驱动。

## 两款 Google 遥控器的共同点与区别

两款都具有方向环、确认、返回、主页、语音、音量、静音、电源和两个应用快捷键。都以蓝牙连接播放器，并可通过红外控制部分电视／音响功能。GY3LE 官方兼容 Google TV Streamer 及旧 Chromecast with Google TV 4K／HD，但这不是 Mac 协议兼容性证明。上述功能和布局依据表中 Google 官方资料。

| 项目 | G9N9N | GY3LE |
| --- | --- | --- |
| 音量键位置 | 右侧 | 正面右列长按键 |
| 语音键位置 | 方向环下第一排右侧 | 正面左列第二颗 |
| 底部右键 | 输入源 | 自定义键 |
| 寻找遥控器 | 官方按键资料未列出该功能 | 支持响铃；背面有发声孔，不是麦克风接口 |
| Mac HID 报文与按键边沿 | 待本项目真机验证 | 待本项目真机验证 |
| Mac ATVV 能力／编码／会话 | 待本项目真机验证 | 待本项目真机验证 |

示意图短标签：H = 主页，M = 静音，MIC = 语音，YT／NF = 应用快捷键，IN = 输入源，星形 = 自定义键。Apple 的 TV 表示电视／控制中心键，右侧窄条表示 Siri 键。

Google 商品页把 Play/Pause 列入功能，但官方布局说明没有单独列出播放／暂停实体键。因此不据此添加未经确认的独立按键位置或 HID 码。

## 实施顺序与验收

1. 分别取得原装 G9N9N、原装 GY3LE 和确定代际的 Siri Remote；第三方 Google 兼容款作为额外样机，不新增产品目录项。
2. 在 macOS 系统蓝牙设置中完成配对，分别记录设备自报型号、固件、HID 描述符与可访问的 GATT 服务。配对成功只表示连接完成。
3. Google 连接和 ATVV 会话使用共用框架，以协商得到的能力决定编码、帧和会话行为；两款保留独立型号识别、布局和按键映射，第三方变体保留可诊断的差异。
4. 验证正常按键、语音开始／结束、PCM 解码、虚拟麦克风输出、长会话、休眠重连与 HID／GATT 共存。Siri Remote 使用自己的接入层，不套用 Google ATVV 假设。
5. 验证兼容款：不能因名称、型号标签、VID/PID 相同就认定完整支持；认证失败时先完成正常配对再探测。区分按键可用、音频可用、服务不可访问和服务确实缺失。
6. G9N9N 已启用公开连接管理与按键映射，向导仍要求实际连接验证。按本清单完成真机验收后才能宣称硬件已经验证；素材准备与编译通过不等于硬件验收。

详细验收条件见[开发说明](development.md#google-remote-compatibility-acceptance)。[vibe-mote](https://github.com/Tilkmilk/vibe-mote) 和 [ATVVoice](https://github.com/b0o/ATVVoice) 是协议研究参考，不将它们的 Windows／Linux 验证当作本项目的 macOS 验收。

## 本轮 G9N9N 实现

仅接受型号确认和 ATVV v1.0／16kHz 能力确认都通过的语音设备。普通按键先支持参考项目记录的 Consumer Control report 2；按键页面不显示尚未捕获到蓝牙报文的电源／输入源键。未知 VID/PID、未知报文或未知型号不会因商品页面写着兼容而自动获得支持。认证失败与缺少语音服务分别处理。真机音质、重连和兼容款批次仍待验收。


## 添加兼容遥控器

设备连接页的“添加新设备”会从设备选择步骤打开向导，保留已有设备、按键映射和输入工具配置。
设备型号及音频能力通过确认后，利用公开 DIS PnP ID（0x2A50）和只读蓝牙 HID 元数据关联按键设备；
自动关联要求 VID/PID、唯一物理指纹和系统名称一致。缺少元数据或存在歧义时，可在连接步骤点击
“按键未识别？关联兼容遥控器”手动选择，随后继续原有按键验证。

非标准 VID/PID 在关联成功时立即随设备配置保存，以后参与扫描；标准 ID 只关联指纹，不重复加入白名单。
删除或重新关联设备会移除旧 ID。Google 按键只有在对应 BLE 设备通过型号和能力确认、处于就绪状态时才解析。
启用 Google 不会绕过小米电源键保护；抑制失败时，小米标准 ID 和兼容 ID 均不进入监听。
保存 ID 不会改变音频协议要求，未知型号、编解码器和 HID 报文仍需独立适配及真机验收。

## 输入法候选框与遥控器按键

如果拼音、五笔或 Rime 等输入法的候选框正在显示，请先选词确认，或按 Escape 取消本次预编辑，再启动语音输入。候选框打开时，方向键和 Return 通常用于选词；遥控器映射成这些键时也会执行输入法的选词动作。

程序不会在每次语音启动或方向键之前自动发送 Escape：这可能丢弃用户尚未确认的输入，也可能关闭目标应用的菜单或对话框。不同输入法和编辑器的预编辑状态并没有在本项目中得到统一、可靠的跨应用验证；没有足够证据时不修改正在输入的内容。

## Mac 配对指引

向导可分别选择 G9N9N 和 GY3LE，并显示各自的示意图。选择型号不会跳过连接和普通按键验证。

1. 打开 Mac 的“系统设置 → 蓝牙”，将遥控器靠近电脑。
2. 同时按住返回（Back）和主页（Home）约 3 秒，直到指示灯开始闪烁。
3. 在 Mac 的蓝牙列表中选择遥控器并连接，再按一个普通按键检查输入。重新配对时，可先忽略原设备。

这些步骤用于连接 Mac；不要等待 Chromecast 或电视上的配对成功提示。
