@echo off
setlocal
cd /d "%~dp0"

echo ==================================================
echo   Channel Manager - Starting Server...
echo ==================================================

:: Kiểm tra và tạo thư mục cần thiết
if not exist "data\profiles" mkdir "data\profiles"
if not exist "data\icons" mkdir "data\icons"
if not exist "installers" mkdir "installers"

:: Copy 2 file installer vào thư mục installers nếu chưa có
if exist "FirefoxPortable_155.0.1_English.paf.exe" (
    if not exist "installers\FirefoxPortable_155.0.1_English.paf.exe" (
        move "FirefoxPortable_155.0.1_English.paf.exe" "installers\" >nul
    )
)
if exist "GoogleChromePortable_153.0.8010.37_online.paf.exe" (
    if not exist "installers\GoogleChromePortable_153.0.8010.37_online.paf.exe" (
        move "GoogleChromePortable_153.0.8010.37_online.paf.exe" "installers\" >nul
    )
)

:: Kiểm tra xem server.ps1 có đang chạy không
tasklist /FI "IMAGENAME eq powershell.exe" /FI "WINDOWTITLE eq ChannelManagerServer" | find /I "powershell.exe" > nul
if errorlevel 1 (
    echo Khởi động HTTP Server ở chế độ nền...
    start "ChannelManagerServer" /b powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "server.ps1"
    
    :: Chờ 2 giây để server khởi động
    timeout /t 2 /nobreak > nul
) else (
    echo Server đang chạy.
)

echo Mở giao diện ứng dụng...
:: Mở bằng Edge App Mode (Giao diện như Desktop App, không có thanh địa chỉ)
start msedge --app="http://localhost:8780" --disable-features=TranslateUI

exit
