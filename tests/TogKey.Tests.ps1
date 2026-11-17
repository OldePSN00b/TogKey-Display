#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Run from the repository folder:  Invoke-Pester .\tests
# No pad is needed: protocol tests use synthetic replies shaped like the VIA 9 / Vial 6 wire format.

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'TogKey Core.psm1') -Force
    if (-not ('TogKeyDisplay.Reader' -as [type])) { Add-Type -LiteralPath (Join-Path $root 'TogKey Hid.cs') }
    if (-not ('TogKeyTests.FakeReportStream' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
namespace TogKeyTests {
    // Stands in for the HID FileStream: each read returns one queued 33-byte input report.
    public sealed class FakeReportStream : Stream {
        public readonly ConcurrentQueue<byte[]> Replies = new ConcurrentQueue<byte[]>();
        public readonly List<byte[]> Written = new List<byte[]>();
        public bool Disconnected;
        public override bool CanRead { get { return true; } }
        public override bool CanWrite { get { return true; } }
        public override bool CanSeek { get { return false; } }
        public override long Length { get { throw new NotSupportedException(); } }
        public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken token) {
            var copy = new byte[count]; Array.Copy(buffer, offset, copy, 0, count); Written.Add(copy);
            return Task.CompletedTask;
        }
        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken token) {
            if (Disconnected) return 0;
            byte[] reply;
            if (Replies.TryDequeue(out reply)) { Array.Copy(reply, 0, buffer, offset, reply.Length); return reply.Length; }
            await Task.Delay(Timeout.Infinite, token);
            return 0;
        }
    }
}
'@
    }

    function New-Packet([byte[]]$Bytes) {
        # 32-byte VIA payload, zero padded.
        $packet = [byte[]]::new(32); [Array]::Copy($Bytes, $packet, $Bytes.Length); return ,$packet
    }
    function New-Report([byte[]]$Payload) {
        # Windows input report: report ID 0 followed by the 32-byte payload.
        $report = [byte[]]::new(33); [Array]::Copy((New-Packet $Payload), 0, $report, 1, 32); return ,$report
    }
    function New-TestHid($Stream, [int]$Seconds = 30) {
        $constructor = [TogKeyDisplay.Hid].GetConstructor([Reflection.BindingFlags]'Instance,NonPublic', $null,
            [type[]]@([IO.Stream], [Threading.CancellationToken]), $null)
        $script:hidTokens = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($Seconds))
        return $constructor.Invoke(@($Stream, $script:hidTokens.Token))
    }
    function New-FakePad {
        # Answers the read commands Reader.Read issues, from an in-memory keymap/encoder/macro image.
        param([uint16[]]$Keys, [uint16[]]$Encoders, [byte[]]$Macros, [int]$MacroCount, [int]$Layers = 4)
        $keymap = [byte[]]::new(72)
        for ($i = 0; $i -lt 36; $i++) { $keymap[2*$i] = $Keys[$i] -shr 8; $keymap[2*$i+1] = $Keys[$i] -band 0xFF }
        $state = @{ Keymap = $keymap; Encoders = $Encoders; Macros = $Macros; MacroCount = $MacroCount; Layers = $Layers }
        return [Func[byte[],byte[]]]{
            param($p)
            $reply = [byte[]]::new(32)
            switch ($p[0]) {
                0x01 { $reply[0] = 1; $reply[2] = 9 }
                0x11 { $reply[0] = 0x11; $reply[1] = $state.Layers }
                0x0C { $reply[0] = 0x0C; $reply[1] = $state.MacroCount }
                0x0D { $reply[0] = 0x0D; $reply[1] = $state.Macros.Length -shr 8; $reply[2] = $state.Macros.Length -band 0xFF }
                { $_ -in 0x12, 0x0E } {
                    $source = if ($p[0] -eq 0x12) { $state.Keymap } else { $state.Macros }
                    $offset = ($p[1] -shl 8) -bor $p[2]
                    [Array]::Copy($p, $reply, 4)
                    [Array]::Copy($source, $offset, $reply, 4, [Math]::Min($p[3], $source.Length - $offset))
                }
                0xFE {
                    if ($p[1] -eq 0) { $reply[0] = 6; [Array]::Copy([byte[]](0x77,0xF7,0x14,0xBB,0x74,0x32,0x66,0xE9), 0, $reply, 4, 8) }
                    if ($p[1] -eq 3) {
                        $layer = $p[2]
                        foreach ($d in 0..1) {
                            $value = $state.Encoders[$layer*2 + $d]
                            $reply[2*$d] = $value -shr 8; $reply[2*$d+1] = $value -band 0xFF
                        }
                    }
                }
            }
            return ,$reply
        }.GetNewClosure()
    }
}

