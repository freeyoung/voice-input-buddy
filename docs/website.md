# 项目官网

官网源文件位于 `pages/`，为无需构建的静态 HTML、CSS 和 JavaScript。默认首页 `index.html` 使用中文，英文页面位于 `index.en.html`；右上角可通过链接切换语言。仓库默认文档 `README.md` 使用中文，`README.en.md` 使用英文，并提供相互切换的链接。两份网页与 README 中英文版本应一起更新。

沿用仓库已有 `.github/workflows/static.yml`：main 中的 `pages/**` 或该 workflow 更新时自动部署；也保留手动触发。发布任务仅上传 pages 目录，不上传 App 源码、构建目录或本地文件。

`pages/CNAME` 为 `voice.zfdang.com`，GitHub Pages 仓库设置已选择 Actions 部署与此自定义域名。域名 DNS 应正确指向 GitHub Pages；TLS 证书和域名验证由 GitHub 与域名服务配置决定。部署完成前，本地预览不等于官网已上线。

本地预览：

```bash
python3 -m http.server 8765 --directory pages
```

页面中的麦克风演示仅改变本地显示，不申请麦克风权限、不录音、不发送网络请求。网站不使用分析或追踪脚本。官网的下载链接指向 GitHub 最新 Release，首次 Release 生成后即可下载。

中英文页面的 `#demo` 区域提供两分钟卡通视频。MP4、封面和可选中文字幕轨道位于
`pages/assets/video/`，由 Pages 一起部署。视频为中文旁白与画内中文字幕；英文页面明确标注视频语言。
播放器使用浏览器原生控制，支持全屏、拖动和下载，不自动播放，只预加载元数据，
不依赖外部播放器或追踪服务。更新视频时同步更新封面、字幕和两种语言的介绍。

视频的动画源文件与旁白位于 `scripts/demo-video/visuals.py` 和
`scripts/demo-video/render.py`，更新时先对照当前程序界面。网页硬件区域列出四项设备，
与输入工具列表并列展示。安装包未公证的提醒仅保留在网页文字说明中；视频不展示此提醒。

在 macOS 上重做视频（需要 `ffmpeg`、`ffprobe` 和系统中文字体）：

```bash
python3 -m venv dist/videos/venv
dist/videos/venv/bin/pip install Pillow edge-tts
dist/videos/venv/bin/python scripts/demo-video/render.py
```

旁白采用 `zh-CN-XiaoxiaoNeural`，首次生成或文字变化时通过 Edge TTS 合成，
相同文字的音频缓存在 `dist/videos/source/`。脚本同步生成两分钟 MP4、WebVTT 字幕和封面，
直接写入 `pages/assets/video/`。完成后检查画面、字幕时间和声音，再提交这些资产。
