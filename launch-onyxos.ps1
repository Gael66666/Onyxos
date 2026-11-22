# OnyxOS 1.0 - Lanceur QEMU
# Delegue a run-test.ps1 pour garder une seule configuration QEMU.

$ISO = "$PSScriptRoot\OnyxOS-1.0-live-x86_64.iso"

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   OnyxOS 1.0 - KDE Plasma Live" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "ISO : $ISO"
Write-Host ""

& "$PSScriptRoot\run-test.ps1" -IsoPath $ISO -KeepRunning
exit $LASTEXITCODE
