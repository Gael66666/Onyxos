# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Official ISO Runner
# Boots the customized OnyxOS Live ISO (based on Fedora KDE Plasma) in QEMU GUI
# ==============================================================================

[CmdletBinding()]
param (
    [string]$IsoPath = "$PSScriptRoot\onyxos-1.0-x86_64.iso",
    [string]$Ram = "4096M",
    [int]$Cores = 4,
    [string]$QemuPath = "E:\qemu\qemu-system-x86_64.exe",
    [string]$LogFile = "$PSScriptRoot\qemu-boot.log",
    [switch]$Headless = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "       ONYXOS 1.0 (PLASMA EDITION) - LIVE ISO RUNNER      " -ForegroundColor Cyan
Write-Host "  Deep Black (#0B0A10) & Electric Violet (#8B5CF6/#A855F7)" -ForegroundColor DarkMagenta
Write-Host "==========================================================" -ForegroundColor Magenta

if (-not (Test-Path $QemuPath)) {
    Write-Error "[FAIL] QEMU introuvable à l'emplacement : $QemuPath"
    exit 1
}

if (-not (Test-Path $IsoPath)) {
    $FallbackIso = "$PSScriptRoot\Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
    if (Test-Path $FallbackIso) {
        $IsoPath = $FallbackIso
    } else {
        Write-Error "[FAIL] Fichier ISO introuvable à : $IsoPath"
        exit 1
    }
}

$ResolvedIso = Resolve-Path $IsoPath
$IsoFullPath = $ResolvedIso.Path
Write-Host "[OK] Image ISO OnyxOS chargée : $IsoFullPath ($(Get-Item $IsoFullPath | Select-Object -ExpandProperty Length) octets)" -ForegroundColor Green

$QemuArgs = @(
    "-m", $Ram,
    "-smp", $Cores,
    "-accel", "whpx",
    "-accel", "tcg",
    "-cdrom", "`"$IsoFullPath`"",
    "-boot", "d",
    "-vga", "virtio",
    "-serial", "file:`"$LogFile`""
)

if ($Headless) {
    $QemuArgs += @("-display", "none")
}

Write-Host "[*] Lancement d'OnyxOS dans QEMU GUI (RAM: $Ram, Cores: $Cores)..." -ForegroundColor Yellow
$ProcessArgs = $QemuArgs -join " "

$Proc = Start-Process -FilePath $QemuPath -ArgumentList $ProcessArgs -PassThru

Start-Sleep -Seconds 3

if ($Proc -and -not $Proc.HasExited) {
    Write-Host "[SUCCESS] OnyxOS 1.0 (Plasma Edition) est actif dans QEMU (PID $($Proc.Id)) !" -ForegroundColor Green
    Write-Host "[INFO] Fenêtre graphique active sur votre bureau." -ForegroundColor Cyan
} else {
    Write-Host "[WARN] Le processus s'est arrêté avec le code $($Proc.ExitCode)" -ForegroundColor Yellow
}
