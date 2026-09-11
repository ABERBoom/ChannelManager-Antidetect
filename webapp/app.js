// Global State
let state = {
    profiles: [],
    proxies: [],
    selectedIds: new Set(),
    activeTab: 'tab-profiles'
};

const API_URL = 'http://localhost:8780/api';

// --- API Helpers ---
async function fetchApi(endpoint, method = 'GET', body = null) {
    try {
        const options = { method };
        if (body) {
            options.headers = { 'Content-Type': 'application/json' };
            options.body = JSON.stringify(body);
        }
        const res = await fetch(`${API_URL}${endpoint}`, options);
        if (!res.ok) {
            let err = 'Lỗi server';
            try { err = (await res.json()).error; } catch(e) {}
            throw new Error(err);
        }
        const data = await res.json();
        if (!data.success) throw new Error(data.error || 'Lỗi không xác định');
        return data.data;
    } catch (err) {
        showToast(err.message, 'error');
        throw err;
    }
}

// --- UI Helpers ---
function showToast(message, type = 'success') {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.className = `toast show ${type}`;
    setTimeout(() => { toast.classList.remove('show'); }, 3000);
}

// --- Initial Load ---
async function loadData() {
    try {
        const config = await fetchApi('/config');
        state.profiles = config.profiles || [];
        
        // Preserve pingStatus for proxies
        const newProxies = config.proxies || [];
        newProxies.forEach(np => {
            const old = state.proxies.find(op => op.id === np.id);
            if (old && old.pingStatus) {
                np.pingStatus = old.pingStatus;
                np.pingMs = old.pingMs;
            }
        });
        state.proxies = newProxies;
        
        state.installersDir = config.installersDir || '';
        renderTable();
        renderProxies();
        checkInstallers();
        
        // Auto-check proxy ping in background
        if (!window._proxyCheckStarted) {
            window._proxyCheckStarted = true;
            checkAllProxies();
            setInterval(checkAllProxies, 60000); // Check every minute
        }
    } catch (e) {
        console.error("Failed to load data", e);
    }
}

async function checkInstallers() {
    try {
        const status = await fetchApi('/installers/status');
        
        const ffSpan = document.getElementById('ff-status');
        const ffInstall = document.getElementById('btn-ff-install');
        const ffDownload = document.getElementById('btn-ff-download');
        
        if (status.firefox) {
            ffSpan.textContent = 'Sẵn sàng';
            ffSpan.style.color = 'green';
            ffInstall.style.display = 'inline-block';
            ffDownload.style.display = 'none';
            ffInstall.onclick = () => runInstaller('firefox');
        } else {
            ffSpan.textContent = 'Thiếu file';
            ffSpan.style.color = 'red';
            ffInstall.style.display = 'none';
            ffDownload.style.display = 'inline-block';
            ffDownload.onclick = () => downloadInstaller('firefox');
        }
        
        const crSpan = document.getElementById('cr-status');
        const crInstall = document.getElementById('btn-cr-install');
        const crDownload = document.getElementById('btn-cr-download');
        
        if (status.chrome) {
            crSpan.textContent = 'Sẵn sàng';
            crSpan.style.color = 'green';
            crInstall.style.display = 'inline-block';
            crDownload.style.display = 'none';
            crInstall.onclick = () => runInstaller('chrome');
        } else {
            crSpan.textContent = 'Thiếu file';
            crSpan.style.color = 'red';
            crInstall.style.display = 'none';
            crDownload.style.display = 'inline-block';
            crDownload.onclick = () => downloadInstaller('chrome');
        }
    } catch(e) {}
}

async function runInstaller(browser) {
    showToast(`Đang mở bộ cài ${browser}... Vui lòng thao tác trên cửa sổ mới.`, 'success');
    try {
        await fetchApi('/installers/run', 'POST', { browser });
    } catch(e) {}
}

async function downloadInstaller(browser) {
    showToast(`Đang tải ${browser}... Vui lòng đợi!`, 'success');
    try {
        await fetchApi('/installers/download', 'POST', { browser });
        showToast(`Tải ${browser} thành công!`, 'success');
        checkInstallers();
    } catch(e) {
        showToast(`Lỗi tải ${browser}`, 'error');
    }
}

