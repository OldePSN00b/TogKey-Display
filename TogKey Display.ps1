#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$VialPath = '',
    [switch]$ValidateOnly,
    [switch]$ReadPadOnly,
    [switch]$Compact,
    [string]$LabelsPath,
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
  <Border x:Name="Frame" Background="#10151F" BorderBrush="#303B4D" BorderThickness="1" Padding="22,18,22,18">
    <StackPanel>
      <Grid x:Name="DragArea" Background="Transparent" Margin="0,0,0,18">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="TOGKEY" FontSize="12" FontWeight="Bold" Foreground="#70DEC2"/>
          <TextBlock x:Name="Subtitle" Text="Your pad, at a glance" FontSize="18" FontWeight="SemiBold" Margin="0,3,0,0"/>
        </StackPanel>
        <Button x:Name="Minimize" Grid.Column="1" Content="−" Width="30" Padding="0,5" Margin="0,0,5,0" VerticalAlignment="Top" ToolTip="Minimize"/>
        <Button x:Name="Close" Grid.Column="2" Content="×" Width="30" Padding="0,5" VerticalAlignment="Top" ToolTip="Close"/>
      </Grid>
      <UniformGrid x:Name="LayerTabs" Columns="4" Margin="-3,0,-3,16">
        <Button x:Name="Layer0" Content="Layer 0" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer1" Content="Layer 1" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer2" Content="Layer 2" Margin="3,0" Padding="5,10"/>
        <Button x:Name="Layer3" Content="Layer 3" Margin="3,0" Padding="5,10"/>
      </UniformGrid>
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
      <TextBlock x:Name="LayerHelp" Text="Select the matching layer above, or enable knob tracking below. Layer selection here changes only this display." Foreground="#94A4BA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"/>
      <Grid x:Name="ReadSettings" Margin="0,0,0,10">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button x:Name="ReadPad" Content="Read from pad" HorizontalAlignment="Left" Background="#29493F" Foreground="#A5F1D9" FontSize="11" Padding="10,8"/>
        <CheckBox x:Name="AutoRead" Grid.Column="1" Content="Auto-read mappings" IsChecked="True" Foreground="#B9C5D6" VerticalAlignment="Center" FontSize="11" ToolTip="Read saved mappings every 8 seconds"/>
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
      <CheckBox x:Name="Compact" Content="Compact" Foreground="#B9C5D6" FontSize="11" Margin="0,12,0,0" ToolTip="Shrink the display. Live reads and knob tracking keep running."/>
    </StackPanel>
  </Border>
</Window>
'@
$reader = [Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
$controls = @{}
foreach ($name in @('DragArea','Minimize','Close','Layer0','Layer1','Layer2','Layer3','LayerHeading','LayerMode','Tiles','KnobRotate','KnobPress','Pin','Reload','Browse','Source','ReadPad','AutoRead','Connection','TrackKnob','TrackingStatus','Frame','Subtitle','LayerTabs','LayerHeader','KnobPanel','KnobHeading','LayerHelp','ReadSettings','Toolbar','Compact')) {
    $controls[$name] = $window.FindName($name)
}
$script:state = @{ Data = $null; Path = $VialPath; Layer = 0; Mode = 'file'; Refreshed = Get-Date; Monitor = $null; Timer = $null; Generation = 0 }
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
function Save-DisplayLabel([string]$Id, [string]$Text) {
    if ($Id -notmatch '^(button:[0-3]:[0-5]|layer:[0-3]|knob:[0-3]:(turn|press))$') { throw 'Invalid label position.' }
    $candidate = $script:displayLabels.Clone()
    $clean = ($Text -replace '\s+', ' ').Trim()
    if ($clean.Length -gt 64) { throw 'Labels must be 64 characters or fewer.' }
    if ([string]::IsNullOrWhiteSpace($clean)) { $candidate.Remove($Id) } else { $candidate[$Id] = $clean }
    $json = @{ version=1; labels=$candidate } | ConvertTo-Json -Depth 8
    $temporaryPath = $script:labelPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $script:labelPath, $true)
    } finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
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

