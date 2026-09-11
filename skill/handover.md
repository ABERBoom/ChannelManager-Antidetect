# Handover Document - Channel Manager

## 1. Tổng quan dự án

**Channel Manager** là ứng dụng Windows desktop để quản lý nhiều profile trình duyệt portable (Firefox, Chrome), phục vụ việc quản lý nhiều kênh/tài khoản cùng lúc.

### Vấn đề cần giải quyết
- Quản lý nhiều trình duyệt portable khó khăn, phải mở từng thư mục
- Các trình duyệt cùng loại bị gộp trên taskbar, khó phân biệt
- Không có cách quản lý tập trung, thêm/xóa profile dễ dàng

### Giải pháp
- App web-based chạy local (PowerShell HTTP server)
- Giao diện quản lý tập trung giống OmniLogin
- Tự động tách taskbar icon + gán icon tùy chỉnh
- Quản lý Proxy độc lập cho từng profile (HTTP/SOCKS5)
- Bảo mật WebRTC Leak Protection cấp độ Antidetect (JS Injection)
- Tạo profile mới chỉ cần 1 click (tự extract từ installer)

---

## 2. Yêu cầu hệ thống

| Yêu cầu | Chi tiết |
|----------|----------|
| OS | Windows 10/11 (64-bit) |
| PowerShell | 5.1+ (có sẵn trên Windows 10+) |
| .NET Framework | 4.5+ (có sẵn trên Windows 10+) |
| RAM | >= 4GB (mỗi browser ~300MB) |
| Disk | >= 2GB (mỗi Firefox portable ~500MB) |
| Port | 8777 (có thể thay đổi trong settings) |

> **Không cần cài thêm bất kỳ phần mềm nào** - App sử dụng hoàn toàn các component có sẵn trên Windows.

---

## 3. Cài đặt & Triển khai

### 3.1 Cài đặt lần đầu
```bash
# 1. Copy toàn bộ thư mục ChannelManager vào vị trí mong muốn
# 2. Đặt file installer vào thư mục installers/
#    - FirefoxPortable_*.paf.exe
#    - GoogleChromePortable_*.paf.exe
# 3. Double-click ChannelManager.bat để khởi động
```

### 3.2 Cấu trúc thư mục sau cài đặt
```
ChannelManager/
├── ChannelManager.bat     ← Double-click để chạy
├── server.ps1             ← Backend server
├── profiles.json          ← Dữ liệu profiles
├── webapp/                ← Frontend files
├── profiles/              ← Browser data (tự tạo)
├── icons/                 ← Icon files (tự tạo)
├── installers/            ← Đặt file .paf.exe vào đây
└── skill/                 ← Tài liệu
```

---

## 4. Hướng dẫn sử dụng

### 4.1 Khởi động app
1. Double-click `ChannelManager.bat`
2. App sẽ mở trình duyệt mặc định tại `http://localhost:8777`
3. Giao diện quản lý sẽ hiển thị

### 4.2 Tạo profile mới
1. Click nút **"+ Tạo Profile"** trên toolbar
2. Nhập tên profile (ví dụ: "Kenh1 - Marketing")
3. Chọn trình duyệt (Firefox hoặc Chrome)
4. Chọn màu badge hoặc upload icon tùy chỉnh
5. Click **"Tạo Profile"**
6. Chờ vài giây để app extract browser portable

### 4.3 Mở trình duyệt
1. Click nút **▶ Play** trên hàng profile
2. Trình duyệt sẽ mở với icon riêng trên taskbar
3. Status chuyển sang **🟢 Đang chạy**

### 4.4 Đóng trình duyệt
1. Click nút **⏹ Stop** trên hàng profile
2. Hoặc đóng trình duyệt bình thường

### 4.5 Xóa profile
1. Chọn checkbox của profile cần xóa
2. Click nút **"Xóa"** trên toolbar
3. Xác nhận xóa trong dialog

---

## 5. Kiến trúc kỹ thuật (tóm tắt)

### Frontend
- **Single-page HTML/CSS/JS** - không framework, không build step
- Giao tiếp với backend qua REST API (fetch)
- Design system với CSS Custom Properties

### Backend
- **PowerShell HTTP Server** (`System.Net.HttpListener`)
- REST API endpoints cho CRUD profiles + browser control
- C# inline code cho Windows API (taskbar icon manipulation)

