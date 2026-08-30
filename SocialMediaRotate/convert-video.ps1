param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

$ffmpeg = "C:\MLVScripts\SocialMediaRotate\ffmpeg.exe"

# ------------------------------------------------------------
# Check FFmpeg
# ------------------------------------------------------------

if (-not (Test-Path $ffmpeg)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "ffmpeg.exe was not found at:`n$ffmpeg",
        "FFmpeg Error"
    )
    exit 1
}

# ------------------------------------------------------------
# Input / output
# ------------------------------------------------------------

if (-not (Test-Path $InputFile)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "Input file was not found:`n$InputFile",
        "FFmpeg Error"
    )
    exit 1
}

$directory = Split-Path $InputFile -Parent
$filename = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)

$output = Join-Path $directory "${filename}_encoded.mp4"

# ------------------------------------------------------------
# Video processing
#
# - Rotate 90 degrees clockwise
# - Pad to 9:16 without cropping
# - Keep 10-bit precision
# - Convert 4:4:4 source to 4:2:0 for phone compatibility
# ------------------------------------------------------------

$videoFilter = "transpose=1,pad='max(iw,ih*9/16)':'max(ih,iw*16/9)':(ow-iw)/2:(oh-ih)/2:black,format=yuv420p10le"

# ------------------------------------------------------------
# Encode
#
# HEVC Main10:
#   - 10-bit preserves smooth gradients much better than 8-bit
#   - 4:2:0 is much more phone-compatible than 4:4:4
#
# CRF 18:
#   Very high visual quality with reasonable file size.
#
# Preset slow:
#   Better compression efficiency than "fast" at the same quality.
#
# hvc1:
#   Improves compatibility with Apple/iOS devices.
#
# AAC:
#   Much more universally supported in MP4 than PCM.
# ------------------------------------------------------------

& $ffmpeg `
    -i $InputFile `
    -vf $videoFilter `
    -c:v libx265 `
    -preset slow `
    -crf 18 `
    -profile:v main10 `
    -pix_fmt yuv420p10le `
    -tag:v hvc1 `
    -c:a aac `
    -b:a 256k `
    -ar 48000 `
    -ac 2 `
    -movflags +faststart `
    $output

# ------------------------------------------------------------
# Check result
# ------------------------------------------------------------

if ($LASTEXITCODE -eq 0) {

    # Make sure the output file actually exists
    if (Test-Path $output) {
        exit 0
    }
    else {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "FFmpeg reported success, but the output file was not created:`n$output",
            "FFmpeg Error"
        )
        exit 1
    }

} else {

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "FFmpeg conversion failed.`nExit code: $LASTEXITCODE",
        "FFmpeg Error"
    )
    exit 1
}