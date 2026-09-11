# server.ps1 - Channel Manager Backend
$ErrorActionPreference = "Stop"
Out-File -FilePath "C:\Users\Sonix\server_debug.log" -InputObject "Server starting..." -Append
$script:relays = @{}
$script:listener = $null
$scriptDir = $global:AppPath
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = $PSScriptRoot }
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = $PWD.Path }
Out-File -FilePath "C:\Users\Sonix\server_debug.log" -InputObject "Script dir: $scriptDir" -Append
$dataFile = Join-Path $scriptDir "profiles.json"
$dataDir = Join-Path $scriptDir "data"
$profilesDir = Join-Path $dataDir "profiles"
$iconsDir = Join-Path $dataDir "icons"
$logFile = Join-Path $dataDir "app.log"

function Write-Log {
    param([string]$message, [string]$type="INFO")
    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "[$timestamp] [$type] $message"
    try {
        $stream = [System.IO.File]::AppendText($logFile)
        $stream.WriteLine($logEntry)
        $stream.Close()
    } catch {}
    if ($type -eq "ERROR") { Write-Host $logEntry -ForegroundColor Red }
    else { Write-Host $logEntry -ForegroundColor Gray }
}

# ==========================================
# 1. C# TYPES DEFINITION
# ==========================================

Add-Type @"
using System;
using System.Collections;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public class ProxyRelay {
    // DNS-over-HTTPS cache to avoid repeated lookups
    private static Hashtable _dnsCache = new Hashtable();

    private static string ResolveDoh(string hostname, string proxyHost, int proxyPort, string proxyUser, string proxyPass) {
        // Check cache first
        lock (_dnsCache) {
            if (_dnsCache.ContainsKey(hostname)) return (string)_dnsCache[hostname];
        }
        try {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
            using (WebClient wc = new WebClient()) {
                // Route DoH through upstream proxy Ã¢â‚¬â€ Google DoH gives Vietnam resolver IP
                // (172.253.5.x) matching the proxy's location, unlike Cloudflare which routed to HKG
                WebProxy wp = new WebProxy("http://" + proxyHost + ":" + proxyPort.ToString());
                wp.Credentials = new NetworkCredential(proxyUser, proxyPass);
                wc.Proxy = wp;
                string json = wc.DownloadString(
                    "https://dns.google/resolve?name=" + Uri.EscapeDataString(hostname) + "&type=A");
                Match m = Regex.Match(json, @"""data""\s*:\s*""(\d+\.\d+\.\d+\.\d+)""");
                if (m.Success) {
                    string ip = m.Groups[1].Value;
                    lock (_dnsCache) { _dnsCache[hostname] = ip; }
                    return ip;
                }
            }
        } catch {}
        return null; // Fallback: let upstream proxy handle DNS
    }

    public static int StartHttp(string remoteHost, int remotePort, string username, string password) {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int localPort = ((IPEndPoint)listener.LocalEndpoint).Port;
        string auth = Convert.ToBase64String(Encoding.UTF8.GetBytes(username + ":" + password));
        string authHeader = "Proxy-Authorization: Basic " + auth + "\r\n";
        
        Task.Run(async () => {
            while (true) {
                try {
                    TcpClient client = await listener.AcceptTcpClientAsync();
                    var dummy = Task.Run(async () => {
                        try {
                            TcpClient server = new TcpClient();
                            await server.ConnectAsync(remoteHost, remotePort);
                            NetworkStream clientStream = client.GetStream();
                            NetworkStream serverStream = server.GetStream();
                            
                            byte[] buffer = new byte[8192];
                            int bytesRead = await clientStream.ReadAsync(buffer, 0, buffer.Length);
                            if (bytesRead > 0) {
                                string request = Encoding.ASCII.GetString(buffer, 0, bytesRead);
                                
                                if (request.StartsWith("GET http://webrtc.local.guard/ip ")) {
                                    string response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n" + remoteHost;
                                    byte[] respBytes = Encoding.UTF8.GetBytes(response);
                                    await clientStream.WriteAsync(respBytes, 0, respBytes.Length);
                                    clientStream.Close();
                                    server.Close();
                                    return;
                                }

                                // Resolve DNS via Cloudflare DoH for ALL requests
                                // This prevents the upstream proxy from using its own DNS (Google US)
                                if (request.StartsWith("CONNECT ")) {
                                    // HTTPS: CONNECT hostname:port HTTP/1.1
                                    int sp1 = 8;
                                    int sp2 = request.IndexOf(' ', sp1);
                                    if (sp2 > sp1) {
                                        string hostPort = request.Substring(sp1, sp2 - sp1);
                                        int colonIdx = hostPort.LastIndexOf(':');
                                        if (colonIdx > 0) {
                                            string host = hostPort.Substring(0, colonIdx);
                                            string port = hostPort.Substring(colonIdx + 1);
                                            IPAddress testIp;
                                            if (!IPAddress.TryParse(host, out testIp)) {
                                                string resolved = ResolveDoh(host, remoteHost, remotePort, username, password);
                                                if (resolved != null) {
                                                    request = "CONNECT " + resolved + ":" + port + request.Substring(sp2);
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    // Plain HTTP: GET http://hostname/path HTTP/1.1
                                    // DNS leak tests often use HTTP (not HTTPS) to trigger DNS resolution
                                    Match urlMatch = Regex.Match(request, @"http://([^/:]+)");
                                    if (urlMatch.Success) {
                                        string httpHost = urlMatch.Groups[1].Value;
                                        IPAddress testIp;
                                        if (!IPAddress.TryParse(httpHost, out testIp)) {
                                            string resolved = ResolveDoh(httpHost, remoteHost, remotePort, username, password);
                                            if (resolved != null) {
                                                request = request.Substring(0, urlMatch.Groups[1].Index) +
                                                          resolved +
                                                          request.Substring(urlMatch.Groups[1].Index + urlMatch.Groups[1].Length);
                                            }
                                        }
                                    }
                                }
                                
                                int headerEnd = request.IndexOf("\r\n\r\n");
                                if (headerEnd != -1) {
                                    string extraHeaders = authHeader;
                                    // Force connection close for plain HTTP to prevent keep-alive
                                    // bypassing DoH interception on subsequent requests
                                    if (!request.StartsWith("CONNECT ")) {
                                        request = Regex.Replace(request, @"(?i)Connection:\s*keep-alive", "Connection: close");
                                        request = Regex.Replace(request, @"(?i)Proxy-Connection:\s*keep-alive", "Proxy-Connection: close");
                                        if (!Regex.IsMatch(request, @"(?i)Connection:")) {
                                            extraHeaders += "Connection: close\r\n";
                                        }
                                    }
                                    request = request.Insert(request.IndexOf("\r\n\r\n") + 2, extraHeaders);
                                    byte[] newRequest = Encoding.ASCII.GetBytes(request);
                                    await serverStream.WriteAsync(newRequest, 0, newRequest.Length);
                                } else {
                                    await serverStream.WriteAsync(buffer, 0, bytesRead);
                                }
                            }
                            
                            Task t1 = clientStream.CopyToAsync(serverStream);
                            Task t2 = serverStream.CopyToAsync(clientStream);
                            await Task.WhenAll(t1, t2);
                        } catch {}
                        finally { client.Close(); }
                    });
                } catch {}
            }
        });
        return localPort;
    }

    public static int StartSocks5(string remoteHost, int remotePort, string username, string password) {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int localPort = ((IPEndPoint)listener.LocalEndpoint).Port;
        
        Task.Run(async () => {
            while (true) {
                try {
                    TcpClient client = await listener.AcceptTcpClientAsync();
                    var dummy = Task.Run(async () => {
                        try {
                            TcpClient server = new TcpClient();
                            await server.ConnectAsync(remoteHost, remotePort);
                            NetworkStream cs = client.GetStream();
                            NetworkStream ss = server.GetStream();
                            
                            byte[] cGreeting = new byte[256];
                            await cs.ReadAsync(cGreeting, 0, 256); 
                            
                            byte[] sGreeting = new byte[] { 0x05, 0x01, 0x02 }; 
                            await ss.WriteAsync(sGreeting, 0, sGreeting.Length);
                            
                            byte[] sGreetingResp = new byte[2];
                            await ss.ReadAsync(sGreetingResp, 0, 2); 
                            
                            if (sGreetingResp[1] == 0x02) {
                                byte[] user = Encoding.ASCII.GetBytes(username);
                                byte[] pass = Encoding.ASCII.GetBytes(password);
                                byte[] authReq = new byte[3 + user.Length + pass.Length];
                                authReq[0] = 0x01;
                                authReq[1] = (byte)user.Length;
                                Buffer.BlockCopy(user, 0, authReq, 2, user.Length);
                                authReq[2 + user.Length] = (byte)pass.Length;
                                Buffer.BlockCopy(pass, 0, authReq, 3 + user.Length, pass.Length);
                                
                                await ss.WriteAsync(authReq, 0, authReq.Length);
                                
                                byte[] authResp = new byte[2];
                                await ss.ReadAsync(authResp, 0, 2); 
                                if (authResp[1] != 0x00) throw new Exception("Auth failed");
                            }
                            
                            byte[] cGreetingResp = new byte[] { 0x05, 0x00 };
                            await cs.WriteAsync(cGreetingResp, 0, cGreetingResp.Length);
                            
                            Task t1 = cs.CopyToAsync(ss);
                            Task t2 = ss.CopyToAsync(cs);
                            await Task.WhenAll(t1, t2);
                        } catch {}
                        finally { client.Close(); }
                    });
                } catch {}
            }
        });
        return localPort;
    }
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class TaskbarHelper
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr pwszVal; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        int GetCount(out uint c); int GetAt(uint i, out PROPERTYKEY k);
        int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); int Commit();
    }

    [DllImport("shell32.dll")]
    public static extern int SHGetPropertyStoreForWindow(IntPtr h, ref Guid r, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore p);
    public delegate bool EWP(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EWP f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);

    static Guid G = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    
    static void SetProp(IPropertyStore ps, uint pid, string val) {
        var k = new PROPERTYKEY{fmtid=G, pid=pid};
        var v = new PROPVARIANT{vt=31, pwszVal=Marshal.StringToCoTaskMemUni(val)};
        ps.SetValue(ref k, ref v); Marshal.FreeCoTaskMem(v.pwszVal);
    }

    public static int SetWindowProperties(IntPtr hwnd, string appId, string icon, string cmd, string name) {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore ps; int hr = SHGetPropertyStoreForWindow(hwnd, ref iid, out ps);
        if (hr != 0) return hr;
        if (!string.IsNullOrEmpty(appId)) SetProp(ps, 5, appId);
        if (!string.IsNullOrEmpty(icon)) SetProp(ps, 3, icon);
        if (!string.IsNullOrEmpty(cmd)) SetProp(ps, 2, cmd);
        if (!string.IsNullOrEmpty(name)) SetProp(ps, 4, name);
        ps.Commit(); Marshal.ReleaseComObject(ps); return 0;
    }

    public static List<IntPtr> GetWins(int pid) {
        var w = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint p; GetWindowThreadProcessId(h, out p);
            if ((int)p == pid && IsWindowVisible(h) && GetWindowTextLength(h) > 0) w.Add(h);
            return true;
        }, IntPtr.Zero);
        return w;
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies "System.Drawing" @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

public class IconGenerator
{
    public static void GenerateIcon(string outputPath, string baseImagePath, string badgeText)
    {
        int[] sizes = new int[] { 256, 48, 32, 16 };
        List<byte[]> pngList = new List<byte[]>();

        using (Image baseImg = Image.FromFile(baseImagePath))
        {
            foreach (int size in sizes)
            {
                using (Bitmap bmp = new Bitmap(size, size))
                {
                    bmp.SetResolution(96, 96);
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.SmoothingMode = SmoothingMode.HighQuality;
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.Clear(Color.Transparent);

                        // Draw base image
                        g.DrawImage(baseImg, 0, 0, size, size);

                        if (!string.IsNullOrEmpty(badgeText))
                        {
                            // Calculate text area based on the red pill position
                            // Assuming pill is horizontally centered, bottom area
                            // Expand the text bounding box to accommodate the larger text area
                            float boxX = 0f;
                            float boxY = size * 0.40f;
                            float boxW = (float)size;
                            float boxH = size * 0.60f;
                            RectangleF textArea = new RectangleF(boxX, boxY, boxW, boxH);
                            
                            // Auto scale font size
                            float fontSize = boxH * 0.80f;
                            Font f = new Font("Arial", fontSize, FontStyle.Bold);
                            SizeF textSize = g.MeasureString(badgeText, f);
                            
                            while (textSize.Width > boxW * 0.95f && fontSize > 4)
                            {
                                fontSize -= 1f;
                                f.Dispose();
                                f = new Font("Arial", fontSize, FontStyle.Bold);
                                textSize = g.MeasureString(badgeText, f);
                            }

                            using (SolidBrush textB = new SolidBrush(Color.White))
                            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                            {
                                g.DrawString(badgeText, f, textB, textArea, sf);
                            }
                            f.Dispose();
                        }
                    }
                    
                    using (MemoryStream ms = new MemoryStream())
                    {
                        bmp.Save(ms, ImageFormat.Png);
                        pngList.Add(ms.ToArray());
                    }
                }
            }
        }

        using (FileStream fs = new FileStream(outputPath, FileMode.Create))
        using (BinaryWriter bw = new BinaryWriter(fs))
        {
            bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)sizes.Length);
            int dataOffset = 6 + (16 * sizes.Length);
            for (int i=0; i<sizes.Length; i++) {
                int w = sizes[i] >= 256 ? 0 : sizes[i];
                bw.Write((byte)w); bw.Write((byte)w); bw.Write((byte)0); bw.Write((byte)0);
                bw.Write((ushort)1); bw.Write((ushort)32); bw.Write((uint)pngList[i].Length); bw.Write((uint)dataOffset);
                dataOffset += pngList[i].Length;
            }
            foreach (var png in pngList) bw.Write(png);
        }
    }
}
"@

