#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$VialPath = '',
    [switch]$ValidateOnly,
    [switch]$ReadPadOnly,
    [switch]$Compact,
    [switch]$Strip,
    [string]$LabelsPath,
    [string]$SettingsPath,
    [string]$PreviewPath
)

$ErrorActionPreference = 'Stop'

function Read-VialLayout([string]$Path) {
    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    if (-not $data.layout -or $data.layout.Count -ne 4) {
        throw 'Please choose a TogKey Pad Plus export containing four layers.'
    }
    foreach ($layer in $data.layout) {
        if ($layer.Count -ne 3) { throw 'This export does not have the expected 3 by 3 matrix.' }
        foreach ($row in $layer) {
            if ($row.Count -ne 3) { throw 'This export does not have the expected 3 by 3 matrix.' }
        }
    }
    return $data
}

function Get-KeyLabel($Code, $Data) {
    $names = @{
        KC_VOLD = 'Volume down'; KC_VOLU = 'Volume up'; KC_MUTE = 'Mute'
        KC_MPRV = 'Previous track'; KC_MPLY = 'Play / Pause'; KC_MNXT = 'Next track'
        KC_NO = 'Unassigned'; KC_TRNS = 'Transparent'; USER00 = 'Cycle layers'
        QK_KB_0 = 'Cycle layers'; TOG_LAY = 'Cycle layers'
        KC_ENTER = 'Enter'; KC_ESC = 'Escape'; KC_SPACE = 'Space'; KC_TAB = 'Tab'
        KC_BSPC = 'Backspace'; KC_DEL = 'Delete'; KC_LGUI = 'Left Windows'; KC_RGUI = 'Right Windows'
        KC_LCTL = 'Left Ctrl'; KC_RCTL = 'Right Ctrl'; KC_LSFT = 'Left Shift'; KC_RSFT = 'Right Shift'
        KC_LALT = 'Left Alt'; KC_RALT = 'Right Alt'; KC_CAPS = 'Caps Lock'; KC_MSTP = 'Stop media'
        KC_LEFT = 'Left arrow'; KC_RIGHT = 'Right arrow'; KC_UP = 'Up arrow'; KC_DOWN = 'Down arrow'
    }
    $key = [string]$Code
    if ($names.ContainsKey($key)) { return $names[$key] }
    if ($key -match '^M(\d+)$') {
        $index = [int]$Matches[1]
        $texts = @()
        if ($index -lt $Data.macro.Count) {
            $texts = @($Data.macro[$index] | Where-Object { $_[0] -eq 'text' } | ForEach-Object { [string]$_[1] })
            foreach ($value in $texts) {
                if ($value -match '^https?://') {
                    $address = $null
                    if ([uri]::TryCreate($value, [UriKind]::Absolute, [ref]$address)) {
                        return $address.Host -replace '^www\.', ''
                    }
                }
                if ($value -match '(?i)\.exe$') {
                    return [IO.Path]::GetFileNameWithoutExtension($value)
                }
            }
        }
        if ($texts.Count -gt 0) {
            $text = ($texts -join ' ').Trim() -replace '\s+', ' '
            if ($text.Length -gt 40) { return $text.Substring(0,37) + '…' }
            if ($text.Length -gt 0) { return $text }
        }
        return "Macro $index"
    }
    if ($key -match '^KC_(.+)$') { return $Matches[1] -replace '_', ' ' }
    return $key
}

function Convert-Keycode([int]$Code) {
    $basic = @{
        0='KC_NO'; 1='KC_TRNS'; 40='KC_ENTER'; 41='KC_ESC'; 42='KC_BSPC'; 43='KC_TAB'; 44='KC_SPACE'
        45='KC_MINUS'; 46='KC_EQUAL'; 47='KC_LBRC'; 48='KC_RBRC'; 49='KC_BSLS'; 50='KC_NUHS'
        51='KC_SCLN'; 52='KC_QUOT'; 53='KC_GRV'; 54='KC_COMM'; 55='KC_DOT'; 56='KC_SLSH'; 57='KC_CAPS'
        70='KC_PSCR'; 71='KC_SCRL'; 72='KC_PAUS'; 73='KC_INS'; 74='KC_HOME'; 75='KC_PGUP'
        76='KC_DEL'; 77='KC_END'; 78='KC_PGDN'; 79='KC_RIGHT'; 80='KC_LEFT'; 81='KC_DOWN'; 82='KC_UP'
        83='KC_NUM'; 84='KC_PSLS'; 85='KC_PAST'; 86='KC_PMNS'; 87='KC_PPLS'; 88='KC_PENT'
        98='KC_P0'; 99='KC_PDOT'; 100='KC_NUBS'; 101='KC_APP'
        168='KC_MUTE'; 169='KC_VOLU'; 170='KC_VOLD'; 171='KC_MNXT'; 172='KC_MPRV'; 173='KC_MSTP'; 174='KC_MPLY'
        175='KC_MSEL'; 176='KC_EJCT'; 177='KC_MAIL'; 178='KC_CALC'; 179='KC_MYCM'
        224='KC_LCTL'; 225='KC_LSFT'; 226='KC_LALT'; 227='KC_LGUI'; 228='KC_RCTL'; 229='KC_RSFT'; 230='KC_RALT'; 231='KC_RGUI'
    }
    if ($basic.ContainsKey($Code)) { return $basic[$Code] }
    if ($Code -ge 4 -and $Code -le 29) { return 'KC_' + [char](65 + $Code - 4) }
    if ($Code -ge 30 -and $Code -le 39) { return 'KC_' + (($Code - 29) % 10) }
    if ($Code -ge 58 -and $Code -le 69) { return 'KC_F' + ($Code - 57) }
    if ($Code -ge 104 -and $Code -le 115) { return 'KC_F' + ($Code - 91) }
    if ($Code -ge 89 -and $Code -le 97) { return 'KC_P' + ($Code - 88) }
    if ($Code -ge 0x7700 -and $Code -le 0x777F) { return 'M' + ($Code - 0x7700) }
    if ($Code -ge 0x7E00 -and $Code -le 0x7E3F) { return 'USER{0:00}' -f ($Code - 0x7E00) }
    if ($Code -ge 0x5700 -and $Code -le 0x57FF) { return 'Tap dance ' + ($Code - 0x5700) }
    $families = @{ 0x5200='TO'; 0x5220='MO'; 0x5240='DF'; 0x5260='TG'; 0x5280='OSL'; 0x52C0='TT'; 0x52E0='PDF' }
    foreach ($start in $families.Keys) {
        if ($Code -ge $start -and $Code -lt ($start+32)) { return '{0}({1})' -f $families[$start],($Code-$start) }
    }
    if ($Code -ge 0x0100 -and $Code -le 0x1FFF) {
        $mask = $Code -shr 8
        $prefix = if ($mask -band 16) { 'Right ' } else { '' }
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($entry in @(@(1,'Ctrl'),@(2,'Shift'),@(4,'Alt'),@(8,'Win'))) {
            if ($mask -band $entry[0]) { $parts.Add($prefix + $entry[1]) }
        }
        $parts.Add(((Convert-Keycode ($Code -band 255)) -replace '^KC_',''))
        return $parts -join ' + '
    }
    return '0x{0:X4}' -f $Code
}

function Convert-PadSnapshot($Snapshot) {
    $layers = [Collections.Generic.List[object]]::new()
    $encoders = [Collections.Generic.List[object]]::new()
    foreach ($layer in 0..3) {
        $rows = [Collections.Generic.List[object]]::new()
        foreach ($row in 0..2) {
            $keys = @(foreach ($column in 0..2) { Convert-Keycode $Snapshot.Keys[($layer*9 + $row*3 + $column)] })
            $rows.Add($keys)
        }
        $layers.Add($rows.ToArray())
        $pair = @((Convert-Keycode $Snapshot.Encoders[$layer*2]), (Convert-Keycode $Snapshot.Encoders[($layer*2+1)]))
        $encoders.Add(@(,$pair))
    }
    $macros = [Collections.Generic.List[object]]::new()
    foreach ($texts in $Snapshot.MacroTexts) {
        $actions = [Collections.Generic.List[object]]::new()
        foreach ($text in $texts) { $actions.Add(@('text', $text)) }
        $macros.Add($actions.ToArray())
    }
    [pscustomobject]@{ layout=$layers.ToArray(); encoder_layout=$encoders.ToArray(); macro=$macros.ToArray() }
}

