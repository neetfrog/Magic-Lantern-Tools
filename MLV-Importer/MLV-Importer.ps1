#requires -version 5.1

<#
    ============================================================
    Magic Lantern MLV Importer
    Windows 11 / PowerShell 5.1+
    ============================================================

    Features:
      - Automatic removable drive detection
      - SD / CF reader support
      - Camera-card detection
      - Photo import
      - MLV import
      - MLV .M00-.M99 span files
      - File stability checking
      - Retry handling
      - Temporary copy files
      - Size / SHA256 verification
      - Duplicate protection
      - Persistent manifest
      - Logging
      - Notifications
      - Optional automatic eject
      - Dry-run mode
      - Configurable organization
      - No Python required
      - No third-party modules required

    IMPORTANT:
      Source files are NEVER deleted or moved.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# GLOBAL PATHS
# ============================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

$ConfigPath = Join-Path $ScriptRoot "config.json"

$DefaultLogDirectory = Join-Path $ScriptRoot "logs"
$DefaultManifestDirectory = Join-Path $ScriptRoot "manifests"

$Global:Config = $null

# ============================================================
# BASIC HELPERS
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

function Test-PathSafe {
    param(
        [string]$Path
    )

    try {
        return Test-Path -LiteralPath $Path
    }
    catch {
        return $false
    }
}

# ============================================================
# CONFIG
# ============================================================

function Load-Configuration {

    if (-not (Test-PathSafe $ConfigPath)) {

        Write-Host ""
        Write-Host "ERROR: config.json not found."
        Write-Host "Expected:"
        Write-Host $ConfigPath
        Write-Host ""

        exit 1
    }

    try {

        $Raw = Get-Content `
            -LiteralPath $ConfigPath `
            -Raw `
            -Encoding UTF8

        $Global:Config = $Raw | ConvertFrom-Json
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Invalid config.json"
        Write-Host $_.Exception.Message
        Write-Host ""

        exit 1
    }
}

Load-Configuration

# ============================================================
# LOGGING
# ============================================================

function Get-LogDirectory {

    $Configured = Get-ConfigValue `
        $Global:Config.Logging `
        "Directory" `
        "logs"

    if ([System.IO.Path]::IsPathRooted($Configured)) {
        return $Configured
    }

    return Join-Path $ScriptRoot $Configured
}

function Get-LogFile {

    $Directory = Get-LogDirectory

    $FileName = Get-ConfigValue `
        $Global:Config.Logging `
        "FileName" `
        "importer.log"

    return Join-Path $Directory $FileName
}

function Initialize-Logging {

    if (-not (Get-ConfigValue $Global:Config.Logging "Enabled" $true)) {
        return
    }

    $Directory = Get-LogDirectory

    if (-not (Test-PathSafe $Directory)) {

        New-Item `
            -ItemType Directory `
            -Path $Directory `
            -Force |
            Out-Null
    }

    # Remove old logs if configured
    $KeepDays = Get-ConfigValue `
        $Global:Config.Logging `
        "KeepDays" `
        30

    if ($KeepDays -gt 0) {

        try {

            Get-ChildItem `
                -LiteralPath $Directory `
                -File `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays)
                } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Logging cleanup must never stop importing
        }
    }
}

