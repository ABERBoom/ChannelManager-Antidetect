# Antidetect Features & Network Security

Tài liệu này ghi lại các cơ chế ẩn danh, giả mạo mạng và chống rò rỉ (Leak Protection) cốt lõi của Channel Manager. Sự kết hợp giữa cấp độ OS (CLI flags) và cấp độ DOM (JS Injection) giúp trình duyệt vượt qua các hệ thống Antidetect kiểm duyệt gắt gao (như IPFighter).

## 1. Proxy Routing Management

Mỗi profile trình duyệt có khả năng định tuyến lưu lượng thông qua một proxy độc lập. Trạng thái proxy được lưu trực tiếp vào file cấu hình `profiles.json` và chỉ có hiệu lực ở phạm vi của profile đó.

### Cơ chế kích hoạt
- **Chrome/Chromium**: Sử dụng OS/Browser flags thông qua Command Line Interface khi khởi động:
  `--proxy-server="http://IP:PORT"` (hoặc `socks5://...`)
  `--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE IP"` (Chống DNS Leak)
- **Firefox**: Can thiệp trực tiếp vào file `prefs.js` trước khi khởi động:
  ```javascript
  user_pref("network.proxy.type", 1);
  user_pref("network.proxy.http", "IP");
  user_pref("network.proxy.http_port", PORT);
  // Cấu hình tương tự với socks5, ssl
  user_pref("network.proxy.socks_remote_dns", true); // Chống DNS Leak
  ```

---

## 2. WebRTC Leak Protection

WebRTC là kênh rò rỉ IP nguy hiểm nhất vì nó sử dụng giao thức UDP (không bị định tuyến qua proxy HTTP thông thường). Channel Manager xử lý WebRTC bằng giải pháp 2 lớp (Layer-2 Protection).

### Lớp 1: Browser Preferences (Ngăn chặn Native Leak)
- **Chrome**: Sử dụng chính sách `disable_non_proxied_udp`. Khi có proxy, trình duyệt bắt buộc phải chạy UDP qua proxy.
  Cấu hình trong `Preferences`:
  `webrtc.ip_handling_policy = "disable_non_proxied_udp"`
  *(Lưu ý: Mặc dù policy này chặn toàn bộ ICE candidates thật, lớp JS Injection sẽ tự tạo ra Fake Candidates để vượt qua bài test N/A).*
- **Firefox**: Cho phép ICE candidates tồn tại để Extension có thể hook và thay thế IP:
  - `media.peerconnection.ice.proxy_only_if_behind_proxy = false` (QUAN TRỌNG: phải là false, nếu true sẽ chặn toàn bộ ICE khi dùng HTTP relay → N/A)
  - `media.peerconnection.ice.default_address_only = true` (Chỉ expose 1 candidate, giảm attack surface)
  - `media.peerconnection.ice.no_host = false` (Cho phép host candidate để Extension hook)
  - `media.peerconnection.ice.obfuscate_host_addresses = false`

### Lớp 2: JS Document Injection (Ngụy trang DOM)
Để ngăn việc các website phát hiện WebRTC bị "N/A" (dấu hiệu của việc dùng proxy rẻ tiền hoặc cố tình tắt WebRTC), chúng ta sử dụng Extension độc quyền `webrtc-guard-chrome` (và bản build `.xpi` cho Firefox) để thực hiện Hooking sâu vào Engine của WebRTC.

Extension này tiêm một file `spoof.js` vào `<all_urls>` tại thời điểm `document_start` nhằm ghi đè các hàm API trước khi website tải xong.