function Initialize-HidReader {
    if (-not ('TogKeyDisplay.Reader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'TogKey Hid.cs') }
}

if ($ReadPadOnly) {
    Initialize-HidReader
    Convert-PadSnapshot ([TogKeyDisplay.Reader]::ReadOnce()) | ConvertTo-Json -Depth 20
    return
}

function Get-ResolvedKey($Data, [int]$Layer, [int]$Row, [int]$Column) {
    $code = $Data.layout[$Layer][$Row][$Column]
    $inherited = $Layer -gt 0 -and $code -eq 'KC_TRNS'
    # This firmware uses layer_move: only the selected layer and default layer 0 apply.
    if ($inherited) { $code = $Data.layout[0][$Row][$Column] }
    [pscustomobject]@{ Code = $code; Label = Get-KeyLabel $code $Data; Inherited = $inherited }
}

if ($ValidateOnly) {
    $data = Read-VialLayout $VialPath
    foreach ($layer in 0..3) {
        $labels = foreach ($row in 1..2) {
            foreach ($column in 0..2) { (Get-ResolvedKey $data $layer $row $column).Label }
        }
        [pscustomobject]@{ Layer = $layer; Buttons = $labels -join ' | '; KnobPress = (Get-ResolvedKey $data $layer 0 2).Label }
    }
    return
}

if (-not $IsWindows) { throw 'This display requires Windows and PowerShell 7.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Start this display with pwsh -STA, or use Start TogKey Display.cmd.'
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
if (-not ('TogKeyDisplay.GlobalHotkey' -as [type])) {
    # Filtering WM_HOTKEY in C# avoids running PowerShell for every window message.
    Add-Type -ReferencedAssemblies ([Windows.Interop.HwndSource].Assembly.Location), ([Windows.Threading.Dispatcher].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
namespace TogKeyDisplay {
    public sealed class GlobalHotkey : IDisposable {
        [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window, int id);
        const int Id = 0x544B;
        readonly HwndSource source; readonly Action pressed; readonly HwndSourceHook hook;
        public GlobalHotkey(IntPtr window, uint modifiers, uint key, Action onPressed) {
            source = HwndSource.FromHwnd(window); pressed = onPressed; hook = Hook;
            if (!RegisterHotKey(window, Id, modifiers | 0x4000, key)) throw new InvalidOperationException("Hotkey registration failed (Win32 error " + Marshal.GetLastWin32Error() + ").");
            source.AddHook(hook);
        }
        IntPtr Hook(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled) {
            if (message == 0x0312 && wParam.ToInt32() == Id) { handled = true; if (pressed != null) pressed(); }
            return IntPtr.Zero;
        }
        public void Dispose() { source.RemoveHook(hook); UnregisterHotKey(source.Handle, Id); }
    }
}
'@
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TogKey Display" Width="442" Height="550" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="NoResize"
        Background="#10151F" Foreground="#F1F5FA" Topmost="True" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#B9C5D6"/>
      <Setter Property="Background" Value="#202A3A"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="Button">
          <Border x:Name="Surface" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.78"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="#70DEC2"/><Setter TargetName="Surface" Property="BorderThickness" Value="1"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>
  <Border x:Name="Frame" Background="#10151F" BorderBrush="#303B4D" BorderThickness="1" Padding="22,18,22,18">
    <StackPanel>
      <Grid x:Name="DragArea" Background="Transparent" Margin="0,0,0,18">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="TOGKEY" FontSize="12" FontWeight="Bold" Foreground="#70DEC2"/>
          <TextBlock x:Name="Subtitle" Text="Your pad, at a glance" FontSize="18" FontWeight="SemiBold" Margin="0,3,0,0"/>
        </StackPanel>
        <Button x:Name="ReleasePad" Grid.Column="1" Content="Release pad" FontSize="11" Padding="8,6" Margin="0,0,5,0" VerticalAlignment="Top" ToolTip="Disconnect from the pad so Vial can use it, without closing this display"/>
        <Button x:Name="Minimize" Grid.Column="2" Content="−" Width="30" Padding="0,5" Margin="0,0,5,0" VerticalAlignment="Top" ToolTip="Minimize"/>
        <Button x:Name="Close" Grid.Column="3" Content="×" Width="30" Padding="0,5" VerticalAlignment="Top" ToolTip="Close"/>
      </Grid>
      <Border x:Name="LockPanel" Background="#342D20" CornerRadius="6" Padding="9,7" Margin="0,0,0,10">
        <StackPanel>
          <TextBlock x:Name="LockHeading" Text="Checking pad lock status…" FontSize="11" FontWeight="SemiBold" Foreground="#EFCB85" TextWrapping="Wrap"/>
          <TextBlock x:Name="LockHelp" Text="" FontSize="10" Foreground="#EFCB85" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
          <Button x:Name="UnlockHelp" Content="How to unlock" FontSize="10" HorizontalAlignment="Left" Padding="7,5" Margin="0,6,0,0" Visibility="Collapsed"/>
        </StackPanel>
      </Border>
      <UniformGrid x:Name="LayerTabs" Columns="4" Margin="-3,0,-3,16">
        <Button x:Name="Layer0" Content="Pad 1" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer1" Content="Pad 2" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer2" Content="Pad 3" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer3" Content="Pad 4" Margin="3,0" Padding="5,10"/>
      </UniformGrid>
      <Border x:Name="SyncPrompt" Background="#342D20" CornerRadius="6" Padding="9,7" Margin="0,0,0,8">
        <TextBlock Text="Click the layer shown on your pad's OLED to sync. Pad 1–4 matches Vial layers 0–3." Foreground="#EFCB85" FontSize="11" TextWrapping="Wrap"/>
      </Border>
      <Grid x:Name="LayerHeader" Margin="0,0,0,12">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="LayerHeading" Text="Layer 0" FontSize="22" FontWeight="SemiBold"/>
        <Border Grid.Column="1" Background="#342D20" CornerRadius="5" Padding="9,5" VerticalAlignment="Center">
          <TextBlock x:Name="LayerMode" Text="MANUAL LAYER" FontSize="10" FontWeight="Bold" Foreground="#EFCB85"/>
        </Border>
      </Grid>
      <UniformGrid x:Name="Tiles" Columns="3" Rows="2" Margin="-4,0,-4,12"/>
      <Border x:Name="KnobPanel" Background="#192231" CornerRadius="8" Padding="13,11" Margin="0,0,0,14">
        <StackPanel>
          <TextBlock x:Name="KnobHeading" Text="KNOB" Foreground="#8395AD" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
          <TextBlock x:Name="KnobRotate" Text="Turn: Volume down / Volume up" FontSize="12" TextWrapping="Wrap"/>
          <TextBlock x:Name="KnobPress" Text="Press: Cycle layers" FontSize="12" Foreground="#70DEC2" Margin="0,4,0,0"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="LayerHelp" Text="Select the matching layer above, or enable knob tracking below. Layer selection here changes only this display. Press F1 for keyboard shortcuts." Foreground="#94A4BA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"/>
      <Grid x:Name="ReadSettings" Margin="0,0,0,10">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button x:Name="ReadPad" Content="Read from pad" HorizontalAlignment="Left" Background="#29493F" Foreground="#A5F1D9" FontSize="11" Padding="10,8"/>
        <CheckBox x:Name="AutoRead" Grid.Column="1" Content="Auto-read mappings" IsChecked="True" Foreground="#B9C5D6" VerticalAlignment="Center" FontSize="11" ToolTip="Read saved mappings every 8 seconds, or every 60 seconds while following knob presses"/>
      </Grid>
      <TextBlock x:Name="Connection" Text="Ready to read the pad" Foreground="#94A4BA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"/>
      <CheckBox x:Name="TrackKnob" Content="Follow knob presses (estimated layer)" Foreground="#B9C5D6" FontSize="11" Margin="0,0,0,5"/>
      <TextBlock x:Name="TrackingStatus" Text="Tracking off · select layers manually" Foreground="#94A4BA" FontSize="10" TextWrapping="Wrap" Margin="0,0,0,14"/>
      <Grid x:Name="Toolbar">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button x:Name="Pin" Content="Pinned ✓" HorizontalAlignment="Left" FontSize="11" Padding="9,7" ToolTip="Keep this display above other windows"/>
        <Button x:Name="Reload" Grid.Column="1" Content="Refresh" FontSize="11" Padding="10,7" Margin="0,0,6,0"/>
        <Button x:Name="Browse" Grid.Column="2" Content="Open .vil" FontSize="11" Padding="10,7"/>
      </Grid>
      <TextBlock x:Name="Source" Foreground="#71839B" FontSize="10" Margin="0,12,0,0" TextTrimming="CharacterEllipsis"/>
      <Grid x:Name="ViewRow" Margin="0,12,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <CheckBox x:Name="Compact" Content="Compact" Foreground="#B9C5D6" FontSize="11" VerticalAlignment="Center" ToolTip="Shrink the display. Live reads and knob tracking keep running."/>
        <Button x:Name="StripView" Grid.Column="1" Content="Strip view" FontSize="11" Padding="9,5" ToolTip="Collapse to a single row of buttons you can park at the top of the screen"/>
      </Grid>
    </StackPanel>
  </Border>
  <Border x:Name="Strip" Visibility="Collapsed" Background="#10151F" BorderBrush="#303B4D" BorderThickness="1" Padding="5" HorizontalAlignment="Left">
    <StackPanel Orientation="Horizontal">
      <Button x:Name="StripLayer" Content="?" Width="40" Padding="0,6" Margin="0,0,3,0" FontSize="13" FontWeight="Bold"/>
      <StackPanel x:Name="StripTiles" Orientation="Horizontal"/>
      <Button x:Name="StripExpand" Content="⤢" Width="28" Padding="0,6" Margin="3,0,0,0" ToolTip="Expand the display"/>
    </StackPanel>
  </Border>
  </Grid>
</Window>
'@
$reader = [Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
$controls = @{}
foreach ($name in @('DragArea','Minimize','Close','Layer0','Layer1','Layer2','Layer3','LayerHeading','LayerMode','Tiles','KnobRotate','KnobPress','Pin','Reload','Browse','Source','ReadPad','AutoRead','Connection','TrackKnob','TrackingStatus','Frame','Subtitle','LayerTabs','LayerHeader','KnobPanel','KnobHeading','LayerHelp','ReadSettings','Toolbar','Compact','SyncPrompt','LockPanel','LockHeading','LockHelp','UnlockHelp','ReleasePad','ViewRow','StripView','Strip','StripLayer','StripTiles','StripExpand')) {
    $controls[$name] = $window.FindName($name)
}
$script:state = @{ Data = $null; Path = $VialPath; Layer = 0; Synced = $false; LockState = 'unknown'; Mode = 'file'; Refreshed = Get-Date; Monitor = $null; Timer = $null; Generation = 0; Released = $false; StripOn = $false; StripPos = $null; NormalPos = $null }
$script:labelPath = if ($LabelsPath) { [IO.Path]::GetFullPath($LabelsPath) } else { Join-Path $PSScriptRoot 'TogKey labels.json' }
$script:displayLabels = @{}
if (Test-Path -LiteralPath $script:labelPath) {
    try {
        $preferences = Get-Content -LiteralPath $script:labelPath -Raw | ConvertFrom-Json -AsHashtable -Depth 8
        if ($preferences.version -ne 1 -or $preferences.labels -isnot [Collections.IDictionary]) { throw 'Unexpected label file format.' }
        foreach ($entry in $preferences.labels.GetEnumerator()) {
            if ($entry.Key -match '^(button:[0-3]:[0-5]|layer:[0-3]|knob:[0-3]:(turn|press))$' -and $entry.Value -is [string] -and $entry.Value.Length -le 64) {
                $script:displayLabels[$entry.Key] = $entry.Value
            }
        }
    } catch { $controls.Connection.Text = 'Custom label file could not be read; automatic labels shown.' }
}

function Get-DisplayLabel([string]$Id, [string]$Automatic) {
    if ($script:displayLabels.ContainsKey($Id)) { return $script:displayLabels[$Id] }
    return $Automatic
}
function Write-FileAtomically([string]$Path, [string]$Text) {
    # Write beside the target, then replace it, so a crash never leaves a half-written file.
    $temporaryPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, $Text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    } finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}
function Save-DisplayLabel([string]$Id, [string]$Text) {
    if ($Id -notmatch '^(button:[0-3]:[0-5]|layer:[0-3]|knob:[0-3]:(turn|press))$') { throw 'Invalid label position.' }
    $candidate = $script:displayLabels.Clone()
    $clean = ($Text -replace '\s+', ' ').Trim()
    if ($clean.Length -gt 64) { throw 'Labels must be 64 characters or fewer.' }
    if ([string]::IsNullOrWhiteSpace($clean)) { $candidate.Remove($Id) } else { $candidate[$Id] = $clean }
    Write-FileAtomically $script:labelPath (@{ version=1; labels=$candidate } | ConvertTo-Json -Depth 8)
    $script:displayLabels = $candidate
    Update-Display
}
function Edit-DisplayLabel([string]$Id, [string]$Automatic, [string]$Description, [switch]$NoShow) {
    $dialog = [Windows.Window]::new()
    $dialog.Title = 'Edit display label'
    if ($window.IsLoaded) { $dialog.Owner = $window }
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Width = 360
    $dialog.SizeToContent = 'Height'
    $dialog.ResizeMode = 'NoResize'
    $dialog.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#10151F')
    $dialog.Foreground = [Windows.Media.Brushes]::White
    $dialog.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI')
    $panel = [Windows.Controls.StackPanel]::new()
    $panel.Margin = [Windows.Thickness]::new(18)
    $heading = [Windows.Controls.TextBlock]::new()
    $heading.Text = $Description
    $heading.FontSize = 16
    $heading.FontWeight = 'SemiBold'
    $panel.Children.Add($heading) | Out-Null
    $help = [Windows.Controls.TextBlock]::new()
    $help.Text = 'Display name only. Your pad keeps its current action.'
    $help.TextWrapping = 'Wrap'
    $help.Foreground = [Windows.Media.Brushes]::LightGray
    $help.Margin = [Windows.Thickness]::new(0,8,0,12)
    $panel.Children.Add($help) | Out-Null
    $labelInput = [Windows.Controls.TextBox]::new()
    $labelInput.Text = Get-DisplayLabel $Id $Automatic
    $labelInput.MaxLength = 64
    $labelInput.FontSize = 15
    $labelInput.Padding = [Windows.Thickness]::new(7)
    $panel.Children.Add($labelInput) | Out-Null
    $automaticText = [Windows.Controls.TextBlock]::new()
    $automaticText.Text = 'Automatic: ' + $Automatic
    $automaticText.TextWrapping = 'Wrap'
    $automaticText.Foreground = [Windows.Media.Brushes]::LightGray
    $automaticText.Margin = [Windows.Thickness]::new(0,8,0,12)
    $panel.Children.Add($automaticText) | Out-Null
    $buttons = [Windows.Controls.WrapPanel]::new()
    $reset = [Windows.Controls.Button]::new(); $reset.Content = 'Use automatic'
    $save = [Windows.Controls.Button]::new(); $save.Content = 'Save'; $save.IsDefault = $true
    $cancel = [Windows.Controls.Button]::new(); $cancel.Content = 'Cancel'; $cancel.IsCancel = $true
    foreach ($button in @($reset,$save,$cancel)) {
        $button.Padding = [Windows.Thickness]::new(10,7,10,7)
        $button.Margin = [Windows.Thickness]::new(0,0,7,0)
        $buttons.Children.Add($button) | Out-Null
    }
    $panel.Children.Add($buttons) | Out-Null
    $dialog.Content = $panel
    # Capture the selected slot now: knob tracking may change layers while the editor is open.
    $editor = @{ Id=$Id; Input=$labelInput; Dialog=$dialog; SaveAction=${function:Save-DisplayLabel} }
    $save.Tag = $editor; $reset.Tag = $editor
    [Windows.NameScope]::SetNameScope($dialog, [Windows.NameScope]::new())
    $dialog.RegisterName('LabelInput',$labelInput)
    $dialog.RegisterName('SaveLabel',$save)
    $dialog.RegisterName('ResetLabel',$reset)
    $save.Add_Click({
        param($sender,$eventArgs)
        $editor = $sender.Tag
        try { & $editor.SaveAction $editor.Id $editor.Input.Text; $editor.Dialog.Close() }
        catch { [void][Windows.MessageBox]::Show($editor.Dialog, $_.Exception.Message, 'Could not save label') }
    })
    $reset.Add_Click({
        param($sender,$eventArgs)
        $editor = $sender.Tag
        try { & $editor.SaveAction $editor.Id ''; $editor.Dialog.Close() }
        catch { [void][Windows.MessageBox]::Show($editor.Dialog, $_.Exception.Message, 'Could not save label') }
    })
    $dialog.Tag = $labelInput
    $dialog.Add_ContentRendered({ param($sender,$eventArgs) $sender.Tag.Focus() | Out-Null; $sender.Tag.SelectAll() })
    if ($NoShow) { return $dialog }
    [void]$dialog.ShowDialog()
}
$controls.Compact.ToolTip = 'Shrink the display. Right-click a button, layer tab, or knob label to rename it.'
$script:tileControls = @()
foreach ($i in 0..5) {
    $border = [Windows.Controls.Border]::new()
    $border.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#202C3E')
    $border.CornerRadius = [Windows.CornerRadius]::new(8)
    $border.Margin = [Windows.Thickness]::new(4)
    $border.Padding = [Windows.Thickness]::new(10)
    $border.Height = 87
    $stack = [Windows.Controls.StackPanel]::new()
    $stack.VerticalAlignment = 'Center'
    $label = [Windows.Controls.TextBlock]::new()
    $label.TextWrapping = 'Wrap'
    $label.TextTrimming = 'CharacterEllipsis'
    $label.FontSize = 13
    $label.FontWeight = 'SemiBold'
    $label.TextAlignment = 'Center'
    $hint = [Windows.Controls.TextBlock]::new()
    $hint.FontSize = 9
    $hint.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#8FA5C0')
    $hint.TextAlignment = 'Center'
    $hint.Margin = [Windows.Thickness]::new(0,5,0,0)
    [void]$stack.Children.Add($label)
    [void]$stack.Children.Add($hint)
    $border.Child = $stack
    [void]$controls.Tiles.Children.Add($border)
    $script:tileControls += @{ Border = $border; Label = $label; Hint = $hint }
}
# Strip view: the same six buttons as one slim row, for parking along a screen edge.
$script:stripTiles = @()
foreach ($i in 0..5) {
    $border = [Windows.Controls.Border]::new()
    $border.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#202C3E')
    $border.CornerRadius = [Windows.CornerRadius]::new(6)
    $border.Margin = [Windows.Thickness]::new(2,0,2,0)
    $border.Padding = [Windows.Thickness]::new(6,0,6,0)
    $border.Width = 108
    $label = [Windows.Controls.TextBlock]::new()
    $label.TextTrimming = 'CharacterEllipsis'
    $label.FontSize = 11
    $label.FontWeight = 'SemiBold'
    $label.TextAlignment = 'Center'
    $label.VerticalAlignment = 'Center'
    $border.Child = $label
    [void]$controls.StripTiles.Children.Add($border)
    $script:stripTiles += @{ Border = $border; Label = $label }
}

function Update-Display {
    $layer = $script:state.Layer
    $data = $script:state.Data
    $defaultNames = @('','','','')
    foreach ($n in 0..3) {
        $name = Get-DisplayLabel "layer:$n" $defaultNames[$n]
        $padNumber = $n + 1
        $text = if ($name) { "$padNumber · $name" } else { "Pad $padNumber" }
        $tabText = [Windows.Controls.TextBlock]::new()
        $tabText.Text = $text; $tabText.TextTrimming = 'CharacterEllipsis'
        $controls["Layer$n"].Content = $tabText
        $controls["Layer$n"].ToolTip = "$text · Vial layer $n · click to sync, right-click to rename"
        $controls["Layer$n"].Tag = $n
        $controls["Layer$n"].DataContext = $defaultNames[$n]
    }
    $controls.LayerHeading.Text = if ($script:state.Synced) { "Pad layer $($layer+1)" } else { 'Choose pad layer' }
    $controls.LayerMode.Text = if (-not $script:state.Synced) { 'SYNC NEEDED' } elseif ($controls.TrackKnob.IsChecked) { 'ESTIMATED LAYER' } else { 'MANUAL LAYER' }
    $controls.SyncPrompt.Visibility = if ($script:state.Synced) { 'Collapsed' } else { 'Visible' }
    $controls.Tiles.IsEnabled = $script:state.Synced
    $controls.KnobPanel.IsEnabled = $script:state.Synced
    foreach ($n in 0..3) {
        $selected = $script:state.Synced -and $n -eq $layer
        $controls["Layer$n"].Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($selected) { '#70DEC2' } else { '#202A3A' }))
        $controls["Layer$n"].Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($selected) { '#10231F' } else { '#B9C5D6' }))
    }
    $i = 0
    foreach ($row in 1..2) {
        foreach ($column in 0..2) {
            $key = Get-ResolvedKey $data $layer $row $column
            $script:tileControls[$i].Label.Text = Get-DisplayLabel "button:${layer}:$i" $key.Label
            $script:tileControls[$i].Hint.Text = $(if ($key.Inherited) { 'from layer 0' } else { ' ' })
            $script:tileControls[$i].Border.ToolTip = "Automatic: $($key.Label) • $($key.Code)`nRight-click to rename this button on layer $layer"
            $script:stripTiles[$i].Label.Text = $script:tileControls[$i].Label.Text
            $script:stripTiles[$i].Border.ToolTip = $script:tileControls[$i].Border.ToolTip
            $i++
        }
    }
    $pressLabel = (Get-ResolvedKey $data $layer 0 2).Label
    $controls.KnobPress.Tag = $pressLabel
    $controls.KnobPress.Text = 'Press: ' + (Get-DisplayLabel "knob:${layer}:press" $pressLabel)
    $encoder = @('KC_NO', 'KC_NO')
    if ($data.encoder_layout -and $data.encoder_layout[$layer].Count -gt 0) {
        $encoder = @($data.encoder_layout[$layer][0])
        foreach ($direction in 0..1) {
            if ($encoder[$direction] -eq 'KC_TRNS') { $encoder[$direction] = $data.encoder_layout[0][0][$direction] }
        }
    }
    $turnLabel = (Get-KeyLabel $encoder[0] $data) + ' / ' + (Get-KeyLabel $encoder[1] $data)
    $controls.KnobRotate.Tag = $turnLabel
    $controls.KnobRotate.Text = 'Turn: ' + (Get-DisplayLabel "knob:${layer}:turn" $turnLabel)
    foreach ($control in @($controls.KnobRotate,$controls.KnobPress)) { $control.ToolTip = 'Automatic: ' + $control.Tag + ' · right-click to rename' }
    if (-not $script:state.Synced) {
        foreach ($tile in $script:tileControls) { $tile.Label.Text = '—'; $tile.Hint.Text = ' ' }
        foreach ($tile in $script:stripTiles) { $tile.Label.Text = '—'; $tile.Border.ToolTip = 'Click the layer badge until it matches the OLED, or right-click for options' }
        $controls.KnobRotate.Text = 'Turn: —'
        $controls.KnobPress.Text = 'Press: —'
    }
    Update-StripBadge
    $sourceName = if ($script:state.Mode -eq 'live') { 'Pad mappings' } elseif ($script:state.Mode -eq 'empty') { 'No mappings loaded' } else { [IO.Path]::GetFileName($script:state.Path) }
    $controls.Source.Text = $sourceName + ' · read ' + $script:state.Refreshed.ToString('h:mm:ss tt')
    $controls.Source.ToolTip = if ($script:state.Mode -eq 'live') { 'Read directly from the pad; active layer is not reported by firmware.' } else { $script:state.Path }
}

function Set-DisplayData($candidate) {
    $script:state.Data = $candidate
    Update-Display
}
function Confirm-PadLayer([int]$Layer) {
    $script:state.Layer = $Layer
    $script:state.Synced = $true
    $script:state.Generation++
    if ($script:state.Monitor) {
        # Discard queued presses from before this explicit synchronization and rebase the switch.
        $script:state.Monitor.TrackingEpoch = $script:state.Generation
        $script:state.Monitor.TrackKnob = [bool]$controls.TrackKnob.IsChecked
    }
    $controls.TrackingStatus.Text = if ($controls.TrackKnob.IsChecked) { 'Synced to pad layer ' + ($Layer+1) + ' · following observed knob presses' } else { 'Layer selected · tracking off' }
    Update-Display
}
function Require-PadSync {
    $script:state.Synced = $false
    if ($script:state.Monitor) { $script:state.Monitor.TrackKnob = $false }
    $controls.TrackingStatus.Text = 'Select the layer shown on your pad before knob tracking begins'
    Update-Display
}
function Open-Layout([string]$Path) {
    $candidate = Read-VialLayout $Path
    $script:state.Path = $Path
    $script:state.Mode = 'file'
    $script:state.Refreshed = Get-Date
    Set-DisplayData $candidate
}
function Show-LoadError($Failure) {
    [void][Windows.MessageBox]::Show($window, "Could not read the Vial export.`n`n$Failure", 'TogKey Display', 'OK', 'Warning')
}
function Select-Layout {
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = 'Choose your TogKey Vial export'
    $dialog.Filter = 'Vial exports (*.vil)|*.vil'
    if ($dialog.ShowDialog($window)) {
        try {
            # Stop the old reader so queued live data cannot replace a deliberately selected export.
            $candidate = Read-VialLayout $dialog.FileName
            Stop-PadMonitor
            $controls.AutoRead.IsChecked = $false
            $controls.TrackKnob.IsChecked = $false
            Open-Layout $dialog.FileName
            Update-LockWarning 'offline'
            $controls.Connection.Text = 'Viewing an export · Read from pad reconnects'
        } catch { Show-LoadError $_.Exception.Message }
    }
}
foreach ($n in 0..3) {
    $controls["Layer$n"].Tag = $n
    $controls["Layer$n"].Add_Click({ param($sender, $eventArgs) Confirm-PadLayer ([int]$sender.Tag) })
    $controls["Layer$n"].Add_MouseRightButtonUp({
        param($sender, $eventArgs)
        Edit-LayerName ([int]$sender.Tag)
        $eventArgs.Handled = $true
    })
}
function Edit-LayerName([int]$Number) {
    Edit-DisplayLabel "layer:$Number" '' "Pad layer $($Number+1) name (Vial $Number)"
}
function Edit-ButtonLabel([int]$Position) {
    $layer = $script:state.Layer
    $row = 1 + [int][Math]::Floor($Position / 3)
    $column = $Position % 3
    $automatic = (Get-ResolvedKey $script:state.Data $layer $row $column).Label
    Edit-DisplayLabel "button:${layer}:$Position" $automatic "Pad layer $($layer+1) · button $($Position+1)"
}
function Edit-KnobLabel([string]$Action) {
    $control = if ($Action -eq 'turn') { $controls.KnobRotate } else { $controls.KnobPress }
    Edit-DisplayLabel "knob:$($script:state.Layer):$Action" ([string]$control.Tag) $(if ($Action -eq 'turn') { 'Knob turn label' } else { 'Knob press label' })
}
$renameButton = {
    param($sender, $eventArgs)
    # Unsynced strip tiles show placeholders; let the strip menu open instead.
    if (-not $script:state.Synced) { return }
    Edit-ButtonLabel ([int]$sender.Tag)
    $eventArgs.Handled = $true
}
foreach ($i in 0..5) {
    foreach ($tile in @($script:tileControls[$i], $script:stripTiles[$i])) {
        $tile.Border.Tag = $i
        $tile.Border.Add_MouseRightButtonUp($renameButton)
    }
}
$controls.KnobRotate.Add_MouseRightButtonUp({ param($sender,$eventArgs) Edit-KnobLabel 'turn'; $eventArgs.Handled = $true })
$controls.KnobPress.Add_MouseRightButtonUp({ param($sender,$eventArgs) Edit-KnobLabel 'press'; $eventArgs.Handled = $true })
$controls.Close.Add_Click({ $window.Close() })
$window.Add_Closed({ Stop-PadMonitor })
$controls.Minimize.Add_Click({ $window.WindowState = 'Minimized' })
$controls.DragArea.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.OriginalSource -isnot [Windows.Controls.Button]) {
        try { $window.DragMove() } catch { }
    }
})
function Switch-Pinned {
    $window.Topmost = -not $window.Topmost
    $controls.Pin.Content = $(if ($window.Topmost) { 'Pinned ✓' } else { 'Pin on top' })
}
$controls.Pin.Add_Click({ Switch-Pinned })

