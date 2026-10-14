# 首次设置

从本项目 GitHub Releases 下载适合 Mac 架构的 PKG，一次安装 App 与虚拟麦克风驱动；打开 `/Applications/Voice Input Buddy.app`。

首次向导依次检查系统权限、准备设备、连接遥控器、按键测试、驱动检查、输入工具、语音测试和完成。按需授予蓝牙、输入监控和辅助功能权限。小米 RC001／RC003 与 G9N9N 可继续连接；G9N9N 真机验收仍待完成，GY3LE 和 Siri Remote 尚不能继续连接。

App 自动输出到 **Voice Input Buddy Mic**，无需选择回环设备。在目标输入工具中选择同名麦克风，配置并测试语音快捷键。App 负责音频路由及按键动作；识别由输入工具完成，不采集使用统计、不保存录音或文本历史、不上传日志。

安装驱动需要管理员授权，会短暂重启音频。当前 PKG 未签名、未公证；App 与驱动使用固定自签名身份。Windows 尚未实现。更多说明：https://github.com/zfdang/voice-input-buddy/blob/main/docs/interface.md
