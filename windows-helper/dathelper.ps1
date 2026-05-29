param([string]$ProtocolUrl)

$diagLog = "$env:TEMP\dathelper-debug.log"
Add-Content -Path $diagLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  RAW ARG: [$ProtocolUrl]"

try {
    # Strip "dathelper:" prefix, parse query string
    $raw = $ProtocolUrl -replace '^dathelper:', ''

    $params = @{}
    foreach ($pair in ($raw -split '&')) {
        $kv = $pair -split '=', 2
        if ($kv.Count -eq 2) {
            $params[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1])
        }
    }

    $action = if ($params['action']) { $params['action'] } else { 'email' }

    # Pattern-logging action — append broken email to log file and exit
    if ($action -eq 'log') {
        $logPath = Join-Path $PSScriptRoot 'broken-patterns.txt'
        $entry   = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($params['email'])"
        Add-Content -Path $logPath -Value $entry
        return
    }

    $to      = if ($params['to'])      { $params['to'] }      else { '' }
    $subject = if ($params['subject']) { $params['subject'] } else { '' }
    $bodyTxt = if ($params['body'])    { $params['body'] }    else { '' }
    $mode    = if ($params['mode'])    { $params['mode'] }    else { 'draft' }

    $outlook = New-Object -ComObject Outlook.Application
    $mail    = $outlook.CreateItem(0)  # olMailItem

    $mail.To      = $to
    $mail.Subject = $subject

    function Bring-Inspector-To-Front($inspector) {
        try { $inspector.Activate() } catch { }

        try {
            if (-not ('Win32.WindowFocus' -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
    public static class WindowFocus {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    }
}
"@
            }

            $hwnd = [IntPtr]$inspector.HWND
            if ($hwnd -ne [IntPtr]::Zero) {
                [Win32.WindowFocus]::ShowWindowAsync($hwnd, 5) | Out-Null  # SW_SHOW
                [Win32.WindowFocus]::SetForegroundWindow($hwnd) | Out-Null
            }
        } catch { }
    }

    function Wait-For-Outlook-Signature($mail, [int]$minMilliseconds = 1200, [int]$maxMilliseconds = 4500) {
        $started = Get-Date
        $lastLength = -1
        $stableReads = 0

        do {
            Start-Sleep -Milliseconds 250
            $elapsed = ((Get-Date) - $started).TotalMilliseconds
            $html = ''
            try { $html = [string]$mail.HTMLBody } catch { }
            $length = $html.Length

            if ($length -gt 0 -and $length -eq $lastLength) {
                $stableReads++
            } else {
                $stableReads = 0
                $lastLength = $length
            }

            if ($elapsed -ge $minMilliseconds -and $stableReads -ge 2) {
                return
            }
        } while (((Get-Date) - $started).TotalMilliseconds -lt $maxMilliseconds)
    }

    function Insert-Content-In-Editor($inspector, $text) {
        $range = $inspector.WordEditor.Range(0, 0)
        $range.InsertBefore($text + "`r`n`r`n")
    }

    function Get-Image-Extension($mimeType) {
        switch -Regex ($mimeType) {
            'jpeg|jpg' { return '.jpg' }
            'png'      { return '.png' }
            'gif'      { return '.gif' }
            'bmp'      { return '.bmp' }
            'webp'     { return '.webp' }
            default    { return '.img' }
        }
    }

    function Resolve-Local-Image-Path($src) {
        if (-not $src) { return $null }
        if ($src -match '^(?i)(https?:|cid:|data:)') { return $null }

        $decoded = [System.Uri]::UnescapeDataString($src).Trim()
        if ($decoded -match '^(?i)file:') {
            try { $decoded = ([System.Uri]$decoded).LocalPath } catch { }
        }
        $decoded = $decoded -replace '/', '\'

        if ([System.IO.Path]::IsPathRooted($decoded) -and (Test-Path -LiteralPath $decoded)) {
            return $decoded
        }

        $sigRoot = Join-Path $env:APPDATA 'Microsoft\Signatures'
        $candidate = Join-Path $sigRoot $decoded
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }

        return $null
    }

    function Add-Inline-Attachment($mail, $path, $contentId) {
        $attachment = $mail.Attachments.Add($path, 1, 0, [System.IO.Path]::GetFileName($path)) # olByValue
        $attachment.PropertyAccessor.SetProperty(
            'http://schemas.microsoft.com/mapi/proptag/0x3712001F',
            $contentId
        )
        $attachment.PropertyAccessor.SetProperty(
            'http://schemas.microsoft.com/mapi/proptag/0x3713001F',
            $contentId
        )
        return $attachment
    }

    function Embed-Signature-Images($mail) {
        $html = ''
        try { $html = [string]$mail.HTMLBody } catch { return }
        if (-not $html) { return }

        $srcMap = @{}
        $tempFiles = New-Object System.Collections.Generic.List[string]
        $pattern = '(?i)(src\s*=\s*)(["''])(.*?)(\2)'

        $updated = [System.Text.RegularExpressions.Regex]::Replace(
            $html,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)

                $prefix = $match.Groups[1].Value
                $quote = $match.Groups[2].Value
                $src = $match.Groups[3].Value

                if ($src -match '^(?i)(cid:|https?:)') {
                    return $match.Value
                }

                if ($srcMap.ContainsKey($src)) {
                    return $prefix + $quote + 'cid:' + $srcMap[$src] + $quote
                }

                $path = $null
                if ($src -match '^(?is)data:([^;,]+);base64,\s*(.+)$') {
                    try {
                        $mimeType = $matches[1]
                        $base64 = ($matches[2] -replace '\s+', '')
                        $bytes = [Convert]::FromBase64String($base64)
                        $path = Join-Path $env:TEMP ("ofp-signature-" + [guid]::NewGuid().ToString('N') + (Get-Image-Extension $mimeType))
                        [System.IO.File]::WriteAllBytes($path, $bytes)
                        $tempFiles.Add($path) | Out-Null
                    } catch {
                        return $match.Value
                    }
                } else {
                    $path = Resolve-Local-Image-Path $src
                }

                if (-not $path -or -not (Test-Path -LiteralPath $path)) {
                    return $match.Value
                }

                try {
                    $contentId = 'ofp-' + [guid]::NewGuid().ToString('N')
                    Add-Inline-Attachment $mail $path $contentId | Out-Null
                    $srcMap[$src] = $contentId
                    return $prefix + $quote + 'cid:' + $contentId + $quote
                } catch {
                    return $match.Value
                }
            }
        )

        if ($updated -ne $html) {
            $mail.HTMLBody = $updated
        }

        foreach ($file in $tempFiles) {
            try { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    if ($mode -eq 'send') {
        # Use Outlook's Word editor, just like draft mode, so the default
        # signature and linked/embedded images finish hydrating before Send().
        $inspector = $mail.GetInspector
        $mail.Display($false)
        Wait-For-Outlook-Signature $mail
        Insert-Content-In-Editor $inspector $bodyTxt
        Embed-Signature-Images $mail
        $mail.Save()
        Start-Sleep -Milliseconds 750
        $mail.Send()
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($inspector) | Out-Null } catch { }
    } else {
        # Initialize the editor before showing the draft so Outlook inserts the signature
        # and our text is already in place when the compose window appears.
        $inspector = $mail.GetInspector
        Insert-Content-In-Editor $inspector $bodyTxt
        $mail.Display($false)
        Start-Sleep -Milliseconds 150
        Bring-Inspector-To-Front $inspector
    }

} catch {
    Add-Content -Path "$env:TEMP\dathelper.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ERROR: $_`r`nURL: $ProtocolUrl`r`n"
}