// --- Renderers ---
function renderTable() {
    const tbody = document.getElementById('profile-list');
    const search = document.getElementById('search-profile').value.toLowerCase();
    
    let html = '';
    state.profiles.forEach((p, index) => {
        if (search && !p.name.toLowerCase().includes(search)) return;
        
        const isSelected = state.selectedIds.has(p.id);
        const isLinked = !!p.path;
        
        let proxyName = '';
        let proxyIp = '';
        let proxyStatus = 'unknown';
        if (p.proxyId) {
            const px = state.proxies.find(x => x.id === p.proxyId);
            if (px) {
                proxyName = px.name || px.proxyString.split(':')[0];
                let ipDomain = px.proxyString.split(':')[0];
                if (px.proxyString.includes('://')) {
                    ipDomain = px.proxyString.split('://')[1].split(':')[0];
                }
                proxyIp = ipDomain;
                proxyStatus = px.pingStatus || 'unknown';
            }
        } else if (p.proxy) { // legacy fallback
            proxyName = p.proxy.split(':')[0] + '...';
            proxyIp = p.proxy.split(':')[0];
        }
        
        html += `
            <tr class="${isSelected ? 'selected' : ''}" data-id="${p.id}">
                <td><input type="checkbox" class="check-row" ${isSelected ? 'checked' : ''}></td>
                <td>${index + 1}</td>
                <td>
                    <strong>${p.name}</strong>
                    <button class="btn-icon edit btn-edit-profile" title="Sửa tên" style="color:var(--text-secondary)"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg></button>
                </td>
                <td>
                    ${!p.browser ? '--' : (p.browser === 'firefox' ? '<span class="browser-badge">🦊 Firefox</span>' : '<span class="browser-badge">🌐 Chrome</span>')}
                    ${p.status === 'running' ? '<span class="badge-running">Đang chạy</span>' : ''}
                </td>
                <td style="font-size: 12px; color: var(--text-secondary); max-width: 300px;">
                    ${p.path ? `<span class="hidden-path" data-path="${p.path}" title="${p.path}">••••••••••</span>` : '<em>Chưa kết nối</em>'}
                </td>
                <td>
                    <div style="display: flex; align-items: center; gap: 8px;">
                        ${proxyName ? `<div class="proxy-dot proxy-${proxyStatus}"></div><span title="${proxyIp}">${proxyName}</span>` : 'Noproxy'}
                    </div>
                </td>
                <td>
                    <div style="display: flex; gap: 8px; align-items: center; justify-content: flex-start;">
                        ${isLinked ? 
                            (p.status === 'running' ?
                                `<button class="btn-icon stop btn-stop" title="Đóng Trình Duyệt" data-id="${p.id}" style="color:var(--danger)"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect></svg></button>` :
                                `<button class="btn-icon play btn-launch" title="Mở Trình Duyệt" data-id="${p.id}" style="color:var(--success)"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg></button>`) : 
                            `<button class="btn-icon play btn-launch" title="Mở Trình Duyệt" disabled style="opacity:0.3"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg></button>`
                        }
                        <button class="btn-icon stop btn-open-dir" title="Mở thư mục gốc" ${!isLinked ? 'disabled style="opacity:0.3"' : 'style="color:var(--text-secondary)"'}><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg></button>
                        ${!isLinked ? 
                            `<button class="btn-icon play btn-link-profile" title="Kết nối thư mục Portable" style="color:var(--primary)"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path></svg></button>` :
                            `<button class="btn-icon stop btn-link-profile" title="Đã kết nối" disabled style="opacity:0.3"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path></svg></button>`
                        }
                        <button class="btn-icon btn-edit-proxy" data-id="${p.id}" title="Cấu hình Proxy" style="color:var(--info)"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg></button>
                    </div>
                </td>
                <td>${p.lastAccessedAt ? new Date(p.lastAccessedAt).toLocaleString() : '--'}</td>
            </tr>
        `;
    });
    
    if (html === '') {
        html = '<tr><td colspan="8" style="text-align: center; padding: 20px;">Không có profile nào</td></tr>';
    }
    
    tbody.innerHTML = html;
    updateToolbar();
}

function updateToolbar() {
    const hasSelected = state.selectedIds.size > 0;
    document.getElementById('btn-delete-selected').disabled = !hasSelected;
    document.getElementById('btn-open-selected').disabled = !hasSelected;
    document.getElementById('btn-close-selected').disabled = !hasSelected;
}

