# Legal Notice & GNU GPL-3.0 Modification Statement (FlClash)

## English Notice (GNU GPL v3.0 Sections 4, 5, 6, 15 & 16)

### 1. Upstream Attribution & Third-Party Licenses
* **Upstream Project:** **[chen08209/FlClash](https://github.com/chen08209/FlClash)** (licensed under GNU GPL v3.0). Original copyright notices are preserved verbatim.
* **Core Engine:** **[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)** and **[chen08209/Clash.Meta](https://github.com/chen08209/Clash.Meta)** (licensed under GNU GPL v3.0, pinned submodule commit `5b453f80dbcee6b3ecfb0415bcace24a48c88707`).
* **Bundled Dependencies & Plugins:** **Flutter** (BSD-3-Clause), **Go standard library** (BSD-3-Clause), and additional bundled libraries listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### 2. Prominent Notice of Modification (GPL v3.0 Section 5(a) & 5(b))
* **Modified Fork (`v0.9.4` – `v0.9.15`, November 2026):** **Copyright (C) 2026 Bùi Đức Huy (`@buiduchuy2010qn-prog`)** — [buiduchuy2010qn-prog/FlClash](https://github.com/buiduchuy2010qn-prog/FlClash).
* Pursuant to **GNU GPL v3.0 Section 5(a)**, this notice states prominently that this repository is a modified version of [chen08209/FlClash](https://github.com/chen08209/FlClash) introducing Vietnamese localization, mobile background/battery/thermal stability improvements, push notification & widget reliability fixes, platform-filtered OTA verification, and build maintenance in November 2026. Dated modification summaries are recorded in [CHANGELOG.md](CHANGELOG.md).
* Pursuant to **GNU GPL v3.0 Section 5(b) & 5(c)**, the entire modified work is licensed under the GNU General Public License v3.0 ([LICENSE](LICENSE)), with no additional restrictions imposed beyond those explicitly permitted by GPL v3.0.

### 3. In-App Legal Notices & Corresponding Source (GPL v3.0 Sections 5(d) & 6)
* **Interactive Legal Notices (Section 5(d)):** All Appropriate Legal Notices, license disclosures (`GPL-3.0`), and the disclaimer screen are preserved inside the application UI ([about.dart](lib/views/about.dart) and [disclaimer.dart](lib/views/disclaimer.dart)).
* **Corresponding Source (Section 6):** Complete Corresponding Source for every binary release—including git release tags, the pinned `core/Clash.Meta` submodule commit (`5b453f80dbcee6b3ecfb0415bcace24a48c88707`), packaging scripts ([tool/package.dart](tool/package.dart)), and release verification files (`SHA256SUMS` and `manifest.json`)—is publicly available in this repository at zero cost.

### 4. Disclaimer of Warranty & Non-Affiliation (GPL v3.0 Sections 15 & 16)
* **NO WARRANTY:** Distributed **"AS IS"**, WITHOUT WARRANTY OF ANY KIND, either express or implied, as detailed in **Sections 15 & 16** of [LICENSE](LICENSE).
* **Non-Affiliation & Trademarks:** This fork is maintained independently by `@buiduchuy2010qn-prog` and is **not affiliated with, endorsed by, or sponsored by** `@chen08209`, MetaCubeX, Google, or any upstream maintainers. Upstream original authors are not responsible for any issues introduced in modified or distributed builds of this fork.

### 5. Acceptable Use, Lawful Scope & Rights-Holder Contact
* This software is strictly a general-purpose, open-source network proxy client interface. It bundles no hosted proxy/VPN servers, no commercial subscriptions, no account credentials, and no billing circumvention features.
* Users are solely responsible for configuring lawful, authorized endpoints and complying with applicable local laws and network terms of service.
* **Copyright, License & Trademark Inquiries:** Upstream maintainers or rights holders may contact `@buiduchuy2010qn-prog` privately via GitHub Security Advisories / Private Vulnerability Reporting as described in [SECURITY.md](SECURITY.md) for prompt review and resolution.

---

## Thông Báo Bản Quyền & Sửa Đổi (Tiếng Việt — GNU GPL v3.0)

* **Dự án gốc & Nhân lõi:** Kế thừa từ **[chen08209/FlClash](https://github.com/chen08209/FlClash)** (GNU GPL v3.0) và nhân lõi **[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)** / **[chen08209/Clash.Meta](https://github.com/chen08209/Clash.Meta)** (GNU GPL v3.0, mã commit submodule `5b453f80dbcee6b3ecfb0415bcace24a48c88707`), sử dụng **Flutter** (BSD-3-Clause) cùng các thành phần bên thứ ba liệt kê tại [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
* **Bản phân nhánh đã sửa đổi (`v0.9.4` – `v0.9.15`, 11/2026 — Mục 5(a) & 5(b) GPL v3.0):** **Copyright (C) 2026 Bùi Đức Huy (`@buiduchuy2010qn-prog`)**. Bản phân nhánh bổ sung bản địa hóa Tiếng Việt, tối ưu ổn định chạy nền/pin trên thiết bị di động, sửa lỗi thông báo đẩy & widget khi bật VPN, lọc cập nhật OTA theo nền tảng và tài liệu tuân thủ bản quyền; toàn bộ chi tiết thay đổi theo ngày được ghi tại [CHANGELOG.md](CHANGELOG.md). Toàn bộ tác phẩm tiếp tục được phát hành theo **[GNU GPL-3.0](LICENSE)** và giữ nguyên toàn vẹn thông báo bản quyền tác giả gốc.
* **Thông báo pháp lý trong ứng dụng & Mã nguồn tương ứng (Mục 5(d) & 6 GPL v3.0):** Ứng dụng giữ nguyên màn hình Tuyên bố miễn trừ trách nhiệm & Giấy phép ([about.dart](lib/views/about.dart), [disclaimer.dart](lib/views/disclaimer.dart)). Toàn bộ mã nguồn tương ứng (bao gồm tag phát hành, commit submodule `core/Clash.Meta`, script đóng gói [tool/package.dart](tool/package.dart), tệp kiểm tra `SHA256SUMS` và `manifest.json`) được công khai đầy đủ trên kho lưu trữ này.
* **Miễn trừ bảo hành, Không liên kết & Mục đích sử dụng hợp pháp (Mục 15 & 16 GPL v3.0):** Phần mềm được cung cấp nguyên trạng (**"AS IS"**), không có bất kỳ bảo hành nào. Đây là bản phân nhánh độc lập, không liên kết hay đại diện cho tác giả gốc `@chen08209`, MetaCubeX hoặc các bên thứ ba. Ứng dụng chỉ là công cụ khách (client) định tuyến mạng đa mục đích hợp pháp; không cung cấp máy chủ, gói dịch vụ, thông tin đăng nhập hay công cụ can thiệp cơ chế tính cước viễn thông. Chủ sở hữu bản quyền/nhãn hiệu có thể liên hệ riêng tư qua kênh hướng dẫn trong [SECURITY.md](SECURITY.md) để được xử lý nhanh chóng.