Describe 'Convert-Keycode' {
    It 'names <Code> as <Name>' -ForEach @(
        @{ Code = 0x0000; Name = 'KC_NO' }
        @{ Code = 0x0001; Name = 'KC_TRNS' }
        @{ Code = 0x0004; Name = 'KC_A' }
        @{ Code = 0x0027; Name = 'KC_0' }
        @{ Code = 0x0045; Name = 'KC_F12' }
        @{ Code = 0x0073; Name = 'KC_F24' }
        @{ Code = 0x005D; Name = 'KC_P5' }
        @{ Code = 0x00A9; Name = 'KC_VOLU' }
        @{ Code = 0x00B6; Name = 'KC_WBAK' }
        @{ Code = 0x00CD; Name = 'KC_MS_U' }
        @{ Code = 0x00D1; Name = 'KC_BTN1' }
        @{ Code = 0x00D9; Name = 'KC_WH_U' }
        @{ Code = 0x0106; Name = 'LCTL(KC_C)' }
        @{ Code = 0x0306; Name = 'LCTL(LSFT(KC_C))' }
        @{ Code = 0x1408; Name = 'RALT(KC_E)' }
        @{ Code = 0x2104; Name = 'MT(MOD_LCTL,KC_A)' }
        @{ Code = 0x254C; Name = 'MT(MOD_LCTL|MOD_LALT,KC_DEL)' }
        @{ Code = 0x412C; Name = 'LT(1,KC_SPACE)' }
        @{ Code = 0x5028; Name = 'LM(1,MOD_LGUI)' }
        @{ Code = 0x5202; Name = 'TO(2)' }
        @{ Code = 0x5221; Name = 'MO(1)' }
        @{ Code = 0x5263; Name = 'TG(3)' }
        @{ Code = 0x52A2; Name = 'OSM(MOD_LSFT)' }
        @{ Code = 0x5703; Name = 'TD(3)' }
        @{ Code = 0x7705; Name = 'M5' }
        @{ Code = 0x7820; Name = 'RGB_TOG' }
        @{ Code = 0x7802; Name = 'BL_TOGG' }
        @{ Code = 0x7C00; Name = 'QK_BOOT' }
        @{ Code = 0x7C73; Name = 'CW_TOGG' }
        @{ Code = 0x7E00; Name = 'USER00' }
        @{ Code = 0x9999; Name = '0x9999' }
    ) {
        Convert-Keycode $Code | Should -BeExactly $Name
    }
}

