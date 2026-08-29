#requires -version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

$ConfigPath = Join-Path $ScriptRoot "config.json"
$ImporterPath = Join-Path $ScriptRoot "MLV-Importer.ps1"

# ============================================================
# CONFIG HELPER
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
# LOAD CONFIG
# ============================================================

function Load-Config {

    try {

        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "config.json not found:`n$ConfigPath"
        }

        return (
            Get-Content `
                -LiteralPath $ConfigPath `
                -Raw `
                -Encoding UTF8 |
            ConvertFrom-Json
        )
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Configuration Error",
            "OK",
            "Error"
        )

        exit 1
    }
}

$Config = Load-Config

# ============================================================
# SAVE
# ============================================================

function Save-Config {

    try {

        $PhotoExtensions = @(
            $txtPhotoExtensions.Text `
                -split '[,;\s]+' |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            ForEach-Object {

                $Ext = $_.Trim()

                if ($Ext.StartsWith(".")) {
                    $Ext.ToUpperInvariant()
                }
                else {
                    "." + $Ext.ToUpperInvariant()
                }
            }
        )

        if ($PhotoExtensions.Count -eq 0) {
            throw "At least one photo extension is required."
        }

        if ([string]::IsNullOrWhiteSpace($txtPhotos.Text)) {
            throw "Photos destination cannot be empty."
        }

        if ([string]::IsNullOrWhiteSpace($txtMLV.Text)) {
            throw "MLV destination cannot be empty."
        }

        $NewConfig = [ordered]@{

            Version = 4

            Destinations = [ordered]@{
                Photos = $txtPhotos.Text.Trim()
                MLV = $txtMLV.Text.Trim()
            }

            Organization = [ordered]@{
                Mode = [string]$cmbOrganization.SelectedItem
                DateFormat = $txtDateFormat.Text.Trim()
            }

            FileTypes = [ordered]@{

                Photos = $PhotoExtensions

                MLVMain = @(
                    ".MLV"
                )

                MLVChunks = [ordered]@{
                    Enabled = $chkMLVChunks.Checked
                    Pattern = "^\.M[0-9]{2}$"
                }
            }

            Scanning = [ordered]@{

                ScanSubfolders = $chkScanSubfolders.Checked

                IgnoreFolders = @(
                    "System Volume Information",
                    '$RECYCLE.BIN'
                )

                MinimumCameraFiles = 1
            }

            Copy = [ordered]@{

                SkipExistingSameSize = $chkSkipExisting.Checked

                ReplaceDifferentSize = $chkReplaceDifferent.Checked

                UseTemporaryFiles = $chkTemporary.Checked

                TemporaryExtension = ".importing"

                Retries = [int]$numRetries.Value

                RetryDelaySeconds = [int]$numRetryDelay.Value
            }

            Verification = [ordered]@{

                Enabled = $chkVerification.Checked

                Method = [string]$cmbVerification.SelectedItem
            }

            Stability = [ordered]@{

                Enabled = $chkStability.Checked

                Checks = 2

                DelaySeconds = 2
            }

            Monitoring = [ordered]@{

                PollIntervalSeconds = 2

                MountSettleSeconds = 3
            }

            Card = [ordered]@{

                OnlyRemovableDrives = $true

                AutoEject = $chkAutoEject.Checked

                EjectDelaySeconds = 2

                DeleteSourceAfterImport = $chkDeleteSource.Checked

                RequireDeleteConfirmation = $true
            }

            Safety = [ordered]@{

                DryRun = $chkDryRun.Checked

                NeverDeleteUnlessVerified = $true

                NeverMoveSource = $true
            }

            Manifest = [ordered]@{

                Enabled = $chkManifest.Checked

                Directory = "manifests"
            }

            Logging = [ordered]@{

                Enabled = $chkLogging.Checked

                Directory = "logs"

                FileName = "importer.log"

                KeepDays = 30
            }

            Notifications = [ordered]@{

                Enabled = $chkNotifications.Checked

                OnCardDetected = $true

                OnImportComplete = $true

                OnError = $true
            }
        }

        $Json = $NewConfig |
            ConvertTo-Json -Depth 10

        Set-Content `
            -LiteralPath $ConfigPath `
            -Value $Json `
            -Encoding UTF8

        return $true
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            "Could not save configuration.`n`n$($_.Exception.Message)",
            "Save Error",
            "OK",
            "Error"
        )

        return $false
    }
}

# ============================================================
# BROWSE
# ============================================================

function Browse-Folder {
    param(
        [System.Windows.Forms.TextBox]$TextBox
    )

    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog

    $Dialog.Description = "Select destination folder"

    if (
        -not [string]::IsNullOrWhiteSpace($TextBox.Text) -and
        (Test-Path -LiteralPath $TextBox.Text)
    ) {
        $Dialog.SelectedPath = $TextBox.Text
    }

    if ($Dialog.ShowDialog() -eq "OK") {
        $TextBox.Text = $Dialog.SelectedPath
    }

    $Dialog.Dispose()
}

# ============================================================
# TEST
# ============================================================

function Test-Configuration {

    $Problems = @()

    if ([string]::IsNullOrWhiteSpace($txtPhotos.Text)) {
        $Problems += "Photos destination is empty."
    }

    if ([string]::IsNullOrWhiteSpace($txtMLV.Text)) {
        $Problems += "MLV destination is empty."
    }

    if (
        -not [string]::IsNullOrWhiteSpace($txtPhotos.Text) -and
        -not [System.IO.Path]::IsPathFullyQualified($txtPhotos.Text)
    ) {
        $Problems += "Photos destination must be a full path."
    }

    if (
        -not [string]::IsNullOrWhiteSpace($txtMLV.Text) -and
        -not [System.IO.Path]::IsPathFullyQualified($txtMLV.Text)
    ) {
        $Problems += "MLV destination must be a full path."
    }

    if ($Problems.Count -eq 0) {

        $DeleteStatus = if ($chkDeleteSource.Checked) {
            "ENABLED"
        }
        else {
            "Disabled"
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Configuration looks good.`n`n" +
            "Photos:`n$($txtPhotos.Text)`n`n" +
            "MLV:`n$($txtMLV.Text)`n`n" +
            "Delete from card: $DeleteStatus`n`n" +
            "Verification: $($cmbVerification.SelectedItem)",
            "Configuration OK",
            "OK",
            "Information"
        )

        return
    }

    [System.Windows.Forms.MessageBox]::Show(
        ($Problems -join "`n"),
        "Configuration Problems",
        "OK",
        "Warning"
    )
}

