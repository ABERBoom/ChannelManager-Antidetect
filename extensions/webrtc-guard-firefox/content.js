// WebRTC Guard - Content Script (Firefox)
// Injects spoofing code into page world to override RTCPeerConnection
(function() {
  var s = document.createElement('script');
  s.src = browser.runtime.getURL('spoof.js');
  s.onload = function() { this.remove(); };
  (document.head || document.documentElement).prepend(s);
})();
