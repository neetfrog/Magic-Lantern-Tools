# Magic Lantern Importer

Automatic SD / CF card importer for Windows 11.

No Python required.

## Folder

Put everything here:

C:\MLVScripts\MLV-Importer\

Files:

- MLV-Importer.ps1
- Config-GUI.ps1
- Config-GUI.cmd
- config.json

## Setup

1. Edit `config.json` or run:

   `Config-GUI.cmd`

2. Set:

   - Photos destination
   - MLV destination
   - File types
   - Verification
   - Card options

3. Click `Save && Start`.

## Import

Insert an SD/CF card.

The importer automatically detects removable cards.

Photos go directly into:

`D:\Camera Import\Photos\`

MLV files go directly into:

`D:\Camera Import\MLV\`

No DCIM/card subfolders are recreated.

## MLV

Magic Lantern split recordings are supported:

- `.MLV`
- `.M00`
- `.M01`
- `.M02`
- etc.

The complete recording is treated as one group.

## Progress

The command window shows:

- Current file
- File number
- File percentage
- Overall percentage
- Bytes copied
- Transfer speed
- ETA

Example:

`File 3/12 | 64.2% | 8.4 GB / 13.1 GB | 92.5 MB/s | ETA 00:51`

## Delete from card

Disabled by default.

Enable:

`Delete files from card after successful verified import`

Source files are deleted only after the copy has succeeded and verification has passed.

For split MLV recordings, the entire group must succeed before any source files are deleted.

A confirmation is shown when the importer starts.

## Verification

Recommended:

`Size`

For maximum verification:

`SHA256`

SHA256 is slower because the files must be read again.

## Auto eject

Optional.

Enable `Eject card` in the GUI.

## Logs

Logs are stored in:

`logs\importer.log`

## Start manually

Run:

`Config-GUI.cmd`

or:

`powershell.exe -ExecutionPolicy Bypass -File MLV-Importer.ps1`

## Stop

Close the PowerShell window.

Do not remove a card while a transfer is in progress.
