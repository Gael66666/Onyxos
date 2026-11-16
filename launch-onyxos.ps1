# OnyxOS 1.0 — Lanceur QEMU Final
# Mode BIOS + optimisations TCG max

$ISO = "C:\Users\OHL\.gemini\antigravity\scratch\onyxos\OnyxOS-1.0-live-x86_64.iso"
$QEMU = "E:\qemu\qemu-system-x86_64.exe"

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   OnyxOS 1.0 - KDE Plasma Live" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "ISO : $ISO"
Write-Host "Demarrage QEMU en mode BIOS..."
Write-Host ""

Start-Process $QEMU -ArgumentList @(
    "-name", "OnyxOS 1.0",
    "-machine", "pc,accel=tcg",
    "-cpu", "max",
    "-smp", "4,sockets=1,cores=4,threads=1",
    "-m", "4096",
    "-boot", "order=d,menu=on",
    "-drive", "file=$ISO,media=cdrom,readonly=on,if=ide",
    "-vga", "virtio",
    "-display", "sdl,gl=off",
    "-audiodev", "none,id=noaudio",
    "-usb",
    "-device", "usb-tablet"
) -WindowStyle Normal

Write-Host "QEMU lance ! Attends le menu OnyxOS..." -ForegroundColor Green
