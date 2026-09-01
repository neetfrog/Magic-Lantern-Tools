#requires -version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot "config.json"

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    [System.Windows.Forms.MessageBox]::Show("config.json not found at $ConfigPath", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Dark Theme Color Palette (VS Code Dark+ inspired)
$DarkBg      = [System.Drawing.Color]::FromArgb(30, 30, 30)
$PanelBg     = [System.Drawing.Color]::FromArgb(37, 37, 38)
$ControlBg   = [System.Drawing.Color]::FromArgb(51, 51, 51)
$TextColor   = [System.Drawing.Color]::FromArgb(240, 240, 240)
$SubText     = [System.Drawing.Color]::FromArgb(160, 160, 160)
$AccentColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$AccentHover = [System.Drawing.Color]::FromArgb(28, 151, 234)
$BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 64)
$SuccessColor= [System.Drawing.Color]::FromArgb(78, 201, 176)

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "MagicDump Configuration"
$Form.Size = New-Object System.Drawing.Size(760, 640)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$Form.MaximizeBox = $false
$Form.BackColor = $DarkBg
$Form.ForeColor = $TextColor

# Main Layout Container (Split into Sidebar Navigation & Content Panel)
$Sidebar = New-Object System.Windows.Forms.Panel
$Sidebar.Location = New-Object System.Drawing.Point(0, 0)
$Sidebar.Size = New-Object System.Drawing.Size(180, 640)
$Sidebar.BackColor = [System.Drawing.Color]::FromArgb(33, 33, 33)
$Form.Controls.Add($Sidebar)

$ContentPanel = New-Object System.Windows.Forms.Panel
$ContentPanel.Location = New-Object System.Drawing.Point(180, 0)
$ContentPanel.Size = New-Object System.Drawing.Size(564, 600)
$ContentPanel.BackColor = $DarkBg
$Form.Controls.Add($ContentPanel)

# Header Title in Content Area
$LblHeader = New-Object System.Windows.Forms.Label
$LblHeader.Text = "Configuration Dashboard"
$LblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$LblHeader.ForeColor = $TextColor
$LblHeader.Location = New-Object System.Drawing.Point(24, 20)
$LblHeader.Size = New-Object System.Drawing.Size(450, 30)
$ContentPanel.Controls.Add($LblHeader)

$LblSubheader = New-Object System.Windows.Forms.Label
$LblSubheader.Text = "Manage import routes, verification behaviors, and tool integrations."
$LblSubheader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$LblSubheader.ForeColor = $SubText
$LblSubheader.Location = New-Object System.Drawing.Point(25, 48)
$LblSubheader.Size = New-Object System.Drawing.Size(500, 20)
$ContentPanel.Controls.Add($LblSubheader)

# Card Container for Settings Forms
$CardPanel = New-Object System.Windows.Forms.Panel
$CardPanel.Location = New-Object System.Drawing.Point(24, 80)
$CardPanel.Size = New-Object System.Drawing.Size(516, 435)
$CardPanel.BackColor = $PanelBg
$CardPanel.AutoScroll = $true
$ContentPanel.Controls.Add($CardPanel)

# Pages Dictionary to hold sections
$Pages = @{}

function New-SettingsPage {
    param($Name, $Title)
    $Page = New-Object System.Windows.Forms.Panel
    $Page.Dock = [System.Windows.Forms.DockStyle]::Fill
    $Page.BackColor = $PanelBg
    $Page.Visible = $false
    $Page.AutoScroll = $true
    $CardPanel.Controls.Add($Page)
    $Pages[$Name] = @{ Panel = $Page; Title = $Title }
    return $Page
}

function Show-SettingsPage {
    param($Name)
    foreach ($Key in $Pages.Keys) {
        $Pages[$Key].Panel.Visible = ($Key -eq $Name)
    }
    $LblHeader.Text = $Pages[$Name].Title
}

