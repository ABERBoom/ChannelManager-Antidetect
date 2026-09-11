param(
    [Parameter(Mandatory=$true)]
    [string]$ChannelName,
    
    [Parameter(Mandatory=$true)]
    [string]$ExePath,
    
    [Parameter(Mandatory=$true)]
    [string]$AppId,
    
    [string]$IconPath = "",
    
    [string]$DisplayName = ""
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Collections.Generic;

public class TaskbarSeparator
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pwszVal;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT propvar);
        int Commit();
    }

    [DllImport("shell32.dll")]
    public static extern int SHGetPropertyStoreForWindow(
        IntPtr hwnd,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore ppv);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    // Guid chung cho tat ca AppUserModel properties
    private static readonly Guid AppUserModelGuid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    private static void SetWindowStringProperty(IPropertyStore propStore, uint pid, string value)
    {
        var key = new PROPERTYKEY { fmtid = AppUserModelGuid, pid = pid };
        var pv = new PROPVARIANT();
        pv.vt = 31; // VT_LPWSTR
        pv.pwszVal = Marshal.StringToCoTaskMemUni(value);
        propStore.SetValue(ref key, ref pv);
        Marshal.FreeCoTaskMem(pv.pwszVal);
    }

    public static int SetWindowProperties(IntPtr hwnd, string appId, string iconPath, string relaunchCmd, string displayName)
    {
        Guid IID_IPropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore propStore;
        int hr = SHGetPropertyStoreForWindow(hwnd, ref IID_IPropertyStore, out propStore);
        if (hr != 0) return hr;

        // pid=5: AppUserModel.ID
        SetWindowStringProperty(propStore, 5, appId);

        // pid=2: AppUserModel.RelaunchCommand
        if (!string.IsNullOrEmpty(relaunchCmd))
            SetWindowStringProperty(propStore, 2, relaunchCmd);

        // pid=3: AppUserModel.RelaunchIconResource
        if (!string.IsNullOrEmpty(iconPath))
            SetWindowStringProperty(propStore, 3, iconPath);

        // pid=4: AppUserModel.RelaunchDisplayNameResource
        if (!string.IsNullOrEmpty(displayName))
            SetWindowStringProperty(propStore, 4, displayName);

        propStore.Commit();
        Marshal.ReleaseComObject(propStore);
        return 0;
    }

    public static List<IntPtr> GetProcessWindows(int processId)
    {
        List<IntPtr> windows = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if ((int)pid == processId && IsWindowVisible(hWnd) && GetWindowTextLength(hWnd) > 0)
            {
                windows.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }
}
"@

Write-Host "[$ChannelName] Starting browser..." -ForegroundColor Cyan

$proc = Start-Process -FilePath $ExePath -PassThru
$launcherPid = $proc.Id

Write-Host "[$ChannelName] Launcher PID: $launcherPid, waiting for browser window..." -ForegroundColor Yellow

# Resolve icon path
if ($IconPath -and -not [System.IO.Path]::IsPathRooted($IconPath)) {
    $IconPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) $IconPath
}

$maxWait = 30
$elapsed = 0
$windowsFound = $false
$processedWindows = @{}

while ($elapsed -lt $maxWait) {
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
    
    $browserProcesses = Get-Process -Name "firefox*","chrome*" -ErrorAction SilentlyContinue
    
    foreach ($bp in $browserProcesses) {
        $windows = [TaskbarSeparator]::GetProcessWindows($bp.Id)
        foreach ($hwnd in $windows) {
            $key = $hwnd.ToString()
            if (-not $processedWindows.ContainsKey($key)) {
                try {
                    $exeFullPath = $bp.MainModule.FileName
                    if ($exeFullPath -like "*$ChannelName*") {
                        $result = [TaskbarSeparator]::SetWindowProperties(
                            $hwnd,
                            $AppId,
                            $IconPath,
                            $ExePath,
                            $DisplayName
                        )
                        if ($result -eq 0) {
                            $title = New-Object System.Text.StringBuilder(256)
                            [TaskbarSeparator]::GetWindowText($hwnd, $title, 256) | Out-Null
                            Write-Host "[$ChannelName] Set AppId + Icon on: $($title.ToString())" -ForegroundColor Green
                            $windowsFound = $true
                        }
                        $processedWindows[$key] = $true
                    }
                } catch {}
            }
        }
    }
    
    if ($windowsFound) {
        Start-Sleep -Seconds 3
        # Final pass for any late windows
        $browserProcesses = Get-Process -Name "firefox*","chrome*" -ErrorAction SilentlyContinue
        foreach ($bp in $browserProcesses) {
            $windows = [TaskbarSeparator]::GetProcessWindows($bp.Id)
            foreach ($hwnd in $windows) {
                $key = $hwnd.ToString()
                if (-not $processedWindows.ContainsKey($key)) {
                    try {
                        $exeFullPath = $bp.MainModule.FileName
                        if ($exeFullPath -like "*$ChannelName*") {
                            [TaskbarSeparator]::SetWindowProperties($hwnd, $AppId, $IconPath, $ExePath, $DisplayName) | Out-Null
                            $processedWindows[$key] = $true
                        }
                    } catch {}
                }
            }
        }
        break
    }
}

if ($windowsFound) {
    Write-Host "[$ChannelName] Done! Taskbar icon set." -ForegroundColor Green
} else {
    Write-Host "[$ChannelName] Warning: Could not find browser windows." -ForegroundColor Yellow
}
