param(
    [string]$OutputDir = '.\dist'
)

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Error 'ps2exe module is required. Install with: Install-Module -Name ps2exe -Scope CurrentUser'
    exit 1
}

Import-Module ps2exe -ErrorAction Stop

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$input = Join-Path $PSScriptRoot 'DriveGuard.ps1'
$output = Join-Path $OutputDir 'Vesper.exe'
$icon = Join-Path $PSScriptRoot 'assets\vesper.ico'

Invoke-ps2exe -inputFile $input -outputFile $output -iconFile $icon -title 'Vesper' -description 'Vesper secure vault' -noConsole

Write-Host "Built EXE: $output"
