# Voice Input Buddy

**English** | [简体中文](README.zh-CN.md)

Turn a remote control into a voice-input button for your computer. Press to talk, release to finish, and let your preferred input method or dictation tool enter text into the current field.

[Website](https://voice.zfdang.com) · [Downloads](https://github.com/zfdang/voice-input-buddy/releases)

Supports **macOS 14 and later**, on Apple Silicon and Intel Macs. Windows support is planned.

## What can it do?

- Use a remote's microphone for voice input, without reaching for the keyboard.
- Map remote buttons to keyboard shortcuts, application actions, or common phrases.
- Configure hold-to-talk or press-to-start/stop behavior for your input tool.
- Set up permissions, the microphone driver, device connection, and input integration in one guide.

Voice Input Buddy does not collect usage statistics, save recordings or transcript history, or upload logs. Recognition and text cleanup are handled by your selected input tool, with that tool's own network and privacy settings.

## How does it work?

```text
Remote microphone → Bluetooth audio → Voice Input Buddy → Virtual microphone → Input tool
Remote voice button → Voice Input Buddy → Voice shortcut → Text in the current field
```

The app decodes remote audio and sends it to a virtual microphone while triggering the selected tool's voice shortcut. It connects hardware to input software; it does not run its own speech-recognition model. Live transcription, recognition speed, and corrections depend on the input tool.

## How do I use it?

Download `Voice_Input_Buddy_*.pkg` from [Releases](https://github.com/zfdang/voice-input-buddy/releases). One installer includes both the app and its virtual microphone driver.

1. Install and open `/Applications/Voice Input Buddy.app`.
2. Follow the guide to grant Bluetooth, Input Monitoring, and Accessibility permissions, and check that the driver is detected. The app follows your system language by default; you can choose English or Chinese on the first screen.
3. Connect your remote. Select the **Voice Input Buddy** microphone in your input tool.
4. Configure the tool's voice shortcut under **Integration**, then test it with the guide.
5. Focus a text field, press the voice button to speak, and release to finish. Adjust the trigger behavior for tools that use separate start/stop taps.

Configure other buttons under **Buttons**. To check the setup again, use **Run Setup Guide Again** at the top of Settings.

Driver installation requires administrator authorization and briefly interrupts audio. Current installers are not Apple-notarized and may be blocked by macOS; updates can require renewed permissions. See [installation and release notes](docs/releases.md).

## Which devices are supported?

| Device | Status |
| --- | --- |
| Xiaomi Bluetooth Remote 2 Pro | Connection and buttons tested locally; audio operation confirmed by the user |
| Compatible Xiaomi RC001 / RC003 series remotes | ATVV audio and button protocol support is included; individual models and firmware need testing |
| Apple Siri Remote, generic Bluetooth/USB buttons, foot pedals | Not currently offered as supported devices |

Bluetooth pairing alone does not establish compatibility: the remote must use a supported button and audio protocol.

## Which input methods and tools can I use?

| Tool | Integration |
| --- | --- |
| WeType / WeChat Input Method | Dedicated setup entry with virtual microphone and voice shortcut |
| Doubao Input Method | Dedicated setup entry with hold and tap behavior |
| Typeless | Configure its voice shortcut and start/stop behavior |
| Vokie | Dedicated setup entry |
| VoiceCursor | Separate entry using the virtual microphone and a custom voice shortcut |
| Other voice-input tools | Configure a custom shortcut under Other Tools |

The tool must accept the virtual microphone and expose a usable voice shortcut. Versions and settings vary: verify the actual behavior with the guide. A configuration entry does not mean every version has been tested.

## More information

- [Interface and troubleshooting](docs/interface.md)
- [Website and deployment](docs/website.md)
- [Development and builds](docs/development.md)
- [Releases and installers](docs/releases.md)
- [Architecture and scope](docs/architecture.md)
- [Privacy and testing](docs/privacy-and-testing.md)
- [Source provenance](docs/provenance.md), [GPL-3.0-only license](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md)

## References

| Project / module | Role |
| --- | --- |
| [remote-mic-app](https://github.com/HD838A/remote-mic-app) | Code foundation for remote connectivity, audio bridging, button mappings, and interface |
| [remote-bridge-hub](https://github.com/xxb26553663-star/remote-bridge-hub) | Xiaomi ATVV protocol, ADPCM decoding, and HID mapping reference |
| [BlackHole](https://github.com/ExistentialAudio/BlackHole) v0.7.1 | Virtual microphone driver |
| [MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice) | USB-transport loopback compatibility design reference |
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.9.4 | macOS update framework; no update feed is configured yet |
| [codex-siri-remote](https://github.com/luobosibing2/codex-siri-remote) | Historical reference for Apple remote HID and touch behavior |
| [SiriRemoteForge](https://github.com/HOLODATA-COM/SiriRemoteForge) | Historical reference for Apple remote audio and PacketLogger formats |
| [iRemote A2854](https://github.com/DaviBaum/iRemote-A2854) | Historical reference for Apple remote diagnostics and authorization |
| [Opus](https://www.opus-codec.org/) | Codec referenced by historical Apple remote compatibility code; its dynamic library is not included in the current installer |

Historical references do not imply current Apple remote support. See the [module inventory](docs/modules.md) for internal modules and macOS frameworks, and [third-party notices](THIRD_PARTY_NOTICES.md) for versions, copyrights, and licenses.
