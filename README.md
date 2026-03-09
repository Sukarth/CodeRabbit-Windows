<div align="center">

```
      ____          _      _____       _     _       _     ____ _     ___ 
     / ___|___   __| | ___|  __ \ __ _| |__ | |__ (_) |_  / ___| |   |_ _|
    | |   / _ \ / _` |/ _ \ |__) / _` | '_ \| '_ \| | __ | |   | |    | | 
    | |__| (_) | (_| |  __/  _  / (_| | |_) | |_) | | |_ | |___| |___ | | 
     \____\___/ \__,_|\___|_| \_\\__,_|_.__/|_.__/|_|\__| \____|_____|___|
```

# CodeRabbit CLI for Windows - Unofficial Port

**Run the official [CodeRabbit CLI](https://coderabbit.ai/cli) natively on Windows. No WSL. No Docker. No admin rights required.**

[![Platform](https://img.shields.io/badge/platform-Windows-blue?logo=windows)](https://github.com/sukarth/coderabbit-windows-port)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## What is this?

The official [CodeRabbit CLI](https://coderabbit.ai/cli) provides free AI-powered code reviews directly in your terminal. However, CodeRabbit officially only ships a binary for Linux and macOS, leaving Windows users dependent on WSL (with an unstable and unsatisfactory experience).

This project is an **unofficial community port** that:
1. Downloads the official CodeRabbit CLI Linux binary.
2. Uses [`bun-decompile`](https://github.com/shepherdjerred/bun-decompile) to extract the embedded JavaScript bundle.
3. Resolves native Windows dependencies.
4. Cross-compiles it into a standalone `coderabbit.exe` using [Bun](https://bun.sh).

The resulting binary is **100% the official CodeRabbit backend**: it uses the exact same authentication, WebSocket review stream, and API endpoints. Only the platform wrapper was changed.


## Requirements

- Windows 10 or later
- Windows Powershell (to run the script)

---

## Installation

Simply open **Windows PowerShell** (no admin rights needed) and run:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/sukarth/coderabbit-windows/main/CrWinInstall.ps1 | iex"
```

That's it! 

The installer will:
- Check if Bun is installed. If not, it will automatically install it
- Download the latest official CodeRabbit Linux release
- Decompile, patch, and recompile it as a native `coderabbit.exe`
- Register both `cr` and `coderabbit` as global commands in your PATH

Please DO **restart your terminal** after installation is complete.


## Updating to the latest version
Just re-run the installer. It will automatically detect your current version and skip the install if you are already up to date:
```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/sukarth/coderabbit-windows/main/CrWinInstall.ps1 | iex"
```

## Usage (CodeRabbit CLI commands work exactly as specified by docs!)

### Authenticate
```powershell
cr auth login
```
This opens your browser for a one-time GitHub OAuth login. Paste the token back into the terminal when prompted.

### Check auth status
```powershell
cr auth status
```

### Review uncommitted changes
```powershell
cd C:\path\to\your\git\repo
cr review
```

### Review in plain text (no interactive UI)
```powershell
cr review --plain
```

### Full command reference
```powershell
cr --help
cr review --help
```

## Uninstallation

Run the uninstall script:
```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/sukarth/coderabbit-windows/main/CrWinUninstall.ps1 | iex"
```

The uninstaller will:
- Ask for confirmation before removing anything
- Delete the `coderabbit.exe` and `cr.exe` binaries
- Clean up your PATH environment variable
- Optionally delete your saved authentication session


## How It Works

```
Official Linux Binary (.zip)
         │
         ▼
  bunx bun-decompile
         │
         ▼
  index.js + package.json
         │
         ▼
    bun install (resolves native Windows deps)
         │
         ▼
  bun build --compile --target=bun-windows-x64
         │
         ▼
  coderabbit.exe  ✓
```

The key insight is that the CodeRabbit CLI is written in JavaScript and bundled using [Bun's `--compile`](https://bun.sh/docs/bundler/executables) feature. The Linux binary is just the Bun Linux runtime with the JavaScript source embedded inside. By decompiling the binary, we extract the pure JS source and recompile it against the Windows runtime: no reverse engineering of network protocols or API keys involved.


## Limitations

- This port re-runs on the official CodeRabbit backend —> any rate limits or account restrictions from CodeRabbit still apply.
- When CodeRabbit publishes a new CLI version, re-run the installer to update.
- This port does not ship a pre-built `.exe`. The executable is compiled fresh on your machine from the official source, ensuring it always uses your trusted local Bun runtime.


## Contributing

Pull requests are welcome! If you run into issues on a specific Windows version or configuration, please open an issue with your PowerShell version (`$PSVersionTable`) and the error output.

## Disclaimer

This is an **unofficial, community-maintained** project and is **not affiliated with or endorsed by CodeRabbit AI**. All CodeRabbit intellectual property, backend services, and trademarks belong to [CodeRabbit AI](https://coderabbit.ai). This tool does not bypass authentication, rate limits, or any terms of service. It is simply a platform wrapper to make the official CLI run natively on Windows.

## License

This project is used the MIT license. See [LICENSE](LICENSE).

---

<div align="center">
Made with ❤️ by <a href="https://github.com/sukarth">Sukarth Acharya</a>
</div>
