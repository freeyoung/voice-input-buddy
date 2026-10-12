#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/architecture.sh"
metadata="$("$root/scripts/release-metadata.sh")"
while IFS='=' read -r key value; do export "$key=$value"; done <<< "$metadata"
mkdir -p "$root/.build" "$root/dist/release"
work="$(mktemp -d "$root/.build/uninstaller.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for component in system data; do
    mkdir -p "$work/$component"
    cp "$root/scripts/uninstaller/"{installer-common.sh,uninstall-user.sh} "$root/scripts/installation-common.sh" "$work/$component/"
    if [[ "$component" == system ]]; then
        cp "$root/scripts/uninstaller/"{preinstall,postinstall,uninstall-system.sh} "$work/$component/"
    else
        cp "$root/scripts/uninstaller/cleanup-postinstall" "$work/$component/postinstall"
    fi
    chmod +x "$work/$component/"*
    pkgbuild --nopayload --scripts "$work/$component" \
        --identifier "com.zfdang.voice-input-buddy.uninstaller.$component" \
        --version "$RELEASE_BUNDLE_VERSION" "$work/$component.pkg"
done
cat > "$work/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Uninstall Voice Input Buddy / 卸载语音搭子</title>
  <options customize="always" require-scripts="true" hostArchitectures="$BUILD_ARCH" rootVolumeOnly="true"/>
  <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
  <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
  <welcome file="welcome.html"/>
  <choices-outline><line choice="system"/><line choice="data"/></choices-outline>
  <choice id="system" title="Remove app and microphone driver / 删除程序和驱动" enabled="false" selected="true"><pkg-ref id="com.zfdang.voice-input-buddy.uninstaller.system"/></choice>
  <choice id="data" title="Delete settings, logs and caches / 删除设置、日志和缓存" start_selected="true" description="Clear personal data for the currently logged-in desktop user. Uncheck to keep it. / 默认清除当前桌面用户的数据，取消勾选即可保留。"><pkg-ref id="com.zfdang.voice-input-buddy.uninstaller.data"/></choice>
  <pkg-ref id="com.zfdang.voice-input-buddy.uninstaller.system" version="$RELEASE_BUNDLE_VERSION" auth="Root">system.pkg</pkg-ref>
  <pkg-ref id="com.zfdang.voice-input-buddy.uninstaller.data" version="$RELEASE_BUNDLE_VERSION" auth="Root">data.pkg</pkg-ref>
</installer-gui-script>
XML
mkdir -p "$work/resources"
cat > "$work/resources/welcome.html" <<'HTML'
<html><meta charset="utf-8"><body style="font:14px -apple-system"><h2>Uninstall Voice Input Buddy</h2><p>This package removes the app, login item and microphone driver. Settings, logs and caches for the desktop user are deleted by default. Uncheck the personal-data option to keep them.</p><p>Core Audio briefly restarts. Close recording and playback apps first. The Installer button says “Install”, but this package only uninstalls.</p><h2>卸载语音搭子</h2><p>删除程序、登录项和麦克风驱动，默认清除当前桌面用户的设置、日志和缓存；取消个人数据选项可保留。音频服务会短暂重启，请先关闭录音和播放软件。</p><p>系统按钮显示“安装”，此包实际执行卸载。</p></body></html>
HTML
productbuild --distribution "$work/Distribution.xml" --resources "$work/resources" \
    --package-path "$work" "$root/dist/release/Voice_Input_Buddy_Uninstaller_${RELEASE_TAG}_macOS_${RELEASE_ARCH_LABEL}.pkg"
python3 "$root/scripts/verify-uninstaller-package.py" "$root/dist/release/Voice_Input_Buddy_Uninstaller_${RELEASE_TAG}_macOS_${RELEASE_ARCH_LABEL}.pkg" "$BUILD_ARCH"
printf 'Built standalone %s uninstall PKG\n' "$RELEASE_ARCH_LABEL"
