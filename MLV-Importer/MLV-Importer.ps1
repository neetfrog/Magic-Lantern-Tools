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
    $Config = Get-Content `
        -LiteralPath $ConfigPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
}
catch {
    Write-Host ""
    Write-Host "ERROR: Could not read config.json" -ForegroundColor Red
    Write-Host $_.Exception.Message
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

$PhotoDestination = [string](
    Get-ConfigValue $Config.Destinations "Photos" "D:\Camera Import\Photos"
)

$MLVDestination = [string](
    Get-ConfigValue $Config.Destinations "MLV" "D:\Camera Import\MLV"
)

$OrganizationMode = [string](
    Get-ConfigValue $Config.Organization "Mode" "Flat"
)

$DateFormat = [string](
    Get-ConfigValue $Config.Organization "DateFormat" "yyyy-MM-dd"
)

$ScanSubfolders = [bool](
    Get-ConfigValue $Config.Scanning "ScanSubfolders" $true
)

$SkipExisting = [bool](
    Get-ConfigValue $Config.Copy "SkipExistingSameSize" $true
)

$ReplaceDifferent = [bool](
    Get-ConfigValue $Config.Copy "ReplaceDifferentSize" $false
)

$UseTemporary = [bool](
    Get-ConfigValue $Config.Copy "UseTemporaryFiles" $true
)

$TemporaryExtension = [string](
    Get-ConfigValue $Config.Copy "TemporaryExtension" ".importing"
)

$Retries = [int](
    Get-ConfigValue $Config.Copy "Retries" 3
)

$RetryDelay = [int](
    Get-ConfigValue $Config.Copy "RetryDelaySeconds" 3
)

$VerificationEnabled = [bool](
    Get-ConfigValue $Config.Verification "Enabled" $true
)

$VerificationMethod = [string](
    Get-ConfigValue $Config.Verification "Method" "Size"
)

$StabilityEnabled = [bool](
    Get-ConfigValue $Config.Stability "Enabled" $true
)

$StabilityChecks = [int](
    Get-ConfigValue $Config.Stability "Checks" 2
)

$StabilityDelay = [int](
    Get-ConfigValue $Config.Stability "DelaySeconds" 2
)

$MLVChunkEnabled = [bool](
    Get-ConfigValue $Config.FileTypes.MLVChunks "Enabled" $true
)

$OnlyRemovable = [bool](
    Get-ConfigValue $Config.Card "OnlyRemovableDrives" $true
)

$AutoEject = [bool](
    Get-ConfigValue $Config.Card "AutoEject" $false
)

$DeleteSource = [bool](
    Get-ConfigValue $Config.Card "DeleteSourceAfterImport" $false
)

$RequireDeleteConfirmation = [bool](
    Get-ConfigValue $Config.Card "RequireDeleteConfirmation" $true
)

$DryRun = [bool](
    Get-ConfigValue $Config.Safety "DryRun" $false
)

$NeverDeleteUnlessVerified = [bool](
    Get-ConfigValue `
        $Config.Safety `
        "NeverDeleteSourceUnlessVerified" `
        $true
)

$ManifestEnabled = [bool](
    Get-ConfigValue $Config.Manifest "Enabled" $true
)

$LoggingEnabled = [bool](
    Get-ConfigValue $Config.Logging "Enabled" $true
)

$NotificationsEnabled = [bool](
    Get-ConfigValue $Config.Notifications "Enabled" $true
)

$PollInterval = [int](
    Get-ConfigValue $Config.Monitoring "PollIntervalSeconds" 2
)

# ============================================================
# EXTENSIONS
# ============================================================

