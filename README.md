````md
# Magic Lantern Tools

Windows tools for **Magic Lantern / MLV workflows**.

## Installation

Clone or download the repository and place the tool folders in:

```text
C:\MLVScripts
````

The folder structure should look like:

```text
C:\MLVScripts\
├── AddBorders\
├── MLV-Importer\
├── RightClickMountFolder\
└── ffmpeg_convert\
```

## Tools

### `AddBorders`

Adds a configurable **white border** to images.

* JPG, JPEG, PNG, BMP, WebP
* Custom border size
* Keeps original files untouched
* Outputs to `Bordered\`
* Windows Explorer context menu

### `MLV-Importer`

Automatically imports **MLV and photo files** from camera cards.

* Detects removable drives
* Configurable destinations
* Optional file verification
* Logs and manifests
* Dry-run mode
* One-time or continuous operation

Configuration:

```text
MLV-Importer\config.json
```

Run once:

```text
Run-Once.cmd
```

Run continuously:

```text
Start-MLV-Importer.cmd
```

### `RightClickMountFolder`

Mounts MLV folders as virtual drives using **MLVFS + Dokan**.

* MLVFS mounting
* Dual-ISO mounting
* Unmounting
* Windows Explorer context menu

### `ffmpeg_convert`

Prepares **cinemascope footage for social media**.

* Rotates video 90°
* Dynamically handles different aspect ratios
* Adds black borders to fit **16:9**
* No stretching or cropping
* H.264 MP4 output
* Copies audio

Especially useful for wide formats such as **2.39:1**.

```text
2.39:1 → Rotate 90° → Dynamic Padding → 16:9
```

Example:

```powershell
.\convert-video.ps1 "C:\Videos\clip.mov"
```

## Requirements

* Windows
* PowerShell
* **FFmpeg** — `ffmpeg_convert`
* **MLVFS + Dokan** — `RightClickMountFolder`

## Typical Workflow

### Video

```text
Camera Card
    ↓
MLV-Importer
    ↓
MLV Files
    ↓
MLVFS / FFmpeg
    ↓
Video Editing
```

### Photos

```text
Photos
    ↓
AddBorders
    ↓
Bordered\
```

## Windows Explorer Integration

Some tools include `.reg` files for adding actions to the Windows Explorer context menu.

* `AddBorders` → `InstallRightClick.reg`
* `RightClickMountFolder` → `UpdateMenu.reg`
* `ffmpeg_convert` → `install-context-menu.reg`

## Backup

Always verify imported footage before formatting or erasing a camera card.

## Repository

[https://github.com/neetfrog/Magic-Lantern-Tools](https://github.com/neetfrog/Magic-Lantern-Tools)

```
```
