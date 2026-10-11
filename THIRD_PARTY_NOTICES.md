# Third-party notices

## Current distribution

Voice Input Buddy bundles its app and the independently named BuddyMic2ch driver in one PKG. Driver sources are BlackHole v0.7.1 with third_party/blackhole/device-usb.patch. The complete source archive includes the actual patched driver and Sparkle sources. RC003 product photos, upstream proprietary artwork, libopus binaries and private extensions are not distributed. The historical descriptions below do not imply they are bundled or supported.

## Sparkle

- Source: <https://github.com/sparkle-project/Sparkle>
- Version: 2.9.4 / `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`
- License: MIT and the framework's included third-party notices

The complete framework and its license resources are preserved in the app; matching source is included with releases. No update feed or upstream signing key is reused.

## remote-mic-app

- Source: <https://github.com/HD838A/remote-mic-app>
- Imported revision: `cae2a23804506538c31003d14ec3239379da66c1`
- License: GPL-3.0-only

Voice Input Buddy is an independent derivative. Original author notices are preserved in `docs/upstream-copyright.md`. The sections below preserve the upstream component inventory and historical descriptions; disabled components are not necessarily included in the macOS app bundle. No upstream proprietary artwork is included. See `docs/provenance.md` for actual build and distribution requirements.

## remote-bridge-hub

- Project: `xxb26553663-star/remote-bridge-hub`
- Source: <https://github.com/xxb26553663-star/remote-bridge-hub>
- Reference revision: `8a93f321ac71a602300c6cd77f7256fa4b63068e`
- License: GNU General Public License v3.0 only (`GPL-3.0-only`)

The Xiaomi RC003 ATVV UUIDs, microphone command behavior, IMA/DVI ADPCM decoding order, capability parsing, and HID usage mapping were adapted from this project. The macOS implementation uses Apple public frameworks and does not include the upstream Windows injection, VB-CABLE packaging, commercial branding, or customer systems.

## codex-siri-remote

- Project: `luobosibing2/codex-siri-remote`
- Source: <https://github.com/luobosibing2/codex-siri-remote>
- Reference revision: `3da8bc74cc840c3e048448de203586cd24108f6a`
- License: GNU General Public License v3.0 or later (`GPL-3.0-or-later`)

The Apple Siri Remote A2854 vendor/product identifiers, HID usage table, dynamically loaded `MultitouchSupport` ABI, small external touch-surface selection rule, and initial circular-scroll tuning were informed by this project. The upstream remote-mic-app implementation reimplements the adapter and lifecycle routing; it does not include the upstream DriverKit components or virtual audio implementation.

## SiriRemoteForge

- Project: `HOLODATA-COM/SiriRemoteForge`
- Source: <https://github.com/HOLODATA-COM/SiriRemoteForge>
- Reference revision: `10581a960f0738e36516defb79db24b18df214d3`
- License: GNU General Public License v3.0 or later (`GPL-3.0-or-later`)

The lossless PacketLogger file-tail capture shape, binary `.pklg` record layout, ACL/L2CAP fragmentation handling, A2854 voice notification framing, Opus packet handling, and packet-loss concealment strategy were informed by this project. The upstream remote-mic-app implementation uses its `MiRemoteV 2ch` output instead of including SiriRemoteForge's HAL driver, root LaunchDaemon, shared-memory ring, application UI, or built-in microphone fallback.

## iRemote A2854

- Project: `DaviBaum/iRemote-A2854`
- Source: <https://github.com/DaviBaum/iRemote-A2854>
- Reference revision: `3f6fd807a6b11df12789df3fdd5874ad9336a684`
- License: MIT

The direct `com.apple.bluetooth.BTPacketLogger` XPC connection, `RequiresAuth` / `Authentication` handshake, `com.apple.PacketLogger.HCI` Authorization Services flow, profile-required diagnostic recognition, and bounded in-memory traffic handling were informed by this project. The upstream remote-mic-app implementation provides a narrowly scoped client and does not include iRemote's Whisper transcription, text insertion, pointer control, UI, model management, or user data handling.

## Opus

- Project: Opus Interactive Audio Codec
- Source: <https://www.opus-codec.org/>
- Historical upstream version: 1.6.1; no libopus binary is bundled in this distribution
- License: BSD 3-Clause (`BSD-3-Clause`)

The retained experimental Apple Remote audio helper can dynamically load an externally installed libopus to decode remote voice packets. This product does not bundle libopus or Apple PacketLogger; Apple Siri Remote remains unsupported in the app.

Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell, Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of Internet Society, IETF or IETF Trust, nor the names of specific contributors, may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## BlackHole

- Project: `ExistentialAudio/BlackHole`
- Source: <https://github.com/ExistentialAudio/BlackHole>
- Pinned source revision: `v0.7.1` / `e2b22aaaba4e507a097131704bf96dabc004d9cf`
- License: GNU General Public License v3.0 (`GPL-3.0`)

BlackHole remains an optional loopback-device choice. `scripts/build-driver.sh` and `third_party/blackhole/device-usb.patch` build the independent `BuddyMic2ch.driver` from pinned BlackHole source. The driver uses USB transport, its own CFPlugIn factory UUID, bundle identifier and BuddyMic UID. It does not replace an installed BlackHole or MiRemoteV driver. The release PKG installs both the app and BuddyMic2ch; matching patched driver source is included in the release source archive.

## MiRemoteVoice

- Project: `VincentKingHsu/MiRemoteVoice`
- Source: <https://github.com/VincentKingHsu/MiRemoteVoice>
- Reference release: `v1.0.0-beta.1`
- Application license: MIT

The Doubao compatibility design is informed by MiRemoteVoice: a side-by-side BlackHole-derived device reports its actual audio Device as USB transport so Doubao can enumerate it. This fork reimplements that idea as a pinned, source-built BlackHole patch instead of reusing MiRemoteVoice's version-specific binary replacement script.

## RC003 product photo

The upstream project included an RC003 product photo. That photo and upstream proprietary app artwork are not included in Voice Input Buddy. The button mapping interface uses the original `BuddyRemoteIllustration.png` schematic.

## Setup guide screenshots

The 16 light/dark setup screenshots in `Resources/Onboarding` are carried over from remote-mic-app (SayAll contributors), under the upstream project license. They illustrate third-party and macOS settings; depicted interface copyrights and trademarks remain with their respective owners. The upstream proprietary app logo and remote product photo are not bundled. `BuddyRemoteIllustration.png` is an original schematic generated by `scripts/generate-remote-illustration.swift`.
