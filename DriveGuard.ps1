param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$DriveLetter = 'E:',

    [string]$DataFolderName = 'VaultData',
    [string]$VaultFileName = 'vault.dgv',
    [switch]$StartMinimized,
    [switch]$SetProtectionOn,
    [switch]$SetProtectionOff,
    [switch]$ExitAfterSet
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:appName = 'Vesper'
$script:drive = $DriveLetter.ToUpper()
$script:vaultFolder = Join-Path $script:drive $DataFolderName
$script:vaultFile = Join-Path $script:drive $VaultFileName
$script:iconPath = Join-Path $PSScriptRoot 'assets\vesper.ico'
$script:VaultMagicV2 = 'DGV2'
$script:VaultMagicV1 = 'DGV1'
$script:KdfIterations = 600000
$script:KdfHash = [System.Security.Cryptography.HashAlgorithmName]::SHA512
$script:settingsDir = Join-Path $env:APPDATA 'Vesper'
$script:settingsPath = Join-Path $script:settingsDir 'settings.json'

$settings = Get-AppSettings
$script:monitorEnabled = [bool]$settings.ProtectionEnabled
$script:recoveryDrive = [string]$settings.RecoveryDrive


function Get-AppSettings {
    if (-not (Test-Path -LiteralPath $script:settingsDir)) {
        New-Item -Path $script:settingsDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:settingsPath)) {
        return [pscustomobject]@{
            ProtectionEnabled = $true
            RecoveryDrive = ''
        }
    }

    try {
        return Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            ProtectionEnabled = $true
            RecoveryDrive = ''
        }
    }
}

