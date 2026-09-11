console.log('[WebRTC Guard] content.js loaded');
var s = document.createElement('script');
s.src = chrome.runtime.getURL('spoof.js');
s.onload = function() { this.remove(); };
(document.head || document.documentElement).appendChild(s);