function Add-Field {
    param($Tab, $Text, $InitialValue, [ref]$YRef, [string]$Type = "Text", [array]$Options = $null)
    
    $CurrentY = [int]$YRef.Value

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Text
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Label.ForeColor = $TextColor
    $Label.Location = New-Object System.Drawing.Point(20, ($CurrentY + 3))
    $Label.Size = New-Object System.Drawing.Size(200, 20)
    $Tab.Controls.Add($Label)

    if ($Type -eq "Check") {
        $Control = New-Object System.Windows.Forms.CheckBox
        $Control.Checked = [bool]$InitialValue
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.ForeColor = $TextColor
        $Control.Location = New-Object System.Drawing.Point(235, $CurrentY)
        $Control.Size = New-Object System.Drawing.Size(245, 22)
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 36
        return $Control
    }
    elseif ($Type -eq "Combo") {
        $Control = New-Object System.Windows.Forms.ComboBox
        $Control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.BackColor = $ControlBg
        $Control.ForeColor = $TextColor
        $Control.Location = New-Object System.Drawing.Point(235, $CurrentY)
        $Control.Size = New-Object System.Drawing.Size(245, 25)
        if ($null -ne $Options) {
            foreach ($Opt in $Options) { [void]$Control.Items.Add($Opt) }
        }
        $Control.SelectedItem = [string]$InitialValue
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 36
        return $Control
    }
    elseif ($Type -eq "Browse") {
        $Control = New-Object System.Windows.Forms.TextBox
        $Control.Text = [string]$InitialValue
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.BackColor = $ControlBg
        $Control.ForeColor = $TextColor
        $Control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $Control.Location = New-Object System.Drawing.Point(235, $CurrentY)
        $Control.Size = New-Object System.Drawing.Size(165, 23)
        $Tab.Controls.Add($Control)

        $BtnBrowse = New-Object System.Windows.Forms.Button
        $BtnBrowse.Text = "Browse"
        $BtnBrowse.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $BtnBrowse.BackColor = $ControlBg
        $BtnBrowse.ForeColor = $TextColor
        $BtnBrowse.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $BtnBrowse.Location = New-Object System.Drawing.Point(406, ($CurrentY - 1))
        $BtnBrowse.Size = New-Object System.Drawing.Size(74, 25)
        $BtnBrowse.Tag = $Control
        $BtnBrowse.Add_Click({
            $Browser = New-Object System.Windows.Forms.FolderBrowserDialog
            $Browser.Description = "Select Folder Destination"
            if ($Browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $this.Tag.Text = $Browser.SelectedPath
            }
        })
        $Tab.Controls.Add($BtnBrowse)

        $YRef.Value = $CurrentY + 36
        return $Control
    }
    else {
        $Control = New-Object System.Windows.Forms.TextBox
        $Control.Text = [string]$InitialValue
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.BackColor = $ControlBg
        $Control.ForeColor = $TextColor
        $Control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $Control.Location = New-Object System.Drawing.Point(235, $CurrentY)
        $Control.Size = New-Object System.Drawing.Size(245, 23)
        $Tab.Controls.Add($Control)
        $YRef.Value = $CurrentY + 36
        return $Control
    }
}

# --- BUILD PAGES ---

# 1. Destinations
$Page1 = New-SettingsPage "Destinations" "Storage & Organization"
$Y1 = [ref][int]20
$TxtPhotos = Add-Field $Page1 "Photos Destination" $Config.Destinations.Photos $Y1 "Browse"
$TxtMLV = Add-Field $Page1 "MLV Destination" $Config.Destinations.MLV $Y1 "Browse"
$InitialPhotoMode = if ($Config.Organization.PhotoMode) { $Config.Organization.PhotoMode } else { $Config.Organization.Mode }
$InitialMLVMode = if ($Config.Organization.MLVMode) { $Config.Organization.MLVMode } else { "Flat" }
$CmbPhotoMode = Add-Field $Page1 "Photo Org Mode" $InitialPhotoMode $Y1 "Combo" $Config.Organization.AvailableModes
$CmbMLVMode = Add-Field $Page1 "MLV Org Mode" $InitialMLVMode $Y1 "Combo" $Config.Organization.AvailableModes
$TxtDateFormat = Add-Field $Page1 "Date Format" $Config.Organization.DateFormat $Y1

