# Magic Lantern Tools

A collection of Windows tools for working with **Magic Lantern / MLV footage**.

## Installation

1. Download or clone this repository.
2. Place the tool folders in:

```text
C:\MLVScripts
```

The folder structure should look like:

```text
C:\MLVScripts\
├── AddBorders\
├── MLV-Importer\
├── RightClickMountFolder\
└── ffmpeg_convert\
```

Some tools also require additional software such as **FFmpeg**, **MLVFS**, or **Dokan**.

## Tools

### `AddBorders`

Adds a white border around images.

* Supports JPG, JPEG, PNG, BMP and WebP
* Configurable border size
* Originals are kept untouched
* Output goes into a `Bordered` folder

`InstallRightClick.reg` adds it to the Windows Explorer context menu.

---

### `MLV-Importer`

Automatically imports MLV and photo files from removable camera cards.

* Detects removable drives
* Copies MLV and photo files
* Configurable destinations
* Optional file verification
* Logs and manifests
* Dry-run mode

Configure:

```text
MLV-Importer/config.json
```

Run once:

```text
Run-Once.cmd
```

Run continuously:

```text
Start-MLV-Importer.cmd
```

---

### `RightClickMountFolder`

Mounts MLV folders as virtual drives using **MLVFS + Dokan**.

Supports:

* Normal MLVFS mounting
* Dual-ISO mounting
* Unmounting

`UpdateMenu.reg` adds the commands to the Windows Explorer right-click menu.

---

### `ffmpeg_convert`

Converts videos to H.264 MP4 using FFmpeg.

`convert-video.ps1` handles rotation, padding, H.264 encoding and audio copying.

Example:

```powershell
.\convert-video.ps1 "C:\Videos\clip.mov"
```

`install-context-menu.reg` adds the converter to Windows Explorer.

## Requirements

* Windows
* PowerShell
* FFmpeg — for `ffmpeg_convert`
* MLVFS + Dokan — for `RightClickMountFolder`

## Typical Workflow

```text
Camera Card
    ↓
MLV-Importer
    ↓
MLV files
    ↓
MLVFS / FFmpeg
    ↓
Video editing
```

For photos:

```text
Photos → AddBorders → Bordered/
```

## Repository

https://github.com/neetfrog/Magic-Lantern-Tools
