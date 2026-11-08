@echo off
:: undo-fix.cmd - reverts fix-sleep.cmd to Windows defaults
::   - AHCI Link Power Management back to HIPM (Windows default) and hidden again
::   - hibernate-on-battery timeout back to "never" (hibernate itself stays enabled)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set SUB_DISK=0012ee47-9041-4b5d-9b77-535fba8b1442
set AHCI_LPM=0b2d69d7-a2a1-449c-9680-f91c70521c60

for /f "tokens=4" %%G in ('powercfg /list ^| findstr /i "GUID:"') do (
    powercfg /setacvalueindex %%G %SUB_DISK% %AHCI_LPM% 1
    powercfg /setdcvalueindex %%G %SUB_DISK% %AHCI_LPM% 1
)
powercfg /setactive SCHEME_CURRENT
powercfg -attributes %SUB_DISK% %AHCI_LPM% +ATTRIB_HIDE
powercfg /change hibernate-timeout-dc 0

echo.
echo Reverted. SATA link power management = HIPM (default), hibernate on battery = never.
powercfg /q SCHEME_CURRENT %SUB_DISK% %AHCI_LPM% | findstr /c:"Current"
echo.
pause
