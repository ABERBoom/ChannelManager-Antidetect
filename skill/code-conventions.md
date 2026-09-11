# Code Conventions - Channel Manager

## 1. Project Structure

```
📂 ChannelManager/
├── 📄 ChannelManager.bat          # Entry point - khởi động app
├── 📄 server.ps1                  # PowerShell HTTP server + API
├── 📄 profiles.json               # Master data file
│
├── 📂 webapp/                     # Frontend (served by HTTP server)
│   ├── 📄 index.html              # Main HTML - single page app
│   ├── 📄 index.css               # All styles - design system + components
│   └── 📄 app.js                  # All logic - API calls + DOM manipulation
│
├── 📂 profiles/                   # Browser profile data
│   └── 📂 {profile-id}/           # One folder per profile
│       ├── 📂 FirefoxPortable/    # or GoogleChromePortable/
│       └── 📄 profile.json        # Profile-specific config
│
├── 📂 icons/                      # Generated & custom icons
│   └── 🖼️ {profile-id}.ico        # One icon per profile
│
├── 📂 installers/                 # Browser portable installers
│   ├── FirefoxPortable_*.paf.exe
│   └── GoogleChromePortable_*.paf.exe
│
└── 📂 skill/                      # Documentation (this folder)
    ├── 📄 README.md
    ├── 📄 ui-ux-design.md
    ├── 📄 architecture.md
    ├── 📄 code-conventions.md
    └── 📄 handover.md
```

---

## 2. Frontend Conventions

### HTML
- Semantic HTML5 elements
- Mỗi interactive element có `id` unique và descriptive
- Data attributes dùng `data-profile-id`, `data-action` etc.
- Không dùng inline styles hoặc inline JS

### CSS
- CSS Custom Properties cho design tokens (colors, spacing, fonts)
- BEM-like naming: `.profile-table__row`, `.profile-table__cell--status`
- Media queries không cần (desktop-only app)
- Animations dùng CSS transitions/keyframes

```css
/* Naming convention */
.component { }
.component__element { }
.component--modifier { }
.component__element--modifier { }

/* Example */
.profile-card { }
.profile-card__name { }
.profile-card__status { }
.profile-card__status--running { }
```

### JavaScript
- Vanilla JS, no frameworks
- ES6+ syntax (const/let, arrow functions, template literals, async/await)
- Module pattern với IIFE hoặc class
- Tất cả API calls qua `fetch()` với error handling
- DOM manipulation qua `document.querySelector`

```javascript
// API call pattern
async function apiCall(endpoint, method = 'GET', body = null) {
    const options = { method, headers: { 'Content-Type': 'application/json' } };
    if (body) options.body = JSON.stringify(body);
    const res = await fetch(`/api/${endpoint}`, options);
    if (!res.ok) throw new Error(`API Error: ${res.status}`);
    return res.json();
}

// Event delegation pattern
document.querySelector('#profile-table').addEventListener('click', (e) => {
    const action = e.target.closest('[data-action]')?.dataset.action;
    const profileId = e.target.closest('[data-profile-id]')?.dataset.profileId;
    if (action && profileId) handleAction(action, profileId);
});
```

---

## 3. Backend Conventions (PowerShell)

### HTTP Server Pattern
```powershell
# Route handling
switch -Regex ($request.Url.LocalPath) {
    '^/api/profiles$' {
        if ($method -eq 'GET') { Get-AllProfiles }
        elseif ($method -eq 'POST') { New-Profile $body }
    }
    '^/api/profiles/([^/]+)$' {
        $id = $matches[1]
        if ($method -eq 'GET') { Get-Profile $id }
        elseif ($method -eq 'PUT') { Update-Profile $id $body }
        elseif ($method -eq 'DELETE') { Remove-Profile $id }
    }
}
```

### Function Naming
- PowerShell verb-noun: `Get-Profile`, `New-Profile`, `Start-Browser`
- Helper functions: `Write-JsonResponse`, `Read-RequestBody`
- C# inline types: `TaskbarHelper`, `IconGenerator`

### Error Response Format
```json
{
    "success": false,
    "error": {
        "code": "PROFILE_NOT_FOUND",
        "message": "Profile with ID 'profile-999' does not exist"
    }
}
```

### Success Response Format
```json
{
    "success": true,
    "data": { ... }
}
```

---

## 4. Data Conventions

### ID Generation
- Format: `profile-{timestamp}-{random4}`
- Example: `profile-1725955200-a3f2`
- Đảm bảo unique, sortable theo thời gian tạo

### Timestamps
- ISO 8601 format: `2026-09-10T14:00:00+07:00`
- Luôn kèm timezone

### File Paths
- Dùng relative path trong JSON (relative to app root)
- Dùng absolute path khi gọi Windows API

---

## 5. Git Conventions (nếu áp dụng)

### Commit Messages
```
feat: thêm tính năng tạo profile mới
fix: sửa lỗi icon không hiển thị trên taskbar
style: cập nhật màu nút Create Profile
docs: thêm tài liệu API
refactor: tách hàm browser launcher
```

### Branching
- `main`: stable release
- `dev`: development
- `feature/xxx`: tính năng mới