function Save-AppSettings {
    param([bool]$ProtectionEnabled, [string]$RecoveryDrive = "")

    if (-not (Test-Path -LiteralPath $script:settingsDir)) {
        New-Item -Path $script:settingsDir -ItemType Directory -Force | Out-Null
    }

    [pscustomobject]@{
        ProtectionEnabled = $ProtectionEnabled
        RecoveryDrive = $RecoveryDrive
        UpdatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $script:settingsPath -Encoding UTF8
}


function Get-RecoveryKeyPath {
    param([string]$DriveLetter)
    return Join-Path ($DriveLetter + '\') 'vesper.recovery.key'
}

function Get-RecoveryBlobPath {
    return Join-Path $script:drive 'vault.recovery'
}

function Ensure-RecoveryKey {
    param([string]$DriveLetter)

    if ([string]::IsNullOrWhiteSpace($DriveLetter)) { return $false }
    $keyPath = Get-RecoveryKeyPath -DriveLetter $DriveLetter

    if (-not (Test-Path -LiteralPath $keyPath)) {
        $bytes = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        [System.IO.File]::WriteAllBytes($keyPath, $bytes)
    }

    return $true
}

function Protect-RecoveryPassword {
    param([string]$Password, [byte[]]$RecoveryKeyBytes)

    $nonce = New-Object byte[] 12
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
    $key = [System.Security.Cryptography.SHA256]::HashData($RecoveryKeyBytes)
    $plain = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $cipher = New-Object byte[] $plain.Length
    $tag = New-Object byte[] 16

    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    $aes.Encrypt($nonce, $plain, $cipher, $tag)

    return [pscustomobject]@{
        nonce = [Convert]::ToBase64String($nonce)
        tag = [Convert]::ToBase64String($tag)
        cipher = [Convert]::ToBase64String($cipher)
    } | ConvertTo-Json
}

function Unprotect-RecoveryPassword {
    param([string]$BlobJson, [byte[]]$RecoveryKeyBytes)

    $obj = $BlobJson | ConvertFrom-Json
    $nonce = [Convert]::FromBase64String($obj.nonce)
    $tag = [Convert]::FromBase64String($obj.tag)
    $cipher = [Convert]::FromBase64String($obj.cipher)

    $key = [System.Security.Cryptography.SHA256]::HashData($RecoveryKeyBytes)
    $plain = New-Object byte[] $cipher.Length
    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    $aes.Decrypt($nonce, $cipher, $tag, $plain)
    return [System.Text.Encoding]::UTF8.GetString($plain)
}

function Add-Log {
    param([string]$Message)

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] $Message"
    $logBox.AppendText("$line`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Get-PasswordDialog {
    $pwForm = New-Object System.Windows.Forms.Form
    $pwForm.Text = "$($script:appName) Password"
    $pwForm.Size = New-Object System.Drawing.Size(420, 170)
    $pwForm.StartPosition = 'CenterParent'
    $pwForm.FormBorderStyle = 'FixedDialog'
    $pwForm.MaximizeBox = $false
    $pwForm.MinimizeBox = $false
    if (Test-Path -LiteralPath $script:iconPath) {
        try {
            $pwForm.Icon = New-Object System.Drawing.Icon($script:iconPath)
        }
        catch { }
    }

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Enter vault password:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $pwForm.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(20, 45)
    $textBox.Size = New-Object System.Drawing.Size(360, 20)
    $textBox.UseSystemPasswordChar = $true
    $pwForm.Controls.Add($textBox)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Location = New-Object System.Drawing.Point(220, 80)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $pwForm.AcceptButton = $ok
    $pwForm.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(305, 80)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $pwForm.CancelButton = $cancel
    $pwForm.Controls.Add($cancel)

    $result = $pwForm.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        return $textBox.Text
    }

    return $null
}

function Protect-Bytes {
    param(
        [byte[]]$PlainBytes,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Password) -or $Password.Length -lt 12) {
        throw 'Password must be at least 12 characters.'
    }

    $salt = New-Object byte[] 16
    $nonce = New-Object byte[] 12
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($salt)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, $script:KdfIterations, $script:KdfHash)
    $key = $kdf.GetBytes(32)

    $cipher = New-Object byte[] $PlainBytes.Length
    $tag = New-Object byte[] 16

    try {
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        $aes.Encrypt($nonce, $PlainBytes, $cipher, $tag)

        $magic = [System.Text.Encoding]::ASCII.GetBytes($script:VaultMagicV2)
        $iterBytes = [System.BitConverter]::GetBytes([int]$script:KdfIterations)

        $output = New-Object System.IO.MemoryStream
        $output.Write($magic, 0, $magic.Length)
        $output.Write($iterBytes, 0, $iterBytes.Length)
        $output.Write($salt, 0, $salt.Length)
        $output.Write($nonce, 0, $nonce.Length)
        $output.Write($tag, 0, $tag.Length)
        $output.Write($cipher, 0, $cipher.Length)

        return $output.ToArray()
    }
    finally {
        [System.Security.Cryptography.CryptographicOperations]::ZeroMemory($key)
    }
}

function Unprotect-Bytes {
    param(
        [byte[]]$EncryptedBytes,
        [string]$Password
    )

    if ($EncryptedBytes.Length -lt 48) {
        throw 'Invalid vault format.'
    }

    $magic = [System.Text.Encoding]::ASCII.GetString($EncryptedBytes, 0, 4)

    if ($magic -eq $script:VaultMagicV2) {
        if ($EncryptedBytes.Length -lt 52) {
            throw 'Invalid V2 vault format.'
        }

        $iterations = [System.BitConverter]::ToInt32($EncryptedBytes, 4)
        if ($iterations -lt 200000) {
            throw 'Invalid KDF iteration count.'
        }

        $salt = $EncryptedBytes[8..23]
        $nonce = $EncryptedBytes[24..35]
        $tag = $EncryptedBytes[36..51]
        $cipher = $EncryptedBytes[52..($EncryptedBytes.Length - 1)]

        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, $iterations, $script:KdfHash)
    }
    elseif ($magic -eq $script:VaultMagicV1) {
        # Backward compatibility with older DGV1 vaults.
        $salt = $EncryptedBytes[4..19]
        $nonce = $EncryptedBytes[20..31]
        $tag = $EncryptedBytes[32..47]
        $cipher = $EncryptedBytes[48..($EncryptedBytes.Length - 1)]

        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, 200000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    }
    else {
        throw 'Unsupported vault header.'
    }

    $key = $kdf.GetBytes(32)
    $plain = New-Object byte[] $cipher.Length

    try {
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        $aes.Decrypt($nonce, $cipher, $tag, $plain)
        return $plain
    }
    finally {
        [System.Security.Cryptography.CryptographicOperations]::ZeroMemory($key)
    }
}

