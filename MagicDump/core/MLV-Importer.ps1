#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# Magic Dump - Magic Lantern Import Tool
# Windows 11 / PowerShell 5.1+
# ============================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot "config.json"

# ============================================================
# LOAD CONFIG
# ============================================================

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host ""
    Write-Host "❌ ERROR: config.json not found:" -ForegroundColor Red
    Write-Host "    $ConfigPath" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}
catch {
    Write-Host ""
    Write-Host "❌ ERROR: Could not read config.json" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================================================
# SAFE CONFIG HELPER
# ============================================================

function Get-ConfigValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $Property = $Object.PSObject.Properties[$Name]

    if ($null -eq $Property) {
        return $Default
    }

    return $Property.Value
}

# ============================================================
# SETTINGS
# ============================================================

$Destinations = Get-ConfigValue $Config "Destinations" $null
$Organization = Get-ConfigValue $Config "Organization" $null
$Scanning = Get-ConfigValue $Config "Scanning" $null
$CopySettings = Get-ConfigValue $Config "Copy" $null
$Verification = Get-ConfigValue $Config "Verification" $null
$Stability = Get-ConfigValue $Config "Stability" $null
$FileTypes = Get-ConfigValue $Config "FileTypes" $null
$CardSettings = Get-ConfigValue $Config "Card" $null
$Safety = Get-ConfigValue $Config "Safety" $null
$Manifest = Get-ConfigValue $Config "Manifest" $null
$Logging = Get-ConfigValue $Config "Logging" $null
$Notifications = Get-ConfigValue $Config "Notifications" $null
$Monitoring = Get-ConfigValue $Config "Monitoring" $null
$MLVFS = Get-ConfigValue $Config "MLVFS" $null
$MLVApp = Get-ConfigValue $Config "MLVApp" $null

$PhotoDestination = [string](
    Get-ConfigValue $Destinations "Photos" "D:\Camera Import\Photos"
)

$MLVDestination = [string](
    Get-ConfigValue $Destinations "MLV" "D:\Camera Import\MLV"
)

$OrganizationMode = [string](
    Get-ConfigValue $Organization "Mode" "Flat"
)

$PhotoOrganizationMode = [string](
    Get-ConfigValue $Organization "PhotoMode" $OrganizationMode
)

$MLVOrganizationMode = [string](
    Get-ConfigValue $Organization "MLVMode" "Flat"
)

$DateFormat = [string](
    Get-ConfigValue $Organization "DateFormat" "yyyy-MM-dd"
)

$ScanSubfolders = [bool](
    Get-ConfigValue $Scanning "ScanSubfolders" $true
)

$MinimumCameraFiles = [int](
    Get-ConfigValue $Scanning "MinimumCameraFiles" 1
)

$SkipExisting = [bool](
    Get-ConfigValue $CopySettings "SkipExistingSameSize" $true
)

$ReplaceDifferent = [bool](
    Get-ConfigValue $CopySettings "ReplaceDifferentSize" $false
)

$UseTemporary = [bool](
    Get-ConfigValue $CopySettings "UseTemporaryFiles" $true
)

$TemporaryExtension = [string](
    Get-ConfigValue $CopySettings "TemporaryExtension" ".importing"
)

$Retries = [int](
    Get-ConfigValue $CopySettings "Retries" 3
)

$RetryDelay = [int](
    Get-ConfigValue $CopySettings "RetryDelaySeconds" 3
)

$VerificationEnabled = [bool](
    Get-ConfigValue $Verification "Enabled" $true
)

$VerificationMethod = [string](
    Get-ConfigValue $Verification "Method" "Size"
)

$StabilityEnabled = [bool](
    Get-ConfigValue $Stability "Enabled" $true
)

$StabilityChecks = [int](
    Get-ConfigValue $Stability "Checks" 2
)

$StabilityDelay = [int](
    Get-ConfigValue $Stability "DelaySeconds" 2
)

$MLVChunkEnabled = $true

if ($null -ne $FileTypes) {
    $MLVChunksObject = Get-ConfigValue $FileTypes "MLVChunks" $null

    if ($null -ne $MLVChunksObject) {
        $MLVChunkEnabled = [bool](
            Get-ConfigValue $MLVChunksObject "Enabled" $true
        )
    }
}

$OnlyRemovable = [bool](
    Get-ConfigValue $CardSettings "OnlyRemovableDrives" $true
)

$AutoEject = [bool](
    Get-ConfigValue $CardSettings "AutoEject" $false
)

$DeleteSource = [bool](
    Get-ConfigValue $CardSettings "DeleteSourceAfterImport" $false
)

$RequireDeleteConfirmation = [bool](
    Get-ConfigValue $CardSettings "RequireDeleteConfirmation" $true
)

$DryRun = [bool](
    Get-ConfigValue $Safety "DryRun" $false
)

$NeverDeleteUnlessVerified = [bool](
    Get-ConfigValue $Safety "NeverDeleteSourceUnlessVerified" $true
)

$ManifestEnabled = [bool](
    Get-ConfigValue $Manifest "Enabled" $true
)

$LoggingEnabled = [bool](
    Get-ConfigValue $Logging "Enabled" $true
)

$NotificationsEnabled = [bool](
    Get-ConfigValue $Notifications "Enabled" $true
)

$PollInterval = [int](
    Get-ConfigValue $Monitoring "PollIntervalSeconds" 2
)

$MountSettleSeconds = [int](
    Get-ConfigValue $Monitoring "MountSettleSeconds" 3
)

# ============================================================
# EXTENSIONS
# ============================================================

$DefaultPhotoExtensions = @(
    ".CR2",
    ".CR3",
    ".JPG",
    ".JPEG",
    ".JPE",
    ".PNG",
    ".TIF",
    ".TIFF"
)

