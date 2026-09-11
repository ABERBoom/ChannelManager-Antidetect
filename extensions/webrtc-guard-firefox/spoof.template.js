(function() {
    const targetIp = "TARGET_PROXY_IP";
    if (!targetIp) {
        console.log('[WebRTC Guard] No proxy IP configured, passthrough mode');
        return;
    }
    console.log('[WebRTC Guard] Active, spoofing to:', targetIp);

    function spoofCandidateString(candidateStr) {
        if (!candidateStr) return candidateStr;
        return candidateStr.replace(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/g, function(match) {
            if (match.startsWith("127.") || match.startsWith("10.") || match.startsWith("192.168.") || match.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) || match === "0.0.0.0") {
                return match;
            }
            return targetIp;
        });
    }

    function spoofSDP(sdp) {
        if (!sdp) return sdp;
        let hasPublic = false;
        let lines = sdp.split('\n').map(line => {
            if (line.startsWith('a=candidate:') || line.startsWith('c=')) {
                let isPublic = false;
                let spoofed = line.replace(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/g, function(match) {
                    if (match.startsWith("127.") || match.startsWith("10.") || match.startsWith("192.168.") || match.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) || match === "0.0.0.0") {
                        if (line.startsWith('c=')) {
                            isPublic = true;
                            return targetIp;
                        }
                        return match;
                    }
                    isPublic = true;
                    return targetIp;
                });
                if (isPublic) hasPublic = true;
                return spoofed;
            }
            return line;
        });
        
        if (!hasPublic) {
            let insertIdx = -1;
            let isEndOfCandidates = false;
            for (let i = lines.length - 1; i >= 0; i--) {
                if (lines[i].startsWith('a=candidate:') || lines[i].startsWith('a=end-of-candidates') || lines[i].startsWith('c=')) {
                    insertIdx = i;
                    if (lines[i].startsWith('a=end-of-candidates')) {
                        isEndOfCandidates = true;
                    }
                    break;
                }
            }
            if (insertIdx !== -1) {
                let fakeCandidate = `a=candidate:842163049 1 udp 1677729535 ${targetIp} 53421 typ srflx raddr 0.0.0.0 rport 0 generation 0`;
                if (lines[insertIdx].endsWith('\r')) {
                    fakeCandidate += '\r';
                }
                if (isEndOfCandidates) {
                    lines.splice(insertIdx, 0, fakeCandidate);
                } else {
                    lines.splice(insertIdx + 1, 0, fakeCandidate);
                }
            }
        }
        return lines.join('\n');
    }

    const toStringMap = new WeakMap();
    const origToString = Function.prototype.toString;
    Function.prototype.toString = function() {
        if (typeof this === 'function' && toStringMap.has(this)) {
            return toStringMap.get(this);
        }
        return origToString.call(this);
    };
    toStringMap.set(Function.prototype.toString, origToString.call(origToString));

    function injectSpoof(win) {
        if (!win || win._webrtcSpoofed) return;
        win._webrtcSpoofed = true;

        const OrigPeerConnection = win.RTCPeerConnection || win.webkitRTCPeerConnection || win.mozRTCPeerConnection;
        if (!OrigPeerConnection) return;

        function spoofMethod(prototype, name, original, spoofed) {
            Object.defineProperty(spoofed, 'name', { value: original.name || name, configurable: true });
            Object.defineProperty(spoofed, 'length', { value: original.length, configurable: true });
            toStringMap.set(spoofed, `function ${name}() { [native code] }`);
            
            let desc = Object.getOwnPropertyDescriptor(prototype, name) || { configurable: true, enumerable: true, writable: true };
            desc.value = spoofed;
            Object.defineProperty(prototype, name, desc);
        }

        const origCreateOffer = OrigPeerConnection.prototype.createOffer;
        if (origCreateOffer) {
            spoofMethod(OrigPeerConnection.prototype, 'createOffer', origCreateOffer, function() {
                const args = arguments;
                if (args.length > 0 && typeof args[0] === 'function') {
                    const successCallback = args[0];
                    const failureCallback = args[1];
                    const options = args[2];
                    const hookedSuccess = function(offer) {
                        if (offer && offer.sdp) {
                            offer = new win.RTCSessionDescription({ type: offer.type, sdp: spoofSDP(offer.sdp) });
                        }
                        if (successCallback) successCallback(offer);
                    };
                    return origCreateOffer.call(this, hookedSuccess, failureCallback, options);
                } else {
                    return origCreateOffer.apply(this, args).then(offer => {
                        if (offer && offer.sdp) {
                            return new win.RTCSessionDescription({ type: offer.type, sdp: spoofSDP(offer.sdp) });
                        }
                        return offer;
                    });
                }
            });
        }

        const origCreateAnswer = OrigPeerConnection.prototype.createAnswer;
        if (origCreateAnswer) {
            spoofMethod(OrigPeerConnection.prototype, 'createAnswer', origCreateAnswer, function() {
                const args = arguments;
                if (args.length > 0 && typeof args[0] === 'function') {
                    const successCallback = args[0];
                    const failureCallback = args[1];
                    const options = args[2];
                    const hookedSuccess = function(answer) {
                        if (answer && answer.sdp) {
                            answer = new win.RTCSessionDescription({ type: answer.type, sdp: spoofSDP(answer.sdp) });
                        }
                        if (successCallback) successCallback(answer);
                    };
                    return origCreateAnswer.call(this, hookedSuccess, failureCallback, options);
                } else {
                    return origCreateAnswer.apply(this, args).then(answer => {
                        if (answer && answer.sdp) {
                            return new win.RTCSessionDescription({ type: answer.type, sdp: spoofSDP(answer.sdp) });
                        }
                        return answer;
                    });
                }
            });
        }

        const origSetLocalDescription = OrigPeerConnection.prototype.setLocalDescription;
        if (origSetLocalDescription) {
            spoofMethod(OrigPeerConnection.prototype, 'setLocalDescription', origSetLocalDescription, function() {
                const args = arguments;
                let desc = args[0];
                if (desc && desc.sdp) {
                    desc = new win.RTCSessionDescription({ type: desc.type, sdp: spoofSDP(desc.sdp) });
                    args[0] = desc;
                }
                return origSetLocalDescription.apply(this, args);
            });
        }

        function patchDescriptionGetter(propName) {
            const desc = Object.getOwnPropertyDescriptor(OrigPeerConnection.prototype, propName);
            if (desc && desc.get) {
                const origGetter = desc.get;
                const spoofedGetter = function() {
                    const d = origGetter.call(this);
                    if (d && d.sdp) {
                        return new win.RTCSessionDescription({ type: d.type, sdp: spoofSDP(d.sdp) });
                    }
                    return d;
                };
                Object.defineProperty(spoofedGetter, 'name', { value: 'get ' + propName, configurable: true });
                toStringMap.set(spoofedGetter, "function get " + propName + "() { [native code] }");
                desc.get = spoofedGetter;
                Object.defineProperty(OrigPeerConnection.prototype, propName, desc);
            }
        }
        patchDescriptionGetter('localDescription');
        patchDescriptionGetter('currentLocalDescription');
        patchDescriptionGetter('pendingLocalDescription');

        const origGetStats = OrigPeerConnection.prototype.getStats;
        if (origGetStats) {
            spoofMethod(OrigPeerConnection.prototype, 'getStats', origGetStats, function(...args) {
                const promise = origGetStats.apply(this, args);
                if (promise && typeof promise.then === 'function') {
                    return promise.then(stats => {
                        if (!stats) return stats;
                        const proxyStats = new Proxy(stats, {
                            get(target, prop, receiver) {
                                let hasPublic = false;
                                for (let val of target.values()) {
                                    if (val && val.type === 'local-candidate') {
                                        if (val.address && val.address.match(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/) && !val.address.startsWith("127.") && !val.address.startsWith("10.") && !val.address.startsWith("192.168.") && !val.address.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) && val.address !== "0.0.0.0") {
                                            hasPublic = true; break;
                                        }
                                        if (val.ip && val.ip.match(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/) && !val.ip.startsWith("127.") && !val.ip.startsWith("10.") && !val.ip.startsWith("192.168.") && !val.ip.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) && val.ip !== "0.0.0.0") {
                                            hasPublic = true; break;
                                        }
                                    }
                                }

                                const fakeStat = {
                                    id: "I842163049",
                                    timestamp: performance.now(),
                                    type: "local-candidate",
                                    url: "stun:stun.l.google.com:19302",
                                    foundation: "842163049",
                                    usernameFragment: "THwj",
                                    transportId: "T01",
                                    isRemote: false,
                                    networkType: "unknown",
                                    ip: targetIp,
                                    address: targetIp,
                                    port: 53421,
                                    protocol: "udp",
                                    candidateType: "srflx",
                                    priority: 1677729535
                                };
                                const fakeRemoteCandidate = {
                                    id: "R842163049",
                                    timestamp: performance.now(),
                                    type: "remote-candidate",
                                    transportId: "T01",
                                    isRemote: true,
                                    ip: "74.125.250.129",
                                    address: "74.125.250.129",
                                    port: 19302,
                                    protocol: "udp",
                                    candidateType: "srflx",
                                    priority: 1677729534
                                };
                                const fakeCandidatePair = {
                                    id: "CP842163049",
                                    timestamp: performance.now(),
                                    type: "candidate-pair",
                                    transportId: "T01",
                                    localCandidateId: "I842163049",
                                    remoteCandidateId: "R842163049",
                                    state: "succeeded",
                                    nominated: true,
                                    writable: true,
                                    bytesSent: 1423,
                                    bytesReceived: 1852,
                                    totalRoundTripTime: 0.052,
                                    currentRoundTripTime: 0.048,
                                    priority: 9115147814917996543
                                };
                                const fakes = [fakeStat, fakeRemoteCandidate, fakeCandidatePair];

                                if (prop === 'get') {
                                    return function(key) {
                                        if (!hasPublic) {
                                            for (let fake of fakes) {
                                                if (key === fake.id) return fake;
                                            }
                                        }
                                        let val = target.get(key);
                                        if (val && val.type === 'local-candidate' && (val.address || val.ip)) {
                                            let cloned = Object.assign({}, val);
                                            if (cloned.address) cloned.address = spoofCandidateString(cloned.address);
                                            if (cloned.ip) cloned.ip = spoofCandidateString(cloned.ip);
                                            return cloned;
                                        }
                                        return val;
                                    };
                                }
                                if (prop === 'forEach') {
                                    return function(callback, thisArg) {
                                        target.forEach((val, key) => {
                                            if (val && val.type === 'local-candidate' && (val.address || val.ip)) {
                                                let cloned = Object.assign({}, val);
                                                if (cloned.address) cloned.address = spoofCandidateString(cloned.address);
                                                if (cloned.ip) cloned.ip = spoofCandidateString(cloned.ip);
                                                callback.call(thisArg, cloned, key, proxyStats);
                                            } else {
                                                callback.call(thisArg, val, key, proxyStats);
                                            }
                                        });
                                        if (!hasPublic) {
                                            for (let fake of fakes) {
                                                callback.call(thisArg, fake, fake.id, proxyStats);
                                            }
                                        }
                                    };
                                }
                                if (prop === 'values') {
                                    return function*() {
                                        for (let val of target.values()) {
                                            if (val && val.type === 'local-candidate' && (val.address || val.ip)) {
                                                let cloned = Object.assign({}, val);
                                                if (cloned.address) cloned.address = spoofCandidateString(cloned.address);
                                                if (cloned.ip) cloned.ip = spoofCandidateString(cloned.ip);
                                                yield cloned;
                                            } else {
                                                yield val;
                                            }
                                        }
                                        if (!hasPublic) {
                                            for (let fake of fakes) {
                                                yield fake;
                                            }
                                        }
                                    };
                                }
                                if (prop === 'entries') {
                                    return function*() {
                                        for (let [key, val] of target.entries()) {
                                            if (val && val.type === 'local-candidate' && (val.address || val.ip)) {
                                                let cloned = Object.assign({}, val);
                                                if (cloned.address) cloned.address = spoofCandidateString(cloned.address);
                                                if (cloned.ip) cloned.ip = spoofCandidateString(cloned.ip);
                                                yield [key, cloned];
                                            } else {
                                                yield [key, val];
                                            }
                                        }
                                        if (!hasPublic) {
                                            for (let fake of fakes) {
                                                yield [fake.id, fake];
                                            }
                                        }
                                    };
                                }
                                if (prop === Symbol.iterator) {
                                    return proxyStats.entries; 
                                }
                                const value = Reflect.get(target, prop, receiver);
                                return typeof value === 'function' ? value.bind(target) : value;
                            }
                        });
                        return proxyStats;
                    });
                }
                return promise;
            });
        }

        const origAddEventListener = OrigPeerConnection.prototype.addEventListener;
        if (origAddEventListener) {
            spoofMethod(OrigPeerConnection.prototype, 'addEventListener', origAddEventListener, function(type, listener, options) {
                if (type === 'icecandidate' && typeof listener === 'function') {
                    const wrapper = function(event) {
                        if (event.candidate) {
                            let str = event.candidate.candidate;
                            let isPublic = false;
                            let spoofedStr = str.replace(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/g, function(match) {
                                if (match.startsWith("127.") || match.startsWith("10.") || match.startsWith("192.168.") || match.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) || match === "0.0.0.0") {
                                    return match;
                                }
                                isPublic = true;
                                return targetIp;
                            });
                            
                            if (isPublic) this._hasSpoofedPublicIp = true;

                            let newCandidate = new win.RTCIceCandidate({
                                candidate: spoofedStr,
                                sdpMid: event.candidate.sdpMid,
                                sdpMLineIndex: event.candidate.sdpMLineIndex,
                                usernameFragment: event.candidate.usernameFragment
                            });
                            
                            if ('address' in event.candidate) {
                                Object.defineProperty(newCandidate, 'address', { value: spoofCandidateString(event.candidate.address), writable: false });
                            }
                            
                            const spoofedEvent = new win.RTCPeerConnectionIceEvent('icecandidate', { candidate: newCandidate });
                            Object.defineProperty(spoofedEvent, 'target', { value: this, enumerable: true });
                            Object.defineProperty(spoofedEvent, 'currentTarget', { value: this, enumerable: true });
                            return listener.call(this, spoofedEvent);
                        } else if (event.candidate === null) {
                            if (!this._hasSpoofedPublicIp) {
                                let fakeCandidateStr = `candidate:842163049 1 udp 1677729535 ${targetIp} 53421 typ srflx raddr 0.0.0.0 rport 0 generation 0`;
                                let fakeCandidate = new win.RTCIceCandidate({ candidate: fakeCandidateStr, sdpMid: "0", sdpMLineIndex: 0 });
                                const fakeEvent = new win.RTCPeerConnectionIceEvent('icecandidate', { candidate: fakeCandidate });
                                Object.defineProperty(fakeEvent, 'target', { value: this, enumerable: true });
                                Object.defineProperty(fakeEvent, 'currentTarget', { value: this, enumerable: true });
                                listener.call(this, fakeEvent);
                                this._hasSpoofedPublicIp = true;
                                setTimeout(() => {
                                    listener.call(this, event);
                                }, 10);
                                return;
                            }
                            return listener.call(this, event);
                        }
                        return listener.call(this, event);
                    };
                    this._iceWrappers = this._iceWrappers || new Map();
                    this._iceWrappers.set(listener, wrapper);
                    return origAddEventListener.call(this, type, wrapper, options);
                }
                return origAddEventListener.call(this, type, listener, options);
            });
        }

        const origRemoveEventListener = OrigPeerConnection.prototype.removeEventListener;
        if (origRemoveEventListener) {
            spoofMethod(OrigPeerConnection.prototype, 'removeEventListener', origRemoveEventListener, function(type, listener, options) {
                if (type === 'icecandidate' && this._iceWrappers && this._iceWrappers.has(listener)) {
                    const wrapper = this._iceWrappers.get(listener);
                    this._iceWrappers.delete(listener);
                    return origRemoveEventListener.call(this, type, wrapper, options);
                }
                return origRemoveEventListener.call(this, type, listener, options);
            });
        }

        const origOnIceCandidateDesc = Object.getOwnPropertyDescriptor(OrigPeerConnection.prototype, 'onicecandidate');
        if (origOnIceCandidateDesc) {
            const origOnIceCandidateSetter = origOnIceCandidateDesc.set;
            const origOnIceCandidateGetter = origOnIceCandidateDesc.get;
            
            const spoofedOnIceSetter = function(listener) {
                if (typeof listener === 'function') {
                    const wrapper = function(event) {
                        if (event.candidate) {
                            let str = event.candidate.candidate;
                            let isPublic = false;
                            let spoofedStr = str.replace(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/g, function(match) {
                                if (match.startsWith("127.") || match.startsWith("10.") || match.startsWith("192.168.") || match.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) || match === "0.0.0.0") {
                                    return match;
                                }
                                isPublic = true;
                                return targetIp;
                            });
                            
                            if (isPublic) this._hasSpoofedPublicIp = true;

                            let newCandidate = new win.RTCIceCandidate({
                                candidate: spoofedStr,
                                sdpMid: event.candidate.sdpMid,
                                sdpMLineIndex: event.candidate.sdpMLineIndex,
                                usernameFragment: event.candidate.usernameFragment
                            });
                            
                            if ('address' in event.candidate) {
                                Object.defineProperty(newCandidate, 'address', { value: spoofCandidateString(event.candidate.address), writable: false });
                            }
                            
                            const spoofedEvent = new win.RTCPeerConnectionIceEvent('icecandidate', { candidate: newCandidate });
                            Object.defineProperty(spoofedEvent, 'target', { value: this, enumerable: true });
                            Object.defineProperty(spoofedEvent, 'currentTarget', { value: this, enumerable: true });
                            return listener.call(this, spoofedEvent);
                        } else if (event.candidate === null) {
                            if (!this._hasSpoofedPublicIp) {
                                let fakeCandidateStr = `candidate:842163049 1 udp 1677729535 ${targetIp} 53421 typ srflx raddr 0.0.0.0 rport 0 generation 0`;
                                let fakeCandidate = new win.RTCIceCandidate({ candidate: fakeCandidateStr, sdpMid: "0", sdpMLineIndex: 0 });
                                const fakeEvent = new win.RTCPeerConnectionIceEvent('icecandidate', { candidate: fakeCandidate });
                                Object.defineProperty(fakeEvent, 'target', { value: this, enumerable: true });
                                Object.defineProperty(fakeEvent, 'currentTarget', { value: this, enumerable: true });
                                listener.call(this, fakeEvent);
                                this._hasSpoofedPublicIp = true;
                                setTimeout(() => {
                                    listener.call(this, event);
                                }, 10);
                                return;
                            }
                            return listener.call(this, event);
                        }
                        return listener.call(this, event);
                    };
                    this._oniceWrapper = wrapper;
                    this._oniceOriginal = listener;
                    return origOnIceCandidateSetter.call(this, wrapper);
                }
                this._oniceWrapper = null;
                this._oniceOriginal = null;
                return origOnIceCandidateSetter.call(this, listener);
            };
            Object.defineProperty(spoofedOnIceSetter, 'name', { value: 'set onicecandidate', configurable: true });
            toStringMap.set(spoofedOnIceSetter, "function set onicecandidate() { [native code] }");
            
            const spoofedOnIceGetter = function() {
                return this._oniceOriginal || origOnIceCandidateGetter.call(this);
            };
            Object.defineProperty(spoofedOnIceGetter, 'name', { value: 'get onicecandidate', configurable: true });
            toStringMap.set(spoofedOnIceGetter, "function get onicecandidate() { [native code] }");

            origOnIceCandidateDesc.set = spoofedOnIceSetter;
            origOnIceCandidateDesc.get = spoofedOnIceGetter;
            Object.defineProperty(OrigPeerConnection.prototype, 'onicecandidate', origOnIceCandidateDesc);
        }
    }

    // Protect all dynamically created iframes
    function protectIframe(iframe) {
        try {
            if (iframe.contentWindow && !iframe.contentWindow._webrtcSpoofed) {
                injectSpoof(iframe.contentWindow);
            }
        } catch (e) {}
    }

    const origAppendChild = Node.prototype.appendChild;
    Node.prototype.appendChild = function(aChild) {
        const result = origAppendChild.call(this, aChild);
        if (aChild && aChild.nodeName === 'IFRAME') {
            protectIframe(aChild);
        }
        return result;
    };
    toStringMap.set(Node.prototype.appendChild, "function appendChild() { [native code] }");

    const origInsertBefore = Node.prototype.insertBefore;
    Node.prototype.insertBefore = function(newNode, referenceNode) {
        const result = origInsertBefore.call(this, newNode, referenceNode);
        if (newNode && newNode.nodeName === 'IFRAME') {
            protectIframe(newNode);
        }
        return result;
    };
    toStringMap.set(Node.prototype.insertBefore, "function insertBefore() { [native code] }");

    const origContentWindowDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'contentWindow');
    if (origContentWindowDesc && origContentWindowDesc.get) {
        const origContentWindowGetter = origContentWindowDesc.get;
        const spoofedContentWindowGetter = function() {
            const cw = origContentWindowGetter.call(this);
            if (cw && !cw._webrtcSpoofed) injectSpoof(cw);
            return cw;
        };
        Object.defineProperty(spoofedContentWindowGetter, 'name', { value: 'get contentWindow', configurable: true });
        toStringMap.set(spoofedContentWindowGetter, "function get contentWindow() { [native code] }");
        origContentWindowDesc.get = spoofedContentWindowGetter;
        Object.defineProperty(HTMLIFrameElement.prototype, 'contentWindow', origContentWindowDesc);
    }

    const origContentDocumentDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'contentDocument');
    if (origContentDocumentDesc && origContentDocumentDesc.get) {
        const origContentDocumentGetter = origContentDocumentDesc.get;
        const spoofedContentDocumentGetter = function() {
            const cd = origContentDocumentGetter.call(this);
            if (cd && cd.defaultView && !cd.defaultView._webrtcSpoofed) injectSpoof(cd.defaultView);
            return cd;
        };
        Object.defineProperty(spoofedContentDocumentGetter, 'name', { value: 'get contentDocument', configurable: true });
        toStringMap.set(spoofedContentDocumentGetter, "function get contentDocument() { [native code] }");
        origContentDocumentDesc.get = spoofedContentDocumentGetter;
        Object.defineProperty(HTMLIFrameElement.prototype, 'contentDocument', origContentDocumentDesc);
    }

    // Inject into the main window
    injectSpoof(window);

})();
