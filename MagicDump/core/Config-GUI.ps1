#requires -version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot "config.json"

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    [System.Windows.Forms.MessageBox]::Show("config.json not found at $ConfigPath", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Magic Lantern Importer - Full Configuration GUI"
$Form.Size = New-Object System.Drawing.Size(560, 560)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$Form.MaximizeBox = $false

$TabControl = New-Object System.Windows.Forms.TabControl
$TabControl.Location = New-Object System.Drawing.Point(12, 12)
$TabControl.Size = New-Object System.Drawing.Size(520, 440)
$Form.Controls.Add($TabControl)

function New-Tab {
    param($Title)
    $Tab = New-Object System.Windows.Forms.TabPage
    $Tab.Text = $Title
    $Tab.AutoScroll = $true
    $TabControl.Controls.Add($Tab)
    return $Tab
}

function Add-Field {
    param($Tab, $Text, $InitialValue, [ref]$YRef, [string]$Type = "Text", [array]$Options = $null)
    
    $CurrentY = [int]$YRef.Value

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Text
    $Label.Location = New-Object System.Drawing.Point(15, $CurrentY)
    $Label.Size = New-Object System.Drawing.Size(220, 20)
    $Tab.Controls.Add($Label)

    if ($Type -eq "Check") {
        $Control = New-Object System.Windows.Forms.CheckBox
        $Control.Checked = [bool]$InitialValue
        $Control.Location = New-Object System.Drawing.Point(245, $CurrentY)
        $Control.Size = New-Object System.Drawing.Size(240, 20)
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 32
        return $Control
    }
    elseif ($Type -eq "Combo") {
        $Control = New-Object System.Windows.Forms.ComboBox
        $Control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $Control.Location = New-Object System.Drawing.Point(245, ($CurrentY - 3))
        $Control.Size = New-Object System.Drawing.Size(240, 21)
        if ($null -ne $Options) {
            foreach ($Opt in $Options) { [void]$Control.Items.Add($Opt) }
        }
        $Control.SelectedItem = [string]$InitialValue
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 32
        return $Control
    }
    else {
        $Control = New-Object System.Windows.Forms.TextBox
        $Control.Text = [string]$InitialValue
        $Control.Location = New-Object System.Drawing.Point(245, ($CurrentY - 3))
        $Control.Size = New-Object System.Drawing.Size(240, 20)
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 32
        return $Control
    }
}

# --- TAB 1: Destinations & Organization ---
$Tab1 = New-Tab "Destinations"
$Y1 = [ref][int]20
$TxtPhotos = Add-Field $Tab1 "Photos Destination:" $Config.Destinations.Photos $Y1
$TxtMLV = Add-Field $Tab1 "MLV Destination:" $Config.Destinations.MLV $Y1
$CmbOrgMode = Add-Field $Tab1 "Organization Mode:" $Config.Organization.Mode $Y1 "Combo" $Config.Organization.AvailableModes
$TxtDateFormat = Add-Field $Tab1 "Date Format:" $Config.Organization.DateFormat $Y1

# --- TAB 2: Card & Safety ---
$Tab2 = New-Tab "Card & Safety"
$Y2 = [ref][int]20
$ChkOnlyRemovable = Add-Field $Tab2 "Only Removable Drives:" $Config.Card.OnlyRemovableDrives $Y2 "Check"
$ChkAutoEject = Add-Field $Tab2 "Auto Eject Drive:" $Config.Card.AutoEject $Y2 "Check"
$ChkDeleteSource = Add-Field $Tab2 "Delete Source After Import:" $Config.Card.DeleteSourceAfterImport $Y2 "Check"
$ChkRequireDelConf = Add-Field $Tab2 "Require Delete Confirmation:" $Config.Card.RequireDeleteConfirmation $Y2 "Check"
$ChkDryRun = Add-Field $Tab2 "Dry Run (Simulate Only):" $Config.Safety.DryRun $Y2 "Check"
$ChkNeverDelUnver = Add-Field $Tab2 "Never Delete Unless Verified:" $Config.Safety.NeverDeleteUnlessVerified $Y2 "Check"
$ChkNeverMove = Add-Field $Tab2 "Never Move Source:" $Config.Safety.NeverMoveSource $Y2 "Check"

# --- TAB 3: Copy & Verification ---
$Tab3 = New-Tab "Copy & Verification"
$Y3 = [ref][int]20
$ChkSkipExist = Add-Field $Tab3 "Skip Existing Same Size:" $Config.Copy.SkipExistingSameSize $Y3 "Check"
$ChkReplaceDiff = Add-Field $Tab3 "Replace Different Size:" $Config.Copy.ReplaceDifferentSize $Y3 "Check"
$ChkUseTemp = Add-Field $Tab3 "Use Temporary Files (.importing):" $Config.Copy.UseTemporaryFiles $Y3 "Check"
$TxtRetries = Add-Field $Tab3 "Retries:" $Config.Copy.Retries $Y3
$TxtRetryDelay = Add-Field $Tab3 "Retry Delay Seconds:" $Config.Copy.RetryDelaySeconds $Y3
$ChkVerEnabled = Add-Field $Tab3 "Verification Enabled:" $Config.Verification.Enabled $Y3 "Check"
$CmbVerMethod = Add-Field $Tab3 "Verification Method:" $Config.Verification.Method $Y3 "Combo" $Config.Verification.AvailableMethods

# --- TAB 4: Scanning, Stability & Monitoring ---
$Tab4 = New-Tab "Scanning & Stability"
$Y4 = [ref][int]20
$ChkScanSub = Add-Field $Tab4 "Scan Subfolders:" $Config.Scanning.ScanSubfolders $Y4 "Check"
$TxtMinFiles = Add-Field $Tab4 "Minimum Camera Files:" $Config.Scanning.MinimumCameraFiles $Y4
$ChkStabEnabled = Add-Field $Tab4 "Stability Check Enabled:" $Config.Stability.Enabled $Y4 "Check"
$TxtStabChecks = Add-Field $Tab4 "Stability Checks Count:" $Config.Stability.Checks $Y4
$TxtStabDelay = Add-Field $Tab4 "Stability Delay Seconds:" $Config.Stability.DelaySeconds $Y4
$TxtPollInterval = Add-Field $Tab4 "Poll Interval Seconds:" $Config.Monitoring.PollIntervalSeconds $Y4
$TxtMountSettle = Add-Field $Tab4 "Mount Settle Seconds:" $Config.Monitoring.MountSettleSeconds $Y4

# --- TAB 5: Advanced & MLVFS ---
$Tab5 = New-Tab "Advanced & MLVFS"
$Y5 = [ref][int]20
$ChkManifest = Add-Field $Tab5 "Manifest Enabled:" $Config.Manifest.Enabled $Y5 "Check"
$TxtManifestDir = Add-Field $Tab5 "Manifest Directory:" $Config.Manifest.Directory $Y5
$ChkLogging = Add-Field $Tab5 "Logging Enabled:" $Config.Logging.Enabled $Y5 "Check"
$TxtLogDir = Add-Field $Tab5 "Log Directory:" $Config.Logging.Directory $Y5
$TxtLogFile = Add-Field $Tab5 "Log File Name:" $Config.Logging.FileName $Y5
$ChkMLVFS = Add-Field $Tab5 "MLVFS Enabled:" $Config.MLVFS.Enabled $Y5 "Check"
$TxtControllerPath = Add-Field $Tab5 "MLVFS Controller Path:" $Config.MLVFS.ControllerPath $Y5
$TxtDriveLetter = Add-Field $Tab5 "MLVFS Drive Letter:" $Config.MLVFS.DriveLetter $Y5

# --- Save Button ---
$BtnSave = New-Object System.Windows.Forms.Button
$BtnSave.Text = "Save All Settings"
$BtnSave.Location = New-Object System.Drawing.Point(210, 465)
$BtnSave.Size = New-Object System.Drawing.Size(130, 35)
$BtnSave.Add_Click({
    # Destinations & Org
    $Config.Destinations.Photos = $TxtPhotos.Text
    $Config.Destinations.MLV = $TxtMLV.Text
    $Config.Organization.Mode = $CmbOrgMode.SelectedItem
    $Config.Organization.DateFormat = $TxtDateFormat.Text

    # Card & Safety
    $Config.Card.OnlyRemovableDrives = $ChkOnlyRemovable.Checked
    $Config.Card.AutoEject = $ChkAutoEject.Checked
    $Config.Card.DeleteSourceAfterImport = $ChkDeleteSource.Checked
    $Config.Card.RequireDeleteConfirmation = $ChkRequireDelConf.Checked
    $Config.Safety.DryRun = $ChkDryRun.Checked
    $Config.Safety.NeverDeleteUnlessVerified = $ChkNeverDelUnver.Checked
    $Config.Safety.NeverMoveSource = $ChkNeverMove.Checked

    # Copy & Verification
    $Config.Copy.SkipExistingSameSize = $ChkSkipExist.Checked
    $Config.Copy.ReplaceDifferentSize = $ChkReplaceDiff.Checked
    $Config.Copy.UseTemporaryFiles = $ChkUseTemp.Checked
    $Config.Copy.Retries = [int]$TxtRetries.Text
    $Config.Copy.RetryDelaySeconds = [int]$TxtRetryDelay.Text
    $Config.Verification.Enabled = $ChkVerEnabled.Checked
    $Config.Verification.Method = $CmbVerMethod.SelectedItem

    # Scanning, Stability & Monitoring
    $Config.Scanning.ScanSubfolders = $ChkScanSub.Checked
    $Config.Scanning.MinimumCameraFiles = [int]$TxtMinFiles.Text
    $Config.Stability.Enabled = $ChkStabEnabled.Checked
    $Config.Stability.Checks = [int]$TxtStabChecks.Text
    $Config.Stability.DelaySeconds = [int]$TxtStabDelay.Text
    $Config.Monitoring.PollIntervalSeconds = [int]$TxtPollInterval.Text
    $Config.Monitoring.MountSettleSeconds = [int]$TxtMountSettle.Text

    # Advanced & MLVFS
    $Config.Manifest.Enabled = $ChkManifest.Checked
    $Config.Manifest.Directory = $TxtManifestDir.Text
    $Config.Logging.Enabled = $ChkLogging.Checked
    $Config.Logging.Directory = $TxtLogDir.Text
    $Config.Logging.FileName = $TxtLogFile.Text
    $Config.MLVFS.Enabled = $ChkMLVFS.Checked
    $Config.MLVFS.ControllerPath = $TxtControllerPath.Text
    $Config.MLVFS.DriveLetter = $TxtDriveLetter.Text

    # Save to JSON preserving deep structure
    $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("All configuration settings saved successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $Form.Close()
})
$Form.Controls.Add($BtnSave)

[void]$Form.ShowDialog()