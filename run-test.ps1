# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Official ISO Runner
# Boots the customized OnyxOS Live ISO (based on Fedora KDE Plasma) in QEMU.
# ==============================================================================

[CmdletBinding()]
param (
    [string]$IsoPath = "$PSScriptRoot\OnyxOS-1.0-live-x86_64.iso",
    [string]$Ram = "4096M",
    [int]$Cores = 4,
    [string]$QemuPath = "E:\qemu\qemu-system-x86_64.exe",
    [string]$LogFile = "$PSScriptRoot\qemu-boot.log",
    [string]$Cpu = "max",
    [switch]$Headless = $false,
    [switch]$KeepRunning = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "       ONYXOS 1.0 (PLASMA EDITION) - LIVE ISO RUNNER      " -ForegroundColor Cyan
Write-Host "  Deep Black (#0B0A10) & Electric Violet (#8B5CF6/#A855F7)" -ForegroundColor DarkMagenta
Write-Host "==========================================================" -ForegroundColor Magenta

if (-not (Test-Path $QemuPath)) {
    Write-Host "[FAIL] QEMU introuvable : $QemuPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $IsoPath)) {
    Write-Host "[FAIL] ISO OnyxOS introuvable : $IsoPath" -ForegroundColor Red
    Write-Host "       Construisez-la avec build_iso.py." -ForegroundColor Yellow
    exit 1
}

$IsoFullPath = (Resolve-Path $IsoPath).Path
$IsoItem = Get-Item $IsoFullPath
Write-Host "[OK] ISO OnyxOS : $IsoFullPath ($($IsoItem.Length) octets)" -ForegroundColor Green

$QemuArgs = @(
    "-name", "OnyxOS 1.0",
    "-machine", "q35",
    "-accel", "tcg,thread=multi",
    "-cpu", $Cpu,
    "-smp", $Cores,
    "-m", $Ram,
    "-drive", "file=$IsoFullPath,if=none,id=cd0,media=cdrom,readonly=on,format=raw",
    "-device", "virtio-scsi-pci,id=scsi0",
    "-device", "scsi-cd,drive=cd0,bus=scsi0.0",
    "-boot", "d",
    "-vga", "std",
    "-serial", "file:$LogFile",
    "-audiodev", "none,id=noaudio"
)

if ($Headless) {
    $QemuArgs += @("-display", "none")
}

Write-Host "[*] Lancement de QEMU (CPU: $Cpu, RAM: $Ram, coeurs: $Cores)..." -ForegroundColor Yellow

if ($KeepRunning) {
    $proc = Start-Process -FilePath $QemuPath -ArgumentList $QemuArgs -PassThru
    Start-Sleep -Seconds 3
    if (-not $proc -or $proc.HasExited) {
        Write-Host "[FAIL] QEMU s'est arrêté immédiatement (code $($proc.ExitCode))." -ForegroundColor Red
        exit 1
    }
    Write-Host "[SUCCESS] OnyxOS 1.0 est actif dans QEMU (PID $($proc.Id))." -ForegroundColor Green
    exit 0
}

& $QemuPath @QemuArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] QEMU a retourné le code $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}