$PhotoExtensions = @(
    @(
        Get-ConfigValue `
            $Config.FileTypes `
            "Photos" `
            @(
                ".CR2",
                ".CR3",
                ".JPG",
                ".JPEG",
                ".JPE",
                ".PNG",
                ".TIF",
                ".TIFF"
            )
    ) |
    ForEach-Object {
        $_.ToString().ToUpperInvariant()
    }
)

# ============================================================
# DIRECTORIES
# ============================================================

if (-not (Test-Path -LiteralPath $PhotoDestination)) {
    New-Item `
        -ItemType Directory `
        -Path $PhotoDestination `
        -Force |
        Out-Null
}

if (-not (Test-Path -LiteralPath $MLVDestination)) {
    New-Item `
        -ItemType Directory `
        -Path $MLVDestination `
        -Force |
        Out-Null
}

$LogDirectory = Join-Path `
    $ScriptRoot `
    (Get-ConfigValue $Config.Logging "Directory" "logs")

$ManifestDirectory = Join-Path `
    $ScriptRoot `
    (Get-ConfigValue $Config.Manifest "Directory" "manifests")

if ($LoggingEnabled) {
    New-Item `
        -ItemType Directory `
        -Path $LogDirectory `
        -Force |
        Out-Null
}

if ($ManifestEnabled) {
    New-Item `
        -ItemType Directory `
        -Path $ManifestDirectory `
        -Force |
        Out-Null
}

$LogFile = Join-Path `
    $LogDirectory `
    (Get-ConfigValue $Config.Logging "FileName" "importer.log")

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

function Format-Speed {
    param(
        [double]$BytesPerSecond
    )

    return "$(Format-Bytes $BytesPerSecond)/s"
}

function Format-Time {
    param(
        [double]$Seconds
    )

    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds)) {
        return "--:--"
    }

    $Time = [TimeSpan]::FromSeconds($Seconds)

    if ($Time.TotalHours -ge 1) {
        return $Time.ToString("hh\:mm\:ss")
    }

    return $Time.ToString("mm\:ss")
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
        Add-Content `
            -LiteralPath $LogFile `
            -Value $Line `
            -Encoding UTF8
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

        $Notify.Icon = [System.Drawing.SystemIcons]::Information
        $Notify.Visible = $true

        $Notify.ShowBalloonTip(
            4000,
            $Title,
            $Message,
            [System.Windows.Forms.ToolTipIcon]::Info
        )

        Start-Sleep -Milliseconds 4200

        $Notify.Dispose()
    }
    catch {
        # Notification failure should never stop importing.
    }
}

# ============================================================
# DRIVE DETECTION
# ============================================================