# ---- Strip view ----
function Update-StripBadge {
    $attention = (-not $script:state.Synced) -or $script:state.Released -or
        ($controls.TrackKnob.IsChecked -and $script:state.LockState -in @('locked','unlocking'))
    $controls.StripLayer.Content = if ($script:state.Synced) { [string]($script:state.Layer + 1) } else { '?' }
    $controls.StripLayer.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($attention) { '#EFCB85' } else { '#70DEC2' }))
    $controls.StripLayer.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#10231F')
}
function Move-StripToTop {
    # Top-center of the monitor the window is on, in WPF units (handles display scaling).
    $source = [Windows.PresentationSource]::FromVisual($window)
    if (-not $source) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    $area = [Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $toWpf = $source.CompositionTarget.TransformFromDevice
    $topLeft = $toWpf.Transform([Windows.Point]::new($area.Left, $area.Top))
    $bottomRight = $toWpf.Transform([Windows.Point]::new($area.Right, $area.Bottom))
    $window.Left = $topLeft.X + [Math]::Max(0, ($bottomRight.X - $topLeft.X - $window.Width) / 2)
    $window.Top = $topLeft.Y
}
function Set-StripView([bool]$Enabled) {
    if ($Enabled -eq [bool]$script:state.StripOn) { return }
    if ($Enabled) {
        if ($window.IsLoaded) { $script:state.NormalPos = @($window.Left, $window.Top) }
        $controls.Frame.Visibility = 'Collapsed'
        $controls.Strip.Visibility = 'Visible'
        $controls.Strip.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $window.Width = [Math]::Ceiling($controls.Strip.DesiredSize.Width)
        $script:state.StripOn = $true
        if ($window.IsLoaded) {
            if ($script:state.StripPos) { $window.Left, $window.Top = $script:state.StripPos } else { Move-StripToTop }
        }
    } else {
        $script:state.StripPos = @($window.Left, $window.Top)
        $controls.Strip.Visibility = 'Collapsed'
        $controls.Frame.Visibility = 'Visible'
        $script:state.StripOn = $false
        Set-CompactDisplay ([bool]$controls.Compact.IsChecked)
        if ($script:state.NormalPos) { $window.Left, $window.Top = $script:state.NormalPos }
    }
}
function Show-NormalView([bool]$CompactView) {
    $controls.Compact.IsChecked = $CompactView
    Set-StripView $false
}
$controls.StripView.Add_Click({ Set-StripView $true })
$controls.StripExpand.Add_Click({ Show-NormalView ([bool]$controls.Compact.IsChecked) })
$controls.StripLayer.Add_Click({
    # Step through layers until the badge matches the OLED; each click also resyncs tracking.
    $next = if ($script:state.Synced) { ($script:state.Layer + 1) % 4 } else { 0 }
    Confirm-PadLayer $next
})
$controls.StripLayer.ToolTip = ' '
$controls.StripLayer.Add_ToolTipOpening({
    param($sender, $eventArgs)
    $lines = [Collections.Generic.List[string]]::new()
    if ($script:state.Synced) {
        $name = Get-DisplayLabel "layer:$($script:state.Layer)" ''
        $lines.Add("Pad layer $($script:state.Layer + 1)" + $(if ($name) { " · $name" } else { '' }) + ' · ' + $controls.LayerMode.Text.ToLower())
        $lines.Add("Knob · $($controls.KnobRotate.Text) · $($controls.KnobPress.Text)")
    } else { $lines.Add('Sync needed · click until this number matches the OLED') }
    if ($controls.LockPanel.Visibility -eq 'Visible') { $lines.Add($controls.LockHeading.Text) }
    $lines.Add($controls.Connection.Text)
    $lines.Add('Click: next layer · Right-click: options · Drag the bar to move it')
    $sender.ToolTip = $lines -join "`n"
})
$controls.Strip.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    try { $window.DragMove() } catch { }
})
$stripMenu = [Windows.Controls.ContextMenu]::new()
$script:stripLayerItems = @()
foreach ($n in 0..3) {
    $item = [Windows.Controls.MenuItem]::new(); $item.Tag = $n
    $item.Add_Click({ param($sender, $eventArgs) Confirm-PadLayer ([int]$sender.Tag) })
    [void]$stripMenu.Items.Add($item); $script:stripLayerItems += $item
}
[void]$stripMenu.Items.Add([Windows.Controls.Separator]::new())
$stripReleaseItem = [Windows.Controls.MenuItem]::new()
$stripReleaseItem.Add_Click({ if ($script:state.Monitor) { Disconnect-Pad } else { Start-PadMonitor -Resume } })
[void]$stripMenu.Items.Add($stripReleaseItem)
$stripPinItem = [Windows.Controls.MenuItem]::new(); $stripPinItem.Header = 'Pinned on top'
$stripPinItem.Add_Click({ Switch-Pinned })
[void]$stripMenu.Items.Add($stripPinItem)
$stripTopItem = [Windows.Controls.MenuItem]::new(); $stripTopItem.Header = 'Move to top of screen'
$stripTopItem.Add_Click({ Move-StripToTop })
[void]$stripMenu.Items.Add($stripTopItem)
[void]$stripMenu.Items.Add([Windows.Controls.Separator]::new())
$stripFullItem = [Windows.Controls.MenuItem]::new(); $stripFullItem.Header = 'Full view'
$stripFullItem.Add_Click({ Show-NormalView $false })
[void]$stripMenu.Items.Add($stripFullItem)
$stripCompactItem = [Windows.Controls.MenuItem]::new(); $stripCompactItem.Header = 'Compact view'
$stripCompactItem.Add_Click({ Show-NormalView $true })
[void]$stripMenu.Items.Add($stripCompactItem)
$stripCloseItem = [Windows.Controls.MenuItem]::new(); $stripCloseItem.Header = 'Close'
$stripCloseItem.Add_Click({ $window.Close() })
[void]$stripMenu.Items.Add($stripCloseItem)
$stripMenu.Add_Opened({
    foreach ($item in $script:stripLayerItems) {
        $n = [int]$item.Tag
        $name = Get-DisplayLabel "layer:$n" ''
        $item.Header = "Pad $($n + 1)" + $(if ($name) { " · $name" } else { '' })
        $item.IsChecked = $script:state.Synced -and $script:state.Layer -eq $n
    }
    $stripReleaseItem.Header = if ($script:state.Monitor) { 'Release pad (for Vial)' } else { 'Reconnect to pad' }
    $stripPinItem.IsChecked = $window.Topmost
})
$controls.Strip.ContextMenu = $stripMenu
$window.Add_Loaded({ if ($script:state.StripOn -and -not $script:state.StripPos) { Move-StripToTop } })
$controls.Reload.Add_Click({
    if ($script:state.Mode -eq 'live' -or $controls.AutoRead.IsChecked) { Start-PadMonitor -Resume }
    else { try { Open-Layout $script:state.Path } catch { Show-LoadError $_.Exception.Message } }
})
$controls.Browse.Add_Click({ Select-Layout })

