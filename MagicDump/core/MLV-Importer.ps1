#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# MAGIC LANTERN MLV / PHOTO IMPORTER
# Windows 11 / PowerShell 5.1+
# ============================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot "config.json"

# ============================================================
# LOAD CONFIG
# ============================================================

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host ""
    Write-Host "ERROR: config.json not found:" -ForegroundColor Red
    Write-Host $ConfigPath
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
    Write-Host "ERROR: Could not read config.json" -ForegroundColor Red
    Write-Host $_.Exception.Message
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
# FORMATTING
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

# ============================================================
# LOGGING
# ============================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "{0} [{1}] {2}" -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $Level,
        $Message

    Write-Host $Line

    if ($LoggingEnabled) {
        try {
            Add-Content `
                -LiteralPath $LogFile `
                -Value $Line `
                -Encoding UTF8
        }
        catch {
            # Logging must never stop an import.
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
# COPY FILE (WITH REAL-TIME PROGRESS, SPEED, AND ETA)
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

            Write-Host ""
            Write-Host "Already exists:" -ForegroundColor Cyan
            Write-Host "  $($SourceFile.Name)"

            if (-not (Test-Copy `
                $SourceFile.FullName `
                $Destination)) {

                Write-Log `
                    "Existing destination failed verification: $Destination" `
                    "ERROR"

                return $false
            }

            Write-Host "  Existing file verified." -ForegroundColor Green

            return $true
        }

        if (-not $ReplaceDifferent) {

            Write-Log `
                "Destination exists and replacement disabled: $Destination" `
                "ERROR"

            return $false
        }

        Write-Host ""
        Write-Host "Replacing existing file:" -ForegroundColor Yellow
        Write-Host "  $Destination"

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
                Remove-Item `
                    -LiteralPath $TempPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }

        try {

            Write-Host ""
            Write-Host "[$FileNumber/$FileCount] $($SourceFile.Name)"
            Write-Host "  Size: $(Format-Bytes $SourceFile.Length)"

            if ($Attempt -gt 1) {
                Write-Host `
                    "  Attempt: $Attempt/$Retries" `
                    -ForegroundColor Yellow
            }

            if ($DryRun) {
                Write-Host "  DRY RUN: Copy skipped." -ForegroundColor Yellow
                return $true
            }

            $DestinationDirectory = Split-Path `
                -Path $TempPath `
                -Parent

            if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
                New-Item `
                    -ItemType Directory `
                    -Path $DestinationDirectory `
                    -Force |
                    Out-Null
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

                        $BarWidth = 15
                        $Filled = [math]::Round(($CopiedBytes / $TotalLength) * $BarWidth)
                        $Empty = $BarWidth - $Filled
                        $Bar = "[" + ("=" * $Filled) + (" " * $Empty) + "]"

                        Write-Host -NoNewline "`r  $Bar $Percent% | $SpeedText | ETA: $ETAText   "
                    }
                }
            }
            finally {
                $SourceStream.Dispose()
                $DestStream.Dispose()
                $Stopwatch.Stop()
                Write-Host ""
            }

            if (-not (Test-Copy `
                $SourceFile.FullName `
                $TempPath)) {

                throw "Temporary file verification failed."
            }

            if ($UseTemporary) {

                Move-Item `
                    -LiteralPath $TempPath `
                    -Destination $Destination `
                    -Force `
                    -ErrorAction Stop
            }

            if (-not (Test-Copy `
                $SourceFile.FullName `
                $Destination)) {

                throw "Final destination verification failed."
            }

            Write-Host "  OK - verified" -ForegroundColor Green

            Write-Log `
                "Successfully imported: $($SourceFile.FullName)"

            return $true
        }
        catch {

            Write-Log `
                "Attempt $Attempt failed for $($SourceFile.Name): $($_.Exception.Message)" `
                "ERROR"

            Write-Host ""
            Write-Host `
                "  FAILED: $($_.Exception.Message)" `
                -ForegroundColor Red

            if (Test-Path -LiteralPath $TempPath) {
                Remove-Item `
                    -LiteralPath $TempPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

            if ($Attempt -lt $Retries) {
                if ($RetryDelay -gt 0) {
                    Start-Sleep -Seconds $RetryDelay
                }
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
        $Extension = $Extension = $File.Extension.ToUpperInvariant()

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
        Write-Host ""
        Write-Host `
            "DRY RUN: source deletion skipped." `
            -ForegroundColor Yellow

        return $true
    }

    foreach ($Item in @($Items)) {

        $SourcePath = $Item.File.FullName

        if (-not (Test-Path -LiteralPath $SourcePath)) {
            Write-Log `
                "Source disappeared before deletion: $SourcePath" `
                "ERROR"

            return $false
        }
    }

    foreach ($Item in @($Items)) {

        $Path = $Item.File.FullName

        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }

        try {

            $Destination = Get-DestinationPath `
                $Item.File `
                $(if ($Item.Type -eq "Photo") {
                    "Photo"
                }
                else {
                    "MLV"
                })

            if ($NeverDeleteUnlessVerified) {

                if (-not (Test-Copy `
                    $Path `
                    $Destination)) {

                    Write-Log `
                        "REFUSING TO DELETE - verification failed: $Path" `
                        "ERROR"

                    return $false
                }
            }

            Write-Host ""
            Write-Host "Deleting source:" -ForegroundColor Yellow
            Write-Host "  $Path"

            Remove-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction Stop
        }
        catch {

            Write-Log `
                "Could not delete source: $Path - $($_.Exception.Message)" `
                "ERROR"

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

    Write-Log "Scanning card: $DriveRoot"

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    Write-Host " CAMERA CARD: $DriveRoot" `
        -ForegroundColor Cyan

    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    $ScanRoot = $DriveRoot
    $Files = @(Get-CameraFiles $ScanRoot)

    if (@($Files).Count -eq 0) {
        Write-Log "No camera files found."
        return $false
    }

    $Photos = @(
        $Files |
            Where-Object {
                $_.Type -eq "Photo"
            }
    )

    $MLVFiles = @(
        $Files |
            Where-Object {
                $_.Type -in @(
                    "MLV",
                    "MLVChunk"
                )
            }
    )

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
    # DISK SPACE PRE-CHECK & RETRIEVAL
    # ============================================================
    $TargetDriveRoot = [System.IO.Path]::GetPathRoot([string]$MLVDestination)
    [double]$FreeSpace = 0
    try {
        $DriveInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($TargetDriveRoot.TrimEnd('\'))'" -ErrorAction Stop
        $FreeSpace = [double]$DriveInfo.FreeSpace

        [double]$RequiredSpace = $TotalBytes + 1GB

        if ($FreeSpace -lt $RequiredSpace) {
            Write-Log "ABORT: Insufficient free space on $TargetDriveRoot. Required: $(Format-Bytes $RequiredSpace), Available: $(Format-Bytes $FreeSpace)" "ERROR"
            
            Write-Host ""
            Write-Host "============================================================" -ForegroundColor DarkGray
            Write-Host " IMPORT ABORTED: INSUFFICIENT DISK SPACE" -ForegroundColor Red
            Write-Host " Target Drive: $TargetDriveRoot" -ForegroundColor Yellow
            Write-Host " Required:     $(Format-Bytes $RequiredSpace) (including buffer)" -ForegroundColor Yellow
            Write-Host " Available:    $(Format-Bytes $FreeSpace)" -ForegroundColor Yellow
            Write-Host "============================================================" -ForegroundColor DarkGray

            Show-Notification "Magic Lantern Importer" "Import aborted: Insufficient disk space on $TargetDriveRoot"
            return $false
        }
    }
    catch {
        Write-Log "Could not verify disk space for $TargetDriveRoot : $($_.Exception.Message)" "ERROR"
    }

    Write-Host ""
    Write-Host "Files found: $TotalFiles" -ForegroundColor Cyan
    Write-Host "Total size:  $(Format-Bytes $TotalBytes)" -ForegroundColor Cyan
    Write-Host " - Photos:   $PhotoFilesCount file(s) ($(Format-Bytes $PhotoBytes))" -ForegroundColor Cyan
    Write-Host " - MLVs:     $MLVFilesCount file(s) ($(Format-Bytes $MLVBytes))" -ForegroundColor Cyan
    if ($FreeSpace -gt 0) {
        Write-Host " Free space: $(Format-Bytes $FreeSpace) ($TargetDriveRoot)" -ForegroundColor Cyan
    }

    if ($DeleteSource) {
        Write-Host ""
        Write-Host `
            "WARNING: SOURCE DELETE IS ENABLED" `
            -ForegroundColor Red
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

                Write-Log `
                    "File was not stable: $($Item.File.FullName)" `
                    "ERROR"

                $GroupSuccess = $false
                $FailedFiles++

                continue
            }

            $Destination = Get-DestinationPath `
                $Item.File `
                $(if ($Item.Type -eq "Photo") {
                    "Photo"
                }
                else {
                    "MLV"
                })

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
            # Clean up partial destination copies for this failed work item/group
            foreach ($CopiedDest in $SuccessfullyCopiedInGroup) {
                if (Test-Path -LiteralPath $CopiedDest) {
                    Write-Host "Cleaning up partial destination file: $CopiedDest" -ForegroundColor Yellow
                    Remove-Item -LiteralPath $CopiedDest -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($GroupSuccess -and $DeleteSource) {

            Write-Host ""
            Write-Host `
                "Import verified. Removing source files..." `
                -ForegroundColor Yellow

            if (-not (Remove-ImportedSource $Work.Group)) {

                Write-Log `
                    "Source deletion failed for work item." `
                    "ERROR"
            }
            else {

                Write-Host `
                    "Source cleanup complete." `
                    -ForegroundColor Green
            }
        }
        elseif (
            (-not $GroupSuccess) -and
            ($Work.Type -eq "MLVGroup")
        ) {

            Write-Host ""
            Write-Host `
                "MLV recording NOT deleted because one or more files failed." `
                -ForegroundColor Red
        }
    }

    $OverallSuccess = ($FailedFiles -eq 0)
    Write-ImportManifest -DriveRoot $DriveRoot -WorkItems $WorkItems -Success $OverallSuccess

$MLVFSEnabled = [bool](Get-ConfigValue $MLVFS "Enabled" $false)
    if ($MLVFSEnabled -and $OverallSuccess -and $MLVFiles.Count -gt 0) {
        $ControllerPath = [string](Get-ConfigValue $MLVFS "ControllerPath" "")
        if (Test-Path -LiteralPath $ControllerPath) {
            
            $TargetMountPath = $MLVDestination

            Write-Host ""
            Write-Host "Copy complete. Mounting imported MLV destination via Controller..." -ForegroundColor Yellow
            Write-Log "Invoking batch mount script post-copy: $ControllerPath mount $TargetMountPath"

            try {
                & "$ControllerPath" "mount" "$TargetMountPath"
                Write-Host "MLVFS mounted successfully to Z:\ ($TargetMountPath)" -ForegroundColor Green
            }
            catch {
                Write-Log "Failed to mount MLV destination: $($_.Exception.Message)" "ERROR"
                Write-Host "WARNING: Post-copy mount failed." -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    if ($OverallSuccess) {
        Write-Host `
            " IMPORT COMPLETE" `
            -ForegroundColor Green
    }
    else {
        Write-Host `
            " IMPORT FINISHED WITH ERRORS" `
            -ForegroundColor Red
    }

    Write-Host " Successful files: $SuccessfulFiles"
    Write-Host " Failed files:     $FailedFiles"
    Write-Host " Total size:       $(Format-Bytes $TotalBytes)"
    Write-Host "  - Photos:        $PhotoFilesCount file(s) ($(Format-Bytes $PhotoBytes))"
    Write-Host "  - MLVs:          $MLVFilesCount file(s) ($(Format-Bytes $MLVBytes))"

    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    Write-Log `
        "Card complete. Successful: $SuccessfulFiles | Failed: $FailedFiles"

    return $OverallSuccess
}

