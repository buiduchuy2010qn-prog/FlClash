<div align="center">

<img src="assets/images/icon.png" alt="FlClash" width="88">

# FlClash

A multi-platform proxy client based on ClashMeta. Simple to use, open source and ad-free.

> **License, Attribution & Acceptable Use:** This repository is an independent GNU GPL-3.0 modified fork of [chen08209/FlClash](https://github.com/chen08209/FlClash), built on the [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) core and Flutter. Provided **AS IS** under [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) solely as a general-purpose open-source network client for lawful user-configured endpoints; it includes no proxy servers or subscriptions. See [CHANGELOG.md](CHANGELOG.md) for fork modifications and [SECURITY.md](SECURITY.md) for security or rights-holder inquiries.

**English** · [简体中文](README_zh_CN.md)

[![Release](https://img.shields.io/github/v/release/chen08209/FlClash?style=flat-square&label=release)](https://github.com/chen08209/FlClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/chen08209/FlClash/total?style=flat-square&logo=github)](https://github.com/chen08209/FlClash/releases)
[![License](https://img.shields.io/github/license/chen08209/FlClash?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-channel-26A5E4?style=flat-square&logo=telegram&logoColor=white)](https://t.me/FlClash)

[Website](https://chen08209.github.io/FlClash) · [Download](#download) · [Changelog](CHANGELOG.md) · [Build from source](#build-from-source)

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="snapshots/preview-dark.png">
    <img alt="FlClash dashboard on a MacBook and a phone" src="snapshots/preview.png" width="92%">
  </picture>
</p>

## Features

- **One app for Android, Windows, macOS and Linux**, with x64 and ARM64 builds on the desktop.
- **mihomo (Clash.Meta) core** with rule routing, proxy groups, latency tests, system proxy and TUN mode.
- **Profiles** from a subscription link or a file, with a built-in editor, override scripts, and custom rules,
  proxies and proxy groups.
- **Live views** of connections, requests, DNS queries and logs.
- **Material You design with Apple-style interaction**: dynamic color, light and dark themes, continuous corners,
  sheets that snap between heights, and layouts that adapt from phones to desktops.
- **Backup and restore** through WebDAV or a local file.
- **Platform touches**: a Quick Settings tile, per-app proxy and Android TV support on Android; a tray menu and
  global hotkeys on the desktop.
- **Open source and ad-free**, licensed under GPL-3.0.

## Download

Get the latest build from [GitHub Releases](https://github.com/chen08209/FlClash/releases/latest), or open the
[website](https://chen08209.github.io/FlClash#download), which picks the right file for your device.

| Platform | Packages | Notes |
| --- | --- | --- |
| Android | APK for `arm64` (arm64-v8a), `armv7` (armeabi-v7a) and `amd64` (x86_64) | Most phones use `arm64`. Also on the F-Droid repository below. |
| Windows 10 and later | Installer (`.exe`) or portable `.zip`, for x64 and ARM64 | Pick ARM64 on Snapdragon and other ARM laptops. |
| macOS 12 and later | DMG for Apple Silicon and Intel | Also on Homebrew. |
| Linux | `.deb`, `.rpm` and AppImage, for x64 and ARM64 | See the tray note below. |

<p>
  <a href="https://chen08209.github.io/FlClash-fdroid-repo/repo?fingerprint=789D6D32668712EF7672F9E58DEEB15FBD6DCEEC5AE7A4371EA72F2AAE8A12FD"><img alt="Get it on F-Droid" src="snapshots/get-it-on-fdroid.svg" height="56"></a>
  <a href="https://github.com/chen08209/FlClash/releases/latest"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" height="56"></a>
</p>

**Homebrew**

```bash
brew tap chen08209/tap
brew install --cask flclash
```

**macOS first launch**

The app is not notarized, so macOS refuses to open it the first time. After dragging it to Applications, run
`xattr -dr com.apple.quarantine /Applications/FlClash*.app`, or choose Open Anyway under System Settings > Privacy &
Security. Later updates install from inside the app.

**Linux tray icon**

The tray icon is a StatusNotifierItem. KDE Plasma, XFCE and most panels show it as is; GNOME needs the
AppIndicator and KStatusNotifierItem Support extension.

**Unattended desktop**

FlClash starts the core only after the disclaimer is accepted. Where nobody can click it, such as a container, set
`FLCLASH_ACCEPT_DISCLAIMER=1` in the app's environment to accept it on first launch.

## Usage

**Import a profile from a link.** Opening a link in this form imports the subscription into FlClash. The `clashmeta://`
and `flclash://` schemes work the same way.

```text
clash://install-config?url=<URL-encoded subscription link>
```

**Automate on Android.** Tasker, MacroDroid and similar apps can start, stop or toggle the proxy by starting an
activity with one of these actions:

```text
com.follow.clash.action.START
com.follow.clash.action.STOP
com.follow.clash.action.TOGGLE
```

From a computer, the same works over adb:

```bash
adb shell am start -a com.follow.clash.action.TOGGLE
```

## Build from source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.50 (release builds use 3.50.1),
[Go](https://go.dev/dl/) 1.27 and [Rust](https://rustup.rs/) installed through rustup. Each platform builds on its own
host, except Android, which builds anywhere.

```bash
git clone --recursive https://github.com/chen08209/FlClash.git
cd FlClash
flutter pub get
dart run tool/package.dart android   # or windows, macos, linux
```

Packages land in `dist/`. The Go core and the Rust libraries are compiled as part of the Flutter build.

| Platform | Also needed |
| --- | --- |
| Android | Android SDK with the NDK. Add `--arch arm64` to build a single ABI. |
| Windows | GCC (MinGW-w64) for the core and [Inno Setup](https://jrsoftware.org/isinfo.php) 6 for the installer. |
| macOS | Xcode and Node.js. The script installs `appdmg` through npm. |
| Linux | Debian or Ubuntu. The script installs the build packages with apt and downloads `appimagetool`. |

Run `dart run tool/package.dart --help` for the remaining options, such as `--targets` to build only some package formats or `--dry-run` to list the files a run would write.

## Support

Starring the repository is the easiest way to support the project. Questions and announcements go to the
[Telegram channel](https://t.me/FlClash); bugs and feature requests go to
[GitHub Issues](https://github.com/chen08209/FlClash/issues).

<a href="https://star-history.com/#chen08209/FlClash&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=chen08209/FlClash&type=Date&theme=dark">
    <img alt="Star history" src="https://api.star-history.com/svg?repos=chen08209/FlClash&type=Date" width="640">
  </picture>
</a>

## License

FlClash and this modified fork are released under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE).

- **Compliance (GPL-3.0 Sections 4, 5 & 6):** All original copyright notices ([chen08209/FlClash](https://github.com/chen08209/FlClash), [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)) are preserved; fork modifications are documented in [NOTICE.md](NOTICE.md) and [CHANGELOG.md](CHANGELOG.md), and third-party component notices are detailed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Full corresponding source code is published alongside every release.
- **No Warranty & Acceptable Use (GPL-3.0 Sections 15 & 16):** Distributed **AS IS**, without warranty of any kind, solely as a general-purpose network client for lawful user-configured endpoints. For security or rights-holder inquiries, see [SECURITY.md](SECURITY.md).