$ConfiguredPhotoExtensions = Get-ConfigValue `
    $FileTypes `
    "Photos" `
    $DefaultPhotoExtensions

$PhotoExtensions = @(
    foreach ($Extension in @($ConfiguredPhotoExtensions)) {
        if ($null -ne $Extension) {
            $Text = $Extension.ToString().Trim()

            if ($Text.Length -gt 0) {
                if (-not $Text.StartsWith(".")) {
                    $Text = "." + $Text
                }

                $Text.ToUpperInvariant()
            }
        }
    }
)

# ============================================================
# DIRECTORIES
# ============================================================

if (-not (Test-Path -LiteralPath $PhotoDestination)) {
    New-Item -ItemType Directory -Path $PhotoDestination -Force |
        Out-Null
}

if (-not (Test-Path -LiteralPath $MLVDestination)) {
    New-Item -ItemType Directory -Path $MLVDestination -Force |
        Out-Null
}

$LogDirectoryName = [string](
    Get-ConfigValue $Logging "Directory" "logs"
)

$ManifestDirectoryName = [string](
    Get-ConfigValue $Manifest "Directory" "manifests"
)

$LogDirectory = Join-Path $ScriptRoot $LogDirectoryName
$ManifestDirectory = Join-Path $ScriptRoot $ManifestDirectoryName

if ($LoggingEnabled) {
    New-Item -ItemType Directory -Path $LogDirectory -Force |
        Out-Null
}

if ($ManifestEnabled) {
    New-Item -ItemType Directory -Path $ManifestDirectory -Force |
        Out-Null
}

$LogFileName = [string](
    Get-ConfigValue $Logging "FileName" "importer.log"
)

$LogFile = Join-Path $LogDirectory $LogFileName

# ============================================================
# FORMATTING & VISUAL ENGINE
# ============================================================

function Format-Bytes {
    param(
        [double]$Bytes
    )

    if ($Bytes -lt 1KB) {
        return "{0:N0} B" -f $Bytes
    }

    if ($Bytes -lt 1MB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }

    if ($Bytes -lt 1GB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -lt 1TB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    return "{0:N2} TB" -f ($Bytes / 1TB)
}

function Write-Divider {
    param([string]$Title = "")
    if ($Title) {
        $Padding = [math]::Max(0, 52 - $Title.Length)
        $LeftPad = [math]::Floor($Padding / 2)
        $RightPad = $Padding - $LeftPad
        $Line = ("=" * $LeftPad) + " [ " + $Title + " ] " + ("=" * $RightPad)
        Write-Host $Line -ForegroundColor Cyan
    } else {
        Write-Host "============================================================" -ForegroundColor Cyan
    }
}

# ============================================================
# LOGGING
# ============================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LevelColor = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        default { "Gray" }
    }

    $Line = "{0} [{1}] {2}" -f $Timestamp, $Level, $Message
    Write-Host "$Timestamp " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $LevelColor
    Write-Host $Message

    if ($LoggingEnabled) {
        try {
            Add-Content `
                -LiteralPath $LogFile `
                -Value $Line `
                -Encoding UTF8
        }
        catch {
            # Logging must never stop a copy.
        }
    }
}

# ============================================================
# NOTIFICATION
# ============================================================

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message
    )

    if (-not $NotificationsEnabled) {
        return
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $Notify = New-Object System.Windows.Forms.NotifyIcon

        try {
            $Notify.Icon = [System.Drawing.SystemIcons]::Information
            $Notify.Visible = $true

            $Notify.ShowBalloonTip(
                3000,
                $Title,
                $Message,
                [System.Windows.Forms.ToolTipIcon]::Info
            )

            Start-Sleep -Milliseconds 3200
        }
        finally {
            $Notify.Dispose()
        }
    }
    catch {
        # Notification failure is harmless.
    }
}

# ============================================================
# DRIVE DETECTION
# ============================================================

function Get-EligibleDrives {
    $IgnoredDriveLetter = [string](Get-ConfigValue (Get-ConfigValue $Config "MLVFS" $null) "DriveLetter" "Z:\")
    if ($IgnoredDriveLetter.Length -ge 1) {
        $IgnoredDriveLetter = $IgnoredDriveLetter.Substring(0, 1).ToUpperInvariant()
    }

    try {
        $Drives = @(
            Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_.DeviceID) -and
                    $_.DeviceID.Substring(0, 1).ToUpperInvariant() -ne $IgnoredDriveLetter
                }
        )
    }
    catch {
        return @()
    }

    if ($OnlyRemovable) {
        $Eligible = @(
            $Drives |
                Where-Object {
                    $_.DriveType -eq 2
                }
        )
    }
    else {
        $Eligible = @(
            $Drives |
                Where-Object {
                    $_.DriveType -in @(2, 3)
                }
        )
    }

    $CameraDrives = @(
        foreach ($Drive in $Eligible) {
            $Root = $Drive.DeviceID + "\"
            
            if (-not (Test-Path -LiteralPath $Root)) {
                continue
            }

            $DcimPath = Join-Path $Root "DCIM"
            
            if (Test-Path -LiteralPath $DcimPath -PathType Container) {
                $Drive
            }
        }
    )

    return $CameraDrives
}

# ============================================================
# FILE TYPE
# ============================================================

function Get-FileType {
    param(
        [System.IO.FileInfo]$File
    )

    $Extension = $File.Extension.ToUpperInvariant()

    if ($PhotoExtensions -contains $Extension) {
        return "Photo"
    }

    if ($Extension -eq ".MLV") {
        return "MLV"
    }

    if (
        $MLVChunkEnabled -and
        $Extension -match '^\.M[0-9]+$'
    ) {
        return "MLVChunk"
    }

    return $null
}

# ============================================================
# CAMERA FILE SCAN
# ============================================================

