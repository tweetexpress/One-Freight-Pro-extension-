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

    # Escape HTML entities, convert newlines to <br>
    $bodyHtml = $bodyTxt `
        -replace '&', '&amp;' `
        -replace '<', '&lt;'  `
        -replace '>', '&gt;'  `
        -replace "`n", '<br>'

    $outlook = New-Object -ComObject Outlook.Application
    $mail    = $outlook.CreateItem(0)  # olMailItem

    $mail.To      = $to
    $mail.Subject = $subject

    $ourContent = "<div style='font-family:Calibri,sans-serif;font-size:11pt;margin:0;'>$bodyHtml</div>"

    function Inject-Content($html, $content) {
        $html = $html -replace '(<p class=MsoNormal><o:p>&nbsp;</o:p></p>){2,}', '<p class=MsoNormal><o:p>&nbsp;</o:p></p>'
        if ($html -match '(?i)<body[^>]*>') {
            return $html -replace '(?i)(<body[^>]*>)', ('$1' + $content)
        }
        return $content + $html
    }

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

    if ($mode -eq 'send') {
        # Let Outlook build the real item's signature so linked images remain valid,
        # then close the inspector before Send() so Outlook does not block auto-send.
        $inspector = $mail.GetInspector
        $baseHtml = $mail.HTMLBody
        $mail.HTMLBody = if ($baseHtml) { Inject-Content $baseHtml $ourContent } else { $ourContent }
        $mail.Save()
        try { $inspector.Close(0) } catch { }  # olSave
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($inspector) | Out-Null } catch { }
        $mail.Send()
    } else {
        # Initialize the editor before showing the draft so Outlook inserts the signature
        # and our text is already in place when the compose window appears.
        $inspector = $mail.GetInspector
        $range = $inspector.WordEditor.Range(0, 0)
        $range.InsertBefore($bodyTxt + "`r`n`r`n")
        $mail.Display($false)
        Start-Sleep -Milliseconds 150
        Bring-Inspector-To-Front $inspector
    }

} catch {
    Add-Content -Path "$env:TEMP\dathelper.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ERROR: $_`r`nURL: $ProtocolUrl`r`n"
}