function Stop-PadMonitor {
    if ($script:state.Timer) { $script:state.Timer.Stop(); $script:state.Timer = $null }
    if ($script:state.Monitor) { $script:state.Monitor.Dispose(); $script:state.Monitor = $null }
    Update-ReleaseButton
}
function Update-ReleaseButton {
    if ($script:state.Monitor) {
        $controls.ReleasePad.Content = 'Release pad'
        $controls.ReleasePad.ToolTip = 'Disconnect from the pad so Vial can use it, without closing this display'
    } else {
        $controls.ReleasePad.Content = 'Reconnect'
        $controls.ReleasePad.ToolTip = 'Close Vial first, then reconnect to read the saved mappings'
    }
}
function Disconnect-Pad {
    # Dispose waits for the reader to close its exclusive handle before reporting that Vial can connect.
    Stop-PadMonitor
    $script:state.Released = $true
    Update-LockWarning 'offline'
    $controls.Connection.Text = 'Pad released · Vial can connect now. Close Vial, then click Reconnect.'
    $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
    if ($controls.TrackKnob.IsChecked) { $controls.TrackingStatus.Text = 'Tracking paused while released · knob presses are not observed' }
    Update-StripBadge
}
function Update-LockWarning([string]$Status) {
    $previous = $script:state.LockState
    $script:state.LockState = $Status
    $controls.LockPanel.Visibility = if ($Status -in @('unlocked','offline')) { 'Collapsed' } else { 'Visible' }
    $needsUnlock = $Status -in @('locked','unlocking')
    $controls.LockHelp.Visibility = if ($needsUnlock) { 'Visible' } else { 'Collapsed' }
    $controls.UnlockHelp.Visibility = if ($needsUnlock) { 'Visible' } else { 'Collapsed' }
    switch ($Status) {
        'locked' {
            $controls.LockHeading.Text = 'Pad locked · knob tracking unavailable'
            $controls.LockHelp.Text = 'Unlock in Vial, then close Vial. Manual layer selection still works.'
        }
        'unlocking' {
            $controls.LockHeading.Text = 'Unlock in progress · finish in Vial'
            $controls.LockHelp.Text = 'Hold the highlighted keys until the progress bar finishes, then close Vial.'
        }
        default { $controls.LockHeading.Text = 'Checking pad lock status…' }
    }
    # Switch events may have been missed while monitoring was locked.
    if ($needsUnlock -and $previous -eq 'unlocked' -and $controls.TrackKnob.IsChecked) { Require-PadSync }
    Update-StripBadge
}
$controls.UnlockHelp.Add_Click({
    $instructions = @'
The pad must be unlocked for knob tracking. Manual selection still works while locked.

1. Click Release pad at the top of this display, then open Vial and select your Pad Plus.
2. Choose Security → Unlock (Ctrl+U in the desktop app).
3. Hold both keys highlighted by Vial. For the supported Pad Plus firmware, these are the upper-left and lower-left of the six main buttons, not the knob.
4. Keep holding until the progress bar finishes and the unlock dialog closes. Follow Vial's highlighted keys if they differ.
5. Close Vial, leaving the pad plugged in. Do not choose Security → Lock.
6. Click Reconnect, select the layer shown on the OLED, then enable Follow knob presses. Expand compact view if needed.

Unplugging, resetting, or losing USB power normally locks the pad again.
'@
    [void][Windows.MessageBox]::Show($window,$instructions,'Unlock your Pad Plus','OK','Information')
})
function Receive-PadNotices {
    if (-not $script:state.Monitor) { return }
    while ($null -ne ($notice = $script:state.Monitor.Next())) {
        switch ($notice.Kind) {
            'lock' { Update-LockWarning $notice.Text }
            'snapshot' {
                $candidate = Convert-PadSnapshot $notice.Data
                $script:state.Mode = 'live'; $script:state.Refreshed = Get-Date
                Set-DisplayData $candidate
                $seconds = if ($controls.TrackKnob.IsChecked) { [TogKeyDisplay.Monitor]::TrackingReadIntervalSeconds } else { [TogKeyDisplay.Monitor]::ReadIntervalSeconds }
                $controls.Connection.Text = 'Mappings read from pad · ' + $(if ($controls.AutoRead.IsChecked) { "auto-read every $seconds seconds" } else { 'auto-read paused' })
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#70DEC2')
            }
            'status' { $controls.Connection.Text = $notice.Text }
            'busy' {
                $controls.Connection.Text = $notice.Text
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
            }
            'responsive' {
                $controls.Connection.Text = $notice.Text
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#70DEC2')
            }
            'retry' {
                Update-LockWarning 'unknown'
                # A slow macro or a transient protocol error does not establish a USB disconnect.
                $controls.Connection.Text = $notice.Text + ' Retrying automatically.'
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
                if ($controls.TrackKnob.IsChecked -and $script:state.Synced) { $controls.TrackingStatus.Text = 'Reader recovering · layer kept; sync only if knob presses were missed' }
            }
            'disconnected' {
                Update-LockWarning 'unknown'
                Require-PadSync
                $controls.Connection.Text = $notice.Text + ' Previous labels retained.'
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
                if ($controls.TrackKnob.IsChecked) { $controls.TrackingStatus.Text = 'Tracking interrupted · select a layer to resync after reconnecting' }
            }
            'error' {
                $controls.Connection.Text = $notice.Text
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
            }
            'tracking' { if ($controls.TrackKnob.IsChecked -and $script:state.Synced) { $controls.TrackingStatus.Text = $notice.Text } }
            'press' {
                if ($controls.TrackKnob.IsChecked -and $script:state.Synced -and $notice.Epoch -eq $script:state.Generation) {
                    $action = (Get-ResolvedKey $script:state.Data $script:state.Layer 0 2).Code
                    if ($action -in @('USER00','QK_KB_0','TOG_LAY')) {
                        $script:state.Layer = ($script:state.Layer + 1) % 4
                        Update-Display
                        $controls.TrackingStatus.Text = 'Knob press seen · estimated layer; select a layer if out of sync'
                    } else { Require-PadSync; $controls.TrackingStatus.Text = 'Knob action differs on this layer · select the layer manually' }
                }
            }
        }
    }
}
function Start-PadMonitor([switch]$Resume) {
    if ($script:state.Released) {
        # Checkbox changes must not grab the pad back while the user is working in Vial.
        if (-not $Resume) {
            $controls.Connection.Text = 'Pad released · click Reconnect after closing Vial'
            return
        }
        $script:state.Released = $false
        # Presses made while released were never observed; the estimated layer may be stale.
        if ($controls.TrackKnob.IsChecked -and $script:state.Synced) { Require-PadSync }
        Update-StripBadge
    }
    try {
        Initialize-HidReader
        if (-not $script:state.Monitor) {
            Update-LockWarning 'unknown'
            $script:state.Monitor = [TogKeyDisplay.Monitor]::new()
            $script:state.Timer = [Windows.Threading.DispatcherTimer]::new()
            $script:state.Timer.Interval = [TimeSpan]::FromMilliseconds(60)
            $script:state.Timer.Add_Tick({
                try { Receive-PadNotices } catch {
                    Stop-PadMonitor
                    $controls.Connection.Text = 'Could not display pad data: ' + $_.Exception.Message
                }
            })
            $script:state.Timer.Start()
            Update-ReleaseButton
        }
        $script:state.Monitor.AutoRead = [bool]$controls.AutoRead.IsChecked
        $script:state.Monitor.TrackingEpoch = $script:state.Generation
        $script:state.Monitor.TrackKnob = [bool]$controls.TrackKnob.IsChecked -and $script:state.Synced
        $script:state.Monitor.Refresh = $true
    } catch { $controls.Connection.Text = 'Reader could not start: ' + $_.Exception.Message }
}
$controls.ReadPad.Add_Click({ Start-PadMonitor -Resume })
$controls.ReleasePad.Add_Click({
    if ($script:state.Monitor) { Disconnect-Pad } else { Start-PadMonitor -Resume }
})
$controls.AutoRead.Add_Checked({ Start-PadMonitor })
$controls.AutoRead.Add_Unchecked({
    if ($script:state.Monitor) { $script:state.Monitor.AutoRead = $false }
    $controls.Connection.Text = 'Auto-read paused · Read from pad updates now'
})
$controls.TrackKnob.Add_Checked({
    $controls.TrackingStatus.Text = if ($script:state.Synced) { 'Checking switch access…' } else { 'Select the layer shown on your pad before knob tracking begins' }
    Update-Display
    Start-PadMonitor
})
$controls.TrackKnob.Add_Unchecked({
    if ($script:state.Monitor) { $script:state.Monitor.TrackKnob = $false }
    $controls.TrackingStatus.Text = 'Tracking off · select layers manually'
    Update-Display
})

