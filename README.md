# ONE Freight Pro

ONE Freight Pro is packaged here as a Chrome/Edge browser extension plus the Windows Outlook helper.

This removes the need to copy code into Tampermonkey. The browser extension runs on `https://one.dat.com/search-loads*` and uses the same stable Windows protocol bridge as the desktop version.

## Folder Layout

```text
ONE-Freight-Pro-Extension\
  browser-extension\
    manifest.json
    background.js
    content.js
    popup.html/css/js
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

## Gmail API Setup

The extension now has the first Gmail API path built in, but it needs a Google OAuth client ID before Gmail can connect.

1. Create a Google Cloud project.
2. Enable the Gmail API.
3. Configure the OAuth consent screen.
4. Create an OAuth client for a Chrome extension.
5. Use the installed extension ID from `edge://extensions` or `chrome://extensions`.
6. Replace this placeholder in `browser-extension\manifest.json`:

```text
REPLACE_WITH_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com
```

The requested scopes are:

```text
https://www.googleapis.com/auth/gmail.send
https://www.googleapis.com/auth/gmail.compose
```

After the client ID is installed, open the ONE Freight Pro extension popup, choose Gmail API under Email Sending, and click Connect Gmail.

## Distribution Next Step

This package is ready for local extension testing. For non-technical users, the next build should wrap these files in a Windows installer and publish the browser extension through the Chrome Web Store or Microsoft Edge Add-ons.