### Taskbar Separation
- Mỗi profile có **executable riêng** (firefox_p001.exe, firefox_p002.exe...)
- Dùng `SHGetPropertyStoreForWindow` để set **AppUserModelID** + **icon** trên window
- Background monitor giám sát và re-apply icon

---

## 6. Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| App không mở | Kiểm tra port 8777, chạy `netstat -an \| findstr 8777` |
| Browser không tách trên taskbar | Đóng hết browser, mở lại qua app |
| WebRTC báo N/A khi không dùng Proxy | Khởi động lại ChannelManager, mở lại trình duyệt |
| IP Proxy không nhận diện đúng | Kiểm tra ping/latency của Proxy, định dạng IP:Port |
| Lỗi "Firefox already running" | Click "Close Firefox" rồi thử lại |

---

## 7. Bảo trì

### Backup
- Backup file `profiles.json` và thư mục `profiles/` để giữ toàn bộ dữ liệu
- Thư mục `icons/` có thể regenerate từ settings trong profiles.json

### Cập nhật browser
- Download file `.paf.exe` mới vào `installers/`
- Cập nhật path trong Settings
- Các profile mới sẽ dùng version mới
- Profile cũ giữ nguyên version (hoặc có thể update thủ công)

### Mở rộng
- Thêm loại browser mới: Thêm installer + cập nhật logic extract trong server.ps1
- Thêm tính năng: Sửa frontend (webapp/) + backend (server.ps1)

---

## 8. Liên hệ & Tham khảo

- **Tài liệu UI/UX**: [ui-ux-design.md](./ui-ux-design.md)
- **Kiến trúc**: [architecture.md](./architecture.md)
- **Code conventions**: [code-conventions.md](./code-conventions.md)
- **PortableApps docs**: https://portableapps.com/development

---

## 9. Bài học kinh nghiệm & Critical Bugs đã xử lý

### Lỗi WebRTC hiển thị N/A hoặc rò rỉ IP thật khi dùng Proxy
**Vấn đề:** 
Khi dùng proxy, WebRTC báo N/A (không có IP) hoặc rò rỉ IP thật. Khi tắt proxy, WebRTC báo N/A thay vì IP thật, gây red flag nghiêm trọng về trust score trên các trang check IP (như ipfighter).

**Nguyên nhân gốc rễ (Root Causes):**
1. **Firefox tích tụ file cấu hình (user.js):** 
   - `server.ps1` dùng cơ chế đọc và ghi nối thêm (append) vào file `user.js` của profile, dẫn đến rác cấu hình bị lặp lại.
2. **Thuộc tính ngầm của Firefox (relay_only):**
   - Khi Firefox dùng proxy, trình duyệt tự động ghi thêm thuộc tính `media.peerconnection.ice.relay_only = true` vào file `prefs.js`. Khi tắt proxy, thuộc tính này vẫn tồn tại chặn toàn bộ ICE candidates.
3. **Race Condition trong Extension của Firefox:**
   - Script `content.js` tải `spoof.js` thông qua `script.src = ...`, quá trình này là bất đồng bộ (asynchronous). Trang web có thể khởi tạo WebRTC trước khi script spoof kịp chạy, dẫn đến rò rỉ IP.
4. **Chrome/Antidetect từ chối extension nội bộ (Path Quoting Bug):**
   - Lỗi phát sinh do tham số `--load-extension` và `--disable-extensions-except` khi truyền vào PowerShell bằng mảng `ArgumentList` mà có chứa khoảng trắng (VD: `E:\TOOL\Source Code\...`) nhưng không được bọc trong cặp ngoặc kép `""`. PowerShell sẽ cắt chuỗi sai, làm Chrome không hiểu đường dẫn và extension WebRTC Guard không được load.
5. **Lỗi hàm mã hóa trong Extension Firefox:**
   - Script `content.js` sử dụng `escape()` để giải mã chuỗi Base64. Hàm này cũ và đôi khi hoạt động không ổn định với UTF-8 trên Firefox, dẫn tới lỗi script crash không thể thực thi. Thêm vào đó, Firefox 115+ có cơ chế ngầm tự động xóa các file `.xpi` không có chữ ký khi đưa vào thư mục extensions.

