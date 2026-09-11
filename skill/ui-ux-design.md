# UI/UX Design - Channel Manager

## 1. Design Philosophy

Lấy cảm hứng từ OmniLogin - giao diện quản lý profile trình duyệt chuyên nghiệp:
- **Clean & Professional**: Tông màu sáng, bố cục rõ ràng
- **Data-driven**: Hiển thị dạng bảng, dễ quản lý số lượng lớn
- **Action-oriented**: Các thao tác chính nổi bật, dễ tiếp cận

---

## 2. Color System

### Primary Palette
| Token | Hex | Sử dụng |
|-------|-----|---------|
| `--primary` | `#2563EB` | Nút chính, link, highlight |
| `--primary-light` | `#DBEAFE` | Background active item |
| `--primary-dark` | `#1D4ED8` | Hover state |

### Semantic Colors
| Token | Hex | Sử dụng |
|-------|-----|---------|
| `--success` | `#22C55E` | Trạng thái "Đang chạy" |
| `--danger` | `#EF4444` | Trạng thái "Đã dừng", nút xóa |
| `--warning` | `#F59E0B` | Cảnh báo |
| `--info` | `#3B82F6` | Thông tin |

### Neutral Colors
| Token | Hex | Sử dụng |
|-------|-----|---------|
| `--bg-primary` | `#FFFFFF` | Background chính |
| `--bg-secondary` | `#F8FAFC` | Background sidebar, header |
| `--bg-tertiary` | `#F1F5F9` | Background row hover |
| `--text-primary` | `#1E293B` | Text chính |
| `--text-secondary` | `#64748B` | Text phụ |
| `--border` | `#E2E8F0` | Viền, phân cách |

---

## 3. Typography

```css
/* Font stack */
font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;

/* Scale */
--font-xs:    12px;  /* Labels, meta info */
--font-sm:    13px;  /* Table data */
--font-base:  14px;  /* Body text */
--font-md:    16px;  /* Section headers */
--font-lg:    20px;  /* Page title */
--font-xl:    24px;  /* App name */
```

---

## 4. Layout Structure

```
┌──────────────────────────────────────────────────────────┐
│ [Logo] Channel Manager              [Minimize][Close]    │  ← Title Bar
├────────────┬─────────────────────────────────────────────┤
│            │  📋 Quản lý Profile                         │  ← Page Header
│  SIDEBAR   │  [+ Tạo Profile] [Xóa] [Mở tất cả]       │  ← Toolbar
│            ├─────────────────────────────────────────────┤
│ • Profiles │  ☐ │ ID │ Tên    │ Trình duyệt │ Trạng    │  ← Table Header
│ • Settings │  ──┼────┼────────┼─────────────┼──────     │
│            │  ☐ │ 1  │ Kenh1  │ 🦊 Firefox  │ 🟢 Chạy  │  ← Profile Row
│            │  ☐ │ 2  │ Kenh2  │ 🌐 Chrome   │ 🔴 Dừng  │  ← Profile Row
│            │  ☐ │ 3  │ Kenh3  │ 🦊 Firefox  │ 🔴 Dừng  │  ← Profile Row
│            │                                             │
│            │  Hiển thị 3 / 3 profile   [1] > 10/trang ▼ │  ← Pagination
├────────────┴─────────────────────────────────────────────┤
│  ℹ️ Ready                                    v1.0.0      │  ← Status Bar
└──────────────────────────────────────────────────────────┘
```

---

## 5. Component Specifications

### 5.1 Sidebar
- Width: 220px (collapsible)
- Background: `--bg-secondary`
- Menu items: icon + text, active state với `--primary-light` background
- Logo ở trên cùng

### 5.2 Profile Table
- Dạng data table với header sticky
- Columns: Checkbox | ID | Tên | Trình duyệt | Trạng thái | Tags | Hành động
- Row hover: `--bg-tertiary`
- Row selected: `--primary-light` background
- Action buttons ẩn, hiện khi hover row

### 5.3 Create Profile Dialog (Modal)
```
┌─────────────────────────────────────┐
│  Tạo Profile mới                  X │
├─────────────────────────────────────┤
│                                     │
│  Tên profile:  [________________]   │
│                                     │
│  Trình duyệt:  ○ Firefox           │
│                 ○ Chrome            │
│                                     │
│  Icon:  [Chọn icon ▼]  [Preview]   │
│         hoặc kéo thả file .ico      │
│                                     │
│  Nhóm:  [Default group ▼]          │
│                                     │
│  Tags:  [+ Thêm tag]               │
│                                     │
├─────────────────────────────────────┤
│              [Hủy]  [Tạo Profile]   │
└─────────────────────────────────────┘
```

### 5.4 Toolbar
- Nút "Tạo Profile": Primary button, xanh dương, nổi bật
- Các nút phụ: Xóa, Mở hàng loạt, Đóng tất cả
- Search bar bên phải
- Sort dropdown

### 5.5 Status Badges
- **Đang chạy**: Badge xanh lá, có pulse animation nhẹ
- **Đã dừng**: Badge đỏ
- **Đang mở**: Badge cam (đang khởi động)

---

## 6. Interactions

### Animations
- Modal: Fade in + scale up (200ms ease-out)
- Row hover: Background transition (150ms)
- Status change: Smooth color transition
- Button hover: Slight elevation + color shift
- Sidebar collapse: Slide animation (250ms)

### User Flows
1. **Tạo profile**: Click "Tạo Profile" → Fill form → Chọn browser → Click "Tạo" → Profile xuất hiện trong bảng
2. **Mở profile**: Click nút Play trên row → Browser khởi động → Status đổi sang "Đang chạy"
3. **Đóng profile**: Click nút Stop → Browser đóng → Status đổi sang "Đã dừng"
4. **Xóa profile**: Chọn checkbox → Click "Xóa" → Confirm dialog → Xóa khỏi bảng
5. **Mở hàng loạt**: Chọn nhiều checkbox → Click "Mở hàng loạt" → Tất cả browser mở

---

## 7. Responsive Behavior
- App sẽ chạy ở chế độ cửa sổ desktop cố định
- Min width: 900px
- Min height: 600px
- Sidebar có thể collapse để tăng không gian bảng

---

## 8. Icon System
- Sử dụng icon set tự tạo bằng System.Drawing
- Mỗi profile có icon riêng với:
  - Logo trình duyệt (Firefox/Chrome) làm nền
  - Badge số thứ tự hoặc chữ cái với màu tùy chọn
  - Hỗ trợ upload icon .ico/.png tùy chỉnh
