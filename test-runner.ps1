$proc = Start-Process -FilePath "E:\qemu\qemu-system-x86_64.exe" -ArgumentList "-m 4096M -cdrom test-onyxos.iso -accel whpx -accel tcg -serial file:qemu-boot.log -display none" -PassThru
Start-Sleep -Seconds 3
if ($proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
if (Test-Path "qemu-boot.log") {
    Get-Content "qemu-boot.log"
} else {
    Write-Host "qemu-boot.log NOT FOUND"
}