# 2. Card & Safety
$Page2 = New-SettingsPage "Safety" "Card & Safety Rules"
$Y2 = [ref][int]20
$ChkOnlyRemovable = Add-Field $Page2 "Only Removable Drives" $Config.Card.OnlyRemovableDrives $Y2 "Check"
$ChkAutoEject = Add-Field $Page2 "Auto Eject Drive" $Config.Card.AutoEject $Y2 "Check"
$ChkDeleteSource = Add-Field $Page2 "Delete Source After Import" $Config.Card.DeleteSourceAfterImport $Y2 "Check"
$ChkRequireDelConf = Add-Field $Page2 "Require Delete Confirm" $Config.Card.RequireDeleteConfirmation $Y2 "Check"
$ChkDryRun = Add-Field $Page2 "Dry Run (Simulate Only)" $Config.Safety.DryRun $Y2 "Check"
$ChkNeverDelUnver = Add-Field $Page2 "Never Delete Unverified" $Config.Safety.NeverDeleteUnlessVerified $Y2 "Check"
$ChkNeverMove = Add-Field $Page2 "Never Move Source" $Config.Safety.NeverMoveSource $Y2 "Check"

# 3. Copy & Verification
$Page3 = New-SettingsPage "Copy" "Copy & Verification Settings"
$Y3 = [ref][int]20
$ChkSkipExist = Add-Field $Page3 "Skip Existing Same Size" $Config.Copy.SkipExistingSameSize $Y3 "Check"
$ChkReplaceDiff = Add-Field $Page3 "Replace Different Size" $Config.Copy.ReplaceDifferentSize $Y3 "Check"
$ChkUseTemp = Add-Field $Page3 "Use Temp Files (.importing)" $Config.Copy.UseTemporaryFiles $Y3 "Check"
$TxtRetries = Add-Field $Page3 "Transfer Retries" $Config.Copy.Retries $Y3
$TxtRetryDelay = Add-Field $Page3 "Retry Delay Seconds" $Config.Copy.RetryDelaySeconds $Y3
$ChkVerEnabled = Add-Field $Page3 "Verification Enabled" $Config.Verification.Enabled $Y3 "Check"
$CmbVerMethod = Add-Field $Page3 "Verification Method" $Config.Verification.Method $Y3 "Combo" $Config.Verification.AvailableMethods

# 4. Scanning & Stability
$Page4 = New-SettingsPage "Scanning" "Scanning & Polling Parameters"
$Y4 = [ref][int]20
$ChkScanSub = Add-Field $Page4 "Scan Subfolders" $Config.Scanning.ScanSubfolders $Y4 "Check"
$TxtMinFiles = Add-Field $Page4 "Minimum Camera Files" $Config.Scanning.MinimumCameraFiles $Y4
$ChkStabEnabled = Add-Field $Page4 "Stability Check Enabled" $Config.Stability.Enabled $Y4 "Check"
$TxtStabChecks = Add-Field $Page4 "Stability Checks Count" $Config.Stability.Checks $Y4
$TxtStabDelay = Add-Field $Page4 "Stability Delay Secs" $Config.Stability.DelaySeconds $Y4
$TxtPollInterval = Add-Field $Page4 "Poll Interval Secs" $Config.Monitoring.PollIntervalSeconds $Y4
$TxtMountSettle = Add-Field $Page4 "Mount Settle Secs" $Config.Monitoring.MountSettleSeconds $Y4

# 5. Advanced & Tools
$Page5 = New-SettingsPage "Advanced" "Advanced & MLV Tools Integration"
$Y5 = [ref][int]20
$ChkManifest = Add-Field $Page5 "Manifest Enabled" $Config.Manifest.Enabled $Y5 "Check"
$TxtManifestDir = Add-Field $Page5 "Manifest Directory" $Config.Manifest.Directory $Y5
$ChkLogging = Add-Field $Page5 "Logging Enabled" $Config.Logging.Enabled $Y5 "Check"
$TxtLogDir = Add-Field $Page5 "Log Directory" $Config.Logging.Directory $Y5
$TxtLogFile = Add-Field $Page5 "Log File Name" $Config.Logging.FileName $Y5
$ChkMLVFS = Add-Field $Page5 "MLVFS Enabled" $Config.MLVFS.Enabled $Y5 "Check"
$TxtControllerPath = Add-Field $Page5 "MLVFS Controller Path" $Config.MLVFS.ControllerPath $Y5
$TxtDriveLetter = Add-Field $Page5 "MLVFS Drive Letter" $Config.MLVFS.DriveLetter $Y5
$ChkMLVApp = Add-Field $Page5 "MLVApp Enabled" $Config.MLVApp.Enabled $Y5 "Check"
$TxtMLVAppPath = Add-Field $Page5 "MLVApp Executable Path" $Config.MLVApp.ExecutablePath $Y5