if ($SetProtectionOn -and $SetProtectionOff) {
    throw 'Choose either -SetProtectionOn or -SetProtectionOff, not both.'
}

if ($SetProtectionOn) {
    Save-AppSettings -ProtectionEnabled $true -RecoveryDrive $script:recoveryDrive
    Write-Host 'Vesper protection set to ON.'
    if ($ExitAfterSet) { return }
}

if ($SetProtectionOff) {
    Save-AppSettings -ProtectionEnabled $false -RecoveryDrive $script:recoveryDrive
    Write-Host 'Vesper protection set to OFF.'
    if ($ExitAfterSet) { return }
}

function Ensure-Folder {
    if (-not (Test-Path -LiteralPath $script:vaultFolder)) {
        New-Item -ItemType Directory -Path $script:vaultFolder | Out-Null
    }
}

function Lock-Vault {
    if (-not (Test-Path -LiteralPath $script:vaultFolder)) {
        Add-Log "Nothing to lock. Folder missing: $script:vaultFolder"
        return $false
    }

    $password = Get-PasswordDialog
    if (-not $password) {
        Add-Log 'Lock canceled (no password entered).'
        return $false
    }

    $tmpZip = Join-Path $env:TEMP ("driveguard_" + [guid]::NewGuid() + '.zip')

    try {
        if (Test-Path -LiteralPath $script:vaultFile) {
            Remove-Item -LiteralPath $script:vaultFile -Force
        }

        Compress-Archive -Path (Join-Path $script:vaultFolder '*') -DestinationPath $tmpZip -CompressionLevel Optimal -Force
        $zipBytes = [System.IO.File]::ReadAllBytes($tmpZip)
        $encrypted = Protect-Bytes -PlainBytes $zipBytes -Password $password
        [System.IO.File]::WriteAllBytes($script:vaultFile, $encrypted)

        if (-not [string]::IsNullOrWhiteSpace($script:recoveryDrive)) {
            $keyPath = Get-RecoveryKeyPath -DriveLetter $script:recoveryDrive
            if (Test-Path -LiteralPath $keyPath) {
                $recoveryKeyBytes = [System.IO.File]::ReadAllBytes($keyPath)
                $blob = Protect-RecoveryPassword -Password $password -RecoveryKeyBytes $recoveryKeyBytes
                Set-Content -LiteralPath (Get-RecoveryBlobPath) -Value $blob -Encoding UTF8
                Add-Log "Recovery USB key package updated."
            }
        }

        Remove-Item -LiteralPath $script:vaultFolder -Recurse -Force
        New-Item -ItemType Directory -Path $script:vaultFolder | Out-Null

        Add-Log "Vault locked to: $script:vaultFile"
        return $true
    }
    catch {
        Add-Log "Lock failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        }
    }
}

