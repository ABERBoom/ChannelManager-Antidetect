// WebRTC Guard - Dynamic Background Script
let proxyIp = null;
let fetchPromise = null;

function fetchProxyIp(retries = 10) {
    return new Promise((resolve) => {
        const xhr = new XMLHttpRequest();
        xhr.open('GET', 'http://webrtc.local.guard/ip', true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200 && xhr.responseText) {
                    proxyIp = xhr.responseText.trim();
                    console.log("[WebRTC Guard] Fetched Proxy IP:", proxyIp);
                    injectContentScript().then(resolve);
                } else {
                    console.error("[WebRTC Guard] Failed to fetch proxy IP. Status:", xhr.status);
                    if (retries > 0) {
                        setTimeout(() => fetchProxyIp(retries - 1).then(resolve), 500);
                    } else {
                        resolve();
                    }
                }
            }
        };
        xhr.onerror = function() {
            console.error("[WebRTC Guard] Error fetching proxy IP (no proxy active?)");
            if (retries > 0) {
                setTimeout(() => fetchProxyIp(retries - 1).then(resolve), 500);
            } else {
                resolve();
            }
        };
        // Set short timeout in case there's no proxy relay answering
        xhr.timeout = 2000;
        xhr.ontimeout = function() {
            console.error("[WebRTC Guard] Timeout fetching proxy IP");
            if (retries > 0) {
                setTimeout(() => fetchProxyIp(retries - 1).then(resolve), 500);
            } else {
                resolve();
            }
        };
        xhr.send();
    });
}

function injectContentScript() {
    if (!proxyIp) return Promise.resolve();
    
    // Read spoof.js
    return fetch(browser.runtime.getURL('spoof.js'))
        .then(response => response.text())
        .then(spoofCode => {
            const fullScript = "const TARGET_PROXY_IP = '" + proxyIp + "';\n" + spoofCode;
            const encoded = btoa(unescape(encodeURIComponent(fullScript)));
            
            const finalCode = `const s = document.createElement('script');
const code = new TextDecoder().decode(Uint8Array.from(atob("${encoded}"), c => c.charCodeAt(0)));
s.textContent = code;
(document.head || document.documentElement).prepend(s);
s.remove();`;
            
            return browser.contentScripts.register({
                matches: ["<all_urls>"],
                js: [{ code: finalCode }],
                runAt: "document_start",
                allFrames: true
            }).then(() => {
                console.log("[WebRTC Guard] Content script registered dynamically.");
            });
        });
}
// Block the first requests until we have the IP, so the content script has time to register
let isInitialized = false;
fetchPromise = fetchProxyIp().then(() => {
    isInitialized = true;
});

browser.webRequest.onBeforeRequest.addListener(
    function(details) {
        if (!isInitialized) {
            // Block the page load completely by returning the promise. 
            // Firefox will wait until fetchPromise resolves before continuing the request!
            return fetchPromise.then(() => ({}));
        }
        return {};
    },
    { urls: ["<all_urls>"], types: ["main_frame"] },
    ["blocking"]
);

