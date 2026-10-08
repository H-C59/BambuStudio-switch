# Bambu Studio Account Switcher

[中文文档](README.md)

A GUI tool for managing multiple Bambu Studio accounts: **hot-swap accounts with one click — fully isolated, each keeping its own login session (no re-login needed)**.

> Original author: **H-C59** | License: [CC BY-NC 4.0](LICENSE) (Attribution-NonCommercial) | Unofficial tool, not affiliated with Bambu Lab

---

## Purpose

The official Bambu Studio client does not support multiple concurrent accounts: switching accounts means logging out and logging back in, and printer bindings / filament presets get mixed together.

This tool leverages a key characteristic of Bambu Studio — **the login session (token + account presets) is fully self-contained in its data directory, and the client only recognizes the exact directory name `%APPDATA%\BambuStudio`** — to achieve true multi-account hot-switching via directory renaming:

- Each account's data (login token, filament/machine/process presets) is stored independently with zero interference
- **No re-login required** after switching — the client opens straight into the target account
- Card-based GUI with support for displaying real nicknames and avatars

## Features

- 🔍 **Auto-discovery**: automatically scans existing account profiles and reads the currently logged-in account ID
- 🖼️ **Avatar & nickname**: "Sync Profile" opens an embedded browser — log in once and your real nickname + avatar are fetched automatically (or set them manually)
- 🔀 **One-click switching**: click a card to switch; if Bambu Studio is running, the tool asks and safely closes it first (graceful close preferred, force-kill requires a second confirmation)
- ➕ **Add account**: guided flow — parks the current profile, launches a fresh client for the new login, one click to register it
- 🛡️ **Safe rollback**: every directory operation rolls back on failure; cancelling leaves no junk data
- 📦 **Single-file exe**: built-in environment checks with automatic download of missing .NET / WebView2 Runtime — works on any Win10/11 machine

## Usage

### Option 1: Download the exe (recommended)

1. Download `BambuStudio-switch-v1.0.0.exe` from the [Releases](../../releases) page
2. Double-click to run (if SmartScreen warns on first run, click "More info → Run anyway")
3. The exe checks your environment and offers to auto-install missing components (internet required)

### Option 2: Run from source

Requires Windows 10/11 (ships with PowerShell 5.1+ and .NET Framework 4.6.2+):

```powershell
# After cloning the repo, double-click
Bambu账号切换器.bat
```

> Note: running from source requires the WebView2 managed DLLs in `webview2-lib\` (not tracked in git).
> Download the nupkg (zip format) from [NuGet](https://www.nuget.org/packages/Microsoft.Web.WebView2),
> extract `lib/net462/Microsoft.Web.WebView2.Core.dll`, `lib/net462/Microsoft.Web.WebView2.Wpf.dll`
> and `build/native/x64/WebView2Loader.dll` into `webview2-lib\`.

### Option 3: Build the exe yourself

After modifying `BambuAccountSwitcher.ps1`, rebuild with the compiler bundled with Windows:

```cmd
cd project-directory
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe @build.rsp
```

### UI operations

| Action | Description |
|---|---|
| **Switch account** | Click "切换到此账号" on an inactive card; check "切换后自动启动" to relaunch the client automatically |
| **Sync Profile (同步资料)** | Opens an embedded browser with the official Bambu login page (credentials never pass through this tool); fetches nickname + avatar automatically. Sessions are isolated per account — stays logged in next time |
| **Edit (编辑)** | Set a custom display name, or pick a local image as the avatar |
| **Add account (＋)** | Parks the current profile → launches a fresh Bambu Studio → log in and fully exit → click "完成添加" |

## How it works

```
%APPDATA%\
├── BambuStudio            ← the active account (the only name the client reads)
├── BambuStudio-personal   ← parked profile A
├── BambuStudio-work       ← parked profile B
└── ...
```

- Bambu Studio stores its login token (encrypted) in `BambuNetworkEngine.conf` and account presets in `user\<uid>\` inside the data directory — everything travels with the directory, so renaming it switches the account with the session fully preserved
- Each profile's `_switcher\profile.json` holds this tool's metadata (display name / nickname / avatar path) and travels with the directory too
- This tool **never reads or modifies any credentials** — switching is purely directory renaming

## Requirements

| Component | Requirement | If missing |
|---|---|---|
| OS | Windows 10 / 11 | — |
| PowerShell | 5.1+ (built-in) | — |
| .NET Framework | 4.6.2+ | exe offers to install 4.8 automatically |
| WebView2 Runtime | Evergreen | exe downloads and installs it (official Microsoft component) |
| Bambu Studio | installed (default path) | — |

## Notes

- Switching closes a running Bambu Studio first (graceful close is attempted; force-kill only with your explicit confirmation)
- If an account's token expires after long disuse, simply log in once in the client — the session is preserved again afterwards
- "Sync Profile" requires logging in once per account in the embedded browser; you can skip it and use custom names/avatars instead

## Disclaimer

This is a third-party open-source project with no affiliation to Bambu Lab. "Bambu Studio", "Bambu Lab" and "MakerWorld" names and trademarks belong to their respective owners. The author accepts no liability for any data loss caused by using this tool — please understand the principle before use, and back up your `%APPDATA%\BambuStudio*` directories if they contain important configurations.

## License

[CC BY-NC 4.0](LICENSE) — Attribution-NonCommercial 4.0 International

You are free to share and adapt this work, provided that: **you credit the original author H-C59**, and **you do not use it for commercial purposes**.

## Credits

- Original author: [H-C59](https://github.com/H-C59)
- Development assistance: Claude (Anthropic)
