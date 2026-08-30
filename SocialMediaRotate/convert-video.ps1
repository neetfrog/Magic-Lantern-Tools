param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

$ffmpeg = "C:\MLVScripts\SocialMediaRotate\ffmpeg.exe"

if (-not (Test-Path $ffmpeg)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "ffmpeg.exe was not found at:`n$ffmpeg",
        "FFmpeg Error"
    )
    exit 1
}

$directory = Split-Path $InputFile -Parent
$filename = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
$output = Join-Path $directory "${filename}_encoded.mp4"

& $ffmpeg `
    -i $InputFile `
    -vf "transpose=1,pad='max(iw,ih*9/16)':'max(ih,iw*16/9)':(ow-iw)/2:(oh-ih)/2:black" `
    -c:v libx264 `
    -crf 16 `
    -preset fast `
    -c:a copy `
    $output

if ($LASTEXITCODE -eq 0) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "Conversion complete:`n$output",
        "FFmpeg"
    )
} else {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "FFmpeg conversion failed.`nExit code: $LASTEXITCODE",
        "FFmpeg Error"
    )
}