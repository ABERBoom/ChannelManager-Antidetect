let checks = 0;
let interval = setInterval(() => {
    checks++;
    let text = document.body.innerText;
    let match = text.match(/WebRTC:\s*([^\n]+)/);
    if (match && match[1] && !match[1].includes('N/A') && !match[1].includes('Checking')) {
        clearInterval(interval);
        fetch('http://localhost:9999/report?webrtc=' + encodeURIComponent(match[1]));
    } else if (match && match[1] && match[1].includes('N/A') && checks > 15) {
        clearInterval(interval);
        fetch('http://localhost:9999/report?webrtc=N_A_DETECTED');
    } else if (checks > 30) {
        clearInterval(interval);
        fetch('http://localhost:9999/report?webrtc=TIMEOUT');
    }
}, 1000);