Describe 'Get-KeyLabel' {
    It 'labels <Name> as <Label>' -ForEach @(
        @{ Name = 'KC_A'; Label = 'A' }
        @{ Name = 'KC_MINUS'; Label = '-' }
        @{ Name = 'KC_PGDN'; Label = 'Page down' }
        @{ Name = 'KC_P5'; Label = 'Keypad 5' }
        @{ Name = 'KC_F13'; Label = 'F13' }
        @{ Name = 'KC_BTN1'; Label = 'Left click' }
        @{ Name = 'MS_BTN2'; Label = 'Right click' }
        @{ Name = 'KC_WH_D'; Label = 'Scroll down' }
        @{ Name = 'KC_WBAK'; Label = 'Browser back' }
        @{ Name = 'RGB_TOG'; Label = 'RGB on/off' }
        @{ Name = 'UG_TOGG'; Label = 'RGB on/off' }
        @{ Name = 'QK_BOOT'; Label = 'Bootloader' }
        @{ Name = 'USER00'; Label = 'Cycle layers' }
        @{ Name = 'LCTL(KC_C)'; Label = 'Ctrl + C' }
        @{ Name = 'LCTL(LSFT(KC_ESC))'; Label = 'Ctrl + Shift + Escape' }
        @{ Name = 'C_S(KC_T)'; Label = 'Ctrl + Shift + T' }
        @{ Name = 'HYPR(KC_K)'; Label = 'Ctrl + Shift + Alt + Win + K' }
        @{ Name = 'RALT(KC_E)'; Label = 'Right Alt + E' }
        @{ Name = 'LCTL_T(KC_A)'; Label = 'A · hold Ctrl' }
        @{ Name = 'C_S_T(KC_X)'; Label = 'X · hold Ctrl + Shift' }
        @{ Name = 'MT(MOD_LCTL|MOD_LALT,KC_DEL)'; Label = 'Delete · hold Ctrl + Alt' }
        @{ Name = 'LT(1,KC_SPACE)'; Label = 'Space · hold Pad 2' }
        @{ Name = 'LT2(KC_TAB)'; Label = 'Tab · hold Pad 3' }
        @{ Name = 'LM(1,MOD_LGUI)'; Label = 'Hold Pad 2 + Win' }
        @{ Name = 'OSM(MOD_LSFT)'; Label = 'One-shot Shift' }
        @{ Name = 'MO(2)'; Label = 'Hold for Pad 3' }
        @{ Name = 'TO(0)'; Label = 'Go to Pad 1' }
        @{ Name = 'TG(3)'; Label = 'Toggle Pad 4' }
        @{ Name = 'TD(0)'; Label = 'Tap dance 0' }
        @{ Name = '0x4105'; Label = 'B · hold Pad 2' }
        @{ Name = '0x9999'; Label = '0x9999' }
        @{ Name = 'SOMETHING_NEW'; Label = 'SOMETHING_NEW' }
    ) {
        Get-KeyLabel $Name $null | Should -BeExactly $Label
    }

    It 'labels every numeric code the same as its name' {
        foreach ($code in 0x0004, 0x0306, 0x254C, 0x412C, 0x5028, 0x52A2, 0x7820) {
            Get-KeyLabel ('0x{0:X4}' -f $code) $null | Should -BeExactly (Get-KeyLabel (Convert-Keycode $code) $null)
        }
    }

    Context 'macros' {
        BeforeAll {
            $data = [pscustomobject]@{ macro = @(
                ,@(,@('text', 'https://www.github.com/OldePSN00b'))
                ,@(,@('text', 'C:\Program Files\App\teams.exe'))
                ,@(,@('text', 'The quick brown fox jumps over the lazy dog again'))
                ,@()
            ) }
        }
        It 'shows a URL macro as its host name' { Get-KeyLabel 'M0' $data | Should -BeExactly 'github.com' }
        It 'shows an application macro as the executable name' { Get-KeyLabel 'M1' $data | Should -BeExactly 'teams' }
        It 'truncates long macro text' { Get-KeyLabel 'M2' $data | Should -BeExactly 'The quick brown fox jumps over the la…' }
        It 'shows a keypress-only macro by number' { Get-KeyLabel 'M3' $data | Should -BeExactly 'Macro 3' }
        It 'shows a macro missing from the data by number' { Get-KeyLabel 'M9' $data | Should -BeExactly 'Macro 9' }
    }
}

Describe 'Get-ResolvedKey' {
    BeforeAll {
        $data = [pscustomobject]@{
            layout = @(
                @(@('KC_NO','KC_NO','USER00'), @('KC_A','KC_B','KC_C'), @('KC_D','KC_E','KC_F')),
                @(@('KC_NO','KC_NO','KC_TRNS'), @('KC_TRNS','KC_X','KC_C'), @('KC_D','KC_E','KC_F')),
                @(@('KC_NO','KC_NO','USER00'), @('KC_A','KC_B','KC_C'), @('KC_D','KC_E','KC_F')),
                @(@('KC_NO','KC_NO','USER00'), @('KC_A','KC_B','KC_C'), @('KC_D','KC_E','KC_F')))
            macro = @()
        }
    }
    It 'inherits transparent keys from layer 0 and marks them' {
        $key = Get-ResolvedKey $data 1 1 0
        $key.Code | Should -BeExactly 'KC_A'
        $key.Inherited | Should -BeTrue
    }
    It 'uses the layer''s own key when it is not transparent' {
        $key = Get-ResolvedKey $data 1 1 1
        $key.Label | Should -BeExactly 'X'
        $key.Inherited | Should -BeFalse
    }
    It 'resolves the knob press from layer 0 when transparent' {
        (Get-ResolvedKey $data 1 0 2).Label | Should -BeExactly 'Cycle layers'
    }
}

