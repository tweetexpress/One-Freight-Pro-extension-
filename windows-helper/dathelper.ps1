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

    if ($mode -eq 'send') {
        # Use Outlook's Word editor, just like draft mode, so the default
        # signature and linked/embedded images finish hydrating before Send().
        $inspector = $mail.GetInspector
        $mail.Display($false)
        Wait-For-Outlook-Signature $mail
        Insert-Content-In-Editor $inspector $bodyTxt
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
