param()

$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinuxProject = '/mnt/c/Users/OHL/.gemini/antigravity/scratch/onyxos'

Write-Host 'Reconstruction propre de l ISO OnyxOS...' -ForegroundColor Magenta
wsl -d Ubuntu -- bash -lc "cd '$LinuxProject' && bash ./rebuild-live-iso.sh"
if ($LASTEXITCODE -ne 0) { throw 'La reconstruction de l ISO a échoué.' }

Write-Host "ISO créée : $Project\OnyxOS-1.0-live-x86_64.iso" -ForegroundColor Green
