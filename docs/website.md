# 项目官网

官网源文件位于 `pages/`，为无需构建的静态 HTML、CSS 和 JavaScript。默认首页 `index.html` 使用英文，`index.zh-CN.html` 使用中文；右上角可切换语言。两份内容与 README 中英文版本应一起更新。

沿用仓库已有 `.github/workflows/static.yml`：main 中的 `pages/**` 或该 workflow 更新时自动部署；也保留手动触发。发布任务仅上传 pages 目录，不上传 App 源码、构建目录或本地文件。

`pages/CNAME` 为 `voice.zfdang.com`，GitHub Pages 仓库设置已选择 Actions 部署与此自定义域名。域名 DNS 应正确指向 GitHub Pages；TLS 证书和域名验证由 GitHub 与域名服务配置决定。部署完成前，本地预览不等于官网已上线。

本地预览：

```bash
python3 -m http.server 8765 --directory pages
```

页面中的麦克风演示仅改变本地显示，不申请麦克风权限、不录音、不发送网络请求。网站不使用分析或追踪脚本。官网的下载链接指向 GitHub 最新 Release，首次 Release 生成后即可下载。
