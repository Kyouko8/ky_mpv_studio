# MPV Studio

#### Cross-platform audio player built on mpv_audio_kit.

[![](https://img.shields.io/badge/built%20with-mpv__audio__kit-orange.svg?style=for-the-badge)](https://pub.dev/packages/mpv_audio_kit)
[![](https://img.shields.io/badge/Flutter-3.27+-blue.svg?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![](https://img.shields.io/github/stars/ales-drnz/mpv_studio?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ales-drnz/mpv_studio)
[![](https://img.shields.io/discord/1485588004029333516?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/g2Qf4Mq9MP)
[![](https://img.shields.io/badge/Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white)](https://www.patreon.com/cw/ales_drnz)
[![](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/ales.drnz)

<table>
<tr>
<td valign="middle" width="90"><img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/mpv_studio.png" width="70" alt="logo"></td>
<td valign="middle"><b>MPV Studio</b> is the standalone reference client for the <a href="https://pub.dev/packages/mpv_audio_kit"><code>mpv_audio_kit</code></a> engine: a cross-platform audio player with a full DSP rack, real-time visualizers, Jellyfin and Plex streaming, and a built-in mpv command console.</td>
</tr>
</table>

---

## Quick start

MPV Studio depends on the `mpv_audio_kit` package via a local path, so clone the two **side by side**:

```bash
git clone https://github.com/ales-drnz/mpv_studio
git clone https://github.com/ales-drnz/mpv_audio_kit   # sibling (path dependency)

cd mpv_studio
flutter pub get
flutter run                # pick a device
```

See [§7. Building from source](#7-building-from-source) for per-platform requirements.

---

## Platforms

One codebase, the same five platforms the engine supports:

| Platform  | Minimum | Architectures |
| :--- | :--- | :--- |
| **Android** | 7.0 (SDK 24) | arm64-v8a, armeabi-v7a, x86_64 |
| **iOS** | 15.0 | arm64, x86_64 |
| **macOS** | 12.0 | arm64, x86_64 |
| **Windows**| 10 | arm64, x86_64 |
| **Linux** | Ubuntu 24.04 | aarch64, x86_64 |

The interface adapts to the device: a sidebar on desktop, a tab bar on mobile, over a dark theme with a `#91D8F9` accent.

---

## Contents

*   [Visuals](#visuals)
*   [Quick start](#quick-start)
*   [Guide](#guide)
    <details>
    <summary><a href="#1-playback"><b>1. Playback</b></a></summary>

    * [1.1 Now playing](#11-now-playing)
    * [1.2 Visualizers](#12-visualizers)

    </details>

    <details>
    <summary><a href="#2-queue"><b>2. Queue</b></a></summary>
    </details>

    <details>
    <summary><a href="#3-streaming"><b>3. Streaming</b></a></summary>

    * [3.1 Jellyfin](#31-jellyfin)
    * [3.2 Plex](#32-plex)

    </details>

    <details>
    <summary><a href="#4-effects"><b>4. Effects</b></a></summary>

    * [4.1 The DSP rack](#41-the-dsp-rack)
    * [4.2 Interactive controls](#42-interactive-controls)

    </details>

    <details>
    <summary><a href="#5-settings"><b>5. Settings</b></a></summary>
    </details>

    <details>
    <summary><a href="#6-console"><b>6. Console</b></a></summary>
    </details>

    <details>
    <summary><a href="#7-building-from-source"><b>7. Building from source</b></a></summary>

    * [7.1 Requirements](#71-requirements)
    * [7.2 Run](#72-run)

    </details>
*   [Project background](#project-background)

---

## Visuals

The six sections of the app: a sidebar on desktop, a tab bar on mobile.

#### Playback

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/playback.gif" width="100%">
</p>

#### Queue

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/queue.gif" width="100%">
</p>

#### Stream

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/stream.gif" width="100%">
</p>

#### Effects

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/effects.gif" width="100%">
</p>

#### Settings

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/settings.gif" width="100%">
</p>

#### Console

<p align="center">
  <img src="https://raw.githubusercontent.com/ales-drnz/mpv_studio/main/imgs/console.gif" width="100%">
</p>

---

## Guide

### 1. Playback

The home screen: cover art, metadata and transport bound to mpv_audio_kit's play-pause **intent**, so the controls never flicker while you scrub.

#### 1.1 Now playing

Cover art, track info, a scrubbable seekbar, and a volume control, driven entirely by the engine's reactive streams.

#### 1.2 Visualizers

Three real-time meters fed by mpv_audio_kit's FFT and PCM streams: a log-spaced **spectrum** curve, a **VU** meter, and a progressive **waveform** seekbar that fills in as network tracks decode.

---

### 2. Queue

A reorderable playlist with drag-and-drop, gapless transitions, and a determinate prefetch indicator for the next track.

---

### 3. Streaming

Browse and play from self-hosted media servers. Each library tab pages lazily as you scroll.

#### 3.1 Jellyfin

Connects to a Jellyfin server and streams its libraries directly (HLS), seeking through transcoded sources.

#### 3.2 Plex

Resolves Plex transcode URLs lazily through an `on_load` hook and a `/decision` session manager, and reports playback progress back to the server.

---

### 4. Effects

A live DSP rack on top of mpv_audio_kit's `AudioEffects` bundle: toggle and tune effects and hear the change immediately.

#### 4.1 The DSP rack

18-band graphic EQ, compressor, loudness normalization, headphone crossfeed, crystalizer, stereo tools, bass and treble, and more.

#### 4.2 Interactive controls

Each effect renders its own live diagram (a compressor curve, a frequency response curve, a crossfeed diagram, a stereo scope, a loudness gauge), driven by per-filter PCM taps so the visualization tracks the actual signal.

---

### 5. Settings

Every mpv subsystem grouped into one screen: audio engine and output, audio track, A-B loop, chapters, demuxer cache, hooks, OS media session, and streaming. Choices persist across launches.

---

### 6. Console

A built-in mpv command console with a command catalog, autocomplete suggestions, and the live engine log, captured from boot, so it's never empty when you open it.

---

### 7. Building from source

#### 7.1 Requirements

- **Flutter** 3.27 or newer (Dart `^3.6.0`).
- The **`mpv_audio_kit`** package cloned **next to** this repo (the `pubspec.yaml` points at `../mpv_audio_kit`).
- The native toolchain for your target platform (Xcode for Apple, Android SDK and NDK for Android, the desktop build tools for Linux and Windows).

#### 7.2 Run

```bash
flutter pub get
flutter run -d macos        # or windows, linux, <android-device>, <ios-device>
```

To build a release artifact, use the standard `flutter build <platform>`.

---

## Project background

The entire app (the adaptive shell, the DSP rack and its visualizers, the Jellyfin and Plex streaming layer, and the mpv console) was implemented through the use of Claude Code.

---

*Developed by Alessandro Di Ronza*