**Giải pháp (Fixes) đã áp dụng:**
- **Sửa lỗi Firefox Race Condition & Cài đặt Extension**:
  - **Sửa lỗi Race Condition (Vòng lặp Retry):** Khác với Chrome (có thể ghi cứng IP thẳng vào code trước khi chạy vì dùng Unpacked Extension), Firefox yêu cầu file `.xpi` tĩnh và có chữ ký điện tử (Signature) từ AMO, không thể sửa đổi file. Do đó, Firefox phải gọi API (`http://webrtc.local.guard/ip`) lúc khởi động để lấy IP. Lỗi xảy ra do Firefox lấy IP ngay mili-giây đầu tiên khi mạng/proxy chưa kết nối xong. **Khắc phục:** Thêm vòng lặp Retry (thử lại liên tục 10 lần) vào `fetchProxyIp()` trong `background.js` kết hợp với `Promise` trong API `webRequest.onBeforeRequest.addListener(..., ["blocking"])`. Trình duyệt sẽ "đóng băng" quá trình tải trang cho đến khi lấy được Proxy IP thành công.
  - **Sửa lỗi Parse Encoding:** Sử dụng `new TextDecoder().decode(Uint8Array.from(atob('...')))` để nhúng mã Base64 đồng bộ và an toàn.
  - **Sửa lỗi cài đặt Extension (Sideloading):** Giữ nguyên phương pháp tự động cài đặt qua thư mục `extensions/` với lưu ý tuyệt đối: Tên file phải khớp chính xác 100% với ID của extension (`webrtc-guard-dynamic@channelmanager.local.xpi`) và file phải được tải trực tiếp từ AMO (Signed file đuôi `.xpi`, nghiêm cấm tự đổi đuôi file `.zip` vì sẽ làm hỏng chữ ký khiến Firefox tự xóa file).
- **Sửa lỗi Chrome Extension qua CLI Path Quoting**:
  - Khôi phục cơ chế `--load-extension` thay vì tiêm qua CDP. Bọc cẩn thận tất cả các đường dẫn chứa khoảng trắng vào cặp ngoặc kép `""` (`--load-extension="{0}"`) trước khi truyền qua `Start-Process`. Điều này đảm bảo Chrome load extension WebRTC ổn định 100%.
- **Quản lý cấu hình Firefox an toàn**:
  - Ghi lại (rewrite) hoàn toàn file `user.js` từ đầu mỗi lần launch profile.
  - Bổ sung lệnh reset thuộc tính ngầm `relay_only` về `false` và dùng regex dọn sạch `prefs.js` trước khi khởi động.
  - Chú ý: Nếu dùng bản build Firefox gốc, cần chú ý Firefox có thể chủ động xoá `.xpi` vì thiếu chữ ký. Có thể phải dùng bản Developer Edition hoặc ESR tuỳ chỉnh.

**Quy tắc rút ra (Lessons Learned):**
- File cấu hình của trình duyệt (`user.js`, `Preferences`) cần được kiểm soát trạng thái hoàn toàn tĩnh (declarative reset), không được dùng phương pháp nối/sửa thêm (imperative).
- Bất kỳ script tiêm nhiễm nào ảnh hưởng đến WebRTC hoặc Fingerprint **bắt buộc** phải thực thi đồng bộ (synchronous). Tuyệt đối không dùng `fetch` hay `script.src` bên trong content script để tránh race conditions.
- Không nên phụ thuộc hoàn toàn vào hệ thống extension của trình duyệt khi build hệ thống antidetect (vì các bản build khác nhau có chính sách chặn extension). Sử dụng CDP injection là cách can thiệp sâu, ổn định và không thể bị chặn bởi browser policies.

---

## 10. Lệnh Cấm Tuyệt Đối (DO NOT TOUCH)

> [!CAUTION]
> **LUỒNG HOẠT ĐỘNG CỦA CHROME ĐÃ ỔN ĐỊNH 100%. NGHIÊM CẤM CHỈNH SỬA!**
> Hiện tại, logic giả mạo WebRTC và khởi chạy cấu hình proxy của **Chrome** (bao gồm CDP Injection, Unpacked Extension, các tham số dòng lệnh) trong file `server.ps1` và thư mục `webrtc-guard-chrome` đã hoàn thiện và hoạt động cực kỳ mượt mà. 
> 
> **Mọi hành động can thiệp, chỉnh sửa, hoặc "tối ưu hóa" vào đoạn mã liên quan đến Chrome đều BỊ CẤM HOÀN TOÀN.** Bất kỳ thay đổi nào (như thêm cờ log, đổi policy WebRTC) cũng có thể dẫn đến việc phá vỡ WebRTC Guard, làm lộ IP thật, hoặc sinh ra các cửa sổ console đen bất thường. KHÔNG ĐƯỢC PHÉP CHẠM VÀO!