Initialize-Logging

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet(
            "INFO",
            "SUCCESS",
            "WARNING",
            "ERROR",
            "DEBUG"
        )]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[{0}] [{1}] {2}" -f `
        $Timestamp,
        $Level,
        $Message

    Write-Host $Line

    if (Get-ConfigValue $Global:Config.Logging "Enabled" $true) {

        try {

            Add-Content `
                -LiteralPath (Get-LogFile) `
                -Value $Line `
                -Encoding UTF8
        }
        catch {
            # Never crash because logging failed
        }
    }
}

# ============================================================
# DIRECTORIES
# ============================================================

function Resolve-ConfiguredPath {
    param(
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $ScriptRoot $Path
}

function Initialize-Directories {

    $PhotoDestination = Resolve-ConfiguredPath `
        $Global:Config.Destinations.Photos

    $MLVDestination = Resolve-ConfiguredPath `
        $Global:Config.Destinations.MLV

    if (-not (Test-PathSafe $PhotoDestination)) {

        New-Item `
            -ItemType Directory `
            -Path $PhotoDestination `
            -Force |
            Out-Null
    }

    if (-not (Test-PathSafe $MLVDestination)) {

        New-Item `
            -ItemType Directory `
            -Path $MLVDestination `
            -Force |
            Out-Null
    }

    $ManifestDirectoryName = Get-ConfigValue `
        $Global:Config.Manifest `
        "Directory" `
        "manifests"

    if ([System.IO.Path]::IsPathRooted($ManifestDirectoryName)) {

        $ManifestDirectory = $ManifestDirectoryName
    }
    else {

        $ManifestDirectory = Join-Path `
            $ScriptRoot `
            $ManifestDirectoryName
    }

    if (-not (Test-PathSafe $ManifestDirectory)) {

        New-Item `
            -ItemType Directory `
            -Path $ManifestDirectory `
            -Force |
            Out-Null
    }
}

Initialize-Directories

# ============================================================
# NOTIFICATIONS
# ============================================================

function Show-Notification {

    param(
        [string]$Title,
        [string]$Message
    )

    if (-not (Get-ConfigValue $Global:Config.Notifications "Enabled" $true)) {
        return
    }

    try {

        # Windows PowerShell 5.1 has no guaranteed built-in
        # toast API. Use the console bell as a universal fallback.

        [console]::beep(800, 120)

        Write-Log "$Title - $Message" "INFO"
    }
    catch {
        # Notifications are optional
    }
}

# ============================================================
# DRIVE DETECTION
# ============================================================

function Get-RemovableDrives {

    try {

        $Drives = Get-CimInstance `
            Win32_LogicalDisk `
            -Filter "DriveType=2"

        return @(
            $Drives |
            Where-Object {

                $DriveLetter = $_.DeviceID

                $DriveLetter -and
                (Test-PathSafe ($DriveLetter + "\"))
            }
        )
    }
    catch {

        Write-Log `
            "Unable to query removable drives: $($_.Exception.Message)" `
            "WARNING"

        return @()
    }
}

# ============================================================
# CARD NAME
# ============================================================

function Get-CardLabel {

    param(
        [string]$DriveRoot
    )

    try {

        $Letter = $DriveRoot.TrimEnd('\')

        $Disk = Get-CimInstance `
            Win32_LogicalDisk `
            -Filter "DeviceID='$Letter'"

        if ($Disk.VolumeName) {
            return $Disk.VolumeName
        }
    }
    catch {
    }

    return $DriveRoot.TrimEnd('\')
}

# ============================================================
# FILE TYPE DETECTION
# ============================================================

function Is-PhotoFile {

    param(
        [System.IO.FileInfo]$File
    )

    $Extension = $File.Extension.ToUpperInvariant()

    foreach ($Allowed in $Global:Config.FileTypes.Photos) {

        if ($Extension -eq $Allowed.ToUpperInvariant()) {
            return $true
        }
    }

    return $false
}

function Is-MLVMainFile {

    param(
        [System.IO.FileInfo]$File
    )

    return (
        $File.Extension.ToUpperInvariant() -eq ".MLV"
    )
}

function Is-MLVChunkFile {

    param(
        [System.IO.FileInfo]$File
    )

    $Settings = $Global:Config.FileTypes.MLVChunks

    if (-not (Get-ConfigValue $Settings "Enabled" $true)) {
        return $false
    }

    $Pattern = Get-ConfigValue `
        $Settings `
        "Pattern" `
        "^\.M[0-9]{2}$"

    return (
        $File.Extension.ToUpperInvariant() -match $Pattern
    )
}

function Is-MLVFile {

    param(
        [System.IO.FileInfo]$File
    )

    return (
        (Is-MLVMainFile $File) -or
        (Is-MLVChunkFile $File)
    )
}

# ============================================================
# CAMERA CARD DETECTION
# ============================================================

function Test-CameraCard {

    param(
        [string]$DriveRoot
    )

    $MinimumFiles = [int](
        Get-ConfigValue `
            $Global:Config.Scanning `
            "MinimumCameraFiles" `
            1
    )

    $CameraFileCount = 0

    try {

        $AllFiles = Get-ChildItem `
            -LiteralPath $DriveRoot `
            -File `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        foreach ($File in $AllFiles) {

            if (Is-PhotoFile $File) {

                $CameraFileCount++
            }
            elseif (Is-MLVFile $File) {

                $CameraFileCount++
            }

            if ($CameraFileCount -ge $MinimumFiles) {

                return $true
            }
        }
    }
    catch {

        Write-Log `
            "Camera-card scan failed for $DriveRoot : $($_.Exception.Message)" `
            "WARNING"
    }

    return $false
}

# ============================================================
# SAFE FILE ENUMERATION
# ============================================================

function Get-MediaFiles {

    param(
        [string]$DriveRoot
    )

    $IgnoreFolders = @(
        Get-ConfigValue `
            $Global:Config.Scanning `
            "IgnoreFolders" `
            @()
    )

    $ScanSubfolders = Get-ConfigValue `
        $Global:Config.Scanning `
        "ScanSubfolders" `
        $true

    try {

        if ($ScanSubfolders) {

            $Files = Get-ChildItem `
                -LiteralPath $DriveRoot `
                -File `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
        else {

            $Files = Get-ChildItem `
                -LiteralPath $DriveRoot `
                -File `
                -Force `
                -ErrorAction SilentlyContinue
        }

        foreach ($File in $Files) {

            $Ignore = $false

            foreach ($Folder in $IgnoreFolders) {

                if (
                    $File.FullName -match
                    [regex]::Escape($Folder)
                ) {

                    $Ignore = $true
                    break
                }
            }

            if ($Ignore) {
                continue
            }

            if (
                (Is-PhotoFile $File) -or
                (Is-MLVFile $File)
            ) {

                $File
            }
        }
    }
    catch {

        Write-Log `
            "Media scan failed: $($_.Exception.Message)" `
            "ERROR"
    }
}

# ============================================================
# RELATIVE PATH
# ============================================================

function Get-RelativePath {

    param(
        [string]$Root,
        [string]$FullPath
    )

    $Root = $Root.TrimEnd('\') + '\'

    if (
        $FullPath.StartsWith(
            $Root,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {

        return $FullPath.Substring($Root.Length)
    }

    return Split-Path `
        -Leaf `
        -Path $FullPath
}

# ============================================================
# DESTINATION ORGANIZATION
# ============================================================

function Get-DestinationPath {

    param(
        [System.IO.FileInfo]$SourceFile,
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [string]$CardLabel
    )

    $Mode = Get-ConfigValue `
        $Global:Config.Organization `
        "Mode" `
        "PreserveSourceFolders"

    $Relative = Get-RelativePath `
        -Root $SourceRoot `
        -FullPath $SourceFile.FullName

    switch ($Mode) {

        "PreserveSourceFolders" {

            return Join-Path `
                $DestinationRoot `
                $Relative
        }

        "ByCard" {

            return Join-Path `
                (Join-Path $DestinationRoot $CardLabel) `
                $Relative
        }

        "ByDate" {

            $DateFolder = $SourceFile.LastWriteTime.ToString(
                (Get-ConfigValue `
                    $Global:Config.Organization `
                    "DateFormat" `
                    "yyyy-MM-dd")
            )

            return Join-Path `
                (Join-Path $DestinationRoot $DateFolder) `
                $SourceFile.Name
        }

        "ByDateAndCard" {

            $DateFolder = $SourceFile.LastWriteTime.ToString(
                (Get-ConfigValue `
                    $Global:Config.Organization `
                    "DateFormat" `
                    "yyyy-MM-dd")
            )

            return Join-Path `
                (Join-Path `
                    (Join-Path $DestinationRoot $DateFolder) `
                    $CardLabel) `
                $SourceFile.Name
        }

        default {

            return Join-Path `
                $DestinationRoot `
                $Relative
        }
    }
}

# ============================================================
# FILE STABILITY
# ============================================================

function Test-FileStable {

    param(
        [string]$Path
    )

    if (-not (Get-ConfigValue $Global:Config.Stability "Enabled" $true)) {
        return $true
    }

    $Checks = [int](
        Get-ConfigValue `
            $Global:Config.Stability `
            "Checks" `
            2
    )

    $Delay = [int](
        Get-ConfigValue `
            $Global:Config.Stability `
            "DelaySeconds" `
            3
    )

    $PreviousLength = -1
    $StableCount = 0

    while ($StableCount -lt $Checks) {

        if (-not (Test-PathSafe $Path)) {
            return $false
        }

        try {

            $Info = Get-Item `
                -LiteralPath $Path `
                -Force

            $Length = $Info.Length
        }
        catch {

            return $false
        }

        if ($Length -eq $PreviousLength) {

            $StableCount++
        }
        else {

            $StableCount = 0
        }

        $PreviousLength = $Length

        if ($StableCount -lt $Checks) {

            Start-Sleep -Seconds $Delay
        }
    }

    return $true
}

# ============================================================
# HASH
# ============================================================

function Get-FileSHA256 {

    param(
        [string]$Path
    )

    try {

        return (
            Get-FileHash `
                -LiteralPath $Path `
                -Algorithm SHA256
        ).Hash.ToUpperInvariant()
    }
    catch {

        Write-Log `
            "SHA256 failed: $Path : $($_.Exception.Message)" `
            "ERROR"

        return $null
    }
}

# ============================================================
# VERIFY
# ============================================================

function Verify-Copy {

    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-PathSafe $Destination)) {

        Write-Log `
            "Verification failed: destination missing: $Destination" `
            "ERROR"

        return $false
    }

    try {

        $SourceInfo = Get-Item `
            -LiteralPath $Source `
            -Force

        $DestinationInfo = Get-Item `
            -LiteralPath $Destination `
            -Force

        if ($SourceInfo.Length -ne $DestinationInfo.Length) {

            Write-Log `
                "Verification failed: size mismatch: $Destination" `
                "ERROR"

            return $false
        }

        $Method = Get-ConfigValue `
            $Global:Config.Verification `
            "Method" `
            "Size"

        if (
            -not (Get-ConfigValue `
                $Global:Config.Verification `
                "Enabled" `
                $true)
        ) {

            return $true
        }

        if ($Method -eq "None") {

            return $true
        }

        if ($Method -eq "Size") {

            return $true
        }

        if ($Method -eq "SHA256") {

            Write-Log `
                "SHA256 verification: $Destination" `
                "DEBUG"

            $SourceHash = Get-FileSHA256 $Source
            $DestinationHash = Get-FileSHA256 $Destination

            if (
                $null -eq $SourceHash -or
                $null -eq $DestinationHash
            ) {

                return $false
            }

            if ($SourceHash -ne $DestinationHash) {

                Write-Log `
                    "SHA256 mismatch: $Destination" `
                    "ERROR"

                return $false
            }

            return $true
        }

        return $true
    }
    catch {

        Write-Log `
            "Verification error: $($_.Exception.Message)" `
            "ERROR"

        return $false
    }
}

# ============================================================
# MANIFEST
# ============================================================

function Get-ManifestDirectory {

    $Configured = Get-ConfigValue `
        $Global:Config.Manifest `
        "Directory" `
        "manifests"

    return Resolve-ConfiguredPath $Configured
}

function Get-ManifestPath {

    param(
        [string]$DriveRoot
    )

    $SafeName = $DriveRoot `
        -replace '[\\/:*?"<>|]', '_' `
        -replace '_+$', ''

    if ([string]::IsNullOrWhiteSpace($SafeName)) {
        $SafeName = "drive"
    }

    return Join-Path `
        (Get-ManifestDirectory) `
        ($SafeName + ".json")
}

function Load-Manifest {

    param(
        [string]$DriveRoot
    )

    if (
        -not (Get-ConfigValue `
            $Global:Config.Manifest `
            "Enabled" `
            $true)
    ) {

        return @{}
    }

    $Path = Get-ManifestPath $DriveRoot

    if (-not (Test-PathSafe $Path)) {

        return @{}
    }

    try {

        $Raw = Get-Content `
            -LiteralPath $Path `
            -Raw `
            -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return @{}
        }

        $Object = $Raw | ConvertFrom-Json

        $Manifest = @{}

        foreach ($Property in $Object.PSObject.Properties) {

            $Manifest[$Property.Name] = $Property.Value
        }

        return $Manifest
    }
    catch {

        Write-Log `
            "Manifest could not be loaded: $Path" `
            "WARNING"

        return @{}
    }
}

function Save-Manifest {

    param(
        [string]$DriveRoot,
        [hashtable]$Manifest
    )

    if (
        -not (Get-ConfigValue `
            $Global:Config.Manifest `
            "Enabled" `
            $true)
    ) {

        return
    }

    try {

        $Path = Get-ManifestPath $DriveRoot

        $Manifest |
            ConvertTo-Json -Depth 10 |
            Set-Content `
                -LiteralPath $Path `
                -Encoding UTF8
    }
    catch {

        Write-Log `
            "Could not save manifest: $($_.Exception.Message)" `
            "WARNING"
    }
}

