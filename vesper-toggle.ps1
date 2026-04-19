param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ON', 'OFF')]
    [string]$State
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appScript = Join-Path $root 'DriveGuard.ps1'

if (-not (Test-Path -LiteralPath $appScript)) {
    throw 'DriveGuard.ps1 not found.'
}

if ($State -eq 'ON') {
    & $appScript -SetProtectionOn -ExitAfterSet | Out-Host
}
else {
    & $appScript -SetProtectionOff -ExitAfterSet | Out-Host
}
