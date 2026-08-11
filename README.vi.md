# Anime Expeditions Ultimate

**Ngôn ngữ:** [English](./README.md) | **Tiếng Việt**

[![Price](https://img.shields.io/badge/price-free-22c55e)](#miễn-phí--mã-nguồn-mở)
[![Source](https://img.shields.io/badge/source-open-3b82f6)](#miễn-phí--mã-nguồn-mở)
[![Language](https://img.shields.io/badge/language-Luau-00a2ff)](https://luau.org/)
[![License](https://img.shields.io/badge/license-MIT-f59e0b)](./LICENSE)

**Anime Expeditions Ultimate** là script Luau miễn phí và mã nguồn mở dành cho Anime Expeditions trên Roblox. Dự án tập trung vào automation, macro và quản lý nhiều chế độ chơi trong một giao diện duy nhất.

Script không có key system, không có paywall và không thu phí người dùng.

> Dự án do cộng đồng phát triển, không liên kết hoặc được chứng thực bởi Roblox hay nhà phát triển Anime Expeditions. Hãy tự chịu trách nhiệm khi sử dụng phần mềm bên thứ ba và tuân thủ điều khoản của nền tảng.

## Tính năng nổi bật

- Auto Join Map với lựa chọn mode, world, difficulty và act.
- Macro In-Game: ghi, lưu, tối ưu và tự chạy macro theo từng map.
- Auto Story, Daily/Weekly Quest và Challenge với macro riêng theo map.
- Auto Event cho Guess That Unit, Boss Bounty và Dragon's Wish.
- Auto Summon theo banner, unit mục tiêu và số lượt quay.
- Auto Shop và Auto Craft trong lobby.
- Auto Load Team riêng cho từng map.
- Expedition automation: Fuel, Training Grounds, Research Lab, Building Rewards và Geode.
- Auto Encounter trong Expedition cho các lựa chọn hội thoại được hỗ trợ.
- Auto Stat Roll với bộ lọc rarity, stat và grade.
- Auto Claim quest, battlepass, calendar, milestone, index và achievement.
- Auto Redeem Code từ API cộng đồng.
- Discord Webhook cho summon, kết quả map và stat roll.
- Config save/load cùng hệ thống chia sẻ macro và config.
- Tích hợp giao diện tiếng Anh và tiếng Việt, mặc định sử dụng tiếng Anh.
- Anti-AFK, FPS cap, Fix Lag, Hide Player Names và hỗ trợ nút UI trên mobile.
- KickBlock được tích hợp ngay từ lúc script khởi động.

## Cài đặt

Chạy đoạn loader sau trong môi trường Luau tương thích khi đã vào game:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Truyem/Anime-Expeditions/refs/heads/main/AnimeExpeditionsUltimate.lua"))()
```

## Yêu cầu

- Môi trường thực thi hỗ trợ Luau và `loadstring`.
- HTTP request qua `request`, `http_request` hoặc `syn.request`.
- File APIs như `readfile`, `writefile`, `isfile` và `makefolder` để lưu UI/config.
- Một số tính năng nâng cao cần `getgc`, `getconnections`, `hookfunction`, `hookmetamethod` và debug APIs.
- Kết nối mạng để tải Fluent UI, SaveManager, code API và dịch vụ chia sẻ.

Khả năng tương thích phụ thuộc vào môi trường thực thi. Nếu thiếu API, một số tính năng có thể không hoạt động dù giao diện vẫn tải được.

## Sử dụng cơ bản

1. Chạy script trong Anime Expeditions.
2. Nhấn `LeftShift` để mở hoặc thu nhỏ giao diện trên PC.
3. Chọn tab phù hợp và cấu hình map, team hoặc macro trước khi bật automation.
4. Đổi `Language` trong Settings rồi chạy lại script nếu muốn dùng tiếng Việt.
5. Kiểm tra kỹ webhook URL và các tùy chọn Auto Leave trước khi AFK.
6. Lưu config sau khi hoàn tất thiết lập.

Config và cache giao diện được lưu trong thư mục `AnimeExpeditions` của workspace executor.

## Miễn phí & Mã nguồn mở

Toàn bộ mã nguồn chính nằm trong [`AnimeExpeditionsUltimate.lua`](./AnimeExpeditionsUltimate.lua) và được công khai miễn phí để cộng đồng đọc, kiểm tra, cải tiến và đóng góp.

- Không mua bán hoặc trả phí để nhận script này.
- Không tin các bản reupload yêu cầu key hoặc thanh toán.
- Nên lấy phiên bản mới nhất trực tiếp từ repository GitHub chính thức.
- Khi chia sẻ hoặc fork, vui lòng giữ copyright notice và license notice.

Dự án được phát hành theo [MIT License](./LICENSE).

## Đóng góp

Pull request và báo lỗi đều được hoan nghênh.

1. Fork repository.
2. Tạo branch cho thay đổi của bạn.
3. Giữ thay đổi nhỏ, rõ ràng và không thêm code bị obfuscate.
4. Kiểm tra cú pháp Luau trước khi gửi pull request.
5. Mô tả hành vi đã thay đổi và cách bạn kiểm tra nó.

Khi báo lỗi, hãy cung cấp mode/map, thao tác gây lỗi, log console liên quan và tên môi trường thực thi. Không đăng webhook URL, token hoặc dữ liệu cá nhân.

## Credits

- **Truyem789**: tác giả Anime Expeditions Ultimate.
- [Fluent](https://github.com/dawid-scripts/Fluent): thư viện giao diện và SaveManager.
- Cộng đồng Anime Expeditions: chia sẻ thông tin, macro và phản hồi.

## Disclaimer

Phần mềm được cung cấp nguyên trạng, không bảo đảm luôn tương thích sau mỗi bản cập nhật game. Tác giả không chịu trách nhiệm cho mất dữ liệu, gián đoạn tài khoản hoặc hậu quả phát sinh từ việc sử dụng script.