function Get-EligibleDrives {

    $Drives = Get-CimInstance Win32_LogicalDisk

    if ($OnlyRemovable) {
        $Drives = $Drives |
            Where-Object {
                $_.DriveType -eq 2
            }
    }
    else {
        $Drives = $Drives |
            Where-Object {
                $_.DriveType -in @(2, 3)
            }
    }

    return @(
        $Drives |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.DeviceID)
        }
    )
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
        $Extension -match '^\.M[0-9]{2}$'
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

        $Files = Get-ChildItem `
            -LiteralPath $Root `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue
    }
    else {

        $Files = Get-ChildItem `
            -LiteralPath $Root `
            -File `
            -ErrorAction SilentlyContinue
    }

    $Result = foreach ($File in $Files) {

        $Type = Get-FileType $File

        if ($null -ne $Type) {

            [PSCustomObject]@{
                File = $File
                Type = $Type
            }
        }
    }

    return @($Result)
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

    $PreviousSize = -1

    for ($i = 0; $i -lt $StabilityChecks; $i++) {

        if (-not (Test-Path -LiteralPath $File.FullName)) {
            return $false
        }

        try {

            $Current = Get-Item `
                -LiteralPath $File.FullName `
                -ErrorAction Stop

            $CurrentSize = $Current.Length

            if ($PreviousSize -ge 0) {

                if ($CurrentSize -ne $PreviousSize) {

                    $PreviousSize = $CurrentSize

                    Start-Sleep `
                        -Seconds $StabilityDelay

                    continue
                }
            }

            $PreviousSize = $CurrentSize

            Start-Sleep `
                -Seconds $StabilityDelay
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
    }
    else {
        $Root = $MLVDestination
    }

    switch ($OrganizationMode) {

        "Flat" {

            return Join-Path `
                $Root `
                $File.Name
        }

        "ByDate" {

            $DateFolder = $File.LastWriteTime.ToString($DateFormat)

            $Folder = Join-Path `
                $Root `
                $DateFolder

            if (-not (Test-Path -LiteralPath $Folder)) {

                New-Item `
                    -ItemType Directory `
                    -Path $Folder `
                    -Force |
                    Out-Null
            }

            return Join-Path `
                $Folder `
                $File.Name
        }

        default {

            # Flat is deliberately the safe fallback.
            return Join-Path `
                $Root `
                $File.Name
        }
    }
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
            -Algorithm SHA256
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

    $SourceInfo = Get-Item -LiteralPath $Source
    $DestinationInfo = Get-Item -LiteralPath $Destination

    if ($SourceInfo.Length -ne $DestinationInfo.Length) {
        return $false
    }

    if (-not $VerificationEnabled) {
        return $true
    }

    switch ($VerificationMethod) {

        "None" {
            return $true
        }

        "Size" {
            return (
                $SourceInfo.Length -eq
                $DestinationInfo.Length
            )
        }

        "SHA256" {

            $SourceHash = Get-FileHashSafe $Source
            $DestinationHash = Get-FileHashSafe $Destination

            return (
                $SourceHash -eq $DestinationHash
            )
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
# COPY WITH LIVE SPEED / ETA
# ============================================================

function Copy-FileWithProgress {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$DisplayName,
        [int64]$OverallCompleted,
        [int64]$OverallTotal,
        [int]$FileNumber,
        [int]$FileCount
    )

    $SourceStream = $null
    $DestinationStream = $null

    try {

        $SourceInfo = Get-Item `
            -LiteralPath $Source `
            -ErrorAction Stop

        $FileSize = [int64]$SourceInfo.Length

        if ($DryRun) {

            Write-Host ""
            Write-Host "DRY RUN: $DisplayName" `
                -ForegroundColor Yellow

            return $true
        }

        $DestinationDirectory = Split-Path `
            $Destination `
            -Parent

        if (-not (Test-Path -LiteralPath $DestinationDirectory)) {

            New-Item `
                -ItemType Directory `
                -Path $DestinationDirectory `
                -Force |
                Out-Null
        }

        $SourceStream = New-Object `
            System.IO.FileStream(
                $Source,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read,
                4MB,
                [System.IO.FileOptions]::SequentialScan
            )

        $DestinationStream = New-Object `
            System.IO.FileStream(
                $Destination,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None,
                4MB,
                [System.IO.FileOptions]::SequentialScan
            )

        $Buffer = New-Object byte[] (4MB)

        [int64]$Copied = 0

        $StartTime = [DateTime]::UtcNow

        $LastDisplay = $StartTime

        while ($Copied -lt $FileSize) {

            $BytesRead = $SourceStream.Read(
                $Buffer,
                0,
                $Buffer.Length
            )

            if ($BytesRead -le 0) {
                break
            }

            $DestinationStream.Write(
                $Buffer,
                0,
                $BytesRead
            )

            $Copied += $BytesRead

            $Now = [DateTime]::UtcNow

            $Elapsed = (
                $Now - $StartTime
            ).TotalSeconds

            if ($Elapsed -le 0) {
                $Elapsed = 0.001
            }

            $Speed = $Copied / $Elapsed

            if ($Speed -gt 0) {

                $Remaining = $FileSize - $Copied

                $ETA = $Remaining / $Speed
            }
            else {
                $ETA = -1
            }

            $OverallNow = $OverallCompleted + $Copied

            if (
                (($Now - $LastDisplay).TotalMilliseconds -ge 150) -or
                ($Copied -eq $FileSize)
            ) {

                $FilePercent = if ($FileSize -gt 0) {
                    ($Copied / $FileSize) * 100
                }
                else {
                    100
                }

                $OverallPercent = if ($OverallTotal -gt 0) {
                    ($OverallNow / $OverallTotal) * 100
                }
                else {
                    100
                }

                Write-Progress `
                    -Id 1 `
                    -Activity "Importing camera card" `
                    -Status (
                        "File {0}/{1} | {2:N1}% | {3} / {4} | {5} | ETA {6}" -f `
                        $FileNumber,
                        $FileCount,
                        $FilePercent,
                        (Format-Bytes $Copied),
                        (Format-Bytes $FileSize),
                        (Format-Speed $Speed),
                        (Format-Time $ETA)
                    ) `
                    -PercentComplete ([Math]::Min(
                        100,
                        [Math]::Max(0, [int]$FilePercent)
                    ))

                Write-Progress `
                    -Id 2 `
                    -ParentId 1 `
                    -Activity "Overall card progress" `
                    -Status (
                        "{0:N1}% | {1} / {2} | {3} | ETA {4}" -f `
                        $OverallPercent,
                        (Format-Bytes $OverallNow),
                        (Format-Bytes $OverallTotal),
                        (Format-Speed $Speed),
                        (Format-Time (
                            if ($Speed -gt 0) {
                                ($OverallTotal - $OverallNow) / $Speed
                            }
                            else {
                                -1
                            }
                        ))
                    ) `
                    -PercentComplete ([Math]::Min(
                        100,
                        [Math]::Max(0, [int]$OverallPercent)
                    ))

                $LastDisplay = $Now
            }
        }

        $DestinationStream.Flush()

        $DestinationStream.Flush($true)

        if ($Copied -ne $FileSize) {

            throw `
                "Copy ended early. Expected $FileSize bytes, copied $Copied bytes."
        }

        return $true
    }
    finally {

        if ($null -ne $DestinationStream) {
            $DestinationStream.Dispose()
        }

        if ($null -ne $SourceStream) {
            $SourceStream.Dispose()
        }
    }
}

