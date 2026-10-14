# 遥控器素材与适配准备

设备范围为小米蓝牙遥控器 2 Pro、Google G9N9N、Google GY3LE、Apple Siri Remote 四项。小米保留现有能力；G9N9N 已可在向导中选择，但连接页会提示适配未完成；GY3LE 与 Siri Remote 暂不可选择。三款新增设备都不能作为已验证连接提供。

## 官方外观资料与应用素材

| 设备 | 官方图片／按键资料 | 应用内素材 |
| --- | --- | --- |
| Chromecast Voice Remote（G9N9N） | [Google 外观与按键图](https://support.google.com/chromecast/answer/10116742?hl=en) | `Resources/ChromecastG9N9NIllustration.png` |
| Google TV Streamer Voice Remote（GY3LE） | [Google 外观与按键图](https://support.google.com/chromecast/answer/15323195?hl=en)、[商品页](https://store.google.com/product/google_tv_streamer_remote?hl=en-US) | `Resources/GoogleStreamerGY3LEIllustration.png` |
| Apple Siri Remote | [Apple 第三代 USB-C 外观图](https://support.apple.com/en-us/111844)、[型号识别](https://support.apple.com/en-au/103233) | `Resources/SiriRemoteA2854Illustration.png` |

官方图片仅作为链接参考，不复制进安装包。新增素材是原创、无品牌标志的透明背景示意图，按项目 GPL-3.0-only 分发；可编辑 SVG 源文件位于 `Resources/RemoteIllustrations/`。示意图不是照片，也不按实际尺寸比例绘制。

Apple 素材以第三代 USB-C A2854 为外观基准（[Apple 官方型号信息](https://www.apple.com/kr-edu/shop/product/mw5g3kh/a/siri-remote)）。它不代表其他 Siri Remote 代际的按键布局或音频协议已得到支持。正式适配前仍需固定实际样机型号。

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
6. G9N9N 允许先选择并进入设置，但实际连接验证保持必需。完成对应型号的真机验收后，再启用连接管理和真实按键映射。素材准备与编译通过不等于硬件验收。

详细验收条件见[开发说明](development.md#google-remote-compatibility-acceptance)。[vibe-mote](https://github.com/Tilkmilk/vibe-mote) 和 [ATVVoice](https://github.com/b0o/ATVVoice) 是协议研究参考，不将它们的 Windows／Linux 验证当作本项目的 macOS 验收。