# --- SIDEBAR NAVIGATION BUTTONS ---

$NavButtons = @()

function Add-NavButton {
    param($Name, $Text, $YPos)
    $Btn = New-Object System.Windows.Forms.Button
    $Btn.Text = "  $Text"
    $Btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $Btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $Btn.BackColor = [System.Drawing.Color]::FromArgb(33, 33, 33)
    $Btn.ForeColor = $TextColor
    $Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Btn.FlatAppearance.BorderSize = 0
    $Btn.Location = New-Object System.Drawing.Point(0, $YPos)
    $Btn.Size = New-Object System.Drawing.Size(180, 42)
    $Btn.Tag = $Name
    $Btn.Add_Click({
        foreach ($B in $NavButtons) {
            $B.BackColor = [System.Drawing.Color]::FromArgb(33, 33, 33)
            $B.ForeColor = $TextColor
        }
        $this.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
        $this.ForeColor = $AccentColor
        Show-SettingsPage $this.Tag
    })
    $Sidebar.Controls.Add($Btn)
    $script:NavButtons += $Btn
    return $Btn
}

# Sidebar Branding Header
$BrandLabel = New-Object System.Windows.Forms.Label
$BrandLabel.Text = "MagicDump"
$BrandLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$BrandLabel.ForeColor = $AccentColor
$BrandLabel.Location = New-Object System.Drawing.Point(16, 20)
$BrandLabel.Size = New-Object System.Drawing.Size(150, 25)
$Sidebar.Controls.Add($BrandLabel)

$BrandSub = New-Object System.Windows.Forms.Label
$BrandSub.Text = "Settings"
$BrandSub.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$BrandSub.ForeColor = $SubText
$BrandSub.Location = New-Object System.Drawing.Point(17, 42)
$BrandSub.Size = New-Object System.Drawing.Size(150, 20)
$Sidebar.Controls.Add($BrandSub)

$Separator = New-Object System.Windows.Forms.Panel
$Separator.Location = New-Object System.Drawing.Point(16, 75)
$Separator.Size = New-Object System.Drawing.Size(148, 1)
$Separator.BackColor = $BorderColor
$Sidebar.Controls.Add($Separator)

# Add Navigation Items
$BtnNav1 = Add-NavButton "Destinations" "Storage Routes" 90
$BtnNav2 = Add-NavButton "Safety" "Card & Safety" 134
$BtnNav3 = Add-NavButton "Copy" "Copy & Verify" 178
$BtnNav4 = Add-NavButton "Scanning" "Scanning & Timing" 222
$BtnNav5 = Add-NavButton "Advanced" "Advanced & Tools" 266


# --- FOOTER ACTION BUTTONS ---