function renderProxies() {
    const tbody = document.getElementById('proxy-list');
    let html = '';
    
    state.proxies.forEach((px, index) => {
        let ipDomain = px.proxyString.split(':')[0];
        if (px.proxyString.includes('://')) {
            ipDomain = px.proxyString.split('://')[1].split(':')[0];
        }
        let pingText = '--';
        let pingColor = 'var(--text-secondary)';
        if (px.pingStatus === 'alive') {
            pingText = px.pingMs + 'ms';
            pingColor = 'var(--success)';
        } else if (px.pingStatus === 'dead') {
            pingText = 'Dead / Timeout';
            pingColor = 'var(--danger)';
        }
        
        html += `
            <tr data-id="${px.id}">
                <td>${index + 1}</td>
                <td><strong>${px.name}</strong></td>
                <td>${ipDomain} <span style="color:var(--text-secondary);font-size:11px;">(***)</span></td>
                <td><span class="ping-status" id="ping-${px.id}" style="color:${pingColor}">${pingText}</span></td>
                <td>
                    <div style="display: flex; gap: 8px;">
                        <button class="btn-icon play btn-ping-proxy" title="Kiểm tra Ping" style="color:var(--primary)"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"></polyline></svg></button>
                        <button class="btn-icon stop btn-delete-proxy" title="Xóa Proxy" style="color:var(--danger)"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg></button>
                    </div>
                </td>
            </tr>
        `;
    });
    
    if (html === '') {
        html = '<tr><td colspan="5" style="text-align: center; padding: 20px;">Chưa có proxy nào</td></tr>';
    }
    tbody.innerHTML = html;
}

// Click to copy path
document.addEventListener('click', (e) => {
    const el = e.target.closest('.hidden-path');
    if (el) {
        const path = el.getAttribute('data-path');
        if (path) {
            navigator.clipboard.writeText(path).then(() => showToast('Đã copy đường dẫn!', 'success')).catch(() => showToast('Không thể copy', 'error'));
        }
    }
});

// --- Event Listeners ---

// TAB NAVIGATION
document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', (e) => {
        if (item.classList.contains('disabled')) return;
        e.preventDefault();
        
        document.querySelectorAll('.nav-item').forEach(nav => nav.classList.remove('active'));
        item.classList.add('active');
        
        const tabId = item.getAttribute('data-tab');
        if (!tabId) {
            state.activeTab = 'tab-profiles';
            document.querySelector('.main-content').style.display = 'block';
            document.getElementById('tab-proxies').style.display = 'none';
            return;
        }
        
        state.activeTab = tabId;
        document.querySelector('.main-content').style.display = 'none';
        document.getElementById('tab-proxies').style.display = 'block';
    });
});

async function checkAllProxies() {
    for (const px of state.proxies) {
        try {
            const res = await fetchApi(`/proxies/${px.id}/ping`, 'POST');
            if (res.status === 'alive') {
                px.pingStatus = 'alive';
                px.pingMs = res.ms;
            } else {
                px.pingStatus = 'dead';
                px.pingMs = -1;
            }
        } catch {
            px.pingStatus = 'dead';
            px.pingMs = -1;
        }
    }
    renderTable();
    if (state.activeTab === 'tab-proxies') {
        renderProxies();
    }
}

// Set Interval for auto-refresh
setInterval(loadData, 5000);

// MODALS LOGIC
const modalCreate = document.getElementById('modal-create');
const modalEdit = document.getElementById('modal-edit');
const modalLink = document.getElementById('modal-link');

// Open Modals
document.getElementById('btn-create-profile').addEventListener('click', () => {
    document.getElementById('form-create-profile').reset();
    
    // Auto-generate default name like "kenh1", "kenh2"
    let nextIndex = state.profiles.length + 1;
    while(state.profiles.find(p => p.name === ('kenh' + nextIndex))) {
        nextIndex++;
    }
    const defaultName = 'kenh' + nextIndex;
    const defaultBadge = nextIndex.toString().padStart(2, '0');
    
    document.getElementById('p-name').value = defaultName;
    document.getElementById('p-badge').value = defaultBadge;
    
    modalCreate.classList.add('active');
    document.getElementById('p-name').focus();
});