function Set-CompactDisplay([bool]$Enabled) {
    $window.Width = if ($Enabled) { 300 } else { 442 }
    $controls.Frame.Padding = if ($Enabled) { [Windows.Thickness]::new(12) } else { [Windows.Thickness]::new(22,18,22,18) }
    foreach ($name in @('Subtitle','KnobHeading','LayerHelp','ReadSettings','TrackKnob','TrackingStatus','Toolbar','Source')) {
        $controls[$name].Visibility = if ($Enabled) { 'Collapsed' } else { 'Visible' }
    }
    $controls.DragArea.Margin = [Windows.Thickness]::new(0,0,0,$(if ($Enabled) { 8 } else { 18 }))
    $controls.LayerTabs.Margin = [Windows.Thickness]::new(-3,0,-3,$(if ($Enabled) { 8 } else { 16 }))
    $controls.LayerHeader.Margin = [Windows.Thickness]::new(0,0,0,$(if ($Enabled) { 6 } else { 12 }))
    $controls.LayerHeading.FontSize = if ($Enabled) { 16 } else { 22 }
    $controls.LayerMode.FontSize = if ($Enabled) { 8 } else { 10 }
    foreach ($n in 0..3) {
        $controls["Layer$n"].Padding = if ($Enabled) { [Windows.Thickness]::new(3,7,3,7) } else { [Windows.Thickness]::new(5,10,5,10) }
        $controls["Layer$n"].FontSize = if ($Enabled) { 10 } else { 12 }
    }
    foreach ($tile in $script:tileControls) {
        $tile.Border.Height = if ($Enabled) { 55 } else { 87 }
        $tile.Border.Padding = [Windows.Thickness]::new($(if ($Enabled) { 5 } else { 10 }))
        $tile.Label.FontSize = if ($Enabled) { 11 } else { 13 }
        $tile.Hint.Visibility = if ($Enabled) { 'Collapsed' } else { 'Visible' }
    }
    $controls.Tiles.Margin = [Windows.Thickness]::new(-4,0,-4,$(if ($Enabled) { 6 } else { 12 }))
    $controls.KnobPanel.Padding = if ($Enabled) { [Windows.Thickness]::new(8,7,8,7) } else { [Windows.Thickness]::new(13,11,13,11) }
    $controls.KnobPanel.Margin = [Windows.Thickness]::new(0,0,0,$(if ($Enabled) { 6 } else { 14 }))
    $controls.KnobRotate.FontSize = if ($Enabled) { 10 } else { 12 }
    $controls.KnobPress.FontSize = if ($Enabled) { 10 } else { 12 }
    $controls.Connection.FontSize = if ($Enabled) { 10 } else { 11 }
    $controls.Connection.TextWrapping = if ($Enabled) { 'NoWrap' } else { 'Wrap' }
    $controls.Connection.TextTrimming = 'CharacterEllipsis'
    $controls.Connection.Margin = [Windows.Thickness]::new(0,0,0,$(if ($Enabled) { 2 } else { 12 }))
    $controls.ViewRow.Margin = [Windows.Thickness]::new(0,$(if ($Enabled) { 4 } else { 12 }),0,0)
    # Settings are hidden visually; the live reader, tracking and selected layer stay intact.
}
$controls.Compact.Add_Checked({ Set-CompactDisplay $true })
$controls.Compact.Add_Unchecked({ Set-CompactDisplay $false })