$BtnReset = New-Object System.Windows.Forms.Button
$BtnReset.Text = "Reset Defaults"
$BtnReset.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BtnReset.BackColor = $ControlBg
$BtnReset.ForeColor = $TextColor
$BtnReset.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$BtnReset.FlatAppearance.BorderColor = $BorderColor
$BtnReset.Location = New-Object System.Drawing.Point(24, 532)
$BtnReset.Size = New-Object System.Drawing.Size(120, 36)
$BtnReset.Add_Click({
    $Confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to reset all fields to their default state?", "Confirm Reset", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($Confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $DefaultConfig = [PSCustomObject]@{
            "Version"      = 4
            "Destinations" = [PSCustomObject]@{
                "Photos" = "C:\MagicDump\Photos"
                "MLV"    = "C:\MagicDump\MLVs"
            }
            "Organization" = [PSCustomObject]@{
                "Mode"           = "Flat"
                "AvailableModes" = @("ByDate", "Flat")
                "DateFormat"     = "yyyy-MM-dd"
                "MLVMode"        = "ByDate"
                "PhotoMode"      = "ByDate"
            }
            "FileTypes"    = [PSCustomObject]@{
                "Photos"    = @(".CR2", ".CR3", ".JPG", ".JPEG", ".JPE", ".PNG", ".TIF", ".TIFF")
                "MLVMain"   = @(".MLV")
                "MLVChunks" = [PSCustomObject]@{
                    "Enabled" = $true
                    "Pattern" = "^\.M[0-9]+$"
                }
            }
            "Scanning"     = [PSCustomObject]@{
                "ScanSubfolders"     = $true
                "IgnoreFolders"      = @("System Volume Information", "`$RECYCLE.BIN")
                "MinimumCameraFiles" = 1
            }
            "Copy"         = [PSCustomObject]@{
                "SkipExistingSameSize" = $true
                "ReplaceDifferentSize" = $false
                "UseTemporaryFiles"    = $false
                "TemporaryExtension"   = ".importing"
                "Retries"              = 1
                "RetryDelaySeconds"    = 1
            }
            "Verification" = [PSCustomObject]@{
                "Enabled"          = $false
                "Method"           = "None"
                "AvailableMethods" = @("None", "Size", "SHA256")
            }
            "Stability"    = [PSCustomObject]@{
                "Enabled"      = $false
                "Checks"       = 1
                "DelaySeconds" = 1
            }
            "Monitoring"   = [PSCustomObject]@{
                "PollIntervalSeconds" = 1
                "MountSettleSeconds"  = 1
            }
            "Card"         = [PSCustomObject]@{
                "OnlyRemovableDrives"       = $true
                "AutoEject"                 = $true
                "EjectDelaySeconds"         = 2
                "DeleteSourceAfterImport"   = $false
                "RequireDeleteConfirmation" = $false
            }
            "Safety"       = [PSCustomObject]@{
                "DryRun"                    = $false
                "NeverDeleteUnlessVerified" = $false
                "NeverMoveSource"           = $true
            }
            "Manifest"     = [PSCustomObject]@{
                "Enabled"   = $true
                "Directory" = "manifests"
            }
            "Logging"      = [PSCustomObject]@{
                "Enabled"   = $true
                "Directory" = "logs"
                "FileName"  = "importer.log"
                "KeepDays"  = 30
            }
            "Notifications"= [PSCustomObject]@{
                "Enabled"          = $true
                "OnCardDetected"   = $true
                "OnImportComplete" = $true
                "OnError"          = $true
            }
            "MLVFS"        = [PSCustomObject]@{
                "Enabled"        = $true
                "ControllerPath" = "C:\MLVScripts\RightClickMountFolder\MLV_Controller.bat"
                "DriveLetter"    = "Z:\"
            }
            "MLVApp"       = [PSCustomObject]@{
                "Enabled"        = $true
                "ExecutablePath" = "C:\MLVScripts\MLVApp\MLVApp.exe"
            }
        }
        
        $TxtPhotos.Text = $DefaultConfig.Destinations.Photos
        $TxtMLV.Text = $DefaultConfig.Destinations.MLV
        $CmbPhotoMode.SelectedItem = $DefaultConfig.Organization.PhotoMode
        $CmbMLVMode.SelectedItem = $DefaultConfig.Organization.MLVMode
        $TxtDateFormat.Text = $DefaultConfig.Organization.DateFormat

        $ChkOnlyRemovable.Checked = $DefaultConfig.Card.OnlyRemovableDrives
        $ChkAutoEject.Checked = $DefaultConfig.Card.AutoEject
        $ChkDeleteSource.Checked = $DefaultConfig.Card.DeleteSourceAfterImport
        $ChkRequireDelConf.Checked = $DefaultConfig.Card.RequireDeleteConfirmation
        $ChkDryRun.Checked = $DefaultConfig.Safety.DryRun
        $ChkNeverDelUnver.Checked = $DefaultConfig.Safety.NeverDeleteUnlessVerified
        $ChkNeverMove.Checked = $DefaultConfig.Safety.NeverMoveSource

        $ChkSkipExist.Checked = $DefaultConfig.Copy.SkipExistingSameSize
        $ChkReplaceDiff.Checked = $DefaultConfig.Copy.ReplaceDifferentSize
        $ChkUseTemp.Checked = $DefaultConfig.Copy.UseTemporaryFiles
        $TxtRetries.Text = $DefaultConfig.Copy.Retries
        $TxtRetryDelay.Text = $DefaultConfig.Copy.RetryDelaySeconds
        $ChkVerEnabled.Checked = $DefaultConfig.Verification.Enabled
        $CmbVerMethod.SelectedItem = $DefaultConfig.Verification.Method

        $ChkScanSub.Checked = $DefaultConfig.Scanning.ScanSubfolders
        $TxtMinFiles.Text = $DefaultConfig.Scanning.MinimumCameraFiles
        $ChkStabEnabled.Checked = $DefaultConfig.Stability.Enabled
        $TxtStabChecks.Text = $DefaultConfig.Stability.Checks
        $TxtStabDelay.Text = $DefaultConfig.Stability.DelaySeconds
        $TxtPollInterval.Text = $DefaultConfig.Monitoring.PollIntervalSeconds
        $TxtMountSettle.Text = $DefaultConfig.Monitoring.MountSettleSeconds

        $ChkManifest.Checked = $DefaultConfig.Manifest.Enabled
        $TxtManifestDir.Text = $DefaultConfig.Manifest.Directory
        $ChkLogging.Checked = $DefaultConfig.Logging.Enabled
        $TxtLogDir.Text = $DefaultConfig.Logging.Directory
        $TxtLogFile.Text = $DefaultConfig.Logging.FileName
        $ChkMLVFS.Checked = $DefaultConfig.MLVFS.Enabled
        $TxtControllerPath.Text = $DefaultConfig.MLVFS.ControllerPath
        $TxtDriveLetter.Text = $DefaultConfig.MLVFS.DriveLetter
        $ChkMLVApp.Checked = $DefaultConfig.MLVApp.Enabled
        $TxtMLVAppPath.Text = $DefaultConfig.MLVApp.ExecutablePath

        [System.Windows.Forms.MessageBox]::Show("Settings restored to default profile values.", "Reset Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$ContentPanel.Controls.Add($BtnReset)

$BtnSave = New-Object System.Windows.Forms.Button
$BtnSave.Text = "Save Configuration"
$BtnSave.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$BtnSave.BackColor = $AccentColor
$BtnSave.ForeColor = [System.Drawing.Color]::White
$BtnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$BtnSave.FlatAppearance.BorderSize = 0
$BtnSave.Location = New-Object System.Drawing.Point(362, 532)
$BtnSave.Size = New-Object System.Drawing.Size(178, 36)
$BtnSave.Add_Click({
    if ($null -eq $Config.Destinations) { $Config | Add-Member -MemberType NoteProperty -Name "Destinations" -Value ([PSCustomObject]@{}) -Force }
    $Config.Destinations.Photos = $TxtPhotos.Text
    $Config.Destinations.MLV = $TxtMLV.Text
    if ($null -eq $Config.Organization) { $Config | Add-Member -MemberType NoteProperty -Name "Organization" -Value ([PSCustomObject]@{}) -Force }
    $Config.Organization.PhotoMode = $CmbPhotoMode.SelectedItem
    $Config.Organization.MLVMode = $CmbMLVMode.SelectedItem
    $Config.Organization.DateFormat = $TxtDateFormat.Text

    if ($null -eq $Config.Card) { $Config | Add-Member -MemberType NoteProperty -Name "Card" -Value ([PSCustomObject]@{}) -Force }
    $Config.Card.OnlyRemovableDrives = $ChkOnlyRemovable.Checked
    $Config.Card.AutoEject = $ChkAutoEject.Checked
    $Config.Card.DeleteSourceAfterImport = $ChkDeleteSource.Checked
    $Config.Card.RequireDeleteConfirmation = $ChkRequireDelConf.Checked
    if ($null -eq $Config.Safety) { $Config | Add-Member -MemberType NoteProperty -Name "Safety" -Value ([PSCustomObject]@{}) -Force }
    $Config.Safety.DryRun = $ChkDryRun.Checked
    $Config.Safety.NeverDeleteUnlessVerified = $ChkNeverDelUnver.Checked
    $Config.Safety.NeverMoveSource = $ChkNeverMove.Checked

    if ($null -eq $Config.Copy) { $Config | Add-Member -MemberType NoteProperty -Name "Copy" -Value ([PSCustomObject]@{}) -Force }
    $Config.Copy.SkipExistingSameSize = $ChkSkipExist.Checked
    $Config.Copy.ReplaceDifferentSize = $ChkReplaceDiff.Checked
    $Config.Copy.UseTemporaryFiles = $ChkUseTemp.Checked
    $Config.Copy.Retries = [int]$TxtRetries.Text
    $Config.Copy.RetryDelaySeconds = [int]$TxtRetryDelay.Text
    if ($null -eq $Config.Verification) { $Config | Add-Member -MemberType NoteProperty -Name "Verification" -Value ([PSCustomObject]@{}) -Force }
    $Config.Verification.Enabled = $ChkVerEnabled.Checked
    $Config.Verification.Method = $CmbVerMethod.SelectedItem

    if ($null -eq $Config.Scanning) { $Config | Add-Member -MemberType NoteProperty -Name "Scanning" -Value ([PSCustomObject]@{}) -Force }
    $Config.Scanning.ScanSubfolders = $ChkScanSub.Checked
    $Config.Scanning.MinimumCameraFiles = [int]$TxtMinFiles.Text
    if ($null -eq $Config.Stability) { $Config | Add-Member -MemberType NoteProperty -Name "Stability" -Value ([PSCustomObject]@{}) -Force }
    $Config.Stability.Enabled = $ChkStabEnabled.Checked
    $Config.Stability.Checks = [int]$TxtStabChecks.Text
    $Config.Stability.DelaySeconds = [int]$TxtStabDelay.Text
    if ($null -eq $Config.Monitoring) { $Config | Add-Member -MemberType NoteProperty -Name "Monitoring" -Value ([PSCustomObject]@{}) -Force }
    $Config.Monitoring.PollIntervalSeconds = [int]$TxtPollInterval.Text
    $Config.Monitoring.MountSettleSeconds = [int]$TxtMountSettle.Text

    if ($null -eq $Config.Manifest) { $Config | Add-Member -MemberType NoteProperty -Name "Manifest" -Value ([PSCustomObject]@{}) -Force }
    $Config.Manifest.Enabled = $ChkManifest.Checked
    $Config.Manifest.Directory = $TxtManifestDir.Text
    if ($null -eq $Config.Logging) { $Config | Add-Member -MemberType NoteProperty -Name "Logging" -Value ([PSCustomObject]@{}) -Force }
    $Config.Logging.Enabled = $ChkLogging.Checked
    $Config.Logging.Directory = $TxtLogDir.Text
    $Config.Logging.FileName = $TxtLogFile.Text
    if ($null -eq $Config.MLVFS) { $Config | Add-Member -MemberType NoteProperty -Name "MLVFS" -Value ([PSCustomObject]@{}) -Force }
    $Config.MLVFS.Enabled = $ChkMLVFS.Checked
    $Config.MLVFS.ControllerPath = $TxtControllerPath.Text
    $Config.MLVFS.DriveLetter = $TxtDriveLetter.Text

    if ($null -eq $Config.MLVApp) { $Config | Add-Member -MemberType NoteProperty -Name "MLVApp" -Value ([PSCustomObject]@{}) -Force }
    $Config.MLVApp.Enabled = $ChkMLVApp.Checked
    $Config.MLVApp.ExecutablePath = $TxtMLVAppPath.Text

    $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("All configuration settings saved successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $Form.Close()
})
$ContentPanel.Controls.Add($BtnSave)

# Initialize starting view to Storage & Organization
Show-SettingsPage "Destinations"
$BtnNav1.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$BtnNav1.ForeColor = $AccentColor

[void]$Form.ShowDialog()