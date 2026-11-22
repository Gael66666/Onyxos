# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Autonomous End-to-End Orchestrator
# Executes asset generation, brand audit, ISO packaging and a QEMU boot.
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
Write-Host "`n[PHASE 1] Generating visual assets and themes..." -ForegroundColor Yellow
& python "$ScriptDir\assets\generate_assets.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Asset generation failed." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Visual identity assets generated." -ForegroundColor Green

# Phase 2: Brand Policy Audit (read-only; the ISO builder does the real work)
Write-Host "`n[PHASE 2] Brand policy audit (no upstream branding allowed)..." -ForegroundColor Yellow
$BrandFiles = @(
    "$ScriptDir\config\os-release",
    "$ScriptDir\config\kcm-about-distrorc",
    "$ScriptDir\onyxos-kde.ks"
)

$BrandViolations = @()
foreach ($file in $BrandFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        if ($content -match "(?m)^(NAME|PRETTY_NAME|VARIANT)=.*Fedora" -or
            $content -match "(?m)^ID=fedora\b") {
            $BrandViolations += $file
        }
    }
}
if ($BrandViolations.Count -gt 0) {
    $BrandViolations | ForEach-Object { Write-Host "[FAIL] Upstream branding in $_" -ForegroundColor Red }
    exit 1
}
Write-Host "[OK] Brand audit passed: 100% OnyxOS." -ForegroundColor Green

# Phase 3: Kickstart Validation
Write-Host "`n[PHASE 3] Validating kickstart recipe (onyxos-kde.ks)..." -ForegroundColor Yellow
$KsContent = Get-Content "$ScriptDir\onyxos-kde.ks" -Raw
if (-not ($KsContent -match "%packages" -and $KsContent -match "%post" -and $KsContent -match "@kde-desktop")) {
    Write-Host "[FAIL] Kickstart structure validation failed." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Kickstart structure validated." -ForegroundColor Green

# Phase 4: Build the live ISO from the Fedora KDE live image
Write-Host "`n[PHASE 4] Building the OnyxOS live ISO from Fedora KDE..." -ForegroundColor Yellow
$BuildStarted = Get-Date
& python "$ScriptDir\build_iso.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] ISO packaging failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

$IsoPath = "$ScriptDir\OnyxOS-1.0-live-x86_64.iso"
if (-not (Test-Path $IsoPath)) {
    Write-Host "[FAIL] Target ISO not found: $IsoPath" -ForegroundColor Red
    exit 1
}
$IsoItem = Get-Item $IsoPath
if ($IsoItem.LastWriteTime -lt $BuildStarted) {
    Write-Host "[WARN] ISO timestamp predates this build; verify build_iso.py output." -ForegroundColor Yellow
}
Write-Host "[OK] Target ISO: $($IsoItem.FullName) ($($IsoItem.Length) bytes)" -ForegroundColor Green

# Phase 5: Launch OS in QEMU
Write-Host "`n[PHASE 5] Starting OnyxOS in QEMU..." -ForegroundColor Yellow
$RunArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "$ScriptDir\run-test.ps1",
    "-IsoPath", $IsoPath,
    "-Ram", "4096M"
)

if ($Headless) {
    $RunArgs += "-Headless"
}
if ($KeepRunning) {
    $RunArgs += "-KeepRunning"
}

& powershell @RunArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] QEMU launcher failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "       ONYXOS 1.0 (PLASMA EDITION) IS LIVE & ACTIVE       " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
