param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$DriveLetter,
    [bool]$IncludeToggleShortcuts = $true
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $root 'DriveGuard.ps1'
$togglePath = Join-Path $root 'vesper-toggle.ps1'
$desktop = [Environment]::GetFolderPath('Desktop')

$wsh = New-Object -ComObject WScript.Shell

function New-VesperShortcut {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$Description,
        [string]$IconFile
    )

    $shortcutPath = Join-Path $desktop $Name
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = 'powershell.exe'
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $root

    if (Test-Path -LiteralPath $IconFile) {
        $shortcut.IconLocation = $IconFile
    }
    else {
        $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
    }

    $shortcut.Description = $Description
    $shortcut.Save()

    Write-Host "Created desktop shortcut: $shortcutPath"
}

New-VesperShortcut -Name 'Vesper.lnk' `
    -Arguments "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -DriveLetter $DriveLetter" `
    -Description 'Vesper secure vault lock/unlock control.' `
    -IconFile (Join-Path $root 'assets\vesper.ico')

if ($IncludeToggleShortcuts) {
    New-VesperShortcut -Name 'Vesper Protection ON.lnk' `
        -Arguments "-ExecutionPolicy Bypass -NoProfile -File `"$togglePath`" -State ON" `
        -Description 'Turn Vesper ejectable-media protection ON.' `
        -IconFile (Join-Path $root 'assets\toggle_on.ico')

    New-VesperShortcut -Name 'Vesper Protection OFF.lnk' `
        -Arguments "-ExecutionPolicy Bypass -NoProfile -File `"$togglePath`" -State OFF" `
        -Description 'Turn Vesper ejectable-media protection OFF.' `
        -IconFile (Join-Path $root 'assets\toggle_off.ico')

    Write-Host "Vesper shortcuts installed (app + ON/OFF toggles) for drive $DriveLetter"
}
else {
    Write-Host "Vesper shortcut installed (app only) for drive $DriveLetter"
}
