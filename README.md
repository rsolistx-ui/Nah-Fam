# Vesper Secure Vault (Windows 11)

No, BitLocker is **not** required anymore.

This version uses a **proprietary encrypted vault format** (`.dgv`) built into the script:

- New vaults now use **DGV2** with AES-256-GCM + PBKDF2-SHA512 (600,000 iterations).
- Existing DGV1 vaults are still readable for backward compatibility (PBKDF2-SHA256, 200,000 iterations).
- On unlock, you enter your password and the vault is decrypted back to `VaultData`.
- The app listens for Windows sleep/suspend and auto-locks when enabled.

## What this gives you

1. Automatic lock on sleep/suspend.
2. Desktop app shortcut launch.
3. Manual ON/OFF protection toggle inside app.
4. Dedicated desktop toggles:
   - `Vesper Protection ON.lnk`
   - `Vesper Protection OFF.lnk`
5. Manual **Lock now** and **Unlock now**.
6. Password required after reboot, because only encrypted `vault.dgv` remains until unlocked.
7. Optional USB recovery key flow to unlock if password is forgotten.

## Requirements

- Windows 11
- PowerShell 5.1+

## Setup

1. Copy this folder somewhere permanent.
2. Open PowerShell in this folder.
3. Create desktop shortcuts (replace `E:` with your drive letter):

```powershell
.\install-shortcut.ps1 -DriveLetter E:
```

Optional (app shortcut only, no desktop ON/OFF toggles):

```powershell
.\install-shortcut.ps1 -DriveLetter E: -IncludeToggleShortcuts $false
```

4. If toggles are enabled, you will get:
   - `Vesper.lnk`
   - `Vesper Protection ON.lnk`
   - `Vesper Protection OFF.lnk`


## Asset generation

Run `powershell -ExecutionPolicy Bypass -File .\generate-assets.ps1` before building.

## Build EXE

If you want a packaged executable (`Vesper.exe`), run:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser
.\build-exe.ps1
```

Output: `dist\Vesper.exe`

## Usage

- Store sensitive files inside `<DriveLetter>\VaultData` while unlocked.
- Click **Lock now** to encrypt and clear plaintext data from `VaultData`.
- Click **Unlock now** to decrypt `vault.dgv` back into `VaultData`.
- Use desktop ON/OFF toggle shortcuts to quickly enable or disable ejectable-media protection.


## USB recovery key (forgot-password fallback)

- Click **Set Recovery USB** and provide a thumb-drive letter (for example `F:`).
- Vesper creates `vesper.recovery.key` on that USB drive.
- During lock, Vesper updates `vault.recovery` on the protected drive.
- If password is forgotten, click **Unlock via USB Key** with the recovery USB inserted.

Treat the recovery USB as highly sensitive. Anyone with both `vault.recovery` and `vesper.recovery.key` can unlock the vault.

## Encryption profile

Current implementation in this codebase:
- AES-256-GCM authenticated encryption
- PBKDF2-SHA512 with 600,000 iterations for new vaults
- Per-vault stored KDF iteration metadata (DGV2 header)
- Backward-compatible decryption for legacy DGV1 vaults

Important: no one can honestly guarantee “absolute most up-to-date forever” cryptography in a static script. This build uses a stronger modern profile than before and is structured for future migration.

## Security notes

- This is a custom (proprietary) workflow and format, not audited like BitLocker.
- If you forget the password and did not configure a recovery USB, recovery is not available.
- Always verify lock completed before unplugging the drive.

## Branding and icon

- The app ships with `assets/vesper.ico` and uses it in the app window and shortcuts.
- Desktop toggle shortcuts use `assets/toggle_on.ico` and `assets/toggle_off.ico`.