function Update-Display {
    $layer = $script:state.Layer
    $data = $script:state.Data
    $defaultNames = @('','','','')
    foreach ($n in 0..3) {
        $name = Get-DisplayLabel "layer:$n" $defaultNames[$n]
        $text = if ($name) { "$n · $name" } else { "Layer $n" }
        $tabText = [Windows.Controls.TextBlock]::new()
        $tabText.Text = $text; $tabText.TextTrimming = 'CharacterEllipsis'
        $controls["Layer$n"].Content = $tabText
        $controls["Layer$n"].ToolTip = "$text · right-click to rename"
        $controls["Layer$n"].Tag = $n
        $controls["Layer$n"].DataContext = $defaultNames[$n]
    }
    $controls.LayerHeading.Text = "Layer $layer"
    foreach ($n in 0..3) {
        $selected = $n -eq $layer
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
    $sourceName = if ($script:state.Mode -eq 'live') { 'Pad mappings' } elseif ($script:state.Mode -eq 'empty') { 'No mappings loaded' } else { [IO.Path]::GetFileName($script:state.Path) }
    $controls.Source.Text = $sourceName + ' · read ' + $script:state.Refreshed.ToString('h:mm:ss tt')
    $controls.Source.ToolTip = if ($script:state.Mode -eq 'live') { 'Read directly from the pad; active layer is not reported by firmware.' } else { $script:state.Path }
}

function Set-DisplayData($candidate) {
    $script:state.Data = $candidate
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
            $controls.Connection.Text = 'Viewing an export · Read from pad reconnects'
        } catch { Show-LoadError $_.Exception.Message }
    }
}
foreach ($n in 0..3) {
    $controls["Layer$n"].Tag = $n
    $controls["Layer$n"].Add_Click({ param($sender, $eventArgs) $script:state.Layer = [int]$sender.Tag; Update-Display })
    $controls["Layer$n"].Add_MouseRightButtonUp({
        param($sender, $eventArgs)
        $number = [int]$sender.Tag
        $automatic = [string]$sender.DataContext
        Edit-DisplayLabel "layer:$number" $automatic "Layer $number name"
        $eventArgs.Handled = $true
    })
}
foreach ($i in 0..5) {
    $script:tileControls[$i].Border.Tag = $i
    $script:tileControls[$i].Border.Add_MouseRightButtonUp({
        param($sender, $eventArgs)
        $position = [int]$sender.Tag
        $layer = $script:state.Layer
        $row = 1 + [int][Math]::Floor($position / 3)
        $column = $position % 3
        $automatic = (Get-ResolvedKey $script:state.Data $layer $row $column).Label
        Edit-DisplayLabel "button:${layer}:$position" $automatic "Layer $layer · button $($position+1)"
        $eventArgs.Handled = $true
    })
}
$controls.KnobRotate.Add_MouseRightButtonUp({
    param($sender,$eventArgs)
    Edit-DisplayLabel "knob:$($script:state.Layer):turn" ([string]$sender.Tag) 'Knob turn label'
    $eventArgs.Handled = $true
})
$controls.KnobPress.Add_MouseRightButtonUp({
    param($sender,$eventArgs)
    Edit-DisplayLabel "knob:$($script:state.Layer):press" ([string]$sender.Tag) 'Knob press label'
    $eventArgs.Handled = $true
})
$controls.Close.Add_Click({ $window.Close() })
$window.Add_Closed({ Stop-PadMonitor })
$controls.Minimize.Add_Click({ $window.WindowState = 'Minimized' })
$controls.DragArea.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.OriginalSource -isnot [Windows.Controls.Button]) {
        try { $window.DragMove() } catch { }
    }
})
$controls.Pin.Add_Click({
    $window.Topmost = -not $window.Topmost
    $controls.Pin.Content = $(if ($window.Topmost) { 'Pinned ✓' } else { 'Pin on top' })
})
$controls.Reload.Add_Click({
    if ($script:state.Mode -eq 'live' -or $controls.AutoRead.IsChecked) { Start-PadMonitor }
    else { try { Open-Layout $script:state.Path } catch { Show-LoadError $_.Exception.Message } }
})
$controls.Browse.Add_Click({ Select-Layout })