// Close Modals
document.querySelectorAll('.btn-close, .btn-secondary').forEach(btn => {
    btn.addEventListener('click', () => {
        modalCreate.classList.remove('active');
        modalEdit.classList.remove('active');
        modalLink.classList.remove('active');
        document.getElementById('modal-proxy').classList.remove('active');
        document.getElementById('modal-create-proxy').classList.remove('active');
    });
});

// Open Proxy Modals
document.getElementById('btn-create-proxy').addEventListener('click', () => {
    document.getElementById('form-create-proxy').reset();
    let nextIndex = state.proxies.length + 1;
    while(state.proxies.find(p => p.name === ('proxy' + nextIndex))) {
        nextIndex++;
    }
    document.getElementById('cp-name').value = 'proxy' + nextIndex;
    document.getElementById('modal-create-proxy').classList.add('active');
    document.getElementById('cp-name').focus();
});

// CREATE PROFILE SUBMIT
document.getElementById('btn-submit-modal').addEventListener('click', async (e) => {
    e.preventDefault();
    const name = document.getElementById('p-name').value;
    if (!name) return showToast('Vui lòng nhập tên profile', 'error');
    
    const payload = {
        name,
        iconBadge: document.getElementById('p-badge').value
    };
    
    modalCreate.classList.remove('active');
    showToast('Đang tạo profile...');
    
    try {
        const newProfile = await fetchApi('/profiles', 'POST', payload);
        state.profiles.push(newProfile);
        renderTable();
        showToast('Tạo profile thành công! Hãy nhấn Kết nối để gán thư mục.');
    } catch (e) {}
});

// EDIT PROFILE SUBMIT
document.getElementById('btn-submit-edit').addEventListener('click', async (e) => {
    e.preventDefault();
    const id = document.getElementById('edit-p-id').value;
    const name = document.getElementById('edit-p-name').value;
    if (!name) return showToast('Vui lòng nhập tên profile', 'error');
    
    modalEdit.classList.remove('active');
    showToast('Đang lưu...');
    
    try {
        await fetchApi(`/profiles/${id}`, 'PUT', { name });
        const profile = state.profiles.find(p => p.id === id);
        if (profile) profile.name = name;
        renderTable();
        showToast('Lưu thành công!');
        // If linked, path might have changed, reload config to get new path
        loadData();
    } catch (e) {}
});

// PICK FOLDER
document.getElementById('btn-pick-folder').addEventListener('click', async () => {
    try {
        const path = await fetchApi('/pick-folder');
        if (path) {
            document.getElementById('link-p-path').value = path;
            // Tá»± Ä‘á»™ng nháº¥n káº¿t ná»‘i luÃ´n cho tiá»‡n!
            document.getElementById('btn-submit-link').click();
        }
    } catch(e) {
        showToast(e.message || 'Lỗi khi gọi hộp thoại chọn thư mục', 'error');
    }
});

// LINK PROFILE SUBMIT
document.getElementById('btn-submit-link').addEventListener('click', async (e) => {
    e.preventDefault();
    const id = document.getElementById('link-p-id').value;
    const path = document.getElementById('link-p-path').value.trim();
    if (!path) return showToast('Vui lòng nhập đường dẫn thư mục', 'error');
    
    try {
        await fetchApi(`/profiles/${id}/link`, 'POST', { path });
        showToast('Kết nối thành công!', 'success');
        modalLink.classList.remove('active');
        loadData();
    } catch (e) {
        showToast(e.message || 'Lỗi kết nối thư mục', 'error');
    }
});

// PROXY SUBMIT (Assign)
document.getElementById('btn-submit-proxy').addEventListener('click', async (e) => {
    e.preventDefault();
    const id = document.getElementById('proxy-p-id').value;
    const proxyId = document.getElementById('proxy-select').value;
    
    document.getElementById('modal-proxy').classList.remove('active');
    showToast('Đang lưu proxy...');
    
    try {
        await fetchApi(`/profiles/${id}/proxy`, 'PUT', { proxyId: proxyId || null });
        showToast('Lưu cấu hình Proxy thành công!', 'success');
        loadData();
    } catch (e) {
        showToast(e.message || 'Lỗi khi lưu proxy', 'error');
    }
});