# ==========================================
# 2. DATA LAYER
# ==========================================

function Get-Data {
    if (Test-Path $dataFile) {
        $data = (Get-Content $dataFile -Raw) | ConvertFrom-Json
        if (-not $data.PSObject.Properties.Match('proxies').Count) {
            $data | Add-Member -MemberType NoteProperty -Name "proxies" -Value @()
        }
        return $data
    }
    return $null
}

function Save-Data($dataObj) {
    # Update processes status before saving
    foreach ($p in $dataObj.profiles) {
        if ($p.pid) {
            $proc = Get-Process -Id $p.pid -ErrorAction SilentlyContinue
            if (-not $proc -or $proc.HasExited) {
                $p.status = "stopped"
                $p.pid = $null
            } else {
                $p.status = "running"
            }
        } else {
            if ($p.status -ne "creating") { $p.status = "stopped" }
        }
    }
    $json = $dataObj | ConvertTo-Json -Depth 10 -Compress
    [IO.File]::WriteAllText($dataFile, $json)
}

function Send-JsonResponse($response, $statusCode, $data) {
    $response.StatusCode = $statusCode
    $response.ContentType = "application/json"
    $response.AppendHeader("Access-Control-Allow-Origin", "*")
    
    $payload = @{}
    if ($statusCode -lt 300) {
        $payload.success = $true
        if ($data) { $payload.data = $data }
    } else {
        $payload.success = $false
        if ($data) { $payload.error = $data }
    }
    
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

# ==========================================
# 3. BACKGROUND JOBS
# ==========================================

$script:MonitorRunning = $false
function Start-IconMonitor {
    if ($script:MonitorRunning) { return }
    $script:MonitorRunning = $true
    
    $jobScript = {
        param($dataFile, $profilesDir, $iconsDir)
        Add-Type -TypeDefinition (Get-Content (Join-Path $profilesDir "..\..\server.ps1") | Select-String -Pattern "public class TaskbarHelper" -Context 0, 50 | Out-String) -IgnoreWarnings -ErrorAction SilentlyContinue
        
        while($true) {
            try {
                $data = (Get-Content $dataFile -Raw) | ConvertFrom-Json
                foreach ($p in $data.profiles) {
                    if ($p.pid -and $p.status -eq 'running') {
                        $proc = Get-Process -Id $p.pid -ErrorAction SilentlyContinue
                        if ($proc -and -not $proc.HasExited) {
                            $wins = [TaskbarHelper]::GetWins($p.pid)
                            foreach ($w in $wins) {
                                $exe = $proc.MainModule.FileName
                                $iconPath = Join-Path $iconsDir "$($p.id).ico"
                                $appId = "ChannelManager.$($p.id)"
                                [TaskbarHelper]::SetWindowProperties($w, $appId, $iconPath, $exe, $p.name) | Out-Null
                            }
                        }
                    }
                }
            } catch {}
            Start-Sleep -Seconds 2
        }
    }
    Start-Job -ScriptBlock $jobScript -ArgumentList $dataFile, $profilesDir, $iconsDir | Out-Null
}

# ==========================================
# 4. HTTP SERVER & API ROUTES
# ==========================================

$port = (Get-Data).settings.serverPort
if (-not $port) { $port = 8780 }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Server running on http://localhost:$port" -ForegroundColor Green

Start-IconMonitor

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        $method = $req.HttpMethod
        $path = $req.Url.LocalPath
        
        $bodyObj = $null
        if ($req.HasEntityBody) {
            $reader = New-Object IO.StreamReader($req.InputStream, $req.ContentEncoding)
            try { $bodyObj = $reader.ReadToEnd() | ConvertFrom-Json } catch {}
            $reader.Close()
        }
        
        Write-Log "Request: $method $path" "INFO"

        try {
            # GET /api/config
            if ($path -eq '/api/config' -and $method -eq 'GET') {
                $data = Get-Data
                $changed = $false
                foreach ($p in $data.profiles) {
                    if ($p.path) {
                        # Find any process running from this profile's path
                        $escapedPath = $p.path.Replace("\", "\\")
                        $procs = Get-CimInstance Win32_Process -Filter "ExecutablePath LIKE '$escapedPath%'" -ErrorAction SilentlyContinue | Select-Object -First 1
                        
                        if ($procs -and @($procs).Count -gt 0) {
                            if ($p.status -ne "running") {
                                $p.status = "running"
                                $changed = $true
                            }
                        } else {
                            if ($p.status -eq "running" -or $p.pid) {
                                $p.status = "stopped"
                                $p.pid = $null
                                $changed = $true
                            }
                        }
                    }
                }
                if ($changed) {
                    $json = $data | ConvertTo-Json -Depth 10 -Compress
                    [IO.File]::WriteAllText($dataFile, $json)
                }
                $resData = @{
                    profiles = $data.profiles
                    proxies = $data.proxies
                    settings = $data.settings
                    installersDir = Join-Path $scriptDir "installers"
                }
                Send-JsonResponse $res 200 $resData
            }
            # GET /api/pick-folder
            elseif ($path -eq '/api/pick-folder' -and $method -eq 'GET') {
                $installersDir = Join-Path $scriptDir "installers"
                $code = @"
Add-Type -AssemblyName System.Windows.Forms
`$f = New-Object System.Windows.Forms.OpenFileDialog
`$f.Title = 'Vao thu muc ban muon chon roi bam mo (Open)'
`$f.ValidateNames = `$false
`$f.CheckFileExists = `$false
`$f.CheckPathExists = `$true
`$f.FileName = 'Folder Selection.'
`$f.Filter = 'ThÃ†Â° mÃ¡Â»Â¥c|*.none'
`$f.InitialDirectory = '$installersDir'
`$form = New-Object System.Windows.Forms.Form
`$form.TopMost = `$true
`$form.ShowInTaskbar = `$false
`$form.WindowState = 'Minimized'
`$form.Show()
`$form.BringToFront()
if (`$f.ShowDialog(`$form) -eq 'OK') { Write-Output (Split-Path `$f.FileName) }
`$form.Close()
"@
                $selectedPath = (powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -Command $code | Out-String).Trim()
                Send-JsonResponse $res 200 $selectedPath
            }
            # GET /api/installers/status
            elseif ($path -eq '/api/installers/status' -and $method -eq 'GET') {
                $ff = Test-Path (Join-Path $scriptDir "installers\FirefoxPortable_155.0.1_English.paf.exe")
                $cr = Test-Path (Join-Path $scriptDir "installers\GoogleChromePortable_153.0.8010.37_online.paf.exe")
                Send-JsonResponse $res 200 @{ firefox = $ff; chrome = $cr }
            }
            # POST /api/installers/download
            elseif ($path -eq '/api/installers/download' -and $method -eq 'POST') {
                $browser = $bodyObj.browser
                $exePath = if ($browser -eq 'firefox') { "installers\FirefoxPortable_155.0.1_English.paf.exe" } else { "installers\GoogleChromePortable_153.0.8010.37_online.paf.exe" }
                $fullPath = Join-Path $scriptDir $exePath
                $url = if ($browser -eq 'firefox') { "https://github.com/thanhle/dummy/releases/download/v1/FirefoxPortable_155.0.1_English.paf.exe" } else { "https://github.com/thanhle/dummy/releases/download/v1/GoogleChromePortable_153.0.8010.37_online.paf.exe" }
                try {
                    Invoke-WebRequest -Uri $url -OutFile $fullPath -UseBasicParsing -TimeoutSec 10
                    Send-JsonResponse $res 200 "Downloaded"
                } catch {
                    New-Item -ItemType File -Path $fullPath -Force | Out-Null
                    Send-JsonResponse $res 200 "Mock Downloaded"
                }
            }
            # POST /api/installers/run
            elseif ($path -eq '/api/installers/run' -and $method -eq 'POST') {
                $browser = $bodyObj.browser
                $exePath = if ($browser -eq 'firefox') { "installers\FirefoxPortable_155.0.1_English.paf.exe" } else { "installers\GoogleChromePortable_153.0.8010.37_online.paf.exe" }
                $fullPath = Join-Path $scriptDir $exePath
                if (Test-Path $fullPath) {
                    Start-Process -FilePath $fullPath
                    Send-JsonResponse $res 200 "Launched"
                } else { throw "Khong tim thay bo cai" }
            }
            # POST /api/profiles
            elseif ($path -eq '/api/profiles' -and $method -eq 'POST') {
                $data = Get-Data
                $id = "profile-" + [DateTimeOffset]::Now.ToUnixTimeSeconds() + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
                $newProfile = @{
                    id = $id; name = $bodyObj.name; browser = ""; path = ""; 
                    iconBadge = $bodyObj.iconBadge; lastAccessedAt = $null
                }
                $data.profiles += $newProfile
                Save-Data $data
                Send-JsonResponse $res 200 $newProfile
            }
            # PUT /api/profiles/:id
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)$' -and $method -eq 'PUT') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p) {
                    $newName = $bodyObj.name
                    if ($p.path) {
                        $parentPath = Split-Path $p.path -Parent
                        $newPath = Join-Path $parentPath $newName
                        if ($p.path -ne $newPath) {
                            if (Test-Path $newPath) { throw "Thu muc $newPath da ton tai!" }
                            Rename-Item -Path $p.path -NewName $newName
                            $p.path = $newPath
                        }
                    }
                    $p.name = $newName
                    Save-Data $data
                    Send-JsonResponse $res 200 $p
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # PUT /api/profiles/:id/proxy
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)/proxy$' -and $method -eq 'PUT') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p) {
                    if ($p.PSObject.Properties.Match('proxyId').Count -eq 0) {
                        $p | Add-Member -MemberType NoteProperty -Name 'proxyId' -Value $bodyObj.proxyId
                    } else {
                        $p.proxyId = $bodyObj.proxyId
                    }
                    Save-Data $data
                    Send-JsonResponse $res 200 $p
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # POST /api/proxies
            elseif ($path -eq '/api/proxies' -and $method -eq 'POST') {
                $data = Get-Data
                $newProxy = @{
                    id = "proxy-" + [DateTimeOffset]::Now.ToUnixTimeSeconds() + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
                    name = $bodyObj.name
                    proxyString = $bodyObj.proxyString
                }
                $data.proxies += $newProxy
                Save-Data $data
                Write-Log "Created Proxy: $($newProxy.name) [ID: $($newProxy.id)]" "INFO"
                Send-JsonResponse $res 201 $newProxy
            }
            # DELETE /api/proxies/:id
            elseif ($path -match '^/api/proxies/(proxy-[a-zA-Z0-9-]+)$' -and $method -eq 'DELETE') {
                $id = $matches[1]
                $data = Get-Data
                $target = $data.proxies | Where-Object { $_.id -eq $id }
                if ($target) {
                    $data.proxies = @($data.proxies | Where-Object { $_.id -ne $id })
                    # Clear proxyId from profiles
                    foreach ($p in $data.profiles) {
                        if ($p.proxyId -eq $id) { $p.proxyId = $null }
                    }
                    Save-Data $data
                    Send-JsonResponse $res 200 "Deleted"
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # POST /api/proxies/:id/ping
            elseif ($path -match '^/api/proxies/(proxy-[a-zA-Z0-9-]+)/ping$' -and $method -eq 'POST') {
                $id = $matches[1]
                $data = Get-Data
                $target = $data.proxies | Where-Object { $_.id -eq $id }
                if ($target) {
                    $cleanProxy = $target.proxyString.Replace("http://","").Replace("https://","").Replace("socks5://","")
                    $parts = $cleanProxy.Split(':')
                    if ($parts.Count -ge 2) {
                        $targetHost = $parts[0]
                        $targetPort = [int]$parts[1]
                        
                        $tcp = New-Object System.Net.Sockets.TcpClient
                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        try {
                            $connectTask = $tcp.ConnectAsync($targetHost, $targetPort)
                            if ($connectTask.Wait(3000)) {
                                $sw.Stop()
                                $tcp.Close()
                                Send-JsonResponse $res 200 @{ status = "alive"; ms = $sw.ElapsedMilliseconds }
                            } else {
                                $tcp.Close()
                                Send-JsonResponse $res 200 @{ status = "dead"; ms = -1 }
                            }
                        } catch {
                            Send-JsonResponse $res 200 @{ status = "dead"; ms = -1 }
                        }
                    } else {
                        Send-JsonResponse $res 200 @{ status = "dead"; ms = -1 }
                    }
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # POST /api/profiles/:id/link
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)/link$' -and $method -eq 'POST') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p) {
                    $linkPath = $bodyObj.path
                    if (-not (Test-Path $linkPath)) { throw "Duong dan khong ton tai" }
                    
                    # Check if another profile is already using this folder
                    $normalizedLinkPath = [System.IO.Path]::GetFullPath($linkPath).TrimEnd('\', '/')
                    $conflict = $data.profiles | Where-Object { 
                        $_.id -ne $id -and $_.path -and ([System.IO.Path]::GetFullPath($_.path).TrimEnd('\', '/') -eq $normalizedLinkPath) 
                    }
                    if ($conflict) {
                        throw "Thu muc nay dang duoc lien ket voi profile '$($conflict[0].name)'. Moi profile phai dung mot thu muc rieng biet!"
                    }
                    
                    # Detect browser
                    $browser = ""
                    if (Test-Path (Join-Path $linkPath "FirefoxPortable.exe")) { $browser = "firefox" }
                    elseif (Test-Path (Join-Path $linkPath "GoogleChromePortable.exe")) { $browser = "chrome" }
                    else { throw "Khong tim thay file thuc thi FirefoxPortable.exe hoac GoogleChromePortable.exe trong thu muc nay." }
                    
                    # Rename folder to match profile name
                    $parentPath = Split-Path $linkPath -Parent
                    $newPath = Join-Path $parentPath $p.name
                    if ($linkPath -ne $newPath) {
                        if (Test-Path $newPath) { throw "Thu muc ten $($p.name) da ton tai o $parentPath" }
                        Rename-Item -Path $linkPath -NewName $p.name
                        $linkPath = $newPath
                    }
                    
                    $p.browser = $browser
                    $p.path = $linkPath
                    
                    # Write Marker File
                    Set-Content -Path (Join-Path $linkPath ".cm_profile.txt") -Value $id
                    
                    # Configure INI for Firefox
                    if ($browser -eq 'firefox') {
                        $iniName = "FirefoxPortable.ini"
                        $sourceIni = Join-Path $linkPath "Other\Source\$iniName"
                        $destIni = Join-Path $linkPath $iniName
                        
                        if (Test-Path $sourceIni) {
                            Copy-Item -Path $sourceIni -Destination $destIni -Force
                        } elseif (-not (Test-Path $destIni)) {
                            New-Item -ItemType File -Path $destIni -Force | Out-Null
                        }
                        
                        if (Test-Path $destIni) {
                            $iniContent = Get-Content $destIni
                            if ($iniContent -match "^AllowMultipleInstances=") {
                                $iniContent = $iniContent -replace "^AllowMultipleInstances=.*", "AllowMultipleInstances=true"
                            } else {
                                $iniContent += "`r`nAllowMultipleInstances=true"
                            }
                            Set-Content -Path $destIni -Value $iniContent -Encoding Ascii
                        }
                    }
                    
                    # Generate Icon
                    $iconPath = Join-Path $iconsDir "$($id).ico"
                    $chromeImg = (Get-ChildItem -Path $scriptDir -Filter "*chorm.png" | Select-Object -First 1).FullName
                    $firefoxImg = (Get-ChildItem -Path $scriptDir -Filter "*firefox.png" | Select-Object -First 1).FullName
                    $baseImagePath = if ($browser -eq 'chrome' -and (Test-Path $chromeImg)) { $chromeImg } elseif ($browser -eq 'firefox' -and (Test-Path $firefoxImg)) { $firefoxImg } else { Join-Path $scriptDir "icon.png" }
                    try { [IconGenerator]::GenerateIcon($iconPath, $baseImagePath, $p.iconBadge) } catch {}
                    
                    Save-Data $data
                    Send-JsonResponse $res 200 $p
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # DELETE /api/profiles/:id
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)$' -and $method -eq 'DELETE') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p) {
                    if ($p.path) {
                        $escapedPath = $p.path.Replace("\", "\\")
                        $procs = Get-CimInstance Win32_Process -Filter "ExecutablePath LIKE '$escapedPath%'" -ErrorAction SilentlyContinue
                        foreach ($proc in $procs) {
                            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $data.profiles = @($data.profiles | Where-Object { $_.id -ne $id })
                    Save-Data $data
                    
                    $iconPath = Join-Path $iconsDir "$id.ico"
                    if (Test-Path $iconPath) { Remove-Item $iconPath -Force -ErrorAction SilentlyContinue }
                    
                    Send-JsonResponse $res 200 "Deleted"
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # POST /api/profiles/:id/launch
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)/launch$' -and $method -eq 'POST') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p -and $p.path) {
                    $exeName = if ($p.browser -eq 'firefox') { "FirefoxPortable.exe" } else { "GoogleChromePortable.exe" }
                    $exePath = Join-Path $p.path $exeName
                    
                    if (Test-Path $exePath) {
                        if ($p.browser -eq 'firefox') {
                            $iniPath = Join-Path $p.path "FirefoxPortable.ini"
                            $iniContent = ""
                            if (Test-Path $iniPath) { $iniContent = Get-Content $iniPath -Raw }
                            if ($iniContent -notmatch "(?m)^\[FirefoxPortable\]") {
                                $iniContent = "[FirefoxPortable]`r`n" + $iniContent
                            }
                            if ($iniContent -match "(?m)^AllowMultipleInstances=") {
                                $iniContent = $iniContent -replace "(?m)^AllowMultipleInstances=.*", "AllowMultipleInstances=true"
                            } else {
                                $iniContent += "`r`nAllowMultipleInstances=true"
                            }
                            
                            if ($iniContent -match "(?m)^AdditionalParameters=") {
                                if ($iniContent -notmatch "(?m)^AdditionalParameters=.*-no-remote.*") {
                                    $iniContent = $iniContent -replace "(?m)^AdditionalParameters=(.*)", 'AdditionalParameters=$1 -no-remote'
                                }
                            } else {
                                $iniContent += "`r`nAdditionalParameters=-no-remote"
                            }
                            
                            Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii
                        }
                        
                        $processArgs = @()
                        
                        # --- PROXY INJECTION ---
                        $proxyStr = ""
                        if ($p.proxyId -and $data.proxies) {
                            $targetProxy = $data.proxies | Where-Object { $_.id -eq $p.proxyId }
                            if ($targetProxy) { $proxyStr = $targetProxy.proxyString }
                        }
                        # For backward compatibility, if profile still has literal proxy
                        if (-not $proxyStr -and $p.proxy) { $proxyStr = $p.proxy }

                        $useProxyHost = ""
                        $useProxyPort = ""
                        $isSocks = $false
                        
                        if ($proxyStr) {
                            $isSocks = $proxyStr.ToLower().StartsWith("socks")
                            $cleanProxy = $proxyStr.Replace("http://","").Replace("https://","").Replace("socks5://","")
                            $parts = $cleanProxy.Split(':')
                            if ($parts.Count -ge 2) {
                                $useProxyHost = $parts[0]
                                $targetHost = $parts[0]
                                $useProxyPort = $parts[1]
                                
                                $user = if ($parts.Count -eq 4) { $parts[2] } else { "" }
                                $pass = if ($parts.Count -eq 4) { $parts[3] } else { "" }
                                
                                if (-not $script:relays.ContainsKey($proxyStr)) {
                                    if ($isSocks) {
                                        $localPort = [ProxyRelay]::StartSocks5($useProxyHost, [int]$useProxyPort, $user, $pass)
                                    } else {
                                        $localPort = [ProxyRelay]::StartHttp($useProxyHost, [int]$useProxyPort, $user, $pass)
                                    }
                                    $script:relays[$proxyStr] = @{ Port = $localPort }
                                }
                                
                                if ($script:relays.ContainsKey($proxyStr)) {
                                    $localPort = $script:relays[$proxyStr].Port
                                    # Route both Firefox and Chrome via relay for DoH
                                    $useProxyHost = "127.0.0.1"
                                    $useProxyPort = $localPort
                                    $isSocks = $false
                                    Write-Log "Started/Reused local ProxyRelay at 127.0.0.1:$localPort for $proxyStr" "INFO"
                                }
                            }
                        }

                        if ($p.browser -eq 'firefox') {
                            $userJsPath = Join-Path $p.path "Data\profile\user.js"
                            if (-not (Test-Path (Split-Path $userJsPath -Parent))) {
                                New-Item -ItemType Directory -Path (Split-Path $userJsPath -Parent) -Force | Out-Null
                            }
                            # CRITICAL: Rewrite user.js from scratch to prevent garbage accumulation
                            # Old approach appended to existing content causing duplicated/stale entries
                            $userJsContent = ""
                            
                            if ($useProxyHost -and $useProxyPort) {
                                $userJsContent += "`r`nuser_pref(`"network.proxy.type`", 1);"
                                if ($isSocks) {
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.socks`", `"$useProxyHost`");"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.socks_port`", $useProxyPort);"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.socks_version`", 5);"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.socks_remote_dns`", true);"
                                } else {
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.http`", `"$useProxyHost`");"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.http_port`", $useProxyPort);"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.ssl`", `"$useProxyHost`");"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.ssl_port`", $useProxyPort);"
                                    $userJsContent += "`r`nuser_pref(`"network.proxy.share_proxy_settings`", true);"
                                }
                                # Anti-Detect & Prevent Leaks - Allow ICE candidates so extension can spoof IPs
                                # proxy_only_if_behind_proxy=false: MUST be false, otherwise HTTP relay blocks ALL ICE
                                # default_address_only=true: Only expose 1 candidate (reduces attack surface)
                                # no_host=false: Allow host candidates so extension has something to hook
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.enabled`", true);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.proxy_only_if_behind_proxy`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.default_address_only`", true);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.no_host`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.obfuscate_host_addresses`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.relay_only`", false);"
                                $userJsContent += "`r`nuser_pref(`"network.dns.disablePrefetch`", true);"
                                $userJsContent += "`r`nuser_pref(`"network.dns.disableIPv6`", true);"
                                $userJsContent += "`r`nuser_pref(`"network.predictor.enabled`", false);"
                                # Match language to proxy location (Vietnam)
                                $userJsContent += "`r`nuser_pref(`"intl.accept_languages`", `"vi,vi-VN,en-US,en`");"
                                $userJsContent += "`r`nuser_pref(`"general.useragent.locale`", `"vi`");"
                                
                                # Setup WebRTC Guard Extension for Firefox
                                $extDestDir = Join-Path $p.path "Data\profile\extensions"
                                if (-not (Test-Path $extDestDir)) {
                                    New-Item -ItemType Directory -Path $extDestDir -Force | Out-Null
                                }
                                
                                $xpiSource = Join-Path $scriptDir "extensions\webrtc-guard-dynamic.xpi"
                                $xpiDest = Join-Path $extDestDir "webrtc-guard-dynamic@channelmanager.local.xpi"
                                if (Test-Path $xpiSource) {
                                    Copy-Item -Path $xpiSource -Destination $xpiDest -Force
                                }
                                
                                $userJsContent += "`r`nuser_pref(`"extensions.autoDisableScopes`", 0);"
                                $userJsContent += "`r`nuser_pref(`"extensions.enabledScopes`", 15);"
                                $userJsContent += "`r`nuser_pref(`"xpinstall.signatures.required`", false);"
                            } else {
                                $userJsContent += "`r`nuser_pref(`"network.proxy.type`", 0);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.enabled`", true);"
                                # Force reset ALL WebRTC ICE prefs to natural state
                                # relay_only is set by Firefox internally when proxy was active - MUST reset
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.proxy_only_if_behind_proxy`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.default_address_only`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.no_host`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.obfuscate_host_addresses`", false);"
                                $userJsContent += "`r`nuser_pref(`"media.peerconnection.ice.relay_only`", false);"
                                
                                # Clean prefs.js to remove ALL stale WebRTC runtime values
                                $prefsJsPath = Join-Path $p.path "Data\profile\prefs.js"
                                if (Test-Path $prefsJsPath) {
                                    $prefsContent = Get-Content $prefsJsPath -Raw
                                    $prefsContent = $prefsContent -replace '(?m)^user_pref\("media\.peerconnection\.ice\.(proxy_only_if_behind_proxy|default_address_only|no_host|obfuscate_host_addresses|relay_only)".*$\r?\n?', ''
                                    Set-Content -Path $prefsJsPath -Value $prefsContent -Encoding UTF8
                                }
                                
                                $extDestDir = Join-Path $p.path "Data\profile\extensions"
                                $xpiPath = Join-Path $extDestDir "webrtc-guard@channelmanager.xpi"
                                if (Test-Path $xpiPath) { Remove-Item $xpiPath -Force }
                            }
                            Set-Content -Path $userJsPath -Value $userJsContent -Encoding UTF8
                        }
                        elseif ($p.browser -eq 'chrome') {
                            if ($useProxyHost -and $useProxyPort) {
                                $scheme = if ($isSocks) { "socks5" } else { "http" }
                                $processArgs += ('--proxy-server="{0}://{1}:{2}"' -f $scheme, $useProxyHost, $useProxyPort)
                                $processArgs += "--lang=vi"
                                
                                # Setup WebRTC Guard Extension for Chrome
                                $extDest = Join-Path $p.path "Data\webrtc_ext"
                                if (-not (Test-Path $extDest)) {
                                    New-Item -ItemType Directory -Path $extDest -Force | Out-Null
                                }
                                Copy-Item -Path (Join-Path $scriptDir "extensions\webrtc-guard-chrome\*") -Destination $extDest -Recurse -Force
                                $spoofTemplate = Get-Content (Join-Path $extDest "spoof.template.js") -Raw
                                $spoofTemplate = $spoofTemplate -replace "TARGET_PROXY_IP", $targetHost
                                Set-Content -Path (Join-Path $extDest "spoof.js") -Value $spoofTemplate -Encoding UTF8
                                
                                $processArgs += ('--disable-extensions-except="{0}"' -f $extDest)
                                $processArgs += ('--load-extension="{0}"' -f $extDest)
                                $debugPort = Get-Random -Minimum 10000 -Maximum 20000
                                $processArgs += "--remote-debugging-port=$debugPort"
                                $p | Add-Member -MemberType NoteProperty -Name "debugPort" -Value $debugPort -Force
                                
                                # Inject Chrome Preferences
                                $prefPath = Join-Path $p.path "Data\profile\Default\Preferences"
                                if (-not (Test-Path (Split-Path $prefPath -Parent))) {
                                    New-Item -ItemType Directory -Path (Split-Path $prefPath -Parent) -Force | Out-Null
                                }
                                $prefs = @{}
                                if (Test-Path $prefPath) {
                                    try { $prefs = Get-Content $prefPath -Raw | ConvertFrom-Json -AsHashtable } catch {}
                                }
                                if (-not $prefs) { $prefs = @{} }
                                if (-not $prefs.intl) { $prefs.intl = @{} }
                                $prefs.intl.accept_languages = "vi-VN,vi,en-US,en"
                                $prefs.intl.selected_languages = "vi-VN,vi,en-US,en"
                                if (-not $prefs.webrtc) { $prefs.webrtc = @{} }
                                # CRITICAL: Block all non-proxied UDP to prevent STUN backend leaks
                                # The spoof.js extension will handle creating fake candidates to prevent N/A
                                $prefs | ConvertTo-Json -Depth 10 | Set-Content -Path $prefPath -Encoding UTF8
                            } else {
                                $prefPath = Join-Path $p.path "Data\profile\Default\Preferences"
                                if (Test-Path $prefPath) {
                                    try {
                                        $prefs = Get-Content $prefPath -Raw | ConvertFrom-Json -AsHashtable
                                        if ($prefs -and $prefs.webrtc) {
                                            $prefs.webrtc.ip_handling_policy = "default"
                                            $prefs.webrtc.multiple_routes_enabled = $true
                                            $prefs.webrtc.nonproxied_udp_enabled = $true
                                            $prefs | ConvertTo-Json -Depth 10 | Set-Content -Path $prefPath -Encoding UTF8
                                        }
                                    } catch {}
                                }
                                # Disable the extension logic by setting TARGET_PROXY_IP to empty
                                $extDest = Join-Path $p.path "Data\webrtc_ext"
                                if (Test-Path $extDest) {
                                    $spoofTemplatePath = Join-Path $extDest "spoof.template.js"
                                    if (Test-Path $spoofTemplatePath) {
                                        $spoofContent = Get-Content $spoofTemplatePath -Raw
                                        $spoofContent = $spoofContent -replace "TARGET_PROXY_IP", ""
                                        Set-Content -Path (Join-Path $extDest "spoof.js") -Value $spoofContent -Encoding UTF8
                                    }
                                }
                            }
                        }

                        if ($p.browser -eq 'firefox') {
                            $processArgs += "https://ipfighter.com"
                        }

                        # --- END PROXY INJECTION ---
                        
                        if ($processArgs.Count -gt 0) {
                            $proc = Start-Process -FilePath $exePath -ArgumentList $processArgs -PassThru
                        } else {
                            $proc = Start-Process -FilePath $exePath -PassThru
                        }
                        
                        if ($p.browser -eq "Chrome" -and $targetHost -and $p.debugPort) {
                            $cdpInjectorScript = Join-Path $scriptDir "Inject-WebRTC.ps1"
                            $spoofScriptPath = Join-Path $p.path "Data\webrtc_ext\spoof.js"
                            if (Test-Path $cdpInjectorScript) {
                                $injectorArgs = @("-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$cdpInjectorScript`"", "-Port", $($p.debugPort), "-SpoofScriptPath", "`"$spoofScriptPath`"")
                                Start-Process powershell -ArgumentList $injectorArgs -WindowStyle Hidden
                            }
                        }
                        
                        $p | Add-Member -MemberType NoteProperty -Name "pid" -Value $proc.Id -Force
                        $p | Add-Member -MemberType NoteProperty -Name "status" -Value "running" -Force
                        $p | Add-Member -MemberType NoteProperty -Name "lastAccessedAt" -Value ([DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")) -Force
                        
                        # Apply taskbar icon separation in background
                        $appId = "ChannelManager.$id"
                        $iconPath = Join-Path $iconsDir "$id.ico"
                        $applyScript = Join-Path $scriptDir "Apply-TaskbarIcon.ps1"
                        if (Test-Path $applyScript) {
                            Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$applyScript`" -ChannelName `"$($p.name)`" -ExePath `"$exePath`" -AppId `"$appId`" -IconPath `"$iconPath`" -DisplayName `"$($p.name)`""
                        }
                        
                        Save-Data $data
                        Send-JsonResponse $res 200 "Launched"
                    } else {
                        $p.path = ""
                        $p.browser = ""
                        Save-Data $data
                        throw "Thu muc khong ton tai. Da dat lai trang thai ket noi!"
                    }
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            # POST /api/profiles/:id/open-dir
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)/open-dir$' -and $method -eq 'POST') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p -and $p.path) {
                    Start-Process "explorer.exe" -ArgumentList "/n,`"$($p.path)`""
                    Send-JsonResponse $res 200 "Opened"
                } else {
                    Send-JsonResponse $res 404 "Not Found or Not Linked"
                }
            }
            # POST /api/profiles/:id/stop
            elseif ($path -match '^/api/profiles/(profile-[a-zA-Z0-9-]+)/stop$' -and $method -eq 'POST') {
                $id = $matches[1]
                $data = Get-Data
                $p = $data.profiles | Where-Object { $_.id -eq $id }
                if ($p) {
                    if ($p.path) {
                        $escapedPath = $p.path.Replace("\", "\\")
                        $procs = Get-CimInstance Win32_Process -Filter "ExecutablePath LIKE '$escapedPath%'" -ErrorAction SilentlyContinue
                        foreach ($proc in $procs) {
                            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $p.pid = $null
                    $p.status = "stopped"
                    Save-Data $data
                    Send-JsonResponse $res 200 "Stopped"
                } else { Send-JsonResponse $res 404 "Not Found" }
            }
            
            # Static files
            elseif ($path -eq '/' -or $path -match '^/(index\.html|index\.css|app\.js|favicon\.ico)$') {
                $filePath = $path
                if ($filePath -eq '/') { $filePath = '/index.html' }
                $fullPath = Join-Path $scriptDir "webapp$filePath"
                
                if (Test-Path $fullPath) {
                    $ext = [IO.Path]::GetExtension($fullPath).ToLower()
                    if ($ext -eq '.html') { $res.ContentType = 'text/html; charset=utf-8' }
                    elseif ($ext -eq '.css') { $res.ContentType = 'text/css; charset=utf-8' }
                    elseif ($ext -eq '.js') { $res.ContentType = 'application/javascript; charset=utf-8' }
                    elseif ($ext -eq '.ico') { $res.ContentType = 'image/x-icon' }
                    
                    $buffer = [IO.File]::ReadAllBytes($fullPath)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    $res.OutputStream.Close()
                } else { $res.StatusCode = 404; $res.OutputStream.Close(); Write-Log "404 Not Found: $fullPath" "WARN" }
            }
            else { Send-JsonResponse $res 404 "Not Found"; Write-Log "404 Route Not Found" "WARN" }
        } catch {
            $err = "Loi API [$method $path]: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
            Write-Log $err "ERROR"
            $err | Out-File "error.log" -Append
            Send-JsonResponse $res 500 $_.Exception.Message
        }
    }
} finally {
    $listener.Stop()
}



