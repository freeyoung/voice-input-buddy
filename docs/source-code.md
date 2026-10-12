# Corresponding source / 对应源码

Each binary release identifies the project Git tag in its release description. View or download that revision from GitHub, including `LICENSE`, `THIRD_PARTY_NOTICES.md`, all application sources and build scripts. GitHub's source downloads are sufficient for the project repository; the bundled dependencies below also have to be obtained to reproduce the binaries.

每个二进制 Release 的说明都链接到对应 Git tag。GitHub 提供本项目该版本的源码下载，包含应用源码、许可证及构建脚本。复现捆绑组件还需下列固定版本的第三方源码；不能只下载当前 main 来代表任意旧版本。

- BlackHole driver source: [e2b22aaaba4e507a097131704bf96dabc004d9cf](https://github.com/ExistentialAudio/BlackHole/tree/e2b22aaaba4e507a097131704bf96dabc004d9cf), version v0.7.1. Apply this revision's `third_party/blackhole/device-usb.patch`; `scripts/build-driver.sh` downloads, verifies and patches it. Its GPL license is retained in the installed driver.
- Sparkle source: [b6496a74a087257ef5e6da1c5b29a447a60f5bd7](https://github.com/sparkle-project/Sparkle/tree/b6496a74a087257ef5e6da1c5b29a447a60f5bd7), version 2.9.4, pinned by `Package.resolved`. The framework is not locally patched; architecture thinning and signing are specified in this repository's scripts.

Follow [development.md](development.md) and [releases.md](releases.md) for build requirements and commands. `scripts/build-release-sources.sh` remains available for an optional local consolidated archive; this archive is not uploaded as another Release attachment. Public source links must remain available for the associated distributed binaries.