# ============================================================
# DELETE CONFIRMATION
# ============================================================

function Confirm-DeleteMode {

    if (-not $DeleteSource) {
        return $true
    }

    if (-not $RequireDeleteConfirmation) {
        return $true
    }

    try {

        Add-Type -AssemblyName System.Windows.Forms

        $Message = @"
DELETE FROM CAMERA CARD IS ENABLED.

Files will ONLY be deleted after a successful verified import.

MLV split files are treated as one recording.

Do you want to continue?
"@

        $Result = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            "Magic Lantern Importer - DELETE ENABLED",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        return (
            $Result -eq
            [System.Windows.Forms.DialogResult]::Yes
        )
    }
    catch {
        Write-Host ""
        Write-Host `
            "Could not display delete confirmation." `
            -ForegroundColor Red

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

    if (-not $AutoEject) {
        return
    }

    try {

        Write-Log "Ejecting card: $DriveRoot"

        $Shell = New-Object -ComObject Shell.Application

        $DriveLetter = $DriveRoot.Substring(0, 2)

        $Drive = $Shell.Namespace(17).ParseName($DriveLetter)

        if ($null -ne $Drive) {
            $Drive.InvokeVerb("Eject")
        }

        Write-Log "Eject requested."
    }
    catch {
        Write-Log `
            "Could not eject card: $($_.Exception.Message)" `
            "ERROR"
    }
}

# ============================================================
# STARTUP
# ============================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "          MAGIC LANTERN CAMERA IMPORTER" `
    -ForegroundColor Cyan

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""
Write-Host "Photos destination:"
Write-Host "  $PhotoDestination"

Write-Host ""
Write-Host "MLV destination:"
Write-Host "  $MLVDestination"

Write-Host ""
Write-Host "Organization:"
Write-Host "  Photos: $PhotoOrganizationMode | MLVs: $MLVOrganizationMode"

Write-Host ""
Write-Host "Verification:"
Write-Host "  $VerificationMethod"

Write-Host ""
Write-Host "Delete source after import:"

if ($DeleteSource) {
    Write-Host "  ENABLED" -ForegroundColor Red
}
else {
    Write-Host "  Disabled" -ForegroundColor Green
}

Write-Host ""

Write-Log "Magic Lantern Importer started."

if ($DeleteSource) {
    if (-not (Confirm-DeleteMode)) {
        Write-Log `
            "Startup cancelled because source deletion was enabled."

        Write-Host ""
        Write-Host "Cancelled." -ForegroundColor Yellow

        exit 0
    }
}

# ============================================================
# DRIVE MONITOR
# ============================================================

$ProcessedDrives = @{}

while ($true) {

    try {

        $Drives = @(Get-EligibleDrives)

        foreach ($Drive in $Drives) {

            $Root = $Drive.DeviceID + "\"

            if ($ProcessedDrives.ContainsKey($Root)) {
                continue
            }

            if (-not (Test-Path -LiteralPath $Root)) {
                continue
            }

            $Files = @(Get-CameraFiles $Root)

            if (@($Files).Count -lt $MinimumCameraFiles) {
                continue
            }

            Write-Log "Camera card detected: $Root"

            Show-Notification `
                "Magic Lantern Importer" `
                "Camera card detected: $Root"

            if ($MountSettleSeconds -gt 0) {
                Start-Sleep -Seconds $MountSettleSeconds
            }

            $FilesAfterSettle = @(Get-CameraFiles $Root)

            if (@($FilesAfterSettle).Count -lt $MinimumCameraFiles) {
                continue
            }

            $Success = Import-Card $Root

            if ($Success) {

                $ProcessedDrives[$Root] = Get-Date

                Write-Log `
                    "Import completed successfully: $Root"

                Show-Notification `
                    "Magic Lantern Importer" `
                    "Import completed: $Root"

                Eject-Drive $Root
            }
            else {

                Write-Log `
                    "Import finished with errors: $Root" `
                    "ERROR"

                Show-Notification `
                    "Magic Lantern Importer" `
                    "Import finished with errors: $Root"
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
            }
        }
    }
    catch {
        Write-Log `
            "Monitor error: $($_.Exception.Message)" `
            "ERROR"

        Write-Host ""
        Write-Host `
            "Monitor error: $($_.Exception.Message)" `
            -ForegroundColor Red
    }

    if ($PollInterval -gt 0) {
        Start-Sleep -Seconds $PollInterval
    }
}