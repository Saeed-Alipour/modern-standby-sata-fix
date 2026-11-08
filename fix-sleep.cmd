@echo off
:: fix-sleep.cmd - Modern Standby SATA fix (see README.md)
::
:: Problem: on Modern Standby laptops with a SATA drive (e.g. an SSD added to the 2.5" bay), Windows leaves
:: "AHCI Link Power Management" at a setting where the SATA link never goes idle. The CPU then can't reach
:: deep sleep (sleep study blocker: NoHwDrips.C2.LTR_SATA), so the laptop runs hot with the fan on while
:: "asleep" and drains the battery.
::
:: What this does:
::   1. Unhides "AHCI Link Power Management - HIPM/DIPM" and sets it to HIPM+DIPM on AC and battery,
::      in every power plan.
::   2. Turns on hibernate and sets "hibernate after 30 min on battery" as a safety net.
::
:: Run: double-click (it asks for administrator rights). Safe to run more than once.
:: Undo: run undo-fix.cmd

:: --- Re-launch as administrator if needed ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set SUB_DISK=0012ee47-9041-4b5d-9b77-535fba8b1442
set AHCI_LPM=0b2d69d7-a2a1-449c-9680-f91c70521c60
:: 0=Active, 1=HIPM, 2=HIPM+DIPM, 3=DIPM, 4=Lowest   (still hot in sleep? try 4)
set LPM_VALUE=2
:: Minutes on battery before standby turns into hibernate. 0 = never.
set HIBERNATE_MINUTES=30

echo.
echo === 1. SATA link power management: HIPM+DIPM ===
powercfg -attributes %SUB_DISK% %AHCI_LPM% -ATTRIB_HIDE
for /f "tokens=4" %%G in ('powercfg /list ^| findstr /i "GUID:"') do (
    powercfg /setacvalueindex %%G %SUB_DISK% %AHCI_LPM% %LPM_VALUE%
    powercfg /setdcvalueindex %%G %SUB_DISK% %AHCI_LPM% %LPM_VALUE%
)
powercfg /setactive SCHEME_CURRENT

echo.
echo === 2. Hibernate after %HIBERNATE_MINUTES% min on battery ===
powercfg /hibernate on
powercfg /change hibernate-timeout-dc %HIBERNATE_MINUTES%

echo.
echo === Verify (expect 0x00000002 for SATA; 0x00000708 = 1800 s hibernate on DC) ===
echo SATA link power management:
powercfg /q SCHEME_CURRENT %SUB_DISK% %AHCI_LPM% | findstr /c:"Current"
echo Hibernate timeout:
powercfg /q SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | findstr /c:"Current"

echo.
echo Done. To confirm it worked: sleep on battery for 30+ minutes, then run check-sleep.ps1
echo from an administrator PowerShell.
echo.
pause
