# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Runner Direct
# ==============================================================================

$QemuPath = "E:\qemu\qemu-system-x86_64.exe"
$IsoPath  = "$PSScriptRoot\onyxos-1.0-x86_64.iso"
$LogFile  = "$PSScriptRoot\qemu-boot.log"

if (-not (Test-Path $IsoPath)) {
    $IsoPath = "$PSScriptRoot\Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
}

$QemuArgs = @(
    "-m", "4096M",
    "-smp", "4",
    "-accel", "whpx",
    "-accel", "tcg",
    "-cdrom", "`"$IsoPath`"",
    "-boot", "d",
    "-vga", "virtio",
    "-serial", "file:`"$LogFile`""
)

Write-Host "[*] Lancement d'OnyxOS 1.0 (Plasma Edition) dans QEMU..." -ForegroundColor Green
$Proc = Start-Process -FilePath $QemuPath -ArgumentList ($QemuArgs -join " ") -PassThru

Start-Sleep -Seconds 3

if ($Proc -and -not $Proc.HasExited) {
    Write-Host "[SUCCESS] QEMU tourne avec succès (PID $($Proc.Id)) !" -ForegroundColor Green
    Write-Host "[INFO] Fenêtre graphique active sur votre bureau." -ForegroundColor Cyan
} else {
    Write-Host "[WARN] Code de sortie : $($Proc.ExitCode)" -ForegroundColor Yellow
}
