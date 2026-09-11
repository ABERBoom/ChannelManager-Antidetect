# Architecture - Channel Manager

## 1. Tech Stack

| Layer | Technology | Lý do |
|-------|-----------|-------|
| **Frontend** | HTML + CSS + Vanilla JS | Đơn giản, không dependency, chạy mọi máy |
| **Backend** | PowerShell HTTP Server | Tích hợp sẵn Windows, không cần cài thêm |
| **Data** | JSON file | Đơn giản, dễ backup, không cần DB |
| **Browser Control** | Windows API (P/Invoke) | Set AppUserModelID, icon trên taskbar |
| **Icon Generation** | System.Drawing (.NET) | Tạo icon động với badge |
| **Installer Extract** | PortableApps PAF.exe | Extract browser portable tự động |
| **Network & Security**| Proxy + WebRTC Hooks | Đảm bảo tính chân thực (authenticity) và ẩn danh tuyệt đối |

> **Tại sao không dùng Electron/Node.js?**
> - Không cần cài thêm runtime
> - PowerShell có sẵn trên mọi Windows 10+
> - Giảm kích thước app xuống < 1MB (không tính browser portable)
> - Tận dụng Windows API trực tiếp qua C# inline

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Channel Manager                       │
├─────────────────┬───────────────────────────────────────────┤
│                 │                                           │
│   Frontend      │         Backend (PowerShell)              │
│   (Browser)     │                                           │
│                 │  ┌──────────────┐  ┌──────────────────┐   │
│  ┌───────────┐  │  │ HTTP Server  │  │ Profile Manager  │   │
│  │ index.html│◄─┼─►│ (port 8777)  │  │ - CRUD profiles  │   │
│  │ index.css │  │  │              │  │ - JSON storage   │   │
│  │ app.js    │  │  │ REST API     │  │ - Icon generator │   │
│  └───────────┘  │  └──────┬───────┘  └────────┬─────────┘   │
│                 │         │                    │             │
│                 │  ┌──────┴────────────────────┴──────────┐  │
│                 │  │        Browser Launcher               │  │
│                 │  │  - Extract PAF installer               │  │
│                 │  │  - Set AppUserModelID on windows       │  │
│                 │  │  - Inject Proxy config & preferences   │  │
│                 │  │  - Compile WebRTC spoof.js extension   │  │
│                 │  │  - Set custom icon on taskbar          │  │
│                 │  │  - Monitor process status              │  │
│                 │  └─────────────────────────────────────┘  │
├─────────────────┴───────────────────────────────────────────┤
│                      File System                             │
│                                                              │
│  📂 ChannelManager/                                          │
│  ├── 📂 profiles/                                            │
│  │   ├── 📂 profile-001/                                     │
│  │   │   ├── 📂 FirefoxPortable/ (hoặc GoogleChromePortable)│
│  │   │   └── 📄 profile.json                                │
│  │   ├── 📂 profile-002/                                     │
│  │   └── ...                                                 │
│  ├── 📂 icons/                                               │
│  │   ├── 🖼️ profile-001.ico                                  │
│  │   └── ...                                                 │
│  ├── 📂 installers/                                          │
│  │   ├── FirefoxPortable_*.paf.exe                           │
│  │   └── GoogleChromePortable_*.paf.exe                      │
│  ├── 📂 webapp/                                              │
│  │   ├── index.html                                          │
│  │   ├── index.css                                           │
│  │   └── app.js                                              │
│  ├── 📂 extensions/            (WebRTC Guard extension)      │
│  ├── 📄 profiles.json          (master profile list)         │
│  ├── 📄 server.ps1             (PowerShell HTTP server)      │
│  └── 📄 ChannelManager.bat     (entry point)                 │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Data Model

### profiles.json
```json
{
  "version": "1.0",
  "profiles": [
    {
      "id": "profile-001",
      "name": "Kenh1 - Said",
      "browser": "firefox",
      "group": "Default group",
      "tags": ["marketing", "youtube"],
      "iconType": "auto",
      "iconBadge": "01",
      "iconBadgeColor": "#DC2626",
      "customIconPath": null,
      "status": "stopped",
      "pid": null,
      "createdAt": "2026-09-10T14:00:00+07:00",
      "lastAccessedAt": "2026-09-10T14:30:00+07:00",
      "notes": ""
    }
  ],
  "groups": ["Default group", "Marketing", "Sales"],
  "settings": {
    "firefoxInstaller": "installers/FirefoxPortable_155.0.1_English.paf.exe",
    "chromeInstaller": "installers/GoogleChromePortable_153.0.8010.37_online.paf.exe",
    "autoStartServer": true,
    "serverPort": 8777,
    "iconMonitorInterval": 2000
  }
}
```

### profile.json (per profile)
```json
{
  "id": "profile-001",
  "browser": "firefox",
  "exeName": "firefox_p001.exe",
  "appUserModelId": "ChannelManager.profile-001",
  "installed": true,
  "installedAt": "2026-09-10T14:00:00+07:00"
}
```