// CREATE PROXY SUBMIT
document.getElementById('btn-submit-create-proxy').addEventListener('click', async (e) => {
    e.preventDefault();
    const name = document.getElementById('cp-name').value.trim();
    const proxyString = document.getElementById('cp-string').value.trim();
    
    if (!name) return showToast('Vui lòng nhập tên proxy', 'error');
    if (!proxyString) return showToast('Vui lòng nhập chuỗi proxy', 'error');
    
    document.getElementById('modal-create-proxy').classList.remove('active');
    
    try {
        await fetchApi('/proxies', 'POST', { name, proxyString });
        showToast('Đã thêm Proxy thành công', 'success');
        loadData();
    } catch (e) {
        showToast(e.message || 'Lỗi khi thêm proxy', 'error');
    }
});

// PROXY TABLE EVENTS
document.getElementById('proxy-list').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr');
    if (!tr) return;
    const id = tr.dataset.id;
    
    if (e.target.closest('.btn-delete-proxy')) {
        if (!confirm('Bạn có chắc chắn muốn xóa Proxy này? Các Profile đang dùng sẽ mất kết nối proxy.')) return;
        try {
            await fetchApi(`/proxies/${id}`, 'DELETE');
            showToast('Đã xóa Proxy', 'success');
            loadData();
        } catch (err) {}
        return;
    }
    
    if (e.target.closest('.btn-ping-proxy')) {
        const span = document.getElementById(`ping-${id}`);
        span.textContent = 'Đang thử...';
        span.style.color = 'var(--text-secondary)';
        
        const px = state.proxies.find(x => x.id === id);
        
        try {
            const res = await fetchApi(`/proxies/${id}/ping`, 'POST');
            if (res.status === 'alive') {
                span.textContent = `${res.ms}ms`;
                span.style.color = 'var(--success)';
                if (px) { px.pingStatus = 'alive'; px.pingMs = res.ms; }
            } else {
                span.textContent = 'Dead / Timeout';
                span.style.color = 'var(--danger)';
                if (px) { px.pingStatus = 'dead'; px.pingMs = -1; }
            }
        } catch (err) {
            span.textContent = 'Lỗi kết nối';
            span.style.color = 'var(--danger)';
            if (px) { px.pingStatus = 'dead'; px.pingMs = -1; }
        }
        renderTable(); // Update dots in profile list
        return;
    }
});

// Delete Selected
document.getElementById('btn-delete-selected').addEventListener('click', async () => {
    if (!confirm(`Bạn có chắc chắn muốn xóa ${state.selectedIds.size} profile đã chọn? (Không xóa thư mục vật lý)`)) return;
    
    const ids = Array.from(state.selectedIds);
    for (const id of ids) {
        try {
            await fetchApi(`/profiles/${id}`, 'DELETE');
            state.profiles = state.profiles.filter(p => p.id !== id);
            state.selectedIds.delete(id);
        } catch (e) {}
    }
    renderTable();
    showToast('Đã xóa profile');
});

// Open Selected
document.getElementById('btn-open-selected').addEventListener('click', async () => {
    const ids = Array.from(state.selectedIds);
    for (const id of ids) {
        const profile = state.profiles.find(p => p.id === id);
        if (profile && profile.path) {
            try {
                await fetchApi(`/profiles/${id}/launch`, 'POST');
            } catch (e) {
                if (e.message.includes('404') || e.message.includes('không tồn tại')) {
                    loadData(); // reload to un-link
                }
            }
        }
    }
    showToast('Đã mở các profile');
});

// Close Selected (Not fully supported in Linker without tracking PID perfectly, but we can try)
document.getElementById('btn-close-selected').addEventListener('click', async () => {
    const ids = Array.from(state.selectedIds);
    for (const id of ids) {
        try { fetchApi(`/profiles/${id}/stop`, 'POST'); } catch (e) {}
    }
    showToast('Đã gửi lệnh đóng');
});

// Search
document.getElementById('search-profile').addEventListener('input', renderTable);

