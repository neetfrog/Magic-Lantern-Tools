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
├── MagicDump\
├── RightClickMountFolder\
└── SocialMediaRotate\
```

Some tools also require additional software such as **FFmpeg**, **MLVFS**, or **Dokan**.

## Tools

### `MagicDump`

Automatically imports MLV and photo files from removable camera cards.

* Detects removable drives
* Copies MLV and photo files
* Configurable destinations
* Optional file verification
* Logs and manifests
* Dry-run mode

Configure:

```text
MagicDump/Config.cmd
```

Run:

```text
MagicDump.cmd
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

### `SocialMediaRotate`

Prepare cinemascope footage for social media.

`convert-video.ps1` - 🔄 Rotates the video 90°
- 📐 Dynamically handles different aspect ratios
- ⬛ Adds black borders to fit a 16:9 frame
- 🎞️ Preserves the original image without stretching or cropping
- 📱 Makes ultra-wide footage more usable on phones

Example:

```powershell
.\convert-video.ps1 "C:\Videos\clip.mov"
```

`install-context-menu.reg` adds the converter to Windows Explorer.

# Magic Lantern MLVFS Windows Bundle

Windows bundle for **Magic Lantern MLVFS** to mount `.MLV` files as a virtual drive. Includes MLVFS, Dokan and Explorer right-click mount script.

![Windows Explorer right-click menu](https://i.ibb.co/gLBJ3HDb/image.png)

![Windows Explorer right-click menu](https://i.ibb.co/NnSRvRFP/image.png)


https://www.magiclantern.fm/forum/index.php?topic=13152.0 <- MLVFS thread on Magic Lantern forums

## Install

1. Download the repository and extract to:

```text
C:\MLVScripts\MLVFS
```

2. Install Dokan:

```text
DokanSetup.exe
```

---

# Explorer Right-Click Mount

Run:

```text
RightClickMountFolder\UpdateMenu.reg
```

This adds **Mount folder with MLVFS** to Windows Explorer.

If MLVFS bundle is located in other directory than:

```text
C:\MLVScripts\MLVFS
```

edit:

```text
RightClickMountFolder\MLV_Controller.bat
```


# Command Line Mount

Run **CMD as Administrator**:

```bat
cd C:\MLVScripts\MLVFS\MLVFS_x64_lossless
mlvfs_x64_lossless.exe Z:\ --mlv-dir=C:\MLVDirectory --resolve-naming
```

Change:

* `Z:\` → mount drive letter
* `C:\MLVDirectory` → folder containing `.MLV` files

Unmount:

```bat
cd "C:\Program Files\Dokan\Dokan Library-1.0.3"
dokanctl.exe /u
```



---

# DaVinci Resolve Workflow Tips

# Audio sync issues

if DNG sequences do not auto-sync WAV audio (happens with 60fps footage using 5dmk3, not sure about the other modes/cameras) do the following:

In the **Media** workspace:

1. Select matching `.dng` + `.wav`
2. Right-click:

```text
Audio Sync > Auto Sync Audio
```

3. Select:

```text
Based on Timecode
```

Repeat for each clip pair.

Then drag the synced DNG clips from the Media Pool into the timeline.

Tip: Filter Media Pool by:

```text
dng
```

to select only DNG clips.

Using Resolve's **Audio Sync** method is preferred over manually linking audio in the timeline because it keeps proper clip/audio retiming behavior.

# Automatically desqueeze footage

Go to Project Settings -> Image Scaling and set Mismatched Resolution Files dropdown to Stretch Frame to all Corners. Just make sure your Timeline aspect ratio is set to the same one as your source footage.

# Flickering exposure

Make sure checkmark in RAW color section on Apply Pre Tone Curve is set to on, otherwise you sometimes get random exposure flickering, not sure if it's Davinci bug but it helps

https://i.ibb.co/39cVfsnp/Resolve-k-FG8-TK6f-OC-ezgif-com-optimize.gif

---

# Miscellaneous Tips

If you want to use an Android phone with a cheap HDMI capture card I find that best app for monitoring is called Nord USB Camera. It has focus peaking, anamorphic squeezing and other useful functions, find it on PlayStore.

# Notes

* This exact version 1.0.3.1000 of Dokan is required. Others didn't work with Windows 11 during my testing.
* Adjust MLVFS options/paths in MLV_Controller.bat file if necessary.

# MLVFS options

```text
- File/folder options:
    --mlv-dir=%s           Directory containing MLV files
    --resolve-naming       DNG file names compatible with DaVinci Resolve

- Processing options:
    --cs2x2                2x2 chroma smoothing
    --cs3x3                3x3 chroma smoothing
    --cs5x5                5x5 chroma smoothing
    --bad-pix              Fix bad pixels (autodetected)
    --really-bad-pix       Aggressive bad pixel fix
    --fix-pattern-noise    Fix row/column noise in shadows (slow)
    --stripes              Vertical stripe correction in highlights (nonuniform column gains)
    --deflicker=%d         Per-frame exposure compensation for flicker-free video
                           (your raw processor must interpret the BaselineExposure DNG tag)

- Dual ISO options:
    --dual-iso-preview     Preview Dual ISO files (fast)
    --dual-iso             Render Dual ISO files (high quality)
    --amaze-edge           Dual ISO: interpolation method (high quality)
    --mean23               Dual ISO: interpolation method (fast)
    --no-alias-map         Dual ISO: disable alias map
    --alias-map            Dual ISO: enable alias map

- Web GUI options:
    --port=%s              Port used for web GUI (default: 8000)
    --fps=%f               FPS used for playback in web GUI

- Diagnostic options:
    --version              Display MLVFS version
```

# Credits

Magic Lantern community & Dokan Project 


## Requirements

* Windows
* PowerShell
* FFmpeg — for `SocialMediaRotate`
* MLVFS + Dokan — for `RightClickMountFolder`

## Typical Workflow

```text
Camera Card
    ↓
MagicDump
    ↓
MLVFS
    ↓
Davinci Resolve
```
