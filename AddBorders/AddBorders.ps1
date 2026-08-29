param (
    [string]$FolderFolderPath
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Prompt user for border percentage via GUI dialog
$inputVal = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Enter desired border percentage (e.g. 5 for 5%, 10 for 10%):", 
    "Add White Borders", 
    "5"
)

# Parse input; default to 0.05 if empty, canceled, or invalid
$parsedPercent = 0
if ([double]::TryParse($inputVal, [ref]$parsedPercent) -and $parsedPercent -gt 0) {
    $borderPercent = $parsedPercent / 100
} else {
    $borderPercent = 0.05
}

$outputFolder = Join-Path $FolderFolderPath "Bordered"

if (-not (Test-Path $outputFolder)) {
    New-Item -Path $outputFolder -ItemType Directory | Out-Null
}

# Maximum JPEG quality setup
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 85L)

$extensions = @(".jpg", ".jpeg", ".png", ".bmp", ".webp")
$files = Get-ChildItem -Path $FolderFolderPath -File | Where-Object { $extensions -contains $_.Extension.ToLower() }

foreach ($file in $files) {
    # Load image via stream to prevent file lock
    $stream = [System.IO.File]::OpenRead($file.FullName)
    $original = [System.Drawing.Image]::FromStream($stream)
    
    # Calculate uniform border thickness based on the shortest side
    $minDimension = [math]::Min($original.Width, $original.Height)
    $borderSize   = [math]::Round($minDimension * $borderPercent)
    
    $newWidth  = [int]($original.Width + ($borderSize * 2))
    $newHeight = [int]($original.Height + ($borderSize * 2))
    
    # Canvas setup maintaining native resolution
    $canvas = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
    $canvas.SetResolution($original.HorizontalResolution, $original.VerticalResolution)
    
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.Clear([System.Drawing.Color]::White)
    
    # High-quality rendering settings
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    
    # Draw image centered with exact equal padding on all 4 sides
    $graphics.DrawImage($original, [int]$borderSize, [int]$borderSize, [int]$original.Width, [int]$original.Height)
    
    $outputPath = Join-Path $outputFolder $file.Name

    # Save logic with WebP fallback handling
    if ($file.Extension -match "jpe?g") {
        $canvas.Save($outputPath, $jpegCodec, $encoderParams)
    } elseif ($file.Extension -eq ".webp") {
        $pngPath = [System.IO.Path]::ChangeExtension($outputPath, ".png")
        $canvas.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $canvas.Save($outputPath, $original.RawFormat)
    }
    
    # Memory and stream cleanup
    $graphics.Dispose()
    $canvas.Dispose()
    $original.Dispose()
    $stream.Dispose()
}