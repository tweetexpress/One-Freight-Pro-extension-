# ONE Freight Pro Windows Helper

The extension talks to Outlook through a **native messaging host** — a small compiled exe that only this extension can launch. No protocol handler, no PowerShell spawned from the browser (this is what Malwarebytes used to flag).

## Install

1. Load the extension: `edge://extensions` (or `chrome://extensions`) → Developer mode → **Load unpacked** → select the `browser-extension` folder.
2. Copy the **extension ID** from the extension card.
3. From `native-host\`, run:

   ```
   powershell -ExecutionPolicy Bypass -File install-native-host.ps1 -ExtensionId <paste-id-here>
   ```

This compiles `ofp-native-host.exe`, registers it for Edge and Chrome (current user only), and removes the old `dathelper:` protocol handler if present.

Re-run the installer any time this folder moves or the extension ID changes (the ID changes if the `browser-extension` folder path changes).

## Legacy files

`install-protocol.ps1` and `dathelper.ps1` are the old `dathelper:` protocol path (browser → PowerShell). They are kept for reference only — **do not run `install-protocol.ps1`**; it re-registers the pattern Malwarebytes blocks.
