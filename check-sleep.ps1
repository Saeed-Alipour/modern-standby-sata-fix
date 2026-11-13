<#
.SYNOPSIS
    Checks whether your laptop actually reaches deep sleep in Modern Standby, and whether
    a SATA drive is what's blocking it.

.DESCRIPTION
    Generates a Windows sleep study (powercfg /sleepstudy), reads the data embedded in the
    HTML report, and prints for each standby session:
      - length, AC/battery, battery drained and average drain in watts
      - % of time in hardware deep sleep ("HW DRIPS"); healthy is > 90%
      - the top things that kept the system awake
    It flags the NoHwDrips...LTR_SATA blocker, which is the problem fix-sleep.cmd addresses.

    Read-only: it changes no settings. Needs administrator rights (powercfg requirement).

.PARAMETER Days
    How many days of history to include (default 3).

.PARAMETER ReportPath
    Analyse an existing sleepstudy HTML report instead of generating a new one.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\check-sleep.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\check-sleep.ps1 -Days 7
#>
[CmdletBinding()]
param(
    [int]$Days = 3,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- 1. Is this a Modern Standby machine? ---
$states = (powercfg /a) -join "`n"
$modern = $states -match 'S0 Low Power Idle'
Write-Host ""
Write-Host "Modern Standby (S0 Low Power Idle): $(if ($modern) {'yes'} else {'no'})"
if (-not $modern) {
    Write-Host "This laptop uses classic S3 sleep, so this tool and fix don't apply." -ForegroundColor Yellow
    return
}

# --- 2. Get a sleep study report ---
if (-not $ReportPath) {
    if (-not (Test-Admin)) {
        Write-Host "Run this from an administrator PowerShell (powercfg /sleepstudy needs it)." -ForegroundColor Red
        exit 1
    }
    $ReportPath = Join-Path $env:TEMP 'sleepstudy-check.html'
    powercfg /sleepstudy /output "$ReportPath" /duration $Days | Out-Null
}
if (-not (Test-Path $ReportPath)) { throw "Sleep study report not found: $ReportPath" }

# --- 3. Pull the JSON out of the HTML ---
$html = [IO.File]::ReadAllText($ReportPath)
$m = [regex]::Match($html, 'var\s+LocalSprData\s*=\s*(\{.*?\});\s*var\s+SourceElement', 'Singleline')
if (-not $m.Success) { throw "Couldn't find sleep study data in $ReportPath (report format changed?)" }
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$data = $ser.DeserializeObject($m.Groups[1].Value)

# --- 4. Show storage setup and current setting ---
$sataDisks = @(Get-PhysicalDisk | Where-Object BusType -eq 'SATA')
Write-Host "SATA drives: $(if ($sataDisks) { ($sataDisks.FriendlyName) -join ', ' } else { 'none' })"
$lpm = powercfg /qh SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 |
       Select-String 'Current (AC|DC) Power Setting Index: 0x([0-9a-f]+)' |
       ForEach-Object { '{0}={1}' -f $_.Matches[0].Groups[1].Value, [Convert]::ToInt32($_.Matches[0].Groups[2].Value, 16) }
$names = @{0='Active (off)';1='HIPM';2='HIPM+DIPM';3='DIPM';4='Lowest'}
if ($lpm) {
    Write-Host ("SATA link power management: " + (($lpm | ForEach-Object { $k,$v = $_ -split '='; "$k=$($names[[int]$v])" }) -join ', '))
}

# --- 5. Analyse standby sessions ---
function Get-BlockerTotals($session) {
    $totals = @{}
    $walk = {
        param($list)
        foreach ($b in $list) {
            $n = $b['Name']
            if (-not $totals.ContainsKey($n)) { $totals[$n] = 0 }
            $totals[$n] += [double]$b['ActiveTime']
            if ($b['Children']) { & $walk $b['Children'] }
        }
    }
    foreach ($g in @($session['BlockerGroups'])) { if ($g) { & $walk $g['Blockers'] } }
    $totals
}

$sessions = @($data['ScenarioInstances'] | Where-Object { $_['Type'] -eq 2 })   # 2 = standby
$rows = @()
$sataHits = 0
foreach ($s in $sessions) {
    $start = [datetime]$s['EntryTimestampLocal'].Substring(0,19)
    $end   = [datetime]$s['ExitTimestampLocal'].Substring(0,19)
    $secs  = ($end - $start).TotalSeconds
    if ($secs -lt 60) { continue }
    $meta = @{}
    foreach ($kv in $s['Metadata']['Values']) { $meta[$kv['Key']] = $kv['Value'] }
    $hw = [double]$meta['Info.HwLowPowerStateTime'] / 1e7     # 100 ns units
    $drop = [double]$s['EntryRemainingCapacity'] - [double]$s['ExitRemainingCapacity']   # mWh
    $blockers = Get-BlockerTotals $s
    $sata = @($blockers.Keys | Where-Object { $_ -match 'LTR_SATA' })
    if ($sata) { $sataHits++ }
    $top = $blockers.GetEnumerator() |
           Where-Object { $_.Key -notmatch '^(Component 0|Low Power Phase|Non-DRIPS Idle Time)$' } |
           Sort-Object Value -Descending | Select-Object -First 2 |
           ForEach-Object { $_.Key -replace '\s*\(\\_SB[^)]*\)', '' }
    $rows += [pscustomobject]@{
        Start      = $start.ToString('MM-dd HH:mm')
        Minutes    = [math]::Round($secs / 60)
        Power      = if ($s['OnAc']) { 'AC' } else { 'Battery' }
        'DeepSleep%' = [math]::Min(100, [math]::Round($hw / $secs * 100))
        'Drain W'  = if (-not $s['OnAc'] -and $drop -ge 0) { [math]::Round($drop / ($secs / 3600) / 1000, 2) } else { '-' }
        SATA       = if ($sata) { 'BLOCKED' } else { '' }
        TopBlockers = ($top -join '; ')
    }
}

Write-Host ""
if (-not $rows) {
    Write-Host "No standby sessions longer than 1 minute in the last $Days day(s). Let the laptop sleep for 30+ minutes and run again." -ForegroundColor Yellow
    return
}
$rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

# Judge on the most recent sessions, so sessions from before a fix don't skew the verdict.
$recent = @($rows | Select-Object -Last 3)
$recentSata = @($recent | Where-Object SATA).Count
$avg = [math]::Round(($recent | Measure-Object 'DeepSleep%' -Average).Average)
Write-Host "Deep sleep, last $($recent.Count) session(s): $avg% average   (healthy Modern Standby: > 90%)"
if ($sataHits -gt $recentSata) {
    Write-Host "($($sataHits - $recentSata) older session(s) were blocked by LTR_SATA.)"
}
Write-Host ""
if ($recentSata -gt 0) {
    Write-Host "RESULT: $recentSata recent session(s) blocked by NoHwDrips...LTR_SATA - the SATA link is keeping the CPU awake." -ForegroundColor Red
    Write-Host "        Run fix-sleep.cmd, sleep on battery for 30+ min, then run this check again." -ForegroundColor Red
} elseif ($avg -ge 90) {
    Write-Host "RESULT: Deep sleep is healthy. No SATA blocker found." -ForegroundColor Green
} else {
    Write-Host "RESULT: Deep sleep is low but not because of SATA. Look at the TopBlockers column" -ForegroundColor Yellow
    Write-Host "        (often drivers, network-in-standby, USB devices or BIOS)." -ForegroundColor Yellow
}
Write-Host "Full report: $ReportPath"
