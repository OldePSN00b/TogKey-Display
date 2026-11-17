# Shared, UI-free functions for TogKey Display: keycode naming, .vil reading, and compiled-type caching.
# Imported as a module by "TogKey Display.ps1" and by the Pester tests in tests\.

function Read-VialLayout([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'No Vial export was specified.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Vial export not found: $Path" }
    try { $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100 }
    catch { throw "This file is not a Vial export (it is not valid JSON): $Path" }
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

# ---- Keycode numbers -> QMK names ----
# Vial protocol 6 uses QMK's current keycode layout. Names match what Vial writes to .vil exports,
# so live reads and imported files share one labelling path (Get-KeyLabel).

$script:BasicKeycodes = @{
    0x00='KC_NO'; 0x01='KC_TRNS'; 0x28='KC_ENTER'; 0x29='KC_ESC'; 0x2A='KC_BSPC'; 0x2B='KC_TAB'; 0x2C='KC_SPACE'
    0x2D='KC_MINUS'; 0x2E='KC_EQUAL'; 0x2F='KC_LBRC'; 0x30='KC_RBRC'; 0x31='KC_BSLS'; 0x32='KC_NUHS'
    0x33='KC_SCLN'; 0x34='KC_QUOT'; 0x35='KC_GRV'; 0x36='KC_COMM'; 0x37='KC_DOT'; 0x38='KC_SLSH'; 0x39='KC_CAPS'
    0x46='KC_PSCR'; 0x47='KC_SCRL'; 0x48='KC_PAUS'; 0x49='KC_INS'; 0x4A='KC_HOME'; 0x4B='KC_PGUP'
    0x4C='KC_DEL'; 0x4D='KC_END'; 0x4E='KC_PGDN'; 0x4F='KC_RIGHT'; 0x50='KC_LEFT'; 0x51='KC_DOWN'; 0x52='KC_UP'
    0x53='KC_NUM'; 0x54='KC_PSLS'; 0x55='KC_PAST'; 0x56='KC_PMNS'; 0x57='KC_PPLS'; 0x58='KC_PENT'
    0x62='KC_P0'; 0x63='KC_PDOT'; 0x64='KC_NUBS'; 0x65='KC_APP'; 0x67='KC_PEQL'
    0x74='KC_EXEC'; 0x75='KC_HELP'; 0x76='KC_MENU'; 0x77='KC_SLCT'; 0x78='KC_STOP'; 0x79='KC_AGIN'
    0x7A='KC_UNDO'; 0x7B='KC_CUT'; 0x7C='KC_COPY'; 0x7D='KC_PSTE'; 0x7E='KC_FIND'
    0xA5='KC_PWR'; 0xA6='KC_SLEP'; 0xA7='KC_WAKE'
    0xA8='KC_MUTE'; 0xA9='KC_VOLU'; 0xAA='KC_VOLD'; 0xAB='KC_MNXT'; 0xAC='KC_MPRV'; 0xAD='KC_MSTP'; 0xAE='KC_MPLY'
    0xAF='KC_MSEL'; 0xB0='KC_EJCT'; 0xB1='KC_MAIL'; 0xB2='KC_CALC'; 0xB3='KC_MYCM'
    0xB4='KC_WSCH'; 0xB5='KC_WHOM'; 0xB6='KC_WBAK'; 0xB7='KC_WFWD'; 0xB8='KC_WSTP'; 0xB9='KC_WREF'; 0xBA='KC_WFAV'
    0xBB='KC_MFFD'; 0xBC='KC_MRWD'; 0xBD='KC_BRIU'; 0xBE='KC_BRID'; 0xBF='KC_CPNL'; 0xC0='KC_ASST'
    0xCD='KC_MS_U'; 0xCE='KC_MS_D'; 0xCF='KC_MS_L'; 0xD0='KC_MS_R'
    0xD1='KC_BTN1'; 0xD2='KC_BTN2'; 0xD3='KC_BTN3'; 0xD4='KC_BTN4'; 0xD5='KC_BTN5'; 0xD6='KC_BTN6'; 0xD7='KC_BTN7'; 0xD8='KC_BTN8'
    0xD9='KC_WH_U'; 0xDA='KC_WH_D'; 0xDB='KC_WH_L'; 0xDC='KC_WH_R'; 0xDD='KC_ACL0'; 0xDE='KC_ACL1'; 0xDF='KC_ACL2'
    0xE0='KC_LCTL'; 0xE1='KC_LSFT'; 0xE2='KC_LALT'; 0xE3='KC_LGUI'; 0xE4='KC_RCTL'; 0xE5='KC_RSFT'; 0xE6='KC_RALT'; 0xE7='KC_RGUI'
}
$script:SpecialKeycodes = @{
    # Lighting (QK_BACKLIGHT_*, QK_UNDERGLOW_* / RGB_*)
    0x7800='BL_ON'; 0x7801='BL_OFF'; 0x7802='BL_TOGG'; 0x7803='BL_DOWN'; 0x7804='BL_UP'; 0x7805='BL_STEP'; 0x7806='BL_BRTG'
    0x7820='RGB_TOG'; 0x7821='RGB_MOD'; 0x7822='RGB_RMOD'; 0x7823='RGB_HUI'; 0x7824='RGB_HUD'; 0x7825='RGB_SAI'; 0x7826='RGB_SAD'
    0x7827='RGB_VAI'; 0x7828='RGB_VAD'; 0x7829='RGB_SPI'; 0x782A='RGB_SPD'; 0x782B='RGB_M_P'; 0x782C='RGB_M_B'; 0x782D='RGB_M_R'
    0x782E='RGB_M_SW'; 0x782F='RGB_M_SN'; 0x7830='RGB_M_K'; 0x7831='RGB_M_X'; 0x7832='RGB_M_G'; 0x7833='RGB_M_T'; 0x7834='RGB_M_TW'
    # Quantum
    0x7C00='QK_BOOT'; 0x7C01='QK_RBT'; 0x7C02='DB_TOGG'; 0x7C03='EE_CLR'; 0x7C16='QK_GESC'; 0x7C73='CW_TOGG'
}

function Get-ModifierName([int]$Mask) {
    # 5-bit QMK modifier mask: Ctrl=1, Shift=2, Alt=4, GUI=8, bit 16 selects the right-hand set.
    $side = if ($Mask -band 0x10) { 'R' } else { 'L' }
    $parts = foreach ($entry in @(@(1,'CTL'),@(2,'SFT'),@(4,'ALT'),@(8,'GUI'))) {
        if ($Mask -band $entry[0]) { "MOD_$side$($entry[1])" }
    }
    if (-not $parts) { return 'MOD_NONE' }
    return $parts -join '|'
}

function Convert-Keycode([int]$Code) {
    if ($script:BasicKeycodes.ContainsKey($Code)) { return $script:BasicKeycodes[$Code] }
    if ($script:SpecialKeycodes.ContainsKey($Code)) { return $script:SpecialKeycodes[$Code] }
    if ($Code -ge 0x04 -and $Code -le 0x1D) { return 'KC_' + [char](65 + $Code - 4) }
    if ($Code -ge 0x1E -and $Code -le 0x27) { return 'KC_' + (($Code - 29) % 10) }
    if ($Code -ge 0x3A -and $Code -le 0x45) { return 'KC_F' + ($Code - 57) }
    if ($Code -ge 0x68 -and $Code -le 0x73) { return 'KC_F' + ($Code - 91) }
    if ($Code -ge 0x59 -and $Code -le 0x61) { return 'KC_P' + ($Code - 88) }
    if ($Code -ge 0x0100 -and $Code -le 0x1FFF) {
        # Modifier + key, written the way Vial does: LCTL(LSFT(KC_C)).
        $mask = ($Code -shr 8) -band 0x1F
        $side = if ($mask -band 0x10) { 'R' } else { 'L' }
        $name = Convert-Keycode ($Code -band 0xFF)
        foreach ($entry in @(@(8,'GUI'),@(4,'ALT'),@(2,'SFT'),@(1,'CTL'))) {
            if ($mask -band $entry[0]) { $name = "$side$($entry[1])($name)" }
        }
        return $name
    }
    if ($Code -ge 0x2000 -and $Code -le 0x3FFF) {
        return 'MT({0},{1})' -f (Get-ModifierName (($Code -shr 8) -band 0x1F)), (Convert-Keycode ($Code -band 0xFF))
    }
    if ($Code -ge 0x4000 -and $Code -le 0x4FFF) {
        return 'LT({0},{1})' -f (($Code -shr 8) -band 0xF), (Convert-Keycode ($Code -band 0xFF))
    }
    if ($Code -ge 0x5000 -and $Code -le 0x51FF) {
        return 'LM({0},{1})' -f (($Code -shr 5) -band 0xF), (Get-ModifierName ($Code -band 0x1F))
    }
    if ($Code -ge 0x52A0 -and $Code -le 0x52BF) { return 'OSM({0})' -f (Get-ModifierName ($Code -band 0x1F)) }
    $families = @{ 0x5200='TO'; 0x5220='MO'; 0x5240='DF'; 0x5260='TG'; 0x5280='OSL'; 0x52C0='TT'; 0x52E0='PDF' }
    foreach ($start in $families.Keys) {
        if ($Code -ge $start -and $Code -lt ($start+32)) { return '{0}({1})' -f $families[$start],($Code-$start) }
    }
    if ($Code -ge 0x5700 -and $Code -le 0x57FF) { return 'TD({0})' -f ($Code - 0x5700) }
    if ($Code -ge 0x7700 -and $Code -le 0x777F) { return 'M' + ($Code - 0x7700) }
    if ($Code -ge 0x7E00 -and $Code -le 0x7E3F) { return 'USER{0:00}' -f ($Code - 0x7E00) }
    return '0x{0:X4}' -f $Code
}

# ---- QMK names -> display labels ----

$script:KeyLabels = @{
    KC_NO = 'Unassigned'; XXXXXXX = 'Unassigned'; KC_TRNS = 'Transparent'; _______ = 'Transparent'
    USER00 = 'Cycle layers'; QK_KB_0 = 'Cycle layers'; TOG_LAY = 'Cycle layers'
    KC_ENTER = 'Enter'; KC_ENT = 'Enter'; KC_ESC = 'Escape'; KC_SPACE = 'Space'; KC_SPC = 'Space'; KC_TAB = 'Tab'
    KC_BSPC = 'Backspace'; KC_DEL = 'Delete'; KC_INS = 'Insert'; KC_HOME = 'Home'; KC_END = 'End'
    KC_PGUP = 'Page up'; KC_PGDN = 'Page down'; KC_CAPS = 'Caps Lock'; KC_PSCR = 'Print screen'
    KC_SCRL = 'Scroll lock'; KC_PAUS = 'Pause'; KC_NUM = 'Num lock'; KC_APP = 'Menu key'
    KC_LEFT = 'Left arrow'; KC_RIGHT = 'Right arrow'; KC_RGHT = 'Right arrow'; KC_UP = 'Up arrow'; KC_DOWN = 'Down arrow'
    KC_MINUS = '-'; KC_MINS = '-'; KC_EQUAL = '='; KC_EQL = '='; KC_LBRC = '['; KC_RBRC = ']'; KC_BSLS = '\'
    KC_NUHS = '# (ISO)'; KC_NUBS = '\ (ISO)'; KC_SCLN = ';'; KC_QUOT = "'"; KC_GRV = '`'; KC_COMM = ','; KC_DOT = '.'; KC_SLSH = '/'
    KC_PSLS = 'Keypad /'; KC_PAST = 'Keypad *'; KC_PMNS = 'Keypad -'; KC_PPLS = 'Keypad +'; KC_PENT = 'Keypad Enter'
    KC_PDOT = 'Keypad .'; KC_PEQL = 'Keypad ='
    KC_LCTL = 'Left Ctrl'; KC_RCTL = 'Right Ctrl'; KC_LSFT = 'Left Shift'; KC_RSFT = 'Right Shift'
    KC_LALT = 'Left Alt'; KC_RALT = 'Right Alt'; KC_LGUI = 'Left Windows'; KC_RGUI = 'Right Windows'
    KC_EXEC = 'Execute'; KC_HELP = 'Help'; KC_MENU = 'Menu'; KC_SLCT = 'Select'; KC_STOP = 'Stop'; KC_AGIN = 'Again'
    KC_UNDO = 'Undo'; KC_CUT = 'Cut'; KC_COPY = 'Copy'; KC_PSTE = 'Paste'; KC_FIND = 'Find'
    KC_PWR = 'Power'; KC_SLEP = 'Sleep'; KC_WAKE = 'Wake'
    KC_VOLD = 'Volume down'; KC_VOLU = 'Volume up'; KC_MUTE = 'Mute'
    KC_MPRV = 'Previous track'; KC_MPLY = 'Play / Pause'; KC_MNXT = 'Next track'; KC_MSTP = 'Stop media'
    KC_MFFD = 'Fast forward'; KC_MRWD = 'Rewind'; KC_MSEL = 'Media player'; KC_EJCT = 'Eject'
    KC_MAIL = 'Mail'; KC_CALC = 'Calculator'; KC_MYCM = 'This PC'; KC_CPNL = 'Control panel'; KC_ASST = 'Assistant'
    KC_WSCH = 'Web search'; KC_WHOM = 'Browser home'; KC_WBAK = 'Browser back'; KC_WFWD = 'Browser forward'
    KC_WSTP = 'Browser stop'; KC_WREF = 'Browser refresh'; KC_WFAV = 'Favorites'
    KC_BRIU = 'Brightness up'; KC_BRID = 'Brightness down'
    KC_MS_U = 'Mouse up'; KC_MS_D = 'Mouse down'; KC_MS_L = 'Mouse left'; KC_MS_R = 'Mouse right'
    MS_UP = 'Mouse up'; MS_DOWN = 'Mouse down'; MS_LEFT = 'Mouse left'; MS_RGHT = 'Mouse right'
    KC_BTN1 = 'Left click'; KC_BTN2 = 'Right click'; KC_BTN3 = 'Middle click'; KC_BTN4 = 'Mouse back'; KC_BTN5 = 'Mouse forward'
    MS_BTN1 = 'Left click'; MS_BTN2 = 'Right click'; MS_BTN3 = 'Middle click'; MS_BTN4 = 'Mouse back'; MS_BTN5 = 'Mouse forward'
    KC_WH_U = 'Scroll up'; KC_WH_D = 'Scroll down'; KC_WH_L = 'Scroll left'; KC_WH_R = 'Scroll right'
    MS_WHLU = 'Scroll up'; MS_WHLD = 'Scroll down'; MS_WHLL = 'Scroll left'; MS_WHLR = 'Scroll right'
    KC_ACL0 = 'Mouse speed 1'; KC_ACL1 = 'Mouse speed 2'; KC_ACL2 = 'Mouse speed 3'
    MS_ACL0 = 'Mouse speed 1'; MS_ACL1 = 'Mouse speed 2'; MS_ACL2 = 'Mouse speed 3'
    BL_ON = 'Backlight on'; BL_OFF = 'Backlight off'; BL_TOGG = 'Backlight on/off'; BL_STEP = 'Backlight step'
    BL_DOWN = 'Backlight −'; BL_DEC = 'Backlight −'; BL_UP = 'Backlight +'; BL_INC = 'Backlight +'; BL_BRTG = 'Backlight breathing'
    RGB_TOG = 'RGB on/off'; UG_TOGG = 'RGB on/off'; RGB_MOD = 'RGB next effect'; UG_NEXT = 'RGB next effect'
    RGB_RMOD = 'RGB previous effect'; UG_PREV = 'RGB previous effect'
    RGB_HUI = 'RGB hue +'; UG_HUEU = 'RGB hue +'; RGB_HUD = 'RGB hue −'; UG_HUED = 'RGB hue −'
    RGB_SAI = 'RGB saturation +'; UG_SATU = 'RGB saturation +'; RGB_SAD = 'RGB saturation −'; UG_SATD = 'RGB saturation −'
    RGB_VAI = 'RGB brightness +'; UG_VALU = 'RGB brightness +'; RGB_VAD = 'RGB brightness −'; UG_VALD = 'RGB brightness −'
    RGB_SPI = 'RGB speed +'; UG_SPDU = 'RGB speed +'; RGB_SPD = 'RGB speed −'; UG_SPDD = 'RGB speed −'
    RGB_M_P = 'RGB plain'; RGB_M_B = 'RGB breathe'; RGB_M_R = 'RGB rainbow'; RGB_M_SW = 'RGB swirl'; RGB_M_SN = 'RGB snake'
    RGB_M_K = 'RGB knight'; RGB_M_X = 'RGB Christmas'; RGB_M_G = 'RGB gradient'; RGB_M_T = 'RGB test'; RGB_M_TW = 'RGB twinkle'
    QK_BOOT = 'Bootloader'; RESET = 'Bootloader'; QK_RBT = 'Reboot'; DB_TOGG = 'Debug on/off'
    EE_CLR = 'Clear EEPROM'; QK_GESC = 'Esc / `'; KC_GESC = 'Esc / `'; CW_TOGG = 'Caps Word'
}
# Modifier tokens as they appear in Vial names: wrappers LCTL(kc), hold-taps LCTL_T(kc), and MOD_* masks.
$script:ModifierLabels = @{
    LCTL = 'Ctrl'; CTL = 'Ctrl'; C = 'Ctrl'; LSFT = 'Shift'; SFT = 'Shift'; S = 'Shift'
    LALT = 'Alt'; ALT = 'Alt'; A = 'Alt'; LOPT = 'Alt'; OPT = 'Alt'
    LGUI = 'Win'; GUI = 'Win'; G = 'Win'; LCMD = 'Win'; CMD = 'Win'; LWIN = 'Win'; WIN = 'Win'
    RCTL = 'Right Ctrl'; RSFT = 'Right Shift'; RALT = 'Right Alt'; ROPT = 'Right Alt'; ALGR = 'AltGr'
    RGUI = 'Right Win'; RCMD = 'Right Win'; RWIN = 'Right Win'
    C_S = 'Ctrl + Shift'; LCS = 'Ctrl + Shift'; LCA = 'Ctrl + Alt'; LSA = 'Shift + Alt'; LCAG = 'Ctrl + Alt + Win'
    SGUI = 'Shift + Win'; SCMD = 'Shift + Win'; SWIN = 'Shift + Win'; LSG = 'Shift + Win'; LAG = 'Alt + Win'
    RCS = 'Right Ctrl + Shift'; RSA = 'Right Shift + Alt'; RSG = 'Right Shift + Win'; RAG = 'Right Alt + Win'; RCAG = 'Right Ctrl + Alt + Win'
    MEH = 'Ctrl + Shift + Alt'; HYPR = 'Ctrl + Shift + Alt + Win'; ALL = 'Ctrl + Shift + Alt + Win'
    NONE = ''
}

function Format-Modifiers([string]$Text) {
    # "MOD_LCTL|MOD_LSFT" or "LCTL" -> "Ctrl + Shift"; $null if a token is not a modifier.
    $parts = foreach ($token in ($Text -split '\|')) {
        $name = ($token.Trim() -replace '^MOD_', '')
        if (-not $script:ModifierLabels.ContainsKey($name)) { return $null }
        if ($script:ModifierLabels[$name]) { $script:ModifierLabels[$name] }
    }
    return (@($parts) -join ' + ')
}

function Split-LayerArgument([string]$Digits, [string]$Inner) {
    # Accept both Vial spellings: LT1(KC_A) and LT(1,KC_A).
    if ($Digits) { return @([int]$Digits, $Inner) }
    if ($Inner -match '^\s*(\d+)\s*,\s*(.+)$') { return @([int]$Matches[1], $Matches[2]) }
    return $null
}

function Get-KeyLabel($Code, $Data) {
    $key = ([string]$Code).Trim()
    if ($script:KeyLabels.ContainsKey($key)) { return $script:KeyLabels[$key] }
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
    # Vial writes keycodes it has no name for as hex; decode them the same way as live reads.
    if ($key -match '^0x([0-9A-Fa-f]{1,4})$') {
        $name = Convert-Keycode ([Convert]::ToInt32($Matches[1], 16))
        if ($name -notmatch '^0x') { return Get-KeyLabel $name $Data }
        return $key
    }
    # Layers are shown with the OLED's 1-4 numbering (Vial layer + 1).
    if ($key -match '^(TO|MO|DF|TG|OSL|TT|PDF)\((\d+)\)$') {
        $pad = [int]$Matches[2] + 1
        $verb = @{ TO='Go to'; MO='Hold for'; DF='Default'; TG='Toggle'; OSL='One-shot'; TT='Tap-toggle'; PDF='Set default' }[$Matches[1]]
        return "$verb Pad $pad"
    }
    if ($key -match '^LT(\d*)\((.+)\)$') {
        $parts = Split-LayerArgument $Matches[1] $Matches[2]
        if ($parts) { return '{0} · hold Pad {1}' -f (Get-KeyLabel $parts[1] $Data), ($parts[0] + 1) }
    }
    if ($key -match '^LM(\d*)\((.+)\)$') {
        $parts = Split-LayerArgument $Matches[1] $Matches[2]
        if ($parts) {
            $mods = Format-Modifiers $parts[1]
            if ($null -ne $mods) { return "Hold Pad $($parts[0] + 1) + $mods" }
        }
    }
    if ($key -match '^MT\(([^,]+),(.+)\)$') {
        $mods = Format-Modifiers $Matches[1]
        if ($null -ne $mods) { return '{0} · hold {1}' -f (Get-KeyLabel $Matches[2] $Data), $mods }
    }
    if ($key -match '^([A-Z_]+?)_T\((.+)\)$') {
        $mods = Format-Modifiers $Matches[1]
        if ($mods) { return '{0} · hold {1}' -f (Get-KeyLabel $Matches[2] $Data), $mods }
    }
    if ($key -match '^OSM\((.+)\)$') {
        $mods = Format-Modifiers $Matches[1]
        if ($mods) { return "One-shot $mods" }
    }
    if ($key -match '^([A-Z_]+)\((.+)\)$') {
        # Modifier wrappers nest, so LCTL(LSFT(KC_C)) becomes "Ctrl + Shift + C".
        $mods = Format-Modifiers $Matches[1]
        if ($mods) { return '{0} + {1}' -f $mods, (Get-KeyLabel $Matches[2] $Data) }
    }
    if ($key -match '^TD\((\d+)\)$') { return "Tap dance $($Matches[1])" }
    if ($key -match '^KC_P(\d)$') { return "Keypad $($Matches[1])" }
    if ($key -match '^KC_(.+)$') { return $Matches[1] -replace '_', ' ' }
    return $key
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

function Get-ResolvedKey($Data, [int]$Layer, [int]$Row, [int]$Column) {
    $code = $Data.layout[$Layer][$Row][$Column]
    $inherited = $Layer -gt 0 -and $code -eq 'KC_TRNS'
    # This firmware uses layer_move: only the selected layer and default layer 0 apply.
    if ($inherited) { $code = $Data.layout[0][$Row][$Column] }
    [pscustomobject]@{ Code = $code; Label = Get-KeyLabel $code $Data; Inherited = $inherited }
}

# ---- Compiled C# cache ----

function Get-CompiledTypeCacheDirectory {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TogKeyDisplay\cache'
}

function Import-CompiledSource {
    # Compiling C# costs roughly half a second per launch; loading a cached DLL takes milliseconds.
    # The cache key covers the source, references and runtime, so any edit or upgrade recompiles.
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$CacheName,
        [string[]]$ReferencedAssemblies = @(),
        [string]$CacheDirectory = (Get-CompiledTypeCacheDirectory)
    )
    if ($TypeName -as [type]) { return }
    $compileOptions = @{ TypeDefinition = $Source }
    if ($ReferencedAssemblies) { $compileOptions.ReferencedAssemblies = $ReferencedAssemblies }
    $fingerprint = $Source, ($ReferencedAssemblies | ForEach-Object { [IO.Path]::GetFileName($_) }) -join '|'
    $fingerprint += '|' + $PSVersionTable.PSVersion + '|' + [Environment]::Version
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($fingerprint))).Substring(0, 16)
    $dll = Join-Path $CacheDirectory "$CacheName-$hash.dll"
    if (Test-Path -LiteralPath $dll) {
        try { Add-Type -LiteralPath $dll; if ($TypeName -as [type]) { return } } catch { }
        # Unreadable or incompatible cache entry: rebuild it below.
        try { Remove-Item -LiteralPath $dll -Force } catch { }
    }
    try {
        [void](New-Item -ItemType Directory -Force -Path $CacheDirectory)
        $temporary = Join-Path $CacheDirectory ("$CacheName-$hash." + [guid]::NewGuid().ToString('N') + '.tmp.dll')
        Add-Type @compileOptions -OutputAssembly $temporary -OutputType Library
        try { [IO.File]::Move($temporary, $dll) } catch { }   # Another instance may have won the race.
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        Add-Type -LiteralPath $dll
    } catch {
        # Cache unavailable (read-only profile, locked file): compile in memory as before.
        if (-not ($TypeName -as [type])) { Add-Type @compileOptions }
    }
    # Remove stale builds of this component; ones still loaded by another instance stay until next time.
    Get-ChildItem -LiteralPath $CacheDirectory -Filter "$CacheName-*.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $dll } |
        ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { } }
}

function Initialize-HidReader {
    Import-CompiledSource -TypeName 'TogKeyDisplay.Reader' -CacheName 'TogKeyHid' `
        -Source (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TogKey Hid.cs') -Raw)
}
Export-ModuleMember -Function Read-VialLayout, Convert-Keycode, Get-KeyLabel, Convert-PadSnapshot, Get-ResolvedKey, Import-CompiledSource, Initialize-HidReader, Get-CompiledTypeCacheDirectory