Describe 'Read-VialLayout' {
    BeforeAll {
        $valid = @{ layout = @(1..4 | ForEach-Object { ,@(1..3 | ForEach-Object { ,@('KC_A','KC_B','KC_C') }) }) } | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath (Join-Path $TestDrive 'valid.vil') -Value $valid
        Set-Content -LiteralPath (Join-Path $TestDrive 'text.vil') -Value 'not json'
        $three = @{ layout = @(1..3 | ForEach-Object { ,@(1..3 | ForEach-Object { ,@('KC_A','KC_B','KC_C') }) }) } | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath (Join-Path $TestDrive 'three.vil') -Value $three
        $wide = @{ layout = @(1..4 | ForEach-Object { ,@(1..3 | ForEach-Object { ,@('KC_A','KC_B','KC_C','KC_D') }) }) } | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath (Join-Path $TestDrive 'wide.vil') -Value $wide
    }
    It 'reads a four-layer 3 by 3 export' { (Read-VialLayout (Join-Path $TestDrive 'valid.vil')).layout.Count | Should -Be 4 }
    It 'rejects an empty path' { { Read-VialLayout '' } | Should -Throw 'No Vial export was specified.' }
    It 'reports a missing file' { { Read-VialLayout (Join-Path $TestDrive 'nope.vil') } | Should -Throw 'Vial export not found*' }
    It 'reports a file that is not JSON' { { Read-VialLayout (Join-Path $TestDrive 'text.vil') } | Should -Throw '*not valid JSON*' }
    It 'rejects the wrong number of layers' { { Read-VialLayout (Join-Path $TestDrive 'three.vil') } | Should -Throw '*four layers*' }
    It 'rejects the wrong matrix size' { { Read-VialLayout (Join-Path $TestDrive 'wide.vil') } | Should -Throw '*3 by 3*' }
}

Describe 'Hid.IsReadCommand' {
    It 'allows read command <Bytes>' -ForEach @(
        @{ Bytes = @(0x01) }; @{ Bytes = @(0x11) }; @{ Bytes = @(0x0C) }; @{ Bytes = @(0x0D) }
        @{ Bytes = @(0x12, 0, 0, 28) }; @{ Bytes = @(0x0E, 0, 28, 1) }; @{ Bytes = @(0x02, 3) }
        @{ Bytes = @(0xFE, 0) }; @{ Bytes = @(0xFE, 3, 1, 0) }; @{ Bytes = @(0xFE, 5) }
    ) {
        [TogKeyDisplay.Hid]::IsReadCommand((New-Packet $Bytes)) | Should -BeTrue
    }
    It 'refuses write or unknown command <Bytes>' -ForEach @(
        @{ Bytes = @(0x05, 0, 0, 0, 0, 4) }   # set keycode
        @{ Bytes = @(0x0F, 0, 0, 1) }         # set macro buffer
        @{ Bytes = @(0x10) }                  # reset macros
        @{ Bytes = @(0x03, 3) }               # set keyboard value
        @{ Bytes = @(0x02, 1) }               # keyboard value other than the switch matrix
        @{ Bytes = @(0x12, 0, 0, 0) }         # zero-length buffer read
        @{ Bytes = @(0x12, 0, 0, 29) }        # longer than one report
        @{ Bytes = @(0xFE, 6) }               # Vial unlock start
        @{ Bytes = @(0xFE, 0x0B) }            # Vial lock
    ) {
        [TogKeyDisplay.Hid]::IsReadCommand((New-Packet $Bytes)) | Should -BeFalse
    }
    It 'refuses a payload that is not 32 bytes' { [TogKeyDisplay.Hid]::IsReadCommand([byte[]](1, 0, 0)) | Should -BeFalse }
}

