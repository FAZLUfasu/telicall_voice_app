# ==============================================================================
# TELICALL VOICE APP: AUTOMATED BUILD & MAGISK SYSTEM-APP DEPLOYMENT
# ==============================================================================

# Define Paths
$Adb = "C:\platform_tools\platform-tools\adb.exe"
$ApkSource = "build\app\outputs\flutter-apk\app-release.apk"
$XmlSource = "android\app\src\main\assets\privapp-permissions-telicall.xml"

Write-Host "[1/6] Cleaning and Building Flutter Release APK..." -ForegroundColor Cyan
flutter clean
flutter pub get
flutter build apk --release

if (-not (Test-Path $ApkSource)) {
    Write-Host "[ERROR] Build failed! APK not found at $ApkSource" -ForegroundColor Red
    exit 1
}

Write-Host "[2/6] Generating module.prop descriptor..." -ForegroundColor Cyan
$ModulePropContent = @"
id=TelicallModule
name=Telicall Voice System App
version=1.0
versionCode=1
author=Ikramul
description=Telicall System Priv App
"@
Set-Content -Path .\module.prop -Value $ModulePropContent -Encoding ASCII

Write-Host "[3/6] Pushing files to temporary device storage (/sdcard/)..." -ForegroundColor Cyan
& $Adb push .\module.prop /sdcard/module.prop
& $Adb push $ApkSource /sdcard/TelicallVoice.apk
& $Adb push $XmlSource /sdcard/privapp-permissions-telicall.xml

Write-Host "[4/6] Constructing Magisk module structure in /data/adb/modules/..." -ForegroundColor Cyan
& $Adb shell "su -c 'mkdir -p /data/adb/modules/TelicallModule/system/priv-app/TelicallVoice'"
& $Adb shell "su -c 'mkdir -p /data/adb/modules/TelicallModule/system/etc/permissions'"

& $Adb shell "su -c 'cp /sdcard/module.prop /data/adb/modules/TelicallModule/module.prop'"
& $Adb shell "su -c 'cp /sdcard/TelicallVoice.apk /data/adb/modules/TelicallModule/system/priv-app/TelicallVoice/TelicallVoice.apk'"
& $Adb shell "su -c 'cp /sdcard/privapp-permissions-telicall.xml /data/adb/modules/TelicallModule/system/etc/permissions/privapp-permissions-com.example.telicall_voice_app.xml'"

Write-Host "[5/6] Enforcing Linux file permissions and SELinux contexts..." -ForegroundColor Cyan
& $Adb shell "su -c 'chmod 755 /data/adb/modules/TelicallModule/system/priv-app/TelicallVoice'"
& $Adb shell "su -c 'chmod 644 /data/adb/modules/TelicallModule/system/priv-app/TelicallVoice/TelicallVoice.apk'"
& $Adb shell "su -c 'chmod 644 /data/adb/modules/TelicallModule/system/etc/permissions/privapp-permissions-com.example.telicall_voice_app.xml'"
& $Adb shell "su -c 'chmod 644 /data/adb/modules/TelicallModule/module.prop'"
& $Adb shell "su -c 'chown -R root:root /data/adb/modules/TelicallModule'"

# Clean temporary files from PC and SDCard
Remove-Item .\module.prop -ErrorAction SilentlyContinue
& $Adb shell "su -c 'rm -f /sdcard/module.prop /sdcard/TelicallVoice.apk /sdcard/privapp-permissions-telicall.xml'"

Write-Host "[6/6] Rebooting device to apply Magisk systemless overlay..." -ForegroundColor Cyan
& $Adb reboot

Write-Host "[SUCCESS] Installation complete! Wait for device to boot, then verify with:" -ForegroundColor Green
Write-Host "   $Adb shell `"pm path com.example.telicall_voice_app`"" -ForegroundColor Yellow