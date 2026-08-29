# Magic Lantern MLVFS Windows Bundle

Windows bundle for **Magic Lantern MLVFS** to mount `.MLV` files as a virtual drive. Includes MLVFS, Dokan and Explorer right-click mount script.

![Windows Explorer right-click menu](https://i.ibb.co/gLBJ3HDb/image.png)

![Windows Explorer right-click menu](https://i.ibb.co/NnSRvRFP/image.png)


https://www.magiclantern.fm/forum/index.php?topic=13152.0 <- MLVFS thread on Magic Lantern forums

## Install

1. Download the repository and extract to:

```text
C:\MLVFS
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
C:\MLVFS
```

edit:

```text
RightClickMountFolder\MLV_Controller.bat
```


# Command Line Mount

Run **CMD as Administrator**:

```bat
cd C:\MLVFS\MLVFS_x64_lossless
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

# DaVinci Resolve Workflow 

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

---

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