Describe 'Hid.MatchesResponse' {
    It '<Case>' -ForEach @(
        @{ Case = 'accepts a VIA version reply'; Request = @(0x01); Reply = @(0x01, 0, 9); Expected = $true }
        @{ Case = 'rejects a version reply with stray data'; Request = @(0x01); Reply = @(0x01, 0, 9, 7); Expected = $false }
        @{ Case = 'rejects a reply to a different command'; Request = @(0x01); Reply = @(0x11, 4); Expected = $false }
        @{ Case = 'accepts a keymap chunk echoing offset and size'; Request = @(0x12, 0, 28, 28); Reply = @(0x12, 0, 28, 28, 0, 4); Expected = $true }
        @{ Case = 'rejects a keymap chunk for another offset'; Request = @(0x12, 0, 28, 28); Reply = @(0x12, 0, 0, 28, 0, 4); Expected = $false }
        @{ Case = 'accepts a keyboard ID reply'; Request = @(0xFE, 0); Reply = @(6, 0, 0, 0, 0x77, 0xF7, 0x14, 0xBB, 0x74, 0x32, 0x66, 0xE9); Expected = $true }
        @{ Case = 'rejects a keyboard ID reply with a non-zero tail'; Request = @(0xFE, 0); Reply = @(6, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 9); Expected = $false }
        @{ Case = 'accepts an unlock-status reply'; Request = @(0xFE, 5); Reply = @(0, 0, 0, 0, 2, 0, 255, 255); Expected = $true }
        @{ Case = 'rejects an unlock-status reply out of range'; Request = @(0xFE, 5); Reply = @(2, 0); Expected = $false }
        @{ Case = 'accepts an encoder reply'; Request = @(0xFE, 3, 0, 0); Reply = @(0, 0xAA, 0, 0xA9); Expected = $true }
        @{ Case = 'rejects an encoder request echoed back unanswered'; Request = @(0xFE, 3, 0, 0); Reply = @(0xFE, 3, 0, 0); Expected = $false }
        @{ Case = 'accepts a switch-matrix reply'; Request = @(0x02, 3); Reply = @(0x02, 3, 4); Expected = $true }
        @{ Case = 'rejects a different keyboard value'; Request = @(0x02, 3); Reply = @(0x02, 1, 4); Expected = $false }
    ) {
        [TogKeyDisplay.Hid]::MatchesResponse((New-Packet $Request), (New-Packet $Reply)) | Should -Be $Expected
    }
}

Describe 'Reader.DecodeMacroTexts' {
    It 'splits macros on NUL and keeps text segments' {
        $buffer = [byte[]]([Text.Encoding]::UTF8.GetBytes('hi') + 0 + 1 + 1 + 0x04 + [Text.Encoding]::UTF8.GetBytes('x') + 0)
        $macros = [TogKeyDisplay.Reader]::DecodeMacroTexts($buffer, 2)
        $macros.Count | Should -Be 2
        $macros[0] | Should -Be @('hi')
        $macros[1] | Should -Be @('x')
    }
    It 'skips delay and 16-bit keycode actions' {
        $buffer = [byte[]](@(1, 4, 0x10, 0x02) + [Text.Encoding]::UTF8.GetBytes('ok') + @(1, 5, 0x77, 0x01, 0))
        ([TogKeyDisplay.Reader]::DecodeMacroTexts($buffer, 1))[0] | Should -Be @('ok')
    }
    It 'decodes UTF-8 text' {
        $buffer = [byte[]]([Text.Encoding]::UTF8.GetBytes('café') + 0)
        ([TogKeyDisplay.Reader]::DecodeMacroTexts($buffer, 1))[0] | Should -Be @('café')
    }
    It 'treats an empty macro as having no text' {
        ([TogKeyDisplay.Reader]::DecodeMacroTexts([byte[]](0), 1))[0].Count | Should -Be 0
    }
    It 'rejects storage with fewer macros than reported' {
        { [TogKeyDisplay.Reader]::DecodeMacroTexts([byte[]](0x61, 0), 2) } | Should -Throw '*Incomplete macro storage*'
    }
    It 'rejects an unknown macro action' {
        { [TogKeyDisplay.Reader]::DecodeMacroTexts([byte[]](1, 9, 0), 1) } | Should -Throw '*Unsupported*'
    }
    It 'rejects a truncated action' {
        { [TogKeyDisplay.Reader]::DecodeMacroTexts([byte[]](1, 4, 0x10), 1) } | Should -Throw '*incomplete*'
    }
}