function Stop-PadMonitor {
    if ($script:state.Timer) { $script:state.Timer.Stop(); $script:state.Timer = $null }
    if ($script:state.Monitor) { $script:state.Monitor.Dispose(); $script:state.Monitor = $null }
}
function Receive-PadNotices {
    if (-not $script:state.Monitor) { return }
    while ($null -ne ($notice = $script:state.Monitor.Next())) {
        switch ($notice.Kind) {
            'snapshot' {
                $candidate = Convert-PadSnapshot $notice.Data
                $script:state.Mode = 'live'; $script:state.Refreshed = Get-Date
                Set-DisplayData $candidate
                $controls.Connection.Text = 'Mappings read from pad · ' + $(if ($controls.AutoRead.IsChecked) { 'auto-read every 8 seconds' } else { 'auto-read paused' })
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#70DEC2')
            }
            'status' { $controls.Connection.Text = $notice.Text }
            'error' {
                $controls.Connection.Text = $notice.Text + ' Previous labels retained.'
                $controls.Connection.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#EFCB85')
                if ($controls.TrackKnob.IsChecked) { $controls.TrackingStatus.Text = 'Tracking interrupted · select a layer to resync after reconnecting' }
            }
            'tracking' { if ($controls.TrackKnob.IsChecked) { $controls.TrackingStatus.Text = $notice.Text } }
            'press' {
                if ($controls.TrackKnob.IsChecked) {
                    $action = (Get-ResolvedKey $script:state.Data $script:state.Layer 0 2).Code
                    if ($action -in @('USER00','QK_KB_0','TOG_LAY')) {
                        $script:state.Layer = ($script:state.Layer + 1) % 4
                        Update-Display
                        $controls.TrackingStatus.Text = 'Knob press seen · estimated layer; select a layer if out of sync'
                    } else { $controls.TrackingStatus.Text = 'Knob action differs on this layer · select the layer manually' }
                }
            }
        }
    }
}
function Start-PadMonitor {
    try {
        Initialize-HidReader
        if (-not $script:state.Monitor) {
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
        }
        $script:state.Monitor.AutoRead = [bool]$controls.AutoRead.IsChecked
        $script:state.Monitor.TrackKnob = [bool]$controls.TrackKnob.IsChecked
        $script:state.Monitor.Refresh = $true
    } catch { $controls.Connection.Text = 'Reader could not start: ' + $_.Exception.Message }
}
$controls.ReadPad.Add_Click({ Start-PadMonitor })
$controls.AutoRead.Add_Checked({ Start-PadMonitor })
$controls.AutoRead.Add_Unchecked({
    if ($script:state.Monitor) { $script:state.Monitor.AutoRead = $false }
    $controls.Connection.Text = 'Auto-read paused · Read from pad updates now'
})
$controls.TrackKnob.Add_Checked({
    $controls.LayerMode.Text = 'ESTIMATED LAYER'
    $controls.TrackingStatus.Text = 'Checking switch access · sync the layer using the buttons above'
    Start-PadMonitor
})
$controls.TrackKnob.Add_Unchecked({
    if ($script:state.Monitor) { $script:state.Monitor.TrackKnob = $false }
    $controls.LayerMode.Text = 'MANUAL LAYER'
    $controls.TrackingStatus.Text = 'Tracking off · select layers manually'
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
    $controls.Compact.Margin = [Windows.Thickness]::new(0,$(if ($Enabled) { 4 } else { 12 }),0,0)
    # Settings are hidden visually; the live reader, tracking and selected layer stay intact.
}
$controls.Compact.Add_Checked({ Set-CompactDisplay $true })
$controls.Compact.Add_Unchecked({ Set-CompactDisplay $false })
if ($Compact) { $controls.Compact.IsChecked = $true }
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
Start-PadMonitor
[void]$window.ShowDialog()
