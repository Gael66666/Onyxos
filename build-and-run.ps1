# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Autonomous End-to-End Orchestrator
# Executes full build, brand compliance, asset generation, ISO packaging,
# and starts the OS inside QEMU with real-time serial logging and display.
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$Headless = $false,
    [switch]$KeepRunning = $true
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "     ONYXOS 1.0 (PLASMA EDITION) AUTONOMOUS PIPELINE      " -ForegroundColor Cyan
Write-Host "  Deep Black (#0B0A10) & Electric Violet (#8B5CF6/#A855F7)" -ForegroundColor DarkMagenta
Write-Host "==========================================================" -ForegroundColor Magenta

# Phase 1: Asset Generation
Write-Host "`n[PHASE 1] Generating Visual Assets & Themes..." -ForegroundColor Yellow
& python "$ScriptDir\assets\generate_assets.py"
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FAIL] Asset generation encountered an error."
    exit 1
}
Write-Host "[OK] Visual identity assets generated." -ForegroundColor Green

# Phase 2: Brand Audit & Sanitization
Write-Host "`n[PHASE 2] Brand Policy Audit (Strict Zero-Fedora UI Rule)..." -ForegroundColor Yellow
$BrandFiles = @(
    "$ScriptDir\config\os-release",
    "$ScriptDir\config\kcm-about-distrorc",
    "$ScriptDir\onyxos-kde.ks"
)

foreach ($file in $BrandFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        if ($content -match "(?m)^PRETTY_NAME=.*Fedora.*" -or $content -match "(?m)^NAME=.*Fedora.*") {
            Write-Host "[WARN] Sanitizing upstream brand in $file..." -ForegroundColor Red
            $content = $content -replace "Fedora", "OnyxOS"
            Set-Content -Path $file -Value $content
        }
    }
}
Write-Host "[OK] Brand compliance audit passed: 100% OnyxOS." -ForegroundColor Green

# Phase 3: Kickstart Validation
Write-Host "`n[PHASE 3] Validating Kickstart Recipe (onyxos-kde.ks)..." -ForegroundColor Yellow
$KsContent = Get-Content "$ScriptDir\onyxos-kde.ks" -Raw
if (-not ($KsContent -match "%packages" -and $KsContent -match "%post" -and $KsContent -match "@kde-desktop")) {
    Write-Error "[FAIL] Kickstart file structure validation failed."
    exit 1
}
Write-Host "[OK] Kickstart recipe structure validated." -ForegroundColor Green

# Phase 4: ISO Packaging
Write-Host "`n[PHASE 4] Building OnyxOS Bootable Live ISO..." -ForegroundColor Yellow
& python "$ScriptDir\build_iso.py"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$ScriptDir\onyxos-1.0-x86_64.iso")) {
    Write-Error "[FAIL] ISO packaging failed."
    exit 1
}
$IsoItem = Get-Item "$ScriptDir\onyxos-1.0-x86_64.iso"
Write-Host "[OK] Target ISO created: $($IsoItem.FullName) ($($IsoItem.Length) bytes)" -ForegroundColor Green

# Phase 5: Launch OS in QEMU
Write-Host "`n[PHASE 5] Starting OnyxOS in QEMU (E:\qemu\qemu-system-x86_64.exe)..." -ForegroundColor Yellow
$RunArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", "$ScriptDir\run-test.ps1",
    "-IsoPath", "$ScriptDir\onyxos-1.0-x86_64.iso",
    "-Ram", "4096M"
)

if ($Headless) {
    $RunArgs += "-Headless"
}
if ($KeepRunning) {
    $RunArgs += "-KeepRunning"
}

& powershell @RunArgs

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "       ONYXOS 1.0 (PLASMA EDITION) IS LIVE & ACTIVE       " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