function Unlock-Vault {
    param([switch]$UseRecoveryKey)
    if (-not (Test-Path -LiteralPath $script:vaultFile)) {
        Add-Log "No vault file found at: $script:vaultFile"
        return $false
    }

    if ($UseRecoveryKey) {
        if ([string]::IsNullOrWhiteSpace($script:recoveryDrive)) {
            Add-Log 'No recovery USB configured.'
            return $false
        }

        $keyPath = Get-RecoveryKeyPath -DriveLetter $script:recoveryDrive
        $blobPath = Get-RecoveryBlobPath

        if (-not (Test-Path -LiteralPath $keyPath) -or -not (Test-Path -LiteralPath $blobPath)) {
            Add-Log 'Recovery unlock unavailable (missing key USB or recovery blob).'
            return $false
        }

        $recoveryKeyBytes = [System.IO.File]::ReadAllBytes($keyPath)
        $blob = Get-Content -LiteralPath $blobPath -Raw
        try {
            $password = Unprotect-RecoveryPassword -BlobJson $blob -RecoveryKeyBytes $recoveryKeyBytes
            Add-Log 'Recovery key accepted. Unlocking with USB recovery package.'
        }
        catch {
            Add-Log 'Recovery key unlock failed.'
            return $false
        }
    }
    else {
        $password = Get-PasswordDialog
        if (-not $password) {
            Add-Log 'Unlock canceled (no password entered).'
            return $false
        }
    }

    $tmpZip = Join-Path $env:TEMP ("driveguard_" + [guid]::NewGuid() + '.zip')

    try {
        $encrypted = [System.IO.File]::ReadAllBytes($script:vaultFile)
        $zipBytes = Unprotect-Bytes -EncryptedBytes $encrypted -Password $password
        [System.IO.File]::WriteAllBytes($tmpZip, $zipBytes)

        if (Test-Path -LiteralPath $script:vaultFolder) {
            Remove-Item -LiteralPath $script:vaultFolder -Recurse -Force
        }

        New-Item -ItemType Directory -Path $script:vaultFolder | Out-Null
        Expand-Archive -LiteralPath $tmpZip -DestinationPath $script:vaultFolder -Force

        Add-Log "Vault unlocked into folder: $script:vaultFolder"
        return $true
    }
    catch {
        Add-Log "Unlock failed. Wrong password or corrupt vault. $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($script:appName) Secure Vault ($script:drive)"
$form.Size = New-Object System.Drawing.Size(620, 460)
$form.StartPosition = 'CenterScreen'
if (Test-Path -LiteralPath $script:iconPath) {
    try {
        $appIcon = New-Object System.Drawing.Icon($script:iconPath)
        $form.Icon = $appIcon
    }
    catch { }
}

$monitorCheckbox = New-Object System.Windows.Forms.CheckBox
$monitorCheckbox.Text = 'Enable automatic lock on Sleep/Suspend'
$monitorCheckbox.AutoSize = $true
$monitorCheckbox.Location = New-Object System.Drawing.Point(20, 20)
$monitorCheckbox.Checked = $script:monitorEnabled
$form.Controls.Add($monitorCheckbox)

$lockButton = New-Object System.Windows.Forms.Button
$lockButton.Text = 'Lock now'
$lockButton.Size = New-Object System.Drawing.Size(110, 35)
$lockButton.Location = New-Object System.Drawing.Point(20, 55)
$form.Controls.Add($lockButton)

$unlockButton = New-Object System.Windows.Forms.Button
$unlockButton.Text = 'Unlock now'
$unlockButton.Size = New-Object System.Drawing.Size(110, 35)
$unlockButton.Location = New-Object System.Drawing.Point(140, 55)
$form.Controls.Add($unlockButton)

$recoverySetupButton = New-Object System.Windows.Forms.Button
$recoverySetupButton.Text = 'Set Recovery USB'
$recoverySetupButton.Size = New-Object System.Drawing.Size(130, 35)
$recoverySetupButton.Location = New-Object System.Drawing.Point(260, 55)
$form.Controls.Add($recoverySetupButton)

$recoveryUnlockButton = New-Object System.Windows.Forms.Button
$recoveryUnlockButton.Text = 'Unlock via USB Key'
$recoveryUnlockButton.Size = New-Object System.Drawing.Size(150, 35)
$recoveryUnlockButton.Location = New-Object System.Drawing.Point(400, 55)
$form.Controls.Add($recoveryUnlockButton)

$helpLabel = New-Object System.Windows.Forms.Label
$helpLabel.Text = "Data folder: $script:vaultFolder | Encrypted vault: $script:vaultFile"
$helpLabel.MaximumSize = New-Object System.Drawing.Size(570, 0)
$helpLabel.AutoSize = $true
$helpLabel.Location = New-Object System.Drawing.Point(20, 100)
$form.Controls.Add($helpLabel)

$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Text = 'Security reminder: Keep files in VaultData and lock before unplugging external media.'
$warningLabel.MaximumSize = New-Object System.Drawing.Size(570, 0)
$warningLabel.AutoSize = $true
$warningLabel.Location = New-Object System.Drawing.Point(20, 120)
$form.Controls.Add($warningLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Size = New-Object System.Drawing.Size(570, 260)
$logBox.Location = New-Object System.Drawing.Point(20, 150)
$form.Controls.Add($logBox)

$monitorCheckbox.Add_CheckedChanged({
    $script:monitorEnabled = $monitorCheckbox.Checked
    if ($script:monitorEnabled) {
        Save-AppSettings -ProtectionEnabled $true -RecoveryDrive $script:recoveryDrive
        Add-Log 'Automatic sleep locking ENABLED (protection ON).'
    }
    else {
        Save-AppSettings -ProtectionEnabled $false -RecoveryDrive $script:recoveryDrive
        Add-Log 'Automatic sleep locking DISABLED (protection OFF).'
    }
})

$lockButton.Add_Click({
    Lock-Vault | Out-Null
})

$unlockButton.Add_Click({
    Unlock-Vault | Out-Null
})

$recoverySetupButton.Add_Click({
    $input = [Microsoft.VisualBasic.Interaction]::InputBox('Enter recovery USB drive letter (example: F:)', 'Vesper Recovery USB', $script:recoveryDrive)
    if (-not [string]::IsNullOrWhiteSpace($input)) {
        $candidate = $input.Trim().ToUpper()
        if ($candidate -notmatch '^[A-Z]:$') {
            Add-Log 'Invalid recovery drive format.'
            return
        }

        try {
            if (Ensure-RecoveryKey -DriveLetter $candidate) {
                $script:recoveryDrive = $candidate
                Save-AppSettings -ProtectionEnabled $script:monitorEnabled -RecoveryDrive $script:recoveryDrive
                Add-Log "Recovery USB configured: $script:recoveryDrive"
            }
        }
        catch {
            Add-Log "Failed to configure recovery USB: $($_.Exception.Message)"
        }
    }
})

$recoveryUnlockButton.Add_Click({
    Unlock-Vault -UseRecoveryKey | Out-Null
})

$powerEventHandler = [Microsoft.Win32.PowerModeChangedEventHandler]{
    param($sender, $eventArgs)

    if ($eventArgs.Mode -eq [Microsoft.Win32.PowerModes]::Suspend) {
        Add-Log 'Power event: Suspend detected.'
        if ($script:monitorEnabled) {
            Lock-Vault | Out-Null
        }
        else {
            Add-Log 'Sleep lock skipped because protection is OFF.'
        }
    }
    elseif ($eventArgs.Mode -eq [Microsoft.Win32.PowerModes]::Resume) {
        Add-Log 'Power event: Resume detected.'
    }
}

[Microsoft.Win32.SystemEvents]::add_PowerModeChanged($powerEventHandler)

$form.Add_Shown({
    Ensure-Folder
    Add-Log "$($script:appName) Secure Vault is running for $($script:drive)."
    Add-Log "Crypto profile: AES-256-GCM + PBKDF2-SHA512 ($($script:KdfIterations) iterations, DGV2)."
    Add-Log ("Protection state: " + ($(if ($script:monitorEnabled) {'ON'} else {'OFF'})))
    if (-not [string]::IsNullOrWhiteSpace($script:recoveryDrive)) {
        Add-Log "Recovery USB: $script:recoveryDrive"
    }
    if ($StartMinimized) {
        $form.WindowState = 'Minimized'
        $form.ShowInTaskbar = $true
    }
})

$form.Add_FormClosed({
    [Microsoft.Win32.SystemEvents]::remove_PowerModeChanged($powerEventHandler)
})

[void]$form.ShowDialog()
