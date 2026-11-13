# Modern Standby SATA fix: laptop hot and fan running while asleep

If your Windows laptop **gets hot, keeps its fan running and drains the battery while it's supposedly asleep**, and it has a **SATA drive** (for example an SSD you added to the 2.5" bay), this may be the cause.

On Modern Standby laptops, Windows can leave the SATA link at a setting where it never goes idle. The CPU then can't enter deep sleep, so the laptop sits half-awake with the lid closed until the battery runs out.

This repo has:

| File | What it does |
|---|---|
| `check-sleep.ps1` | Reads a Windows sleep study and tells you whether you have this problem. Changes nothing. |
| `fix-sleep.cmd` | Applies the fix (two power settings). Double-click to run. |
| `undo-fix.cmd` | Reverts the fix. |

## Do you have this problem?

You probably do if **all** of these are true:

- The laptop is warm, the fan runs, or the battery drains in a bag or overnight while asleep.
- `powercfg /a` lists **Standby (S0 Low Power Idle)**, which means the laptop uses Modern Standby.
- It has a **SATA** drive. Check with `Get-PhysicalDisk` in PowerShell and look for `BusType = SATA`.
- In a sleep study, deep sleep ("HW DRIPS") is near **0%** and the blockers include **`NoHwDrips.C2.LTR_SATA`**.

`check-sleep.ps1` checks all of this for you. Open **PowerShell as administrator** in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\check-sleep.ps1
```

Example output from a laptop with the problem:

```
Start       Minutes Power   DeepSleep% Drain W SATA    TopBlockers
-----       ------- -----   ---------- ------- ----    -----------
11-05 17:12      34 Battery          0 4.78    BLOCKED NoHwDrips.INTERNAL_BLOCKER; NoHwDrips.C2.LTR_SATA
11-07 03:23     927 AC               0 -       BLOCKED NoHwDrips.INTERNAL_BLOCKER; NoHwDrips.C2.LTR_SATA

RESULT: session(s) blocked by NoHwDrips...LTR_SATA - the SATA link is keeping the CPU awake.
```

## The fix

Double-click **`fix-sleep.cmd`** and click **Yes** on the administrator prompt. It:

1. Unhides the Windows power setting **"AHCI Link Power Management - HIPM/DIPM"** and sets it to **HIPM+DIPM** on battery and AC, in every power plan. This lets the SATA link idle so the CPU can reach deep sleep.
2. Turns on hibernate and sets **hibernate after 30 minutes on battery**. This is a safety net: even if something else keeps the laptop awake, it powers off fully after 30 minutes on battery.

Then let the laptop sleep **on battery for 30+ minutes** and run `check-sleep.ps1` again. You want deep sleep above 90% and no `LTR_SATA` blocker.

Still hot? Open `fix-sleep.cmd` in Notepad, change `set LPM_VALUE=2` to `4` ("Lowest") and run it again.

The settings are kept until Windows is reinstalled or the power plan is reset, so keep a copy of this repo somewhere safe and re-run the fix after a reinstall. A Windows feature or security update can also re-hide the setting in Power Options (it stays at HIPM+DIPM underneath, Windows just stops showing it) — `check-sleep.ps1` reads it either way, so re-run it after big updates if you want to confirm.

## Results

Lenovo ThinkBook 15 G2 ITL (20VE), Intel Core i3-1115G4, SK Hynix NVMe SSD plus a Samsung 850 EVO SATA SSD in the 2.5" bay, Windows 11:

| | Before | After |
|---|---|---|
| Time in hardware deep sleep | **0%** in every session | **94–99%** (one short session at 47%) |
| `LTR_SATA` blocker | Present | Gone |
| Battery drain while asleep | **about 2.4–6 W** | **about 0.6–1.3 W** |
| Overnight on charger (19 h) | Fan running, hot | 99% deep sleep |

## Things that did NOT help on this laptop

- **Driver and BIOS updates.** Lenovo Vantage reported the system up to date (BIOS F8CN59WW), and the problem remained.
- **Intel Rapid Storage Technology (RST).** On 11th-gen Intel, the RST driver (`iaStorVD`) only works when the BIOS is in **VMD** mode. In AHCI mode it doesn't attach to anything. **Don't switch the BIOS storage mode to fix this.** If Windows was installed in AHCI mode, switching usually stops it from booting (`INACCESSIBLE_BOOT_DEVICE`).
- **Lenovo System Update.** It only supports ThinkPad, ThinkCentre and ThinkStation. On a ThinkBook it reports "No packages applicable". Use Lenovo Vantage instead.

## Likely affected

Any Modern Standby laptop with a SATA drive could be affected, especially models with an empty 2.5" bay that owners fill themselves:

- Lenovo ThinkBook 14 / 15 G2 ITL and G3, IdeaPad 5 14/15 ITL05
- Similar HP, Dell and Asus laptops with a 2.5" SATA bay or M.2 SATA SSD

If this fixed (or didn't fix) your laptop, please open an issue with your model and the `check-sleep.ps1` output, so the list above can be improved.

## How it works

On Modern Standby (S0 Low Power Idle) systems, the CPU package can only reach its deepest idle state (hardware DRIPS, C10) when every device reports that it can tolerate the wake-up delay. This is called Latency Tolerance Reporting (LTR). The sleep study blocker `NoHwDrips.C2.LTR_SATA` means the SATA controller's latency requirement held the CPU at package C2, so it never went deeper.

AHCI Link Power Management controls whether the SATA link can drop into its low-power Partial/Slumber states. Setting it to HIPM+DIPM allows both the host and the drive to start those transitions, which relaxes the SATA latency requirement and lets the CPU sleep.

The setting is GUID `0b2d69d7-a2a1-449c-9680-f91c70521c60` in the Disk subgroup `0012ee47-9041-4b5d-9b77-535fba8b1442`. Values: `0` Active (off), `1` HIPM, `2` HIPM+DIPM, `3` DIPM, `4` Lowest. Note that the order isn't intuitive: 2 is HIPM+DIPM and 3 is DIPM only. See [Microsoft's documentation](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/disk-settings-link-power-management-mode---hipm-dipm).

## Undo

Run **`undo-fix.cmd`**. It sets SATA link power management back to HIPM (the Windows default), hides the setting again, and sets hibernate on battery back to "never".

## Disclaimer

These scripts only change two standard Windows power settings with `powercfg`, which Microsoft supports. They don't touch the registry, drivers or BIOS. Use them at your own risk. Very old SATA drives that don't support link power management may see short pauses when waking. If that happens, run `undo-fix.cmd`.

## License

MIT
