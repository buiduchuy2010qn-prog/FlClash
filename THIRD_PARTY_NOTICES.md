# Third-Party Notices & Open-Source Component Inventory

This repository is distributed under the **GNU General Public License v3.0** ([LICENSE](LICENSE)) and incorporates or depends on the following open-source components verified in this codebase. Each component remains subject to its respective license terms and copyright notices.

| Component | Path / Source | License | Attribution / Notes |
| --- | --- | --- | --- |
| **FlClash (Upstream)** | [`chen08209/FlClash`](https://github.com/chen08209/FlClash) | GNU GPL-3.0 | See verbatim [LICENSE](LICENSE) (674 lines) |
| **mihomo / Clash.Meta Core** | [`core/Clash.Meta`](core/Clash.Meta) (`5b453f80dbcee6b3ecfb0415bcace24a48c88707`) | GNU GPL-3.0 | See [core/Clash.Meta/LICENSE](core/Clash.Meta/LICENSE); upstream [`MetaCubeX/mihomo`](https://github.com/MetaCubeX/mihomo) / [`chen08209/Clash.Meta`](https://github.com/chen08209/Clash.Meta) |
| **prism_ui Plugin** | [`plugins/prism_ui`](plugins/prism_ui) | GNU GPL-3.0 | See [plugins/prism_ui/LICENSE](plugins/prism_ui/LICENSE) |
| **code_forge Plugin** | [`plugins/code_forge`](plugins/code_forge) | MIT License | `Copyright (c) 2025 FlClash`, `Copyright (c) 2025 Athul A S`; see [plugins/code_forge/LICENSE](plugins/code_forge/LICENSE) |
| **dynamic_color Plugin** | [`plugins/dynamic_color`](plugins/dynamic_color) | Apache License 2.0 | See [plugins/dynamic_color/LICENSE](plugins/dynamic_color/LICENSE) |
| **rust_api Native Bridge** | [`plugins/rust_api`](plugins/rust_api) | GNU GPL-3.0 (repository component) | Part of this GPL-3.0 work; links `flutter_rust_bridge` (MIT) and `rquickjs` / QuickJS (MIT) |
| **Dart QR Matrix Renderer** | [`lib/ui/qr_matrix.dart`](lib/ui/qr_matrix.dart) | BSD-3-Clause | `Copyright 2014, the Dart QR project authors. All rights reserved.` |
| **Flutter SDK & Go Standard Library** | External build toolchains | BSD-3-Clause | Standard runtime and tooling libraries |

## GPL-3.0 Compatibility Notice
* Per GNU GPL v3.0, all MIT, Apache-2.0, and BSD-3-Clause notices embedded in the files above are preserved intact alongside the repository's GNU GPL v3.0 license ([LICENSE](LICENSE)) and fork modification notice ([NOTICE.md](NOTICE.md)).
* For complete lockfile and build dependency metadata, see [pubspec.yaml](pubspec.yaml) and `core/go.mod`.