function Get-CameraFiles {
    param(
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    if ($ScanSubfolders) {
        $Files = @(
            Get-ChildItem `
                -LiteralPath $Root `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue
        )
    }
    else {
        $Files = @(
            Get-ChildItem `
                -LiteralPath $Root `
                -File `
                -ErrorAction SilentlyContinue
        )
    }

    $Result = @(
        foreach ($File in $Files) {
            $Type = Get-FileType $File

            if ($null -ne $Type) {
                [PSCustomObject]@{
                    File = $File
                    Type = $Type
                }
            }
        }
    )

    return $Result
}

# ============================================================
# FILE STABILITY
# ============================================================

function Test-FileStable {
    param(
        [System.IO.FileInfo]$File
    )

    if (-not $StabilityEnabled) {
        return $true
    }

    if ($StabilityChecks -le 0) {
        return $true
    }

    $PreviousSize = -1

    for ($i = 0; $i -lt $StabilityChecks; $i++) {

        if (-not (Test-Path -LiteralPath $File.FullName)) {
            return $false
        }

        try {
            $Current = Get-Item `
                -LiteralPath $File.FullName `
                -ErrorAction Stop

            $CurrentSize = [int64]$Current.Length

            if ($PreviousSize -ge 0) {
                if ($CurrentSize -ne $PreviousSize) {
                    $PreviousSize = $CurrentSize

                    if ($StabilityDelay -gt 0) {
                        Start-Sleep -Seconds $StabilityDelay
                    }

                    continue
                }
            }

            $PreviousSize = $CurrentSize

            if ($StabilityDelay -gt 0) {
                Start-Sleep -Seconds $StabilityDelay
            }
        }
        catch {
            return $false
        }
    }

    return $true
}

# ============================================================
# DESTINATION PATH
# ============================================================

function Get-DestinationPath {
    param(
        [System.IO.FileInfo]$File,
        [string]$Type
    )

    if ($Type -eq "Photo") {
        $Root = $PhotoDestination
        $CurrentMode = $PhotoOrganizationMode
    }
    else {
        $Root = $MLVDestination
        $CurrentMode = $MLVOrganizationMode
    }

    if ($CurrentMode -eq "ByDate") {

        $DateFolder = $File.LastWriteTime.ToString($DateFormat)

        $Folder = Join-Path $Root $DateFolder

        if (-not (Test-Path -LiteralPath $Folder)) {
            New-Item `
                -ItemType Directory `
                -Path $Folder `
                -Force |
                Out-Null
        }

        return Join-Path $Folder $File.Name
    }

    return Join-Path $Root $File.Name
}

# ============================================================
# HASH
# ============================================================

function Get-FileHashSafe {
    param(
        [string]$Path
    )

    return (
        Get-FileHash `
            -LiteralPath $Path `
            -Algorithm SHA256 `
            -ErrorAction Stop
    ).Hash
}

# ============================================================
# VERIFY COPY
# ============================================================

function Test-Copy {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        return $false
    }

    try {
        $SourceInfo = Get-Item `
            -LiteralPath $Source `
            -ErrorAction Stop

        $DestinationInfo = Get-Item `
            -LiteralPath $Destination `
            -ErrorAction Stop
    }
    catch {
        return $false
    }

    if ($SourceInfo.Length -ne $DestinationInfo.Length) {
        return $false
    }

    if (-not $VerificationEnabled) {
        return $true
    }

    switch ($VerificationMethod.ToUpperInvariant()) {

        "NONE" {
            return $true
        }

        "SIZE" {
            return (
                $SourceInfo.Length -eq
                $DestinationInfo.Length
            )
        }

        "SHA256" {
            try {
                $SourceHash = Get-FileHashSafe $Source
                $DestinationHash = Get-FileHashSafe $Destination

                return (
                    $SourceHash -eq $DestinationHash
                )
            }
            catch {
                return $false
            }
        }

        default {
            return (
                $SourceInfo.Length -eq
                $DestinationInfo.Length
            )
        }
    }
}

# ============================================================
# COPY FILE (WITH PROGRESS BAR)
# ============================================================

function Copy-SafeFile {
    param(
        [System.IO.FileInfo]$SourceFile,
        [string]$Destination,
        [int]$FileNumber,
        [int]$FileCount
    )

    if (Test-Path -LiteralPath $Destination) {

        try {
            $Existing = Get-Item `
                -LiteralPath $Destination `
                -ErrorAction Stop
        }
        catch {
            $Existing = $null
        }

        if (
            $null -ne $Existing -and
            $SkipExisting -and
            $Existing.Length -eq $SourceFile.Length
        ) {

            Write-Host "  ℹ️ " -NoNewline -ForegroundColor Cyan
            Write-Host "Skipped (Already Exists): " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($SourceFile.Name)"

            if (-not (Test-Copy `
                $SourceFile.FullName `
                $Destination)) {

                Write-Log `
                    "Existing destination failed verification: $Destination" `
                    "ERROR"

                return $false
            }

            Write-Host "      └─ ✔️ Verified integrity." -ForegroundColor Green
            return $true
        }

        if (-not $ReplaceDifferent) {
            Write-Log `
                "Destination exists and replacement disabled: $Destination" `
                "ERROR"
            return $false
        }

        Write-Host "  ⚠️ " -NoNewline -ForegroundColor Yellow
        Write-Host "Overwriting conflicting file: $Destination" -ForegroundColor DarkGray

        Remove-Item `
            -LiteralPath $Destination `
            -Force `
            -ErrorAction Stop
    }

    for ($Attempt = 1; $Attempt -le $Retries; $Attempt++) {

        $TempPath = $Destination

        if ($UseTemporary) {
            $TempPath = $Destination + $TemporaryExtension
            if (Test-Path -LiteralPath $TempPath) {
                Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
            }
        }

        try {
            Write-Host ""
            Write-Host "  📁 [$FileNumber/$FileCount] " -NoNewline -ForegroundColor Cyan
            Write-Host "$($SourceFile.Name) " -NoNewline -ForegroundColor White
            Write-Host "($(Format-Bytes $SourceFile.Length))" -ForegroundColor DarkGray

            if ($Attempt -gt 1) {
                Write-Host "      └─ 🔄 Retry Attempt: $Attempt/$Retries" -ForegroundColor Yellow
            }

            if ($DryRun) {
                Write-Host "      └─ 🧪 [DRY RUN] Copy skipped." -ForegroundColor Yellow
                return $true
            }

            $DestinationDirectory = Split-Path -Path $TempPath -Parent
            if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
                New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
            }

            $SourceStream = New-Object System.IO.FileStream($SourceFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            $DestStream = New-Object System.IO.FileStream($TempPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            
            $BufferSize = 1MB
            $Buffer = New-Object byte[] $BufferSize
            $TotalLength = $SourceFile.Length
            $CopiedBytes = 0
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                while (($ReadCount = $SourceStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
                    $DestStream.Write($Buffer, 0, $ReadCount)
                    $CopiedBytes += $ReadCount

                    $Elapsed = $Stopwatch.Elapsed.TotalSeconds
                    if ($Elapsed -gt 0) {
                        $Speed = $CopiedBytes / $Elapsed
                        $Percent = [math]::Min(100, [math]::Round(($CopiedBytes / $TotalLength) * 100))
                        $RemainingBytes = $TotalLength - $CopiedBytes
                        $ETA = if ($Speed -gt 0) { [TimeSpan]::FromSeconds($RemainingBytes / $Speed) } else { [TimeSpan]::Zero }

                        $SpeedText = if ($Speed -lt 1MB) { "{0:N2} KB/s" -f ($Speed / 1KB) } else { "{0:N2} MB/s" -f ($Speed / 1MB) }
                        $ETAText = "{0:D2}:{1:D2}" -f $ETA.Minutes, $ETA.Seconds
                        if ($ETA.Hours -gt 0) { $ETAText = "$($ETA.Hours):$ETAText" }

                        $BarWidth = 20
                        $Filled = [math]::Round(($CopiedBytes / $TotalLength) * $BarWidth)
                        $Empty = $BarWidth - $Filled
                        $Bar = ("█" * $Filled) + ("░" * $Empty)

                        Write-Host -NoNewline "`r      [$Bar] $Percent% | ⚡ $SpeedText | ⏱️ ETA: $ETAText   "
                    }
                }
            }
            finally {
                $SourceStream.Dispose()
                $DestStream.Dispose()
                $Stopwatch.Stop()
                Write-Host ""
            }

            if (-not (Test-Copy $SourceFile.FullName $TempPath)) {
                throw "Temporary file verification failed."
            }

            if ($UseTemporary) {
                Move-Item -LiteralPath $TempPath -Destination $Destination -Force -ErrorAction Stop
            }

            if (-not (Test-Copy $SourceFile.FullName $Destination)) {
                throw "Final destination verification failed."
            }

            Write-Host "      └─ " -NoNewline -ForegroundColor DarkGray
            Write-Host "✔ SUCCESS & VERIFIED" -ForegroundColor Green

            $SuccessLogMsg = "Successfully copied: $($SourceFile.FullName)"
            if ($LoggingEnabled) {
                $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Add-Content -LiteralPath $LogFile -Value "$Timestamp [INFO] $SuccessLogMsg" -Encoding UTF8
            }

            return $true
        }
        catch {
            Write-Log "Attempt $Attempt failed for $($SourceFile.Name): $($_.Exception.Message)" "ERROR"
            Write-Host "      └─ ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red

            if (Test-Path -LiteralPath $TempPath) {
                Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
            }

            if ($Attempt -lt $Retries -and $RetryDelay -gt 0) {
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    return $false
}

# ============================================================
# MLV GROUPING
# ============================================================

function Get-MLVGroups {
    param(
        [array]$MLVFiles
    )

    $Groups = @{}

    foreach ($Item in @($MLVFiles)) {

        $File = $Item.File
        $Extension = $File.Extension.ToUpperInvariant()

        if ($Extension -eq ".MLV") {

            $Key = Join-Path `
                $File.DirectoryName `
                $File.BaseName

            if (-not $Groups.ContainsKey($Key)) {
                $Groups[$Key] = @()
            }

            $Groups[$Key] += $Item
        }
    }

    foreach ($Item in @($MLVFiles)) {

        $File = $Item.File
        $Extension = $File.Extension.ToUpperInvariant()

        if ($Extension -match '^\.M[0-9]+$') {

            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
                $File.Name
            )

            $Key = Join-Path `
                $File.DirectoryName `
                $BaseName

            if (-not $Groups.ContainsKey($Key)) {
                $Groups[$Key] = @()
            }

            $Groups[$Key] += $Item
        }
    }

    foreach ($Key in @($Groups.Keys)) {

        $Groups[$Key] = @(
            $Groups[$Key] |
                Sort-Object {
                    $Extension = $_.File.Extension.ToUpperInvariant()

                    if ($Extension -eq ".MLV") {
                        return -1
                    }

                    try {
                        return [int]($Extension -replace '^\.M', '')
                    }
                    catch {
                        return 999999
                    }
                }
        )
    }

    return $Groups
}

# ============================================================
# MANIFEST WRITER
# ============================================================

function Write-ImportManifest {
    param(
        [string]$DriveRoot,
        [array]$WorkItems,
        [bool]$Success
    )

    if (-not $ManifestEnabled) {
        return
    }

    try {
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $DriveName = $DriveRoot -replace '[:\\]', ''
        $ManifestFileName = "manifest_{0}_{1}.json" -f $DriveName, $Timestamp
        $ManifestFilePath = Join-Path $ManifestDirectory $ManifestFileName

        $ManifestData = [PSCustomObject]@{
            Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            DriveRoot  = $DriveRoot
            Success    = $Success
            WorkItems  = @(
                foreach ($Work in $WorkItems) {
                    [PSCustomObject]@{
                        Type  = $Work.Type
                        Files = @(
                            foreach ($Item in $Work.Group) {
                                [PSCustomObject]@{
                                    Source      = $Item.File.FullName
                                    Destination = (Get-DestinationPath $Item.File $(if ($Item.Type -eq "Photo") { "Photo" } else { "MLV" }))
                                    Size        = $Item.File.Length
                                    FileType    = $Item.Type
                                }
                            }
                        )
                    }
                }
            )
        }

        $ManifestData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestFilePath -Encoding UTF8
        Write-Log "Manifest saved: $ManifestFilePath"
    }
    catch {
        Write-Log "Failed to write manifest: $($_.Exception.Message)" "ERROR"
    }
}

# ============================================================
# SAFE SOURCE DELETE
# ============================================================

function Remove-ImportedSource {
    param(
        [array]$Items
    )

    if (-not $DeleteSource) {
        return $true
    }

    if ($DryRun) {
        Write-Host "  🧪 [DRY RUN] Source deletion skipped." -ForegroundColor Yellow
        return $true
    }

    foreach ($Item in @($Items)) {
        $SourcePath = $Item.File.FullName
        if (-not (Test-Path -LiteralPath $SourcePath)) {
            Write-Log "Source disappeared before deletion: $SourcePath" "ERROR"
            return $false
        }
    }

    foreach ($Item in @($Items)) {
        $Path = $Item.File.FullName
        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }

        try {
            $Destination = Get-DestinationPath $Item.File $(if ($Item.Type -eq "Photo") { "Photo" } else { "MLV" })

            if ($NeverDeleteUnlessVerified) {
                if (-not (Test-Copy $Path $Destination)) {
                    Write-Log "REFUSING TO DELETE - verification failed: $Path" "ERROR"
                    return $false
                }
            }

            Write-Host "  🗑️ [Deleting Source] " -NoNewline -ForegroundColor Yellow
            Write-Host "$Path" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Could not delete source: $Path - $($_.Exception.Message)" "ERROR"
            return $false
        }
    }

    return $true
}

# ============================================================
# IMPORT CARD
# ============================================================

function Import-Card {
    param(
        [string]$DriveRoot
    )

    Write-Log "Starting copy process for volume: $DriveRoot"

    Write-Host ""
    Write-Divider "📷 CARD DETECTED: $DriveRoot"

    $ScanRoot = $DriveRoot
    $Files = @(Get-CameraFiles $ScanRoot)

    if (@($Files).Count -eq 0) {
        Write-Log "No camera media detected."
        return $false
    }

    $Photos = @($Files | Where-Object { $_.Type -eq "Photo" })
    $MLVFiles = @($Files | Where-Object { $_.Type -in @("MLV", "MLVChunk") })
    $MLVGroups = Get-MLVGroups $MLVFiles

    $WorkItems = New-Object System.Collections.ArrayList

    foreach ($Item in @($Photos)) {
        [void]$WorkItems.Add(
            [PSCustomObject]@{
                File = $Item.File
                Type = "Photo"
                Group = @($Item)
            }
        )
    }

    foreach ($Key in @($MLVGroups.Keys)) {
        $Group = @($MLVGroups[$Key])
        if (@($Group).Count -gt 0) {
            [void]$WorkItems.Add(
                [PSCustomObject]@{
                    File = $Group[0].File
                    Type = "MLVGroup"
                    Group = $Group
                }
            )
        }
    }

    [double]$TotalBytes = 0
    [double]$PhotoBytes = 0
    [double]$MLVBytes = 0
    [int]$PhotoFilesCount = 0
    [int]$MLVFilesCount = 0

    foreach ($Work in @($WorkItems)) {
        foreach ($Item in @($Work.Group)) {
            [double]$Length = [double]$Item.File.Length
            $TotalBytes += $Length
            if ($Item.Type -eq "Photo") {
                $PhotoBytes += $Length
                $PhotoFilesCount++
            }
            else {
                $MLVBytes += $Length
                $MLVFilesCount++
            }
        }
    }

    [int]$TotalFiles = 0
    foreach ($Work in @($WorkItems)) {
        $TotalFiles += @($Work.Group).Count
    }

    # ============================================================
    # DISK SPACE PRE-CHECK
    # ============================================================
    $TargetDriveRoot = [System.IO.Path]::GetPathRoot([string]$MLVDestination)
    [double]$FreeSpace = 0
    try {
        $DriveInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($TargetDriveRoot.TrimEnd('\'))'" -ErrorAction Stop
        $FreeSpace = [double]$DriveInfo.FreeSpace

        [double]$RequiredSpace = $TotalBytes + 1GB

        if ($FreeSpace -lt $RequiredSpace) {
            Write-Log "ABORT: Insufficient disk space on $TargetDriveRoot. Required: $(Format-Bytes $RequiredSpace), Available: $(Format-Bytes $FreeSpace)" "ERROR"
            
            Write-Host ""
            Write-Divider "❌ ERROR: INSUFFICIENT DISK SPACE"
            Write-Host " 💾 Destination Volume: $TargetDriveRoot" -ForegroundColor Yellow
            Write-Host " 📦 Required Space:     $(Format-Bytes $RequiredSpace)" -ForegroundColor Yellow
            Write-Host " 📉 Available Space:    $(Format-Bytes $FreeSpace)" -ForegroundColor Red
            Write-Divider

            Show-Notification "MagicDump" "Import aborted: Insufficient space on $TargetDriveRoot"
            return $false
        }
    }
    catch {
        Write-Log "Could not verify disk space for $TargetDriveRoot : $($_.Exception.Message)" "ERROR"
    }

    Write-Host "  📊 [Stats] " -NoNewline -ForegroundColor Cyan
    Write-Host "Total Size: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$(Format-Bytes $TotalBytes) " -NoNewline -ForegroundColor White
    Write-Host "($TotalFiles files)" -ForegroundColor DarkGray

    Write-Host "          ├─ 🖼️ Photos : $PhotoFilesCount file(s) ($(Format-Bytes $PhotoBytes))" -ForegroundColor Cyan
    Write-Host "          └─ 🎬 MLVs   : $MLVFilesCount file(s) ($(Format-Bytes $MLVBytes))" -ForegroundColor Cyan

    if ($FreeSpace -gt 0) {
        Write-Host "  💾 [Disk]  " -NoNewline -ForegroundColor Cyan
        Write-Host "Free Space: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$(Format-Bytes $FreeSpace) " -NoNewline -ForegroundColor Green
        Write-Host "available on $TargetDriveRoot" -ForegroundColor DarkGray
    }

    if ($DeleteSource) {
        Write-Host ""
        Write-Host "  ⚠️ [WARNING]: SOURCE FILES WILL BE DELETED AFTER COPY [!]" -ForegroundColor Red
    }

    Write-Host ""

    [int]$SuccessfulFiles = 0
    [int]$FailedFiles = 0
    [int]$FileNumber = 0

    foreach ($Work in @($WorkItems)) {

        $GroupSuccess = $true
        $SuccessfullyCopiedInGroup = New-Object System.Collections.ArrayList

        foreach ($Item in @($Work.Group)) {

            $FileNumber++

            if (-not (Test-FileStable $Item.File)) {
                Write-Log "File is not stable: $($Item.File.FullName)" "ERROR"
                $GroupSuccess = $false
                $FailedFiles++
                continue
            }

            $Destination = Get-DestinationPath $Item.File $(if ($Item.Type -eq "Photo") { "Photo" } else { "MLV" })

            $Success = Copy-SafeFile `
                -SourceFile $Item.File `
                -Destination $Destination `
                -FileNumber $FileNumber `
                -FileCount $TotalFiles

            if ($Success) {
                $SuccessfulFiles++
                [void]$SuccessfullyCopiedInGroup.Add($Destination)
            }
            else {
                $FailedFiles++
                $GroupSuccess = $false
            }
        }

        if (-not $GroupSuccess) {
            foreach ($CopiedDest in $SuccessfullyCopiedInGroup) {
                if (Test-Path -LiteralPath $CopiedDest) {
                    Write-Host "  🧹 [Cleanup] Removing partial file: $CopiedDest" -ForegroundColor Yellow
                    Remove-Item -LiteralPath $CopiedDest -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($GroupSuccess -and $DeleteSource) {
            Write-Host ""
            Write-Host "  🧹 [Cleanup] Copy verified. Deleting source files..." -ForegroundColor Yellow
            if (-not (Remove-ImportedSource $Work.Group)) {
                Write-Log "Source deletion failed." "ERROR"
            }
            else {
                Write-Host "  🗑️ [Cleanup] Source files deleted." -ForegroundColor Green
            }
        }
        elseif ((-not $GroupSuccess) -and ($Work.Type -eq "MLVGroup")) {
            Write-Host ""
            Write-Host "  🛡️ [Protection] MLV group kept on card due to copy errors." -ForegroundColor Red
        }
    }

    $OverallSuccess = ($FailedFiles -eq 0)
    Write-ImportManifest -DriveRoot $DriveRoot -WorkItems $WorkItems -Success $OverallSuccess

$MLVFSEnabled = [bool](Get-ConfigValue $MLVFS "Enabled" $false)
    if ($MLVFSEnabled -and $OverallSuccess -and $MLVFiles.Count -gt 0) {
        $ControllerPath = [string](Get-ConfigValue $MLVFS "ControllerPath" "")
        if (Test-Path -LiteralPath $ControllerPath) {
            # Collect unique parent directories for all imported MLVs in this batch
            $ImportedMLVFolders = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Work in @($WorkItems)) {
                if ($Work.Type -eq "MLVGroup") {
                    foreach ($Item in $Work.Group) {
                        if ($Item.File.Extension.ToUpperInvariant() -eq ".MLV") {
                            $ResolvedDest = Get-DestinationPath $Item.File "MLV"
                            $ParentDir = Split-Path -Path $ResolvedDest -Parent
                            [void]$ImportedMLVFolders.Add($ParentDir)
                        }
                    }
                }
            }

            # If everything is from one day, mount that specific folder.
            # If it spans multiple days, fall back to the root $MLVDestination.
            if ($ImportedMLVFolders.Count -eq 1) {
                $TargetMountPath = @($ImportedMLVFolders)[0]
            }
            else {
                $TargetMountPath = $MLVDestination
            }

            Write-Host ""
            Write-Host "  💽 [MLVFS] " -NoNewline -ForegroundColor Magenta
            Write-Host "Mounting virtual drive..." -ForegroundColor Yellow
            Write-Log "Running controller: $ControllerPath mount $TargetMountPath"

            try {
                & "$ControllerPath" "mount" "$TargetMountPath"
                Write-Host "  💽 [MLVFS] Mounted successfully to Z:\ ($TargetMountPath)" -ForegroundColor Green
            }
            catch {
                Write-Log "Failed to mount MLV destination: $($_.Exception.Message)" "ERROR"
                Write-Host "  💽 [MLVFS] WARNING: Virtual mount failed." -ForegroundColor Red
            }
        }
    }

    $MLVAppEnabled = [bool](Get-ConfigValue $MLVApp "Enabled" $false)
    if ($MLVAppEnabled -and $OverallSuccess -and $MLVFiles.Count -gt 0) {
        $MLVAppPath = [string](Get-ConfigValue $MLVApp "ExecutablePath" "C:\MLVScripts\MLVApp\MLVApp.exe")
        if (Test-Path -LiteralPath $MLVAppPath) {
            Write-Host ""
            Write-Host "  🎬 [MLVApp] " -NoNewline -ForegroundColor Magenta
            Write-Host "Creating session file for MLVApp..." -ForegroundColor Yellow
            Write-Log "Generating session file for MLVApp"

            try {
                $SessionItems = @()
                foreach ($Work in @($WorkItems)) {
                    if ($Work.Type -eq "MLVGroup") {
                        foreach ($Item in $Work.Group) {
                            if ($Item.File.Extension.ToUpperInvariant() -eq ".MLV") {
                                $DestinationPath = Get-DestinationPath $Item.File "MLV"
                                if (Test-Path -LiteralPath $DestinationPath) {
                                    $NormalizedPath = $DestinationPath -replace '\\', '/'
                                    $SessionItems += $NormalizedPath
                                }
                            }
                        }
                    }
                }

                if ($SessionItems.Count -gt 0) {
                    $SessionFilePath = Join-Path $Env:TEMP "MagicDump_Session_$([DateTime]::Now.ToString('yyyyMMdd_HHmmss')).masxml"
                    
                    $XmlBuilder = New-Object System.Text.StringBuilder
                    [void]$XmlBuilder.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
                    [void]$XmlBuilder.AppendLine('<mlv_files version="4" mlvapp="1.16">')
                    
                    foreach ($Path in $SessionItems) {
                        [void]$XmlBuilder.AppendLine("    <clip file=`"$Path`" relative=`"$Path`" mark=`"0`">")
                        [void]$XmlBuilder.AppendLine("        <exposure>0</exposure>")
                        [void]$XmlBuilder.AppendLine("        <contrast>0</contrast>")
                        [void]$XmlBuilder.AppendLine("        <pivot>75</pivot>")
                        [void]$XmlBuilder.AppendLine("        <temperature>-1</temperature>")
                        [void]$XmlBuilder.AppendLine("        <tint>0</tint>")
                        [void]$XmlBuilder.AppendLine("        <clarity>0</clarity>")
                        [void]$XmlBuilder.AppendLine("        <vibrance>0</vibrance>")
                        [void]$XmlBuilder.AppendLine("        <saturation>0</saturation>")
                        [void]$XmlBuilder.AppendLine("        <ds>20</ds>")
                        [void]$XmlBuilder.AppendLine("        <dr>70</dr>")
                        [void]$XmlBuilder.AppendLine("        <ls>0</ls>")
                        [void]$XmlBuilder.AppendLine("        <lr>50</lr>")
                        [void]$XmlBuilder.AppendLine("        <lightening>0</lightening>")
                        [void]$XmlBuilder.AppendLine("        <gradationCurve>1e-5;1e-5;1;1;?1e-5;1e-5;1;1;?1e-5;1e-5;1;1;?1e-5;1e-5;1;1;</gradationCurve>")
                        [void]$XmlBuilder.AppendLine("        <hueVsHue>0;0;1;0;</hueVsHue>")
                        [void]$XmlBuilder.AppendLine("        <hueVsSaturation>0;0;1;0;</hueVsSaturation>")
                        [void]$XmlBuilder.AppendLine("        <hueVsLuminance>0;0;1;0;</hueVsLuminance>")
                        [void]$XmlBuilder.AppendLine("        <lumaVsSaturation>0;0;1;0;</lumaVsSaturation>")
                        [void]$XmlBuilder.AppendLine("        <shadows>0</shadows>")
                        [void]$XmlBuilder.AppendLine("        <highlights>0</highlights>")
                        [void]$XmlBuilder.AppendLine("        <sharpen>0</sharpen>")
                        [void]$XmlBuilder.AppendLine("        <gamma>315</gamma>")
                        [void]$XmlBuilder.AppendLine("        <allowCreativeAdjustments>1</allowCreativeAdjustments>")
                        [void]$XmlBuilder.AppendLine("        <agx>1</agx>")
                        [void]$XmlBuilder.AppendLine("        <rawFixesEnabled>1</rawFixesEnabled>")
                        [void]$XmlBuilder.AppendLine("        <cutIn>1</cutIn>")
                        [void]$XmlBuilder.AppendLine("        <cutOut>2147483647</cutOut>")
                        [void]$XmlBuilder.AppendLine("        <debayer>5</debayer>")
                        [void]$XmlBuilder.AppendLine("    </clip>")
                    }
                    
                    [void]$XmlBuilder.AppendLine('</mlv_files>')
                    Set-Content -LiteralPath $SessionFilePath -Value $XmlBuilder.ToString() -Encoding UTF8
                    
                    Start-Process -FilePath $MLVAppPath -ArgumentList "`"$SessionFilePath`""
                    Write-Host "  🎬 [MLVApp] Opened successfully." -ForegroundColor Green
                }
            }
            catch {
                Write-Log "Failed to launch MLVApp: $($_.Exception.Message)" "ERROR"
                Write-Host "  🎬 [MLVApp] WARNING: Failed to launch application." -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    if ($OverallSuccess) {
        Write-Divider "🎉 IMPORT COMPLETE: SUCCESS"
        Write-Host "  ✔️ Successful Files : $SuccessfulFiles" -ForegroundColor Green
        Write-Host "  ❌ Failed Files     : $FailedFiles" -ForegroundColor DarkGray
        Write-Host "  📦 Total Copied     : $(Format-Bytes $TotalBytes)" -ForegroundColor White
    }
    else {
        Write-Divider "⚠️ IMPORT COMPLETE WITH WARNINGS"
        Write-Host "  ✔️ Successful Files : $SuccessfulFiles" -ForegroundColor Green
        Write-Host "  ❌ Failed Files     : $FailedFiles" -ForegroundColor Red
    }
    Write-Divider

    Write-Log "Import session finished. Success: $SuccessfulFiles | Failed: $FailedFiles"
    return $OverallSuccess
}

# ============================================================
# DELETE CONFIRMATION
# ============================================================

function Confirm-DeleteMode {
    if (-not $DeleteSource) { return $true }
    if (-not $RequireDeleteConfirmation) { return $true }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $Message = @"
WARNING:
DELETE SOURCE FILES AFTER IMPORT IS ENABLED.

Files will be permanently deleted from the camera card AFTER verification passes.

Do you want to continue?
"@

        $Result = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            "MagicDump - Delete Source Enabled",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        return ($Result -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    catch {
        Write-Host "Could not display confirmation dialog." -ForegroundColor Red
        return $false
    }
}

# ============================================================
# EJECT
# ============================================================

function Eject-Drive {
    param(
        [string]$DriveRoot
    )

    if (-not $AutoEject) { return }

    try {
        Write-Log "Safely removing drive: $DriveRoot"

        $Volume = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -eq $DriveRoot.TrimEnd('\') }
        if ($null -ne $Volume) {
            Invoke-CimMethod -InputObject $Volume -MethodName Dismount -Arguments @{ Force = $true; Permanent = $false } | Out-Null
        }

        $Shell = New-Object -ComObject Shell.Application
        $DriveLetterOnly = $DriveRoot.Substring(0, 2)
        $Drive = $Shell.Namespace(17).ParseName($DriveLetterOnly)

        if ($null -ne $Drive) {
            $Drive.InvokeVerb("Eject")
        }

        Write-Log "Drive dismounted."
    }
    catch {
        Write-Log "Could not unmount volume: $($_.Exception.Message)" "ERROR"
    }
}

# ============================================================
# STARTUP SCREEN & INITIALIZATION
# ============================================================

Clear-Host

Write-Host ""
Write-Host "  📸 MagicDump | github.com/neetfrog/Magic-Lantern-Tools" -ForegroundColor Cyan
Write-Host ""

Write-Divider "⚙️ SETTINGS"
Write-Host "  🖼️ Photos Destination   : " -NoNewline -ForegroundColor DarkGray
Write-Host "$PhotoDestination" -ForegroundColor White

Write-Host "  🎬 MLV Destination      : " -NoNewline -ForegroundColor DarkGray
Write-Host "$MLVDestination" -ForegroundColor White

Write-Host "  📁 Organization         : " -NoNewline -ForegroundColor DarkGray
Write-Host "Photos [$PhotoOrganizationMode] | MLVs [$MLVOrganizationMode]" -ForegroundColor Cyan

Write-Host "  🛡️ Verification         : " -NoNewline -ForegroundColor DarkGray
if ($VerificationEnabled) {
    Write-Host "$VerificationMethod verification active" -ForegroundColor Green
}
else {
    Write-Host "Name" -ForegroundColor DarkGray
}

Write-Host "  🗑️ Delete Source        : " -NoNewline -ForegroundColor DarkGray
if ($DeleteSource) {
    Write-Host "Enabled (Remove files from card)" -ForegroundColor Red
}
else {
    Write-Host "Disabled (Keep files on card)" -ForegroundColor Green
}
Write-Divider
Write-Host ""

Write-Log "Application started."

if ($DeleteSource) {
    if (-not (Confirm-DeleteMode)) {
        Write-Log "Startup aborted: User declined delete source mode."
        Write-Host "  ⚠️ [!] Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================
# DRIVE MONITOR & QUEUE SYSTEM
# ============================================================

$ProcessedDrives = @{}
$CardQueue = [System.Collections.Generic.Queue[string]]::new()
$QueuedDrives = @{}

Write-Host "  ℹ️ Monitoring drives for camera cards..." -ForegroundColor Cyan
Write-Host ""

while ($true) {

    try {
        $Drives = @(Get-EligibleDrives)

        foreach ($Drive in $Drives) {
            $Root = $Drive.DeviceID + "\"

            if ($ProcessedDrives.ContainsKey($Root) -or $QueuedDrives.ContainsKey($Root)) {
                continue
            }

            if (-not (Test-Path -LiteralPath $Root)) {
                continue
            }

            $Files = @(Get-CameraFiles $Root)

            if (@($Files).Count -lt $MinimumCameraFiles) {
                continue
            }

            if ($MountSettleSeconds -gt 0) {
                Start-Sleep -Seconds $MountSettleSeconds
            }

            $FilesAfterSettle = @(Get-CameraFiles $Root)
            if (@($FilesAfterSettle).Count -lt $MinimumCameraFiles) {
                continue
            }

            # Enqueue the detected camera card safely to prevent concurrent collisions
            $CardQueue.Enqueue($Root)
            $QueuedDrives[$Root] = $true
            
            Write-Log "Camera card queued: $Root (Queue depth: $($CardQueue.Count))"
            Write-Host "  📥 [Queue] Card added to import queue: $Root [Queue Position: $($CardQueue.Count)]" -ForegroundColor Yellow
            Show-Notification "MagicDump" "Camera card queued: $Root"
        }

        # Process the queue sequentially to avoid write collisions on destinations
        while ($CardQueue.Count -gt 0) {
            $CurrentRoot = $CardQueue.Dequeue()

            Write-Host ""
            Write-Host "  ⏳ [Queue] Processing next card from queue: $CurrentRoot" -ForegroundColor Cyan

            $Success = Import-Card $CurrentRoot

            if ($Success) {
                $ProcessedDrives[$CurrentRoot] = Get-Date
                Write-Log "Import finished successfully: $CurrentRoot"
                Show-Notification "MagicDump" "Import complete: $CurrentRoot"
                Eject-Drive $CurrentRoot
            }
            else {
                Write-Log "Import finished with errors: $CurrentRoot" "ERROR"
                Show-Notification "MagicDump" "Import failed: $CurrentRoot"
            }
        }

        $CurrentRoots = @(
            $Drives |
                ForEach-Object {
                    $_.DeviceID + "\"
                }
        )

        foreach ($OldRoot in @($ProcessedDrives.Keys)) {
            if ($CurrentRoots -notcontains $OldRoot) {
                [void]$ProcessedDrives.Remove($OldRoot)
                [void]$QueuedDrives.Remove($OldRoot)
            }
        }
    }
    catch {
        Write-Log "Monitor Error: $($_.Exception.Message)" "ERROR"
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($PollInterval -gt 0) {
        Start-Sleep -Seconds $PollInterval
    }
}