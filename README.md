# ONE Freight Pro

ONE Freight Pro is packaged here as a Chrome/Edge browser extension plus the Windows Outlook helper.

This removes the need to copy code into Tampermonkey. The browser extension runs on `https://one.dat.com/search-loads*` and uses the same stable Windows protocol bridge as the desktop version.

## Folder Layout

```text
ONE-Freight-Pro-Extension\
  browser-extension\
    manifest.json
    content.js
    icons\
      icon-128.png
  windows-helper\
    dathelper.ps1
    install-protocol.ps1
```

## Install For Testing

1. Open Chrome or Edge.
2. Go to `chrome://extensions` or `edge://extensions`.
3. Turn on Developer mode.
4. Click Load unpacked.
5. Select:

```text
C:\Users\rbric\Documents\Codex\2026-05-02\i-built-this-tool-to-run\ONE-Freight-Pro-Extension\browser-extension
```

6. Open PowerShell in:

```text
C:\Users\rbric\Documents\Codex\2026-05-02\i-built-this-tool-to-run\ONE-Freight-Pro-Extension\windows-helper
```

7. Run:

```powershell
.\install-protocol.ps1
```

## Use

Go to `https://one.dat.com/search-loads`, open a load card, then click the broker email or press `Shift+E`.

Draft Mode opens an Outlook draft. Money Mode sends immediately.

## Distribution Next Step

This package is ready for local extension testing. For non-technical users, the next build should wrap these files in a Windows installer and publish the browser extension through the Chrome Web Store or Microsoft Edge Add-ons.