# ---- Saved preferences (view, positions, pin, reading options) ----
$script:settingsPath = if ($SettingsPath) { [IO.Path]::GetFullPath($SettingsPath) } else { Join-Path $PSScriptRoot 'TogKey preferences.json' }
function Read-DisplaySettings {
    if (-not (Test-Path -LiteralPath $script:settingsPath)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 4
        if ($raw.version -ne 1) { throw 'Unexpected preferences format.' }
        $settings = @{}
        foreach ($name in @('compact','strip','pinned','autoRead','trackKnob')) {
            if ($raw[$name] -is [bool]) { $settings[$name] = $raw[$name] }
        }
        foreach ($name in @('normalPosition','stripPosition')) {
            $value = @($raw[$name])
            if ($value.Count -eq 2 -and ($value | Where-Object { ($_ -is [double] -or $_ -is [long] -or $_ -is [int]) -and [double]::IsFinite($_) }).Count -eq 2) {
                $settings[$name] = @([double]$value[0], [double]$value[1])
            }
        }
        return $settings
    } catch {
        $controls.Connection.Text = 'Preferences file could not be read; defaults used.'
        return $null
    }
}
function Test-PositionVisible($Position) {
    # Discard positions from a monitor that is no longer attached; keep the title area reachable.
    if (-not $Position) { return $false }
    $left = [Windows.SystemParameters]::VirtualScreenLeft; $top = [Windows.SystemParameters]::VirtualScreenTop
    $right = $left + [Windows.SystemParameters]::VirtualScreenWidth; $bottom = $top + [Windows.SystemParameters]::VirtualScreenHeight
    return ($Position[0] + 80) -ge $left -and ($Position[0] + 80) -le $right -and $Position[1] -ge $top -and ($Position[1] + 30) -le $bottom
}
function Save-DisplaySettings {
    $bounds = if ($window.WindowState -eq 'Normal') { [Windows.Rect]::new($window.Left, $window.Top, 1, 1) } else { $window.RestoreBounds }
    $current = @([Math]::Round($bounds.Left), [Math]::Round($bounds.Top))
    if ($script:state.StripOn) { $script:state.StripPos = $current } else { $script:state.NormalPos = $current }
    $settings = [ordered]@{
        version = 1
        compact = [bool]$controls.Compact.IsChecked
        strip = [bool]$script:state.StripOn
        pinned = [bool]$window.Topmost
        autoRead = [bool]$controls.AutoRead.IsChecked
        trackKnob = [bool]$controls.TrackKnob.IsChecked
        normalPosition = $script:state.NormalPos
        stripPosition = $script:state.StripPos
    }
    try { Write-FileAtomically $script:settingsPath ($settings | ConvertTo-Json -Depth 4) } catch { }
}
$script:savedSettings = Read-DisplaySettings
if ($script:savedSettings) {
    if ($script:savedSettings.ContainsKey('pinned') -and -not $script:savedSettings.pinned) { Switch-Pinned }
    if ($script:savedSettings.ContainsKey('autoRead')) { $controls.AutoRead.IsChecked = $script:savedSettings.autoRead }
    if (Test-PositionVisible $script:savedSettings.normalPosition) { $script:state.NormalPos = $script:savedSettings.normalPosition }
    if (Test-PositionVisible $script:savedSettings.stripPosition) { $script:state.StripPos = $script:savedSettings.stripPosition }
}
# Command-line view switches override the saved view.
$controls.Compact.IsChecked = $Compact -or ($script:savedSettings -and $script:savedSettings.compact -and -not $Strip)
if ($Strip -or ($script:savedSettings -and $script:savedSettings.strip -and -not $Compact)) { Set-StripView $true }
$startPosition = if ($script:state.StripOn) { $script:state.StripPos } else { $script:state.NormalPos }
if ($startPosition) {
    $window.WindowStartupLocation = 'Manual'
    $window.Left, $window.Top = $startPosition
}
$window.Add_Closing({ if (-not $PreviewPath) { Save-DisplaySettings } })