Describe 'Reader.Read' {
    BeforeAll {
        $keys = [uint16[]]::new(36)
        $keys[2] = 0x7E00                       # layer 0 knob press: USER00
        $keys[3] = 0x0106; $keys[4] = 0x7700     # Ctrl+C, M0
        $keys[9 + 3] = 0x0001                    # layer 1 button 1: transparent
        $encoders = [uint16[]](0x00AA, 0x00A9, 1, 1, 1, 1, 1, 1)
        $macros = [byte[]]([Text.Encoding]::UTF8.GetBytes('https://example.com') + 0 + [Text.Encoding]::UTF8.GetBytes('notepad.exe') + 0)
        $pad = New-FakePad -Keys $keys -Encoders $encoders -Macros $macros -MacroCount 2
    }
    It 'reads keys, encoders and macros into a snapshot' {
        $snapshot = [TogKeyDisplay.Reader]::Read($pad)
        $snapshot.Keys[3] | Should -Be 0x0106
        $snapshot.Keys[12] | Should -Be 1
        $snapshot.Encoders[0] | Should -Be 0x00AA
        $snapshot.MacroTexts.Count | Should -Be 2
        $snapshot.MacroTexts[1] | Should -Be @('notepad.exe')
    }
    It 'produces display labels end to end' {
        $data = Convert-PadSnapshot ([TogKeyDisplay.Reader]::Read($pad))
        (Get-ResolvedKey $data 0 1 0).Label | Should -BeExactly 'Ctrl + C'
        (Get-ResolvedKey $data 0 1 1).Label | Should -BeExactly 'example.com'
        (Get-ResolvedKey $data 0 0 2).Label | Should -BeExactly 'Cycle layers'
        $inherited = Get-ResolvedKey $data 1 1 0
        $inherited.Label | Should -BeExactly 'Ctrl + C'
        $inherited.Inherited | Should -BeTrue
        $data.encoder_layout[0][0] | Should -Be @('KC_VOLD', 'KC_VOLU')
    }
    It 'refuses a pad with a different layer count' {
        $other = New-FakePad -Keys $keys -Encoders $encoders -Macros $macros -MacroCount 2 -Layers 3
        { [TogKeyDisplay.Reader]::Read($other) } | Should -Throw '*four-layer*'
    }
}

Describe 'Reader.ReadLockState' {
    It 'reports <State>' -ForEach @(
        @{ Reply = @(1, 0); State = 'unlocked' }
        @{ Reply = @(0, 0); State = 'locked' }
        @{ Reply = @(0, 1); State = 'unlocking' }
    ) {
        $reply = New-Packet $Reply
        [TogKeyDisplay.Reader]::ReadLockState([Func[byte[],byte[]]]{ param($p) ,$reply }.GetNewClosure()) | Should -BeExactly $State
    }
}

Describe 'Hid.Query' {
    It 'discards stale and foreign reports and returns the matching reply' {
        $stream = [TogKeyTests.FakeReportStream]::new()
        $stream.Replies.Enqueue((New-Report @(0x11, 4)))          # stale reply to another command
        $stream.Replies.Enqueue((New-Report @(0x01, 0, 9, 5)))    # wrong shape
        $stream.Replies.Enqueue((New-Report @(0x01, 0, 9)))       # the real answer
        $hid = New-TestHid $stream
        $reply = $hid.Query((New-Packet @(0x01)))
        $reply[2] | Should -Be 9
        $stream.Written.Count | Should -Be 1                     # not resent while filtering
        $stream.Written[0][0] | Should -Be 0                     # report ID
        $stream.Written[0][1] | Should -Be 1
    }
    It 'never sends a write command' {
        $stream = [TogKeyTests.FakeReportStream]::new()
        $hid = New-TestHid $stream
        { $hid.Query((New-Packet @(0x05, 0, 0, 0, 0, 4))) } | Should -Throw '*read commands only*'
        $stream.Written.Count | Should -Be 0
    }
    It 'reports a disconnect when the device stream ends' {
        $stream = [TogKeyTests.FakeReportStream]::new(); $stream.Disconnected = $true
        $hid = New-TestHid $stream
        $failure = { $hid.Query((New-Packet @(0x01))) } | Should -Throw -PassThru
        $failure.Exception.InnerException | Should -BeOfType ([TogKeyDisplay.PadDisconnectedException])
    }
    It 'reports a busy pad after the six-second reply timeout' {
        $stream = [TogKeyTests.FakeReportStream]::new()
        $hid = New-TestHid $stream
        $failure = { $hid.Query((New-Packet @(0x01))) } | Should -Throw -PassThru
        $failure.Exception.InnerException | Should -BeOfType ([TogKeyDisplay.PadBusyException])
    }
}

