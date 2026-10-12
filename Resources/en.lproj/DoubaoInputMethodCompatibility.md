# Virtual microphone setup

Voice Input Buddy uses a separate two-channel BlackHole-based loopback driver, named **Voice Input Buddy Mic** with UID `BuddyMic2ch_UID`. It does not replace BlackHole or the upstream application driver.

This initial port provides local development builds. Build the driver using `scripts/build-driver.sh`, then create `dist/VoiceInputBuddy-Microphone.pkg` with `scripts/build-driver-package.sh`. No DMG or public signed installer is provided yet.

When you choose to install the local PKG, macOS Installer requires administrator authorization. The package installs only `/Library/Audio/Plug-Ins/HAL/VoiceInputBuddyMic.driver`; it does not launch the app. After installation it restarts Core Audio to load the device; this briefly interrupts playback and recording. If restart fails, restart your Mac.

In the setup wizard, refresh audio devices and select Voice Input Buddy as the output. In your dictation application, select Voice Input Buddy as the microphone and configure the matching voice shortcut. BlackHole 2ch can also be selected if already installed.

For verification, select the loopback microphone in QuickTime Player's New Audio Recording and check the level while holding the remote voice button. Then test a focused editable text field with the target input tool. A successful build is not a completed hardware test.

Download the matching architecture uninstaller PKG from Releases and open it in macOS Installer. By default it removes the app, driver, and your settings, logs and caches. You may choose to keep personal data. Driver removal needs administrator authorization and restarts Core Audio.

The driver uses pinned BlackHole v0.7.1 GPL source. Its matching source and patch must accompany any future public binary release.