# ============================================================
# START IMPORTER
# ============================================================

function Start-Importer {

    if (-not (Save-Config)) {
        return
    }

    if (-not (Test-Path -LiteralPath $ImporterPath)) {

        [System.Windows.Forms.MessageBox]::Show(
            "MLV-Importer.ps1 was not found:`n`n$ImporterPath",
            "Importer Not Found",
            "OK",
            "Error"
        )

        return
    }

    try {

        Start-Process `
            powershell.exe `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "`"$ImporterPath`""
            )

        $Form.Close()
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            "Could not start importer.`n`n$($_.Exception.Message)",
            "Start Error",
            "OK",
            "Error"
        )
    }
}

# ============================================================
# FORM
# ============================================================

$Form = New-Object System.Windows.Forms.Form

$Form.Text = "Magic Lantern Importer"

$Form.StartPosition = "CenterScreen"

$Form.ClientSize = New-Object System.Drawing.Size(720, 735)

$Form.FormBorderStyle = "FixedDialog"

$Form.MaximizeBox = $false

# ============================================================
# TITLE
# ============================================================

$lblTitle = New-Object System.Windows.Forms.Label

$lblTitle.Text = "Magic Lantern Importer"

$lblTitle.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    18,
    [System.Drawing.FontStyle]::Bold
)

$lblTitle.Location = New-Object System.Drawing.Point(25, 18)

$lblTitle.Size = New-Object System.Drawing.Size(600, 35)

$Form.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label

$lblSubtitle.Text = "Automatic SD / CF photo and MLV importer"

$lblSubtitle.ForeColor = [System.Drawing.Color]::DimGray

$lblSubtitle.Location = New-Object System.Drawing.Point(28, 53)

$lblSubtitle.Size = New-Object System.Drawing.Size(600, 25)

$Form.Controls.Add($lblSubtitle)

# ============================================================
# DESTINATIONS
# ============================================================

$grpDestinations = New-Object System.Windows.Forms.GroupBox

$grpDestinations.Text = "Destinations"

$grpDestinations.Location = New-Object System.Drawing.Point(20, 85)

$grpDestinations.Size = New-Object System.Drawing.Size(680, 125)

$Form.Controls.Add($grpDestinations)

$lblPhotos = New-Object System.Windows.Forms.Label
$lblPhotos.Text = "Photos:"
$lblPhotos.Location = New-Object System.Drawing.Point(15, 30)
$lblPhotos.Size = New-Object System.Drawing.Size(70, 25)
$grpDestinations.Controls.Add($lblPhotos)

$txtPhotos = New-Object System.Windows.Forms.TextBox
$txtPhotos.Location = New-Object System.Drawing.Point(85, 27)
$txtPhotos.Size = New-Object System.Drawing.Size(500, 25)

$txtPhotos.Text = Get-ConfigValue `
    $Config.Destinations `
    "Photos" `
    "D:\Camera Import\Photos"

$grpDestinations.Controls.Add($txtPhotos)

$btnPhotos = New-Object System.Windows.Forms.Button
$btnPhotos.Text = "Browse..."
$btnPhotos.Location = New-Object System.Drawing.Point(590, 26)
$btnPhotos.Size = New-Object System.Drawing.Size(75, 27)

$btnPhotos.Add_Click({
    Browse-Folder $txtPhotos
})

$grpDestinations.Controls.Add($btnPhotos)

$lblMLV = New-Object System.Windows.Forms.Label
$lblMLV.Text = "MLV:"
$lblMLV.Location = New-Object System.Drawing.Point(15, 72)
$lblMLV.Size = New-Object System.Drawing.Size(70, 25)
$grpDestinations.Controls.Add($lblMLV)

$txtMLV = New-Object System.Windows.Forms.TextBox
$txtMLV.Location = New-Object System.Drawing.Point(85, 69)
$txtMLV.Size = New-Object System.Drawing.Size(500, 25)

$txtMLV.Text = Get-ConfigValue `
    $Config.Destinations `
    "MLV" `
    "D:\Camera Import\MLV"

$grpDestinations.Controls.Add($txtMLV)

$btnMLV = New-Object System.Windows.Forms.Button
$btnMLV.Text = "Browse..."
$btnMLV.Location = New-Object System.Drawing.Point(590, 68)
$btnMLV.Size = New-Object System.Drawing.Size(75, 27)

$btnMLV.Add_Click({
    Browse-Folder $txtMLV
})

$grpDestinations.Controls.Add($btnMLV)

# ============================================================
# ORGANIZATION
# ============================================================

$grpOrganization = New-Object System.Windows.Forms.GroupBox

$grpOrganization.Text = "Organization"

$grpOrganization.Location = New-Object System.Drawing.Point(20, 220)

$grpOrganization.Size = New-Object System.Drawing.Size(680, 80)

$Form.Controls.Add($grpOrganization)

$lblOrganization = New-Object System.Windows.Forms.Label
$lblOrganization.Text = "Folder mode:"
$lblOrganization.Location = New-Object System.Drawing.Point(15, 30)
$lblOrganization.Size = New-Object System.Drawing.Size(90, 25)
$grpOrganization.Controls.Add($lblOrganization)

$cmbOrganization = New-Object System.Windows.Forms.ComboBox
$cmbOrganization.Location = New-Object System.Drawing.Point(110, 27)
$cmbOrganization.Size = New-Object System.Drawing.Size(190, 25)
$cmbOrganization.DropDownStyle = "DropDownList"

[void]$cmbOrganization.Items.Add("Flat")
[void]$cmbOrganization.Items.Add("ByDate")

$Mode = Get-ConfigValue `
    $Config.Organization `
    "Mode" `
    "Flat"

if ($cmbOrganization.Items.Contains($Mode)) {
    $cmbOrganization.SelectedItem = $Mode
}
else {
    $cmbOrganization.SelectedItem = "Flat"
}

$grpOrganization.Controls.Add($cmbOrganization)

$lblDateFormat = New-Object System.Windows.Forms.Label
$lblDateFormat.Text = "Date format:"
$lblDateFormat.Location = New-Object System.Drawing.Point(350, 30)
$lblDateFormat.Size = New-Object System.Drawing.Size(80, 25)
$grpOrganization.Controls.Add($lblDateFormat)

$txtDateFormat = New-Object System.Windows.Forms.TextBox
$txtDateFormat.Location = New-Object System.Drawing.Point(435, 27)
$txtDateFormat.Size = New-Object System.Drawing.Size(180, 25)

$txtDateFormat.Text = Get-ConfigValue `
    $Config.Organization `
    "DateFormat" `
    "yyyy-MM-dd"

$grpOrganization.Controls.Add($txtDateFormat)

# ============================================================
# FILE TYPES
# ============================================================

$grpFiles = New-Object System.Windows.Forms.GroupBox

$grpFiles.Text = "File Types"

$grpFiles.Location = New-Object System.Drawing.Point(20, 310)

$grpFiles.Size = New-Object System.Drawing.Size(680, 105)

$Form.Controls.Add($grpFiles)

$lblExtensions = New-Object System.Windows.Forms.Label
$lblExtensions.Text = "Photo extensions:"
$lblExtensions.Location = New-Object System.Drawing.Point(15, 30)
$lblExtensions.Size = New-Object System.Drawing.Size(115, 25)
$grpFiles.Controls.Add($lblExtensions)

$txtPhotoExtensions = New-Object System.Windows.Forms.TextBox
$txtPhotoExtensions.Location = New-Object System.Drawing.Point(135, 27)
$txtPhotoExtensions.Size = New-Object System.Drawing.Size(515, 25)

$txtPhotoExtensions.Text = (
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
    ) -join ", "
)

$grpFiles.Controls.Add($txtPhotoExtensions)

$chkMLVChunks = New-Object System.Windows.Forms.CheckBox

$chkMLVChunks.Text = "Import MLV split files (.M00, .M01, .M02...)"

$chkMLVChunks.Location = New-Object System.Drawing.Point(135, 62)

$chkMLVChunks.Size = New-Object System.Drawing.Size(400, 25)

$chkMLVChunks.Checked = Get-ConfigValue `
    $Config.FileTypes.MLVChunks `
    "Enabled" `
    $true

$grpFiles.Controls.Add($chkMLVChunks)

# ============================================================
# IMPORT OPTIONS
# ============================================================

$grpImport = New-Object System.Windows.Forms.GroupBox

$grpImport.Text = "Import Options"

$grpImport.Location = New-Object System.Drawing.Point(20, 425)

$grpImport.Size = New-Object System.Drawing.Size(680, 170)

$Form.Controls.Add($grpImport)

$chkScanSubfolders = New-Object System.Windows.Forms.CheckBox
$chkScanSubfolders.Text = "Scan subfolders"
$chkScanSubfolders.Location = New-Object System.Drawing.Point(15, 25)
$chkScanSubfolders.Size = New-Object System.Drawing.Size(200, 25)

$chkScanSubfolders.Checked = Get-ConfigValue `
    $Config.Scanning `
    "ScanSubfolders" `
    $true

$grpImport.Controls.Add($chkScanSubfolders)

$chkSkipExisting = New-Object System.Windows.Forms.CheckBox
$chkSkipExisting.Text = "Skip same-size existing files"
$chkSkipExisting.Location = New-Object System.Drawing.Point(15, 52)
$chkSkipExisting.Size = New-Object System.Drawing.Size(230, 25)

$chkSkipExisting.Checked = Get-ConfigValue `
    $Config.Copy `
    "SkipExistingSameSize" `
    $true

$grpImport.Controls.Add($chkSkipExisting)

$chkReplaceDifferent = New-Object System.Windows.Forms.CheckBox
$chkReplaceDifferent.Text = "Replace different-size files"
$chkReplaceDifferent.Location = New-Object System.Drawing.Point(15, 79)
$chkReplaceDifferent.Size = New-Object System.Drawing.Size(230, 25)

$chkReplaceDifferent.Checked = Get-ConfigValue `
    $Config.Copy `
    "ReplaceDifferentSize" `
    $false

$grpImport.Controls.Add($chkReplaceDifferent)

$chkTemporary = New-Object System.Windows.Forms.CheckBox
$chkTemporary.Text = "Use temporary copy files"
$chkTemporary.Location = New-Object System.Drawing.Point(15, 106)
$chkTemporary.Size = New-Object System.Drawing.Size(230, 25)

$chkTemporary.Checked = Get-ConfigValue `
    $Config.Copy `
    "UseTemporaryFiles" `
    $true

$grpImport.Controls.Add($chkTemporary)

$chkStability = New-Object System.Windows.Forms.CheckBox
$chkStability.Text = "Wait for stable files"
$chkStability.Location = New-Object System.Drawing.Point(15, 133)
$chkStability.Size = New-Object System.Drawing.Size(230, 25)

$chkStability.Checked = Get-ConfigValue `
    $Config.Stability `
    "Enabled" `
    $true

$grpImport.Controls.Add($chkStability)

$lblRetries = New-Object System.Windows.Forms.Label
$lblRetries.Text = "Retries:"
$lblRetries.Location = New-Object System.Drawing.Point(300, 25)
$lblRetries.Size = New-Object System.Drawing.Size(60, 25)
$grpImport.Controls.Add($lblRetries)

$numRetries = New-Object System.Windows.Forms.NumericUpDown
$numRetries.Location = New-Object System.Drawing.Point(360, 23)
$numRetries.Size = New-Object System.Drawing.Size(65, 25)
$numRetries.Minimum = 1
$numRetries.Maximum = 20

$numRetries.Value = [decimal](
    Get-ConfigValue `
        $Config.Copy `
        "Retries" `
        3
)

$grpImport.Controls.Add($numRetries)

$lblRetryDelay = New-Object System.Windows.Forms.Label
$lblRetryDelay.Text = "Delay:"
$lblRetryDelay.Location = New-Object System.Drawing.Point(450, 25)
$lblRetryDelay.Size = New-Object System.Drawing.Size(50, 25)
$grpImport.Controls.Add($lblRetryDelay)

$numRetryDelay = New-Object System.Windows.Forms.NumericUpDown
$numRetryDelay.Location = New-Object System.Drawing.Point(500, 23)
$numRetryDelay.Size = New-Object System.Drawing.Size(65, 25)
$numRetryDelay.Minimum = 0
$numRetryDelay.Maximum = 60

$numRetryDelay.Value = [decimal](
    Get-ConfigValue `
        $Config.Copy `
        "RetryDelaySeconds" `
        3
)

$grpImport.Controls.Add($numRetryDelay)

$lblVerification = New-Object System.Windows.Forms.Label
$lblVerification.Text = "Verification:"
$lblVerification.Location = New-Object System.Drawing.Point(300, 58)
$lblVerification.Size = New-Object System.Drawing.Size(75, 25)
$grpImport.Controls.Add($lblVerification)

$cmbVerification = New-Object System.Windows.Forms.ComboBox
$cmbVerification.Location = New-Object System.Drawing.Point(380, 55)
$cmbVerification.Size = New-Object System.Drawing.Size(185, 25)
$cmbVerification.DropDownStyle = "DropDownList"

[void]$cmbVerification.Items.Add("None")
[void]$cmbVerification.Items.Add("Size")
[void]$cmbVerification.Items.Add("SHA256")

$VerificationMethod = Get-ConfigValue `
    $Config.Verification `
    "Method" `
    "Size"

if ($cmbVerification.Items.Contains($VerificationMethod)) {
    $cmbVerification.SelectedItem = $VerificationMethod
}
else {
    $cmbVerification.SelectedItem = "Size"
}

$grpImport.Controls.Add($cmbVerification)

$chkVerification = New-Object System.Windows.Forms.CheckBox
$chkVerification.Text = "Enable verification"
$chkVerification.Location = New-Object System.Drawing.Point(380, 85)
$chkVerification.Size = New-Object System.Drawing.Size(180, 25)

$chkVerification.Checked = Get-ConfigValue `
    $Config.Verification `
    "Enabled" `
    $true

$grpImport.Controls.Add($chkVerification)

# ============================================================
# SOURCE CARD
# ============================================================

$grpCard = New-Object System.Windows.Forms.GroupBox

$grpCard.Text = "Source Card"

$grpCard.Location = New-Object System.Drawing.Point(20, 605)

$grpCard.Size = New-Object System.Drawing.Size(680, 75)

$Form.Controls.Add($grpCard)

$chkDeleteSource = New-Object System.Windows.Forms.CheckBox

$chkDeleteSource.Text = "Delete files from card after successful verified import"

$chkDeleteSource.Location = New-Object System.Drawing.Point(15, 18)

$chkDeleteSource.Size = New-Object System.Drawing.Size(470, 25)

$chkDeleteSource.Checked = Get-ConfigValue `
    $Config.Card `
    "DeleteSourceAfterImport" `
    $false

$grpCard.Controls.Add($chkDeleteSource)

$chkAutoEject = New-Object System.Windows.Forms.CheckBox

$chkAutoEject.Text = "Eject card"

$chkAutoEject.Location = New-Object System.Drawing.Point(500, 18)

$chkAutoEject.Size = New-Object System.Drawing.Size(120, 25)

$chkAutoEject.Checked = Get-ConfigValue `
    $Config.Card `
    "AutoEject" `
    $false

$grpCard.Controls.Add($chkAutoEject)

$lblDeleteWarning = New-Object System.Windows.Forms.Label

$lblDeleteWarning.Text = "Deletion is OFF by default. MLV split sets are deleted only after the entire set succeeds."

$lblDeleteWarning.ForeColor = [System.Drawing.Color]::DarkRed

$lblDeleteWarning.Location = New-Object System.Drawing.Point(15, 44)

$lblDeleteWarning.Size = New-Object System.Drawing.Size(640, 20)

$grpCard.Controls.Add($lblDeleteWarning)

# ============================================================
# HIDDEN SETTINGS
# ============================================================

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Checked = Get-ConfigValue $Config.Safety "DryRun" $false

$chkManifest = New-Object System.Windows.Forms.CheckBox
$chkManifest.Checked = Get-ConfigValue $Config.Manifest "Enabled" $true

$chkLogging = New-Object System.Windows.Forms.CheckBox
$chkLogging.Checked = Get-ConfigValue $Config.Logging "Enabled" $true

$chkNotifications = New-Object System.Windows.Forms.CheckBox
$chkNotifications.Checked = Get-ConfigValue $Config.Notifications "Enabled" $true

# ============================================================
# BUTTONS
# ============================================================

$btnTest = New-Object System.Windows.Forms.Button

$btnTest.Text = "Test"

$btnTest.Location = New-Object System.Drawing.Point(270, 700)

$btnTest.Size = New-Object System.Drawing.Size(80, 32)

$btnTest.Add_Click({
    Test-Configuration
})

$Form.Controls.Add($btnTest)

$btnSave = New-Object System.Windows.Forms.Button

$btnSave.Text = "Save"

$btnSave.Location = New-Object System.Drawing.Point(360, 700)

$btnSave.Size = New-Object System.Drawing.Size(80, 32)

$btnSave.Add_Click({

    if (Save-Config) {

        [System.Windows.Forms.MessageBox]::Show(
            "Configuration saved.",
            "Saved",
            "OK",
            "Information"
        )
    }
})

$Form.Controls.Add($btnSave)

$btnStart = New-Object System.Windows.Forms.Button

$btnStart.Text = "Save && Start"

$btnStart.Location = New-Object System.Drawing.Point(450, 700)

$btnStart.Size = New-Object System.Drawing.Size(105, 32)

$btnStart.Add_Click({
    Start-Importer
})

$Form.Controls.Add($btnStart)

$btnClose = New-Object System.Windows.Forms.Button

$btnClose.Text = "Close"

$btnClose.Location = New-Object System.Drawing.Point(565, 700)

$btnClose.Size = New-Object System.Drawing.Size(80, 32)

$btnClose.Add_Click({
    $Form.Close()
})

$Form.Controls.Add($btnClose)

$Form.AcceptButton = $btnSave
$Form.CancelButton = $btnClose

# ============================================================
# SHOW
# ============================================================

[void]$Form.ShowDialog()