# ============================================================
# FILE ID
# ============================================================

function Get-FileIdentity {

    param(
        [System.IO.FileInfo]$File
    )

    return "{0}|{1}|{2}" -f `
        $File.Name.ToUpperInvariant(),
        $File.Length,
        $File.LastWriteTimeUtc.Ticks
}

# ============================================================
# SAFE COPY
# ============================================================

function Copy-MediaFile {

    param(
        [System.IO.FileInfo]$SourceFile,
        [string]$Destination,
        [hashtable]$Manifest,
        [string]$SourceRoot
    )

    $DryRun = Get-ConfigValue `
        $Global:Config.Safety `
        "DryRun" `
        $false

    $Identity = Get-FileIdentity $SourceFile

    # --------------------------------------------------------
    # Manifest duplicate check
    # --------------------------------------------------------

    if ($Manifest.ContainsKey($Identity)) {

        $PreviousDestination = [string]$Manifest[$Identity]

        if (
            $PreviousDestination -and
            (Test-PathSafe $PreviousDestination)
        ) {

            Write-Log `
                "MANIFEST SKIP: $($SourceFile.Name)" `
                "DEBUG"

            return "Skipped"
        }
    }

    # --------------------------------------------------------
    # Existing destination
    # --------------------------------------------------------

    if (Test-PathSafe $Destination) {

        $Existing = Get-Item `
            -LiteralPath $Destination `
            -Force

        if (
            (Get-ConfigValue `
                $Global:Config.Copy `
                "SkipExistingSameSize" `
                $true) -and
            ($Existing.Length -eq $SourceFile.Length)
        ) {

            Write-Log `
                "SKIP existing: $Destination" `
                "INFO"

            $Manifest[$Identity] = $Destination

            return "Skipped"
        }

        if (-not (
            Get-ConfigValue `
                $Global:Config.Copy `
                "ReplaceDifferentSize" `
                $false
        )) {

            Write-Log `
                "CONFLICT - destination exists with different size: $Destination" `
                "WARNING"

            return "Conflict"
        }
    }

    # --------------------------------------------------------
    # Dry run
    # --------------------------------------------------------

    if ($DryRun) {

        Write-Log `
            "DRY RUN: $($SourceFile.FullName) -> $Destination" `
            "INFO"

        return "DryRun"
    }

    # --------------------------------------------------------
    # Check source stability
    # --------------------------------------------------------

    if (-not (Test-FileStable $SourceFile.FullName)) {

        Write-Log `
            "Source file is not stable: $($SourceFile.FullName)" `
            "WARNING"

        return "Failed"
    }

    # --------------------------------------------------------
    # Ensure destination directory
    # --------------------------------------------------------

    $DestinationDirectory = Split-Path `
        $Destination `
        -Parent

    if (-not (Test-PathSafe $DestinationDirectory)) {

        New-Item `
            -ItemType Directory `
            -Path $DestinationDirectory `
            -Force |
            Out-Null
    }

    # --------------------------------------------------------
    # Temporary destination
    # --------------------------------------------------------

    $UseTemporary = Get-ConfigValue `
        $Global:Config.Copy `
        "UseTemporaryFiles" `
        $true

    $TempExtension = Get-ConfigValue `
        $Global:Config.Copy `
        "TemporaryExtension" `
        ".importing"

    if ($UseTemporary) {

        $TemporaryDestination = `
            $Destination + $TempExtension

        # Remove stale temp file
        if (Test-PathSafe $TemporaryDestination) {

            try {
                Remove-Item `
                    -LiteralPath $TemporaryDestination `
                    -Force
            }
            catch {
            }
        }
    }
    else {

        $TemporaryDestination = $Destination
    }

    # --------------------------------------------------------
    # Copy with retries
    # --------------------------------------------------------

    $Retries = [int](
        Get-ConfigValue `
            $Global:Config.Copy `
            "Retries" `
            3
    )

    $RetryDelay = [int](
        Get-ConfigValue `
            $Global:Config.Copy `
            "RetryDelaySeconds" `
            3
    )

    for ($Attempt = 1; $Attempt -le $Retries; $Attempt++) {

        try {

            Write-Log `
                "COPY [$Attempt/$Retries]: $($SourceFile.FullName)" `
                "INFO"

            Copy-Item `
                -LiteralPath $SourceFile.FullName `
                -Destination $TemporaryDestination `
                -Force

            # Verify before rename
            if (-not (
                Verify-Copy `
                    -Source $SourceFile.FullName `
                    -Destination $TemporaryDestination
            )) {

                throw "Verification failed."
            }

            # ------------------------------------------------
            # Atomic-ish finalization
            # ------------------------------------------------

            if ($UseTemporary) {

                if (Test-PathSafe $Destination) {

                    Remove-Item `
                        -LiteralPath $Destination `
                        -Force
                }

                Move-Item `
                    -LiteralPath $TemporaryDestination `
                    -Destination $Destination `
                    -Force
            }

            Write-Log `
                "SUCCESS: $Destination" `
                "SUCCESS"

            $Manifest[$Identity] = $Destination

            return "Copied"
        }
        catch {

            Write-Log `
                "Copy attempt $Attempt failed: $($_.Exception.Message)" `
                "WARNING"

            if ($Attempt -lt $Retries) {

                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    Write-Log `
        "FAILED: $($SourceFile.FullName)" `
        "ERROR"

    return "Failed"
}

# ============================================================
# EJECT
# ============================================================

function Eject-Drive {

    param(
        [string]$DriveRoot
    )

    $Delay = [int](
        Get-ConfigValue `
            $Global:Config.Card `
            "EjectDelaySeconds" `
            2
    )

    Start-Sleep -Seconds $Delay

    try {

        $DriveLetter = $DriveRoot.TrimEnd('\')

        $Shell = New-Object -ComObject Shell.Application

        $Drive = $Shell.Namespace(17).ParseName($DriveLetter)

        if ($null -eq $Drive) {

            Write-Log `
                "Could not obtain eject object for $DriveLetter" `
                "WARNING"

            return
        }

        $Drive.InvokeVerb("Eject")

        Write-Log `
            "Eject command sent: $DriveLetter" `
            "SUCCESS"
    }
    catch {

        Write-Log `
            "Eject failed: $($_.Exception.Message)" `
            "WARNING"
    }
}

# ============================================================
# IMPORT CARD
# ============================================================

function Import-Card {

    param(
        [string]$DriveRoot
    )

    Write-Log ""
    Write-Log "============================================================"
    Write-Log "CARD DETECTED: $DriveRoot"
    Write-Log "============================================================"

    $CardLabel = Get-CardLabel $DriveRoot

    Write-Log "Card label: $CardLabel"

    $MountSettle = [int](
        Get-ConfigValue `
            $Global:Config.Monitoring `
            "MountSettleSeconds" `
            3
    )

    Start-Sleep -Seconds $MountSettle

    if (-not (Test-PathSafe $DriveRoot)) {

        Write-Log `
            "Card disappeared during mount initialization." `
            "WARNING"

        return
    }

    if (-not (Test-CameraCard $DriveRoot)) {

        Write-Log `
            "Not recognized as a camera card: $DriveRoot" `
            "INFO"

        return
    }

    Show-Notification `
        "Camera card detected" `
        "$CardLabel is ready for import."

    # --------------------------------------------------------
    # Scan
    # --------------------------------------------------------

    Write-Log "Scanning media files..."

    $MediaFiles = @(
        Get-MediaFiles $DriveRoot
    )

    $Photos = @(
        $MediaFiles |
        Where-Object {
            Is-PhotoFile $_
        }
    )

    $MLVFiles = @(
        $MediaFiles |
        Where-Object {
            Is-MLVFile $_
        }
    )

    Write-Log "Photos found: $($Photos.Count)"
    Write-Log "MLV/span files found: $($MLVFiles.Count)"

    # --------------------------------------------------------
    # Manifest
    # --------------------------------------------------------

    $Manifest = Load-Manifest $DriveRoot

    # --------------------------------------------------------
    # Counters
    # --------------------------------------------------------

    $Stats = @{
        Copied = 0
        Skipped = 0
        Failed = 0
        Conflict = 0
        DryRun = 0
        Photos = 0
        MLV = 0
    }

    # --------------------------------------------------------
    # PHOTO IMPORT
    # --------------------------------------------------------

    foreach ($Photo in $Photos) {

        if (-not (Test-PathSafe $DriveRoot)) {

            Write-Log `
                "CARD REMOVED DURING PHOTO IMPORT!" `
                "ERROR"

            return
        }

        $Destination = Get-DestinationPath `
            -SourceFile $Photo `
            -SourceRoot $DriveRoot `
            -DestinationRoot (
                Resolve-ConfiguredPath `
                    $Global:Config.Destinations.Photos
            ) `
            -CardLabel $CardLabel

        $Result = Copy-MediaFile `
            -SourceFile $Photo `
            -Destination $Destination `
            -Manifest $Manifest `
            -SourceRoot $DriveRoot

        switch ($Result) {

            "Copied" {
                $Stats.Copied++
                $Stats.Photos++
            }

            "Skipped" {
                $Stats.Skipped++
                $Stats.Photos++
            }

            "Failed" {
                $Stats.Failed++
            }

            "Conflict" {
                $Stats.Conflict++
            }

            "DryRun" {
                $Stats.DryRun++
                $Stats.Photos++
            }
        }

        # Save manifest periodically
        if (
            ($Stats.Copied % 10) -eq 0 -and
            $Stats.Copied -gt 0
        ) {

            Save-Manifest `
                -DriveRoot $DriveRoot `
                -Manifest $Manifest
        }
    }

    # --------------------------------------------------------
    # MLV IMPORT
    #
    # Sequential intentionally:
    # large MLV files can be hundreds of GB and memory/storage
    # bandwidth is generally the bottleneck.
    # --------------------------------------------------------

    foreach ($MLV in $MLVFiles) {

        if (-not (Test-PathSafe $DriveRoot)) {

            Write-Log `
                "CARD REMOVED DURING MLV IMPORT!" `
                "ERROR"

            return
        }

        $Destination = Get-DestinationPath `
            -SourceFile $MLV `
            -SourceRoot $DriveRoot `
            -DestinationRoot (
                Resolve-ConfiguredPath `
                    $Global:Config.Destinations.MLV
            ) `
            -CardLabel $CardLabel

        $Result = Copy-MediaFile `
            -SourceFile $MLV `
            -Destination $Destination `
            -Manifest $Manifest `
            -SourceRoot $DriveRoot

        switch ($Result) {

            "Copied" {
                $Stats.Copied++
                $Stats.MLV++
            }

            "Skipped" {
                $Stats.Skipped++
                $Stats.MLV++
            }

            "Failed" {
                $Stats.Failed++
            }

            "Conflict" {
                $Stats.Conflict++
            }

            "DryRun" {
                $Stats.DryRun++
                $Stats.MLV++
            }
        }

        Save-Manifest `
            -DriveRoot $DriveRoot `
            -Manifest $Manifest
    }

    # --------------------------------------------------------
    # Final manifest save
    # --------------------------------------------------------

    Save-Manifest `
        -DriveRoot $DriveRoot `
        -Manifest $Manifest

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

    Write-Log ""
    Write-Log "IMPORT FINISHED: $CardLabel"
    Write-Log "  Copied:    $($Stats.Copied)"
    Write-Log "  Skipped:   $($Stats.Skipped)"
    Write-Log "  Failed:    $($Stats.Failed)"
    Write-Log "  Conflicts: $($Stats.Conflict)"
    Write-Log "  Dry run:   $($Stats.DryRun)"
    Write-Log "  Photos:    $($Stats.Photos)"
    Write-Log "  MLV:       $($Stats.MLV)"
    Write-Log ""

    if ($Stats.Failed -gt 0 -or $Stats.Conflict -gt 0) {

        Show-Notification `
            "Import finished with problems" `
            "$CardLabel - failed: $($Stats.Failed), conflicts: $($Stats.Conflict)"
    }
    else {

        Show-Notification `
            "Import complete" `
            "$CardLabel - copied: $($Stats.Copied), skipped: $($Stats.Skipped)"
    }

    # --------------------------------------------------------
    # Optional eject
    # --------------------------------------------------------

    if (
        (Get-ConfigValue `
            $Global:Config.Card `
            "AutoEject" `
            $false) -and
        (Test-PathSafe $DriveRoot)
    ) {

        Eject-Drive $DriveRoot
    }
}

# ============================================================
# MAIN
# ============================================================

Write-Log ""
Write-Log "============================================================"
Write-Log "Magic Lantern MLV Importer"
Write-Log "============================================================"
Write-Log "Script: $ScriptRoot"
Write-Log "Photos: $($Global:Config.Destinations.Photos)"
Write-Log "MLV:    $($Global:Config.Destinations.MLV)"
Write-Log "Dry run: $($Global:Config.Safety.DryRun)"
Write-Log "============================================================"
Write-Log ""

$KnownDrives = @{}

# ------------------------------------------------------------
# Detect drives already connected when program starts
#
# We deliberately mark them as known instead of immediately
# importing them. This prevents accidental re-import every time
# the application starts.
# ------------------------------------------------------------

foreach ($Drive in Get-RemovableDrives) {

    $Root = $Drive.DeviceID + "\"

    $KnownDrives[$Root] = $true

    Write-Log "Existing removable drive: $Root" "DEBUG"
}

Write-Log "Waiting for SD/CF cards..."
Write-Log "Press CTRL+C to stop."
Write-Log ""

# ------------------------------------------------------------
# Infinite monitoring loop
# ------------------------------------------------------------

while ($true) {

    try {

        $CurrentDrives = @{}

        foreach ($Drive in Get-RemovableDrives) {

            $Root = $Drive.DeviceID + "\"

            $CurrentDrives[$Root] = $true

            if (-not $KnownDrives.ContainsKey($Root)) {

                try {

                    Import-Card $Root
                }
                catch {

                    Write-Log `
                        "Unhandled import error: $($_.Exception.Message)" `
                        "ERROR"

                    if (
                        Get-ConfigValue `
                            $Global:Config.Notifications `
                            "OnError" `
                            $true
                    ) {

                        Show-Notification `
                            "MLV Importer error" `
                            $_.Exception.Message
                    }
                }
            }
        }

        $KnownDrives = $CurrentDrives

        Start-Sleep -Seconds (
            [int](
                Get-ConfigValue `
                    $Global:Config.Monitoring `
                    "PollIntervalSeconds" `
                    2
            )
        )
    }
    catch {

        Write-Log `
            "Main monitoring loop error: $($_.Exception.Message)" `
            "ERROR"

        Start-Sleep -Seconds 5
    }
}