---

## 4. API Design (REST)

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| `GET` | `/api/profiles` | Danh sách tất cả profiles |
| `GET` | `/api/profiles/:id` | Chi tiết 1 profile |
| `POST` | `/api/profiles` | Tạo profile mới |
| `PUT` | `/api/profiles/:id` | Cập nhật profile |
| `DELETE` | `/api/profiles/:id` | Xóa profile |
| `POST` | `/api/profiles/:id/launch` | Mở trình duyệt |
| `POST` | `/api/profiles/:id/stop` | Đóng trình duyệt |
| `POST` | `/api/profiles/batch/launch` | Mở hàng loạt |
| `POST` | `/api/profiles/batch/stop` | Đóng hàng loạt |
| `GET` | `/api/profiles/:id/status` | Kiểm tra trạng thái |
| `POST` | `/api/profiles/:id/icon` | Upload icon tùy chỉnh |
| `GET` | `/api/installers` | Danh sách installer có sẵn |
| `GET` | `/api/settings` | Cài đặt app |
| `PUT` | `/api/settings` | Cập nhật cài đặt |

---

## 5. Key Processes

### 5.1 Tạo Profile mới
```
User click "Tạo Profile"
    → Frontend POST /api/profiles { name, browser, ... }
    → Backend:
        1. Generate unique ID (profile-XXX)
        2. Create folder: profiles/profile-XXX/
        3. Extract PAF installer vào folder (silent mode: /S /D=path)
        4. Rename firefox.exe → firefox_pXXX.exe (hoặc chrome)
        5. Cập nhật FirefoxPortable.ini / ChromePortable.ini
        6. Generate icon .ico với badge
        7. Save profile.json
        8. Update profiles.json
    → Frontend nhận response, thêm row vào bảng
```

### 5.2 Mở Profile
```
User click Play button
    → Frontend POST /api/profiles/:id/launch
    → Backend:
        1. Kiểm tra trạng thái Proxy của profile.
        2. Compile `spoof.js` (WebRTC Guard) với IP Proxy tương ứng.
        3. Start FirefoxPortable.exe / GoogleChromePortable.exe kèm flags proxy.
        4. Wait for browser window (poll EnumWindows)
        5. Set AppUserModelID trên window (SHGetPropertyStoreForWindow)
        6. Set RelaunchIconResource = custom .ico path
        7. Set RelaunchDisplayNameResource = profile name
        8. Update status = "running", save PID
        9. Start background monitor (giám sát process alive)
    → Frontend cập nhật status badge
```

### 5.3 Icon Generation
```
Input: browserType, badgeText, badgeColor
    → Tạo Bitmap 256x256
    → Vẽ browser base icon (Firefox/Chrome simplified)
    → Vẽ badge circle với badgeColor
    → Vẽ badgeText (số/chữ) lên badge
    → Export multi-size ICO (256, 48, 32, 16)
    → Save to icons/profile-XXX.ico
```

---

## 6. Browser Taskbar Separation Strategy

### Vấn đề
Firefox tự gọi `SetCurrentProcessExplicitAppUserModelID()` với hash cố định → Windows gộp tất cả Firefox cùng 1 nhóm trên taskbar.

### Giải pháp (đã verify hoạt động)
1. **Rename executable**: Mỗi profile có `firefox_pXXX.exe` riêng → Windows nhận diện process khác nhau
2. **Set window-level AppUserModelID**: Dùng `SHGetPropertyStoreForWindow()` để override ID trên mỗi cửa sổ
3. **Set RelaunchIconResource**: Gán icon .ico tùy chỉnh lên cửa sổ
4. **Background monitor**: Định kỳ re-apply properties để đảm bảo icon không bị Firefox ghi đè

### Implementation
```csharp
// Set trên mỗi window của browser
SHGetPropertyStoreForWindow(hwnd, IID_IPropertyStore, out propStore);
propStore.SetValue(PKEY_AppUserModel_ID, "ChannelManager.profile-001");
propStore.SetValue(PKEY_AppUserModel_RelaunchIconResource, "path/to/icon.ico");
propStore.SetValue(PKEY_AppUserModel_RelaunchCommand, "path/to/launcher.exe");
propStore.SetValue(PKEY_AppUserModel_RelaunchDisplayNameResource, "Kenh1 - Firefox");
propStore.Commit();
```

---

## 7. Error Handling

| Lỗi | Xử lý |
|-----|--------|
| PAF extract thất bại | Retry 1 lần, thông báo user |
| Browser không mở được | Kiểm tra lock file, kill zombie process |
| Icon không set được | Retry 3 lần với delay, fallback icon gốc |
| Port 8777 đã dùng | Tự tìm port trống tiếp theo |
| JSON corrupt | Backup tự động, restore từ backup |