Describe 'Import-CompiledSource' {
    BeforeAll {
        function New-Source([string]$Namespace, [string]$Value) {
            "namespace $Namespace { public static class Probe { public static string Value() { return `"$Value`"; } } }"
        }
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'TogKey Core.psm1'
        function Invoke-InChild([string]$Namespace, [string]$Value, [string]$Cache) {
            # A fresh process is needed to observe loading from the cache instead of the current session.
            $source = New-Source $Namespace $Value
            $script = "Import-Module '$modulePath'; Import-CompiledSource -TypeName '$Namespace.Probe' -CacheName 'Probe' -CacheDirectory '$Cache' -Source '$($source -replace "'", "''")'; [$Namespace.Probe]::Value() + '|' + [$Namespace.Probe].Assembly.Location"
            pwsh -NoProfile -Command $script
        }
    }
    It 'compiles once, then loads the cached DLL in a new process' {
        $cache = Join-Path $TestDrive 'cache-a'
        $namespace = 'ProbeA' + [guid]::NewGuid().ToString('N')
        $first = Invoke-InChild $namespace 'one' $cache
        $files = @(Get-ChildItem $cache -Filter 'Probe-*.dll')
        $files.Count | Should -Be 1
        $first | Should -BeExactly ('one|' + $files[0].FullName)
        $before = $files[0].LastWriteTimeUtc
        $second = Invoke-InChild $namespace 'one' $cache
        $second | Should -BeExactly ('one|' + $files[0].FullName)
        (Get-Item $files[0].FullName).LastWriteTimeUtc | Should -Be $before
    }
    It 'rebuilds when the source changes and removes the stale DLL' {
        $cache = Join-Path $TestDrive 'cache-b'
        $namespace = 'ProbeB' + [guid]::NewGuid().ToString('N')
        [void](Invoke-InChild $namespace 'old' $cache)
        $old = (Get-ChildItem $cache -Filter 'Probe-*.dll').FullName
        (Invoke-InChild $namespace 'new' $cache) | Should -BeLike 'new|*'
        Test-Path $old | Should -BeFalse
        @(Get-ChildItem $cache -Filter 'Probe-*.dll').Count | Should -Be 1
    }
    It 'falls back to compiling in memory when the cache cannot be written' {
        $blocker = Join-Path $TestDrive 'not-a-folder'
        Set-Content -LiteralPath $blocker -Value 'file in the way'
        $namespace = 'ProbeC' + [guid]::NewGuid().ToString('N')
        Import-CompiledSource -TypeName "$namespace.Probe" -CacheName 'Probe' -CacheDirectory (Join-Path $blocker 'cache') -Source (New-Source $namespace 'memory')
        ("$namespace.Probe" -as [type])::Value() | Should -BeExactly 'memory'
        ("$namespace.Probe" -as [type]).Assembly.Location | Should -BeNullOrEmpty
    }
}

Describe 'Version and release package' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $builder = Join-Path $root 'build\New-ReleasePackage.ps1'
    }
    It 'has a semantic version' {
        Get-TogKeyVersion | Should -Match '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$'
    }
    It 'reports the version from the command line' {
        pwsh -NoProfile -File (Join-Path $root 'TogKey Display.ps1') -Version | Should -BeExactly "TogKey Display $(Get-TogKeyVersion)"
    }
    It 'packages exactly the runtime files inside a TogKey Display folder' {
        # Personal files beside the script must never be picked up.
        $result = & $builder -OutputDirectory (Join-Path $TestDrive 'dist')
        $result.Package | Should -BeLike "*TogKey-Display-v$(Get-TogKeyVersion).zip"
        $zip = [IO.Compression.ZipFile]::OpenRead($result.Package)
        try { $entries = @($zip.Entries.FullName | Sort-Object) } finally { $zip.Dispose() }
        $entries | Should -Be (@('LICENSE', 'README.md', 'Start TogKey Display.cmd', 'TogKey Core.psm1', 'TogKey Display.ps1', 'TogKey Hid.cs') |
            ForEach-Object { "TogKey Display/$_" } | Sort-Object)
    }
    It 'writes a matching SHA-256 file' {
        $result = & $builder -OutputDirectory (Join-Path $TestDrive 'dist-hash')
        $line = Get-Content -LiteralPath $result.HashFile -Raw
        $line | Should -BeExactly ("{0}  {1}" -f (Get-FileHash $result.Package -Algorithm SHA256).Hash.ToLowerInvariant(), [IO.Path]::GetFileName($result.Package))
    }
    It 'accepts a tag that matches the version' {
        { & $builder -OutputDirectory (Join-Path $TestDrive 'dist-tag') -ExpectedVersion "v$(Get-TogKeyVersion)" } | Should -Not -Throw
    }
    It 'refuses a tag that does not match the version' {
        { & $builder -OutputDirectory (Join-Path $TestDrive 'dist-bad') -ExpectedVersion 'v0.0.1' } | Should -Throw '*does not match*'
    }
}