# ============================================================
# COPY ONE FILE SAFELY
# ============================================================

function Copy-SafeFile {
    param(
        [System.IO.FileInfo]$SourceFile,
        [string]$Destination,
        [int64]$OverallCompleted,
        [int64]$OverallTotal,
        [int]$FileNumber,
        [int]$FileCount
    )

    if (Test-Path -LiteralPath $Destination) {

        $Existing = Get-Item `
            -LiteralPath $Destination

        if (
            $SkipExisting -and
            $Existing.Length -eq $SourceFile.Length
        ) {

            Write-Host ""
            Write-Host "Already exists:" `
                -ForegroundColor Cyan

            Write-Host "  $($SourceFile.Name)"

            # Even when skipped, verify before allowing deletion.
            if (-not (Test-Copy `
                $SourceFile.FullName `
                $Destination)) {

                Write-Log `
                    "Existing destination failed verification: $Destination" `
                    "ERROR"

                return $false
            }

            return $true
        }

        if (-not $ReplaceDifferent) {

            Write-Log `
                "Destination exists and replacement disabled: $Destination" `
                "ERROR"

            return $false
        }

        Write-Host ""
        Write-Host "Replacing existing file:" `
            -ForegroundColor Yellow

        Write-Host "  $Destination"

        Remove-Item `
            -LiteralPath $Destination `
            -Force
    }

    for ($Attempt = 1; $Attempt -le $Retries; $Attempt++) {

        $TempPath = $Destination

        if ($UseTemporary) {

            $TempPath =
                $Destination +
                $TemporaryExtension

            if (Test-Path -LiteralPath $TempPath) {

                Remove-Item `
                    -LiteralPath $TempPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }

        try {

            Write-Host ""
            Write-Host "[$FileNumber/$FileCount] $($SourceFile.Name)" `
                -ForegroundColor White

            Write-Host "  Size: $(Format-Bytes $SourceFile.Length)"

            if ($Attempt -gt 1) {

                Write-Host "  Attempt: $Attempt/$Retries" `
                    -ForegroundColor Yellow
            }

            if ($DryRun) {

                Write-Host "  DRY RUN - copy skipped" `
                    -ForegroundColor Yellow

                return $true
            }

            $CopiedOK = Copy-FileWithProgress `
                -Source $SourceFile.FullName `
                -Destination $TempPath `
                -DisplayName $SourceFile.Name `
                -OverallCompleted $OverallCompleted `
                -OverallTotal $OverallTotal `
                -FileNumber $FileNumber `
                -FileCount $FileCount

            if (-not $CopiedOK) {
                throw "Copy operation failed."
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
                    -Force
            }

            if (-not (Test-Copy `
                $SourceFile.FullName `
                $Destination)) {

                throw "Final destination verification failed."
            }

            Write-Host ""
            Write-Host "  OK - verified" `
                -ForegroundColor Green

            Write-Log `
                "Successfully imported: $($SourceFile.FullName)"

            return $true
        }
        catch {

            Write-Log `
                "Attempt $Attempt failed for $($SourceFile.Name): $($_.Exception.Message)" `
                "ERROR"

            Write-Host ""
            Write-Host "  FAILED: $($_.Exception.Message)" `
                -ForegroundColor Red

            if (Test-Path -LiteralPath $TempPath) {

                Remove-Item `
                    -LiteralPath $TempPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

            if ($Attempt -lt $Retries) {

                Start-Sleep `
                    -Seconds $RetryDelay
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

    foreach ($Item in $MLVFiles) {

        $File = $Item.File

        if ($File.Extension.ToUpperInvariant() -eq ".MLV") {

            $Key = [System.IO.Path]::Combine(
                $File.DirectoryName,
                $File.BaseName
            )

            if (-not $Groups.ContainsKey($Key)) {
                $Groups[$Key] = @()
            }

            $Groups[$Key] += $Item
        }
    }

    foreach ($Item in $MLVFiles) {

        $File = $Item.File

        if (
            $File.Extension.ToUpperInvariant() -match
            '^\.M[0-9]{2}$'
        ) {

            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
                $File.Name
            )

            $Key = [System.IO.Path]::Combine(
                $File.DirectoryName,
                $BaseName
            )

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
                if ($_.File.Extension.ToUpperInvariant() -eq ".MLV") {
                    -1
                }
                else {
                    try {
                        [int](
                            $_.File.Extension.Substring(2)
                        )
                    }
                    catch {
                        999999
                    }
                }
            }
        )
    }

    return $Groups
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
        Write-Host "DRY RUN: source deletion skipped." `
            -ForegroundColor Yellow

        return $true
    }

    if ($NeverDeleteUnlessVerified) {

        foreach ($Item in $Items) {

            $SourcePath = $Item.File.FullName

            if (-not (Test-Path -LiteralPath $SourcePath)) {
                return $false
            }
        }
    }

    foreach ($Item in $Items) {

        $Path = $Item.File.FullName

        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }

        try {

            # Final verification immediately before deletion.
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
            Write-Host "Deleting source:" `
                -ForegroundColor Yellow

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

    $Files = Get-CameraFiles $DriveRoot

    if ($Files.Count -eq 0) {

        Write-Log "No camera files found."

        return $false
    }

    # --------------------------------------------------------
    # PHOTOS
    # --------------------------------------------------------

    $Photos = @(
        $Files |
        Where-Object {
            $_.Type -eq "Photo"
        }
    )

    # --------------------------------------------------------
    # MLV GROUPS
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # BUILD WORK LIST
    # --------------------------------------------------------

    $WorkItems = New-Object System.Collections.ArrayList

    foreach ($Item in $Photos) {

        [void]$WorkItems.Add(
            [PSCustomObject]@{
                File = $Item.File
                Type = "Photo"
                Group = @($Item)
            }
        )
    }

    foreach ($Key in $MLVGroups.Keys) {

        $Group = @($MLVGroups[$Key])

        if ($Group.Count -gt 0) {

            [void]$WorkItems.Add(
                [PSCustomObject]@{
                    File = $Group[0].File
                    Type = "MLVGroup"
                    Group = $Group
                }
            )
        }
    }

    # --------------------------------------------------------
    # TOTAL BYTES
    # --------------------------------------------------------

    [int64]$TotalBytes = 0

    foreach ($Work in $WorkItems) {

        foreach ($Item in $Work.Group) {

            $TotalBytes += [int64]$Item.File.Length
        }
    }

    $TotalFiles = 0

    foreach ($Work in $WorkItems) {
        $TotalFiles += $Work.Group.Count
    }

    Write-Host ""
    Write-Host "Files found: $TotalFiles" `
        -ForegroundColor Cyan

    Write-Host "Total size:  $(Format-Bytes $TotalBytes)" `
        -ForegroundColor Cyan

    if ($DeleteSource) {

        Write-Host ""
        Write-Host "WARNING: SOURCE DELETE IS ENABLED" `
            -ForegroundColor Red
    }

    Write-Host ""

    # --------------------------------------------------------
    # PROCESS
    # --------------------------------------------------------

    [int64]$OverallCompleted = 0
    $SuccessfulFiles = 0
    $FailedFiles = 0
    $FileNumber = 0

    foreach ($Work in $WorkItems) {

        $GroupSuccess = $true

        foreach ($Item in $Work.Group) {

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
                -OverallCompleted $OverallCompleted `
                -OverallTotal $TotalBytes `
                -FileNumber $FileNumber `
                -FileCount $TotalFiles

            if ($Success) {

                $SuccessfulFiles++

                $OverallCompleted += [int64]$Item.File.Length
            }
            else {

                $FailedFiles++

                $GroupSuccess = $false
            }
        }

        # ----------------------------------------------------
        # DELETE GROUP ONLY AFTER EVERYTHING SUCCEEDED
        # ----------------------------------------------------

        if ($GroupSuccess -and $DeleteSource) {

            Write-Host ""
            Write-Host "Import verified. Removing source files..." `
                -ForegroundColor Yellow

            if (-not (Remove-ImportedSource $Work.Group)) {

                Write-Log `
                    "Source deletion failed for group." `
                    "ERROR"
            }
            else {

                Write-Host "Source cleanup complete." `
                    -ForegroundColor Green
            }
        }
        elseif (
            -not $GroupSuccess -and
            $Work.Type -eq "MLVGroup"
        ) {

            Write-Host ""
            Write-Host "MLV group NOT deleted because one or more files failed." `
                -ForegroundColor Red
        }
    }

    Write-Progress -Id 2 -Activity "Overall card progress" -Completed
    Write-Progress -Id 1 -Activity "Importing camera card" -Completed

    # --------------------------------------------------------
    # SUMMARY
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    if ($FailedFiles -eq 0) {

        Write-Host " IMPORT COMPLETE" `
            -ForegroundColor Green
    }
    else {

        Write-Host " IMPORT FINISHED WITH ERRORS" `
            -ForegroundColor Red
    }

    Write-Host " Successful files: $SuccessfulFiles"
    Write-Host " Failed files:     $FailedFiles"
    Write-Host " Total size:       $(Format-Bytes $TotalBytes)"

    Write-Host "============================================================" `
        -ForegroundColor DarkGray

    Write-Log `
        "Card complete. Successful: $SuccessfulFiles | Failed: $FailedFiles"

    return ($FailedFiles -eq 0)
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

        $Result = [System.Windows.Forms.MessageBox]::Show(
            "DELETE FROM CAMERA CARD IS ENABLED.`n`n" +
            "Files will ONLY be deleted after a successful verified import.`n`n" +
            "MLV split files are treated as a group.`n`n" +
            "Do you want to continue?",
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
        Write-Host "Could not display delete confirmation." `
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
Write-Host "  $OrganizationMode"

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

# ============================================================
# DELETE CONFIRMATION
# ============================================================

if ($DeleteSource) {

    if (-not (Confirm-DeleteMode)) {

        Write-Log `
            "Startup cancelled because source deletion was enabled."

        Write-Host ""
        Write-Host "Cancelled." `
            -ForegroundColor Yellow

        exit 0
    }
}

# ============================================================
# DRIVE MONITOR
# ============================================================

$ProcessedDrives = @{}

while ($true) {

    try {

        $Drives = Get-EligibleDrives

        foreach ($Drive in $Drives) {

            $Root = $Drive.DeviceID + "\"

            if ($ProcessedDrives.ContainsKey($Root)) {
                continue
            }

            $Files = Get-CameraFiles $Root

            if ($Files.Count -lt (
                Get-ConfigValue `
                    $Config.Scanning `
                    "MinimumCameraFiles" `
                    1
            )) {
                continue
            }

            Write-Log "Camera card detected: $Root"

            Show-Notification `
                "Magic Lantern Importer" `
                "Camera card detected: $Root"

            # Give USB/card reader a moment to settle.
            $MountSettle = [int](
                Get-ConfigValue `
                    $Config.Monitoring `
                    "MountSettleSeconds" `
                    3
            )

            if ($MountSettle -gt 0) {
                Start-Sleep -Seconds $MountSettle
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

        # Forget cards that have been removed.
        $CurrentRoots = @(
            $Drives |
            ForEach-Object {
                $_.DeviceID + "\"
            }
        )

        foreach ($OldRoot in @($ProcessedDrives.Keys)) {

            if ($CurrentRoots -notcontains $OldRoot) {

                $ProcessedDrives.Remove($OldRoot)
            }
        }
    }
    catch {

        Write-Log `
            "Monitor error: $($_.Exception.Message)" `
            "ERROR"

        Write-Host ""
        Write-Host "Monitor error: $($_.Exception.Message)" `
            -ForegroundColor Red
    }

    Start-Sleep -Seconds $PollInterval
}