# ---- Keyboard shortcuts ----
$script:shortcutHelp = @'
While the display is focused:
  1 – 4            Select pad layer (also resyncs knob tracking)
  ← / →            Previous / next layer
  F2               Rename the button, knob action, or layer tab under the mouse pointer
                   (otherwise the current layer's name)
  F5               Read from pad / reconnect
  R                Release pad for Vial / reconnect
  S                Strip view on / off
  C                Compact view on / off
  P                Pin on top on / off
  F1               This list

Anywhere in Windows:
  Ctrl + Alt + K   Show / minimize the display
'@
function Invoke-RenameShortcut {
    foreach ($i in 0..5) {
        if ($script:tileControls[$i].Border.IsMouseOver -or $script:stripTiles[$i].Border.IsMouseOver) {
            if ($script:state.Synced) { Edit-ButtonLabel $i }
            return
        }
    }
    if ($script:state.Synced -and $controls.KnobRotate.IsMouseOver) { Edit-KnobLabel 'turn'; return }
    if ($script:state.Synced -and $controls.KnobPress.IsMouseOver) { Edit-KnobLabel 'press'; return }
    foreach ($n in 0..3) { if ($controls["Layer$n"].IsMouseOver) { Edit-LayerName $n; return } }
    if ($script:state.Synced) { Edit-LayerName $script:state.Layer }
}
$window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    # Letter shortcuts only without modifiers, so system shortcuts (Alt+F4 and others) still work.
    if ([Windows.Input.Keyboard]::Modifiers -ne [Windows.Input.ModifierKeys]::None) { return }
    $key = $eventArgs.Key
    $handled = $true
    switch -Regex ([string]$key) {
        '^(D|NumPad)([1-4])$' { Confirm-PadLayer ([int]$Matches[2] - 1); break }
        '^Right$' { Confirm-PadLayer $(if ($script:state.Synced) { ($script:state.Layer + 1) % 4 } else { 0 }); break }
        '^Left$' { Confirm-PadLayer $(if ($script:state.Synced) { ($script:state.Layer + 3) % 4 } else { 3 }); break }
        '^F2$' { Invoke-RenameShortcut; break }
        '^F5$' { Start-PadMonitor -Resume; break }
        '^R$' { if ($script:state.Monitor) { Disconnect-Pad } else { Start-PadMonitor -Resume }; break }
        '^S$' { if ($script:state.StripOn) { Show-NormalView ([bool]$controls.Compact.IsChecked) } else { Set-StripView $true }; break }
        '^C$' { if ($script:state.StripOn) { Show-NormalView $true } else { $controls.Compact.IsChecked = -not $controls.Compact.IsChecked }; break }
        '^P$' { Switch-Pinned; break }
        '^F1$' { [void][Windows.MessageBox]::Show($window, $script:shortcutHelp, 'TogKey Display shortcuts', 'OK', 'Information'); break }
        default { $handled = $false }
    }
    $eventArgs.Handled = $handled
})
$window.Add_SourceInitialized({
    try {
        $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
        # Ctrl+Alt+K: restore and focus the display, or minimize it if it is already showing.
        $script:hotkey = [TogKeyDisplay.GlobalHotkey]::new($handle, 3, 0x4B, [Action]{
            if ($window.WindowState -eq 'Minimized') {
                $window.WindowState = 'Normal'
                [void]$window.Activate()
            } else { $window.WindowState = 'Minimized' }
        })
    } catch { $controls.Connection.Text = 'Ctrl+Alt+K is in use by another app; the show/hide shortcut is unavailable.' }
})
$window.Add_Closed({ if ($script:hotkey) { $script:hotkey.Dispose(); $script:hotkey = $null } })
$binding = [Windows.Data.Binding]::new('Text')
$binding.Source = $controls.Connection
[void]$controls.Connection.SetBinding([Windows.FrameworkElement]::ToolTipProperty,$binding)

if ($VialPath -and (Test-Path -LiteralPath $VialPath)) {
    try { Open-Layout $VialPath } catch {
        if ($PreviewPath) { throw }
        Show-LoadError $_.Exception.Message
    }
}
if (-not $script:state.Data) {
    Initialize-HidReader
    $script:state.Mode = 'empty'
    $blank = [TogKeyDisplay.Snapshot]::new()
    $blank.MacroTexts = [string[][]]@()
    Set-DisplayData (Convert-PadSnapshot $blank)
}

if ($PreviewPath) {
    # Render the window content without opening a desktop window.
    $content = $window.Content
    $content.Measure([Windows.Size]::new($window.Width, [double]::PositiveInfinity))
    $size = $content.DesiredSize
    $content.Arrange([Windows.Rect]::new(0, 0, $window.Width, $size.Height))
    $content.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.Width, [int][Math]::Ceiling($size.Height), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($PreviewPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    return
}
# Applied after mappings load: the TrackKnob handler redraws the display and starts the reader.
if ($script:savedSettings -and $script:savedSettings.trackKnob) { $controls.TrackKnob.IsChecked = $true }
Start-PadMonitor
[void]$window.ShowDialog()