**Các API bị kiểm soát:**
1. **`RTCPeerConnection.prototype.createOffer` / `createAnswer`**: Quét và thay thế toàn bộ địa chỉ IP thật bằng IP Proxy trong chuỗi SDP (Session Description Protocol).
2. **`setLocalDescription` / `localDescription` / `currentLocalDescription`**: Hook vào Getter/Setter để đảm bảo mô tả kết nối luôn chứa IP giả mạo.
3. **`onicecandidate` (EventListener)**: Sửa đổi các ICE Candidates được tạo ra theo thời gian thực.
4. **`getStats()` (Deep Hook)**: Đánh chặn Proxy Array/Iterator của `RTCStatsReport`. Hook này ghi đè thuộc tính `ip` và `address` thành IP Proxy trước khi trả về, xử lý triệt để cả các lệnh `forEach`, `values`, và `entries`.
5. **Dynamic Iframe Protection**: Đánh chặn `Node.prototype.appendChild`, `insertBefore` và Getter của `contentWindow` / `contentDocument`. Tính năng này đảm bảo Script ngụy trang WebRTC được tiêm vào *ngay khoảnh khắc* một Iframe ẩn vừa được sinh ra, đánh bại mọi Script quét IP tàng hình.

---

## 3. Chống rò rỉ DNS (DNS Leak Protection) qua Local Proxy Relay

Lỗi kinh điển của Antidetect Browser là rò rỉ máy chủ phân giải tên miền (DNS Leak). Khi sử dụng proxy, trình duyệt thường giao việc phân giải DNS cho Proxy Upstream (ví dụ: Proxy VN nhưng dùng Google DNS của US), dẫn đến cờ đỏ do lệch location.

Channel Manager xử lý việc này bằng **C# Local TCP Proxy Relay** tích hợp ngay trong `server.ps1`:
1. Trình duyệt kết nối vào Local Relay (ví dụ `127.0.0.1:51882`).
2. Local Relay đánh chặn các gói tin HTTP `GET` và `CONNECT`.
3. Trích xuất Hostname và thực hiện phân giải DNS cục bộ thông qua **Cloudflare DoH (DNS over HTTPS)**.
4. Ghi đè Hostname thành IP đã phân giải trước khi đẩy gói tin lên Upstream Proxy.
-> **Kết quả**: Upstream Proxy chỉ nhận được IP đích, không cần phân giải DNS. Hoàn toàn loại bỏ DNS Leak!

---

## 4. Cơ chế Khôi phục trạng thái (No-Proxy Cleanup)

Để đảm bảo tính "Authentic" (Chân thật) khi người dùng **KHÔNG** sử dụng Proxy, hệ thống không giữ lại các dấu vết ngụy trang của phiên trước.

1. **Khôi phục Preference**: `server.ps1` sẽ:
   - Ghi đè chính sách WebRTC về `default` (Chrome) hoặc force reset tất cả ICE preferences về `false` (Firefox)
   - Dọn dẹp `prefs.js` (Firefox) để xóa giá trị runtime cũ từ phiên proxy trước (nếu không, Firefox giữ giá trị cũ gây WebRTC N/A)
2. **Vô hiệu hóa Hook**: 
   - **Chrome**: Compile lại `spoof.js` với `TARGET_PROXY_IP = ""`. Extension tự ngắt hook (`if (!targetIp) return;`) và cho phép IP thật hiển thị tự nhiên.
   - **Firefox**: Xóa file `.xpi` khỏi thư mục `extensions/`, trả lại Profile sạch hoàn toàn.
3. **Injection Method**:
   - **Chrome**: Manifest V3 `"world": "MAIN"` inject trực tiếp `spoof.js` vào page world.
   - **Firefox**: `content.js` tạo `<script src="spoof.js">` (file-based via `browser.runtime.getURL`), tránh lỗi inline escape.

---

## 5. Kịch bản Kiểm thử & Troubleshooting

Trong quá trình phát triển, chúng ta đã xây dựng công cụ Test khắc nghiệt (`leak_tester.html` & Playwright Automation) để đóng giả làm một Antidetect Scanner.
- **Tiêu chuẩn vượt qua**:
  - `onicecandidate` (Main Window + Iframe) == Proxy IP
  - `localDescription` SDP == Proxy IP
  - `getStats().forEach/values/entries` == Proxy IP
- **Khắc phục sự cố N/A**: Nếu WebRTC báo N/A hoặc `Connection Refused` khi không có proxy, thường do trình duyệt chưa kịp dọn dẹp Extension cũ. Việc khởi động lại Channel Manager và Play lại trình duyệt sẽ khắc phục triệt để.
