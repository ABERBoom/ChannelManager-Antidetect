param(
    [int]$Port,
    [string]$SpoofScriptPath
)

$logPath = "E:\TOOL\Source Code\Agent Antigravity\scratch\inject_log.txt"
function log($msg) { Add-Content -Path $logPath -Value ($msg) }

log "Starting on port $Port"
$url = "http://127.0.0.1:$Port/json/version"
$wsUrl = $null
for ($i = 0; $i -lt 30; $i++) {
    try {
        $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
        $wsUrl = $response.webSocketDebuggerUrl
        log "Found wsUrl: $wsUrl"
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $wsUrl) { log "Could not find wsUrl"; exit }

Add-Type -AssemblyName System.Net.Http

# C# helper for WebSocket since PowerShell 5 doesn't easily do async WebSockets in runspaces
$csCode = @"
using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.IO;

public class CDPHelper {
    public static void Log(string msg) {
        File.AppendAllText(@"E:\TOOL\Source Code\Agent Antigravity\scratch\inject_log.txt", msg + "\n");
    }

    public static async Task Inject(string wsUrl, string script) {
        using (ClientWebSocket ws = new ClientWebSocket()) {
            await ws.ConnectAsync(new Uri(wsUrl), CancellationToken.None);
            Log("Connected to WS");
            
            // SetDiscoverTargets
            string msg1 = "{\"id\":1,\"method\":\"Target.setDiscoverTargets\",\"params\":{\"discover\":true}}";
            await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(msg1)), WebSocketMessageType.Text, true, CancellationToken.None);
            
            byte[] buffer = new byte[8192];
            while (ws.State == WebSocketState.Open) {
                WebSocketReceiveResult result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
                string response = Encoding.UTF8.GetString(buffer, 0, result.Count);
                Log("RECV: " + response);
                
                if (response.Contains("Target.targetCreated") && response.Contains("\"type\":\"page\"")) {
                    int idx = response.IndexOf("\"targetId\":\"") + 12;
                    int endIdx = response.IndexOf("\"", idx);
                    string targetId = response.Substring(idx, endIdx - idx);
                    
                    string msg2 = "{\"id\":2,\"method\":\"Target.attachToTarget\",\"params\":{\"targetId\":\"" + targetId + "\",\"flatten\":true}}";
                    await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(msg2)), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                
                if (response.Contains("Target.attachedToTarget")) {
                    int idx = response.IndexOf("\"sessionId\":\"") + 13;
                    int endIdx = response.IndexOf("\"", idx);
                    string sessionId = response.Substring(idx, endIdx - idx);
                    
                    string escapedScript = script.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "\\r");
                    
                    string msg3 = "{\"id\":3,\"sessionId\":\"" + sessionId + "\",\"method\":\"Page.addScriptToEvaluateOnNewDocument\",\"params\":{\"source\":\"" + escapedScript + "\"}}";
                    await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(msg3)), WebSocketMessageType.Text, true, CancellationToken.None);
                    
                    string msg4 = "{\"id\":4,\"sessionId\":\"" + sessionId + "\",\"method\":\"Page.enable\"}";
                    await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(msg4)), WebSocketMessageType.Text, true, CancellationToken.None);
                }
            }
        }
    }
}
"@

try {
    Add-Type -TypeDefinition $csCode
} catch {}

$scriptContent = Get-Content $SpoofScriptPath -Raw
[CDPHelper]::Inject($wsUrl, $scriptContent).Wait()