// Table interactions (Delegation)
document.getElementById('profile-list').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr');
    if (!tr) return;
    const id = tr.dataset.id;
    const profile = state.profiles.find(p => p.id === id);
    if (!profile) return;
    
    // Checkbox
    if (e.target.classList.contains('check-row')) {
        if (e.target.checked) state.selectedIds.add(id);
        else state.selectedIds.delete(id);
        renderTable();
        return;
    }
    
    // Play button
    if (e.target.closest('.btn-launch')) {
        const btn = e.target.closest('.btn-launch');
        const originalHtml = btn.innerHTML;
        btn.innerHTML = '<span class="spinner" style="width:14px;height:14px;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;display:inline-block;animation:spin 1s linear infinite;"></span>';
        try {
            await fetchApi(`/profiles/${id}/launch`, 'POST');
            showToast('Đã khởi chạy', 'success');
            loadData();
        } catch (err) {
            if (err.message && (err.message.includes('không tồn tại') || err.message.includes('404'))) {
                showToast(`Cảnh báo: Thư mục không tồn tại! Có thể bạn đã xóa nó. Đã mở lại nút Kết nối.`, 'error');
                loadData();
            } else {
                showToast(err.message, 'error');
            }
            btn.innerHTML = originalHtml;
        }
        return;
    }
    
    if (e.target.closest('.btn-stop')) {
        const btn = e.target.closest('.btn-stop');
        const originalHtml = btn.innerHTML;
        btn.innerHTML = '<span class="spinner" style="width:14px;height:14px;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;display:inline-block;animation:spin 1s linear infinite;"></span>';
        try {
            await fetchApi(`/profiles/${id}/stop`, 'POST');
            showToast('Đã đóng trình duyệt', 'info');
            loadData();
        } catch (err) {
            showToast(err.message, 'error');
            btn.innerHTML = originalHtml;
        }
        return;
    }
    
    // Open Dir button
    if (e.target.closest('.btn-open-dir')) {
        try {
            await fetchApi(`/profiles/${id}/open-dir`, 'POST');
        } catch (err) {
            showToast('Lỗi khi mở thư mục: ' + err.message, 'error');
        }
        return;
    }
    
    // Link button
    if (e.target.closest('.btn-link-profile')) {
        document.getElementById('link-p-id').value = id;
        document.getElementById('link-p-path').value = state.installersDir || '';
        modalLink.classList.add('active');
        document.getElementById('link-p-path').focus();
        return;
    }

    // Edit button
    if (e.target.closest('.btn-edit-profile')) {
        document.getElementById('edit-p-id').value = id;
        document.getElementById('edit-p-name').value = profile.name;
        modalEdit.classList.add('active');
        document.getElementById('edit-p-name').focus();
        return;
    }

    // Edit Proxy button
    if (e.target.closest('.btn-edit-proxy')) {
        document.getElementById('proxy-p-id').value = id;
        
        const select = document.getElementById('proxy-select');
        let optionsHtml = '<option value="">-- Không dùng Proxy --</option>';
        state.proxies.forEach(px => {
            optionsHtml += `<option value="${px.id}">${px.name} (${px.proxyString.split(':')[0]})</option>`;
        });
        select.innerHTML = optionsHtml;
        
        select.value = profile.proxyId || '';
        
        document.getElementById('modal-proxy').classList.add('active');
        select.focus();
        return;
    }
});

// Check all
document.getElementById('check-all').addEventListener('change', (e) => {
    if (e.target.checked) {
        state.profiles.forEach(p => state.selectedIds.add(p.id));
    } else {
        state.selectedIds.clear();
    }
    renderTable();
});

// Polling status (every 5s to reduce load, just to check if path changes externally)
setInterval(async () => {
    try {
        const config = await fetchApi('/config');
        if (config && config.profiles) {
            let changed = false;
            if (state.profiles.length !== config.profiles.length) changed = true;
            else {
                config.profiles.forEach(newP => {
                    const oldP = state.profiles.find(p => p.id === newP.id);
                    if (!oldP || oldP.path !== newP.path || oldP.name !== newP.name || oldP.status !== newP.status) {
                        changed = true;
                    }
                });
            }
            if (changed) {
                state.profiles = config.profiles;
                state.installersDir = config.installersDir || '';
                renderTable();
            }
        }
    } catch (e) {}
}, 5000);

// Init
loadData();

// Extension Folder
const btnOpenExtFolder = document.getElementById('btn-open-ext-folder');
if (btnOpenExtFolder) {
    btnOpenExtFolder.addEventListener('click', async () => {
        try {
            const res = await fetch('/api/open-extension-folder', { method: 'POST' });
            if (res.ok) {
                showToast('Đã mở thư mục Extension', 'success');
            } else {
                showToast('Lỗi khi mở thư mục', 'error');
            }
        } catch (e) {
            showToast('Lỗi kết nối', 'error');
        }
    });
}
