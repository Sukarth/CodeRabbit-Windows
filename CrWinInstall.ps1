<#
.SYNOPSIS
Unofficial Native Windows Installer & Updater for CodeRabbit CLI

.DESCRIPTION
Downloads the official Linux binary, decompiles the JavaScript bundle,
and cross-compiles it into a native Windows executable (coderabbit.exe).
#>

$ErrorActionPreference = 'Stop'

# Force TLS 1.2/1.3 — Windows 10 sometimes defaults to TLS 1.0/1.1,
# which cli.coderabbit.ai rejects, causing SChannel negotiation failures.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
} catch {
    # TLS 1.3 not available on this .NET version; TLS 1.2 will be used
}

# ---------------------------------------------------------------------------
# Download helpers — try SChannel first, then curl.exe, then bun (BoringSSL)
# ---------------------------------------------------------------------------

function Invoke-DownloadString {
    param([string]$Uri)

    # Attempt 1: Invoke-WebRequest via SChannel (with TLS forced above)
    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop
        return $response.Content.Trim()
    } catch {
        Write-Host "  [~] Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Attempt 2: curl.exe — ships with Windows 10 1803+
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        try {
            $curlOutput = @()
            & curl.exe -fsL $Uri 2>&1 | ForEach-Object { $curlOutput += $_ }
            if ($LASTEXITCODE -eq 0 -and $curlOutput) { 
                return ($curlOutput -join '').Trim() 
            }
        } catch {
            Write-Host "  [~] curl.exe failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    # Attempt 3: bun — prerequisite, bundles BoringSSL (OpenSSL-compatible)
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        try {
            $jsUri = $Uri -replace '\\', '\\\\' -replace "'", "\'"
            $bunOutput = @()
            & bun -e "fetch('$jsUri').then(r=>r.text()).then(t=>process.stdout.write(t.trim()))" 2>&1 | ForEach-Object { $bunOutput += $_ }
            if ($LASTEXITCODE -eq 0 -and $bunOutput) { 
                return ($bunOutput -join '').Trim() 
            }
        } catch {
            Write-Host "  [~] bun fetch failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    throw "All download methods failed for: $Uri"
}

function Invoke-DownloadFile {
    param([string]$Uri, [string]$Destination, [string]$DisplayName = "Downloading...")

    # Attempt 1: BITS Transfer (fast, built-in progress, uses SChannel with TLS forced)
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Uri -Destination $Destination -DisplayName $DisplayName -ErrorAction Stop
        if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
    } catch {
        Write-Host "  [~] BITS transfer failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Attempt 2: Invoke-WebRequest via SChannel
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
    } catch {
        Write-Host "  [~] Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Attempt 3: curl.exe
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        try {
            $null = & curl.exe -fsL -o $Destination $Uri 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
        } catch {
            Write-Host "  [~] curl.exe failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    # Attempt 4: bun (BoringSSL — works even when SChannel cipher negotiation fails)
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        try {
            $jsDest = $Destination -replace '\\', '\\\\'
            $jsUri  = $Uri         -replace '\\', '\\\\' -replace "'", "\'"
            $null = & bun -e @"
const r = await fetch('$jsUri');
if (!r.ok) throw new Error('HTTP ' + r.status);
const buf = await r.arrayBuffer();
require('fs').writeFileSync('$jsDest', Buffer.from(buf));
"@ 2>&1
            if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
        } catch {
            Write-Host "  [~] bun fetch failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    throw "All download methods failed for: $Uri -> $Destination"
}

# ---------------------------------------------------------------------------

function Show-Banner {
    Write-Host "==========================================================================" -ForegroundColor Blue
    $banner = @"
 	 	   __         __               __
		  /   _  _| _|__)_ |_ |_ .|_  /  |  |
		  \__(_)(_|(-| \(_||_)|_)||_  \__|__|

			   CodeRabbit CLI
                      Unofficial Windows Port
                    Maintained by Sukarth Acharya
            https://github.com/sukarth/coderabbit-windows
"@
    Write-Host $banner -ForegroundColor DarkCyan
    Write-Host "==========================================================================" -ForegroundColor Blue
}

Show-Banner

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\CodeRabbit"
$BinDir     = Join-Path $InstallDir "bin"
$ExePath    = Join-Path $BinDir "coderabbit.exe"

# --- 1. Version Checking ---
Write-Host "`n[*] Checking latest version..."
$LatestVersionUrl = "https://cli.coderabbit.ai/releases/latest/VERSION"
$LatestVersion    = Invoke-DownloadString -Uri $LatestVersionUrl

if (Test-Path $ExePath) {
    $CurrentVersion = (& $ExePath --version 2>&1).Trim()

    if ($CurrentVersion -eq $LatestVersion) {
        Write-Host "You already have the latest version installed: " -NoNewline
        Write-Host "v$CurrentVersion" -ForegroundColor Green
        Write-Host "`nInstallation skipped. Your CLI is up to date!"
        exit
    } else {
        Write-Host "Update available! " -NoNewline
        Write-Host "v$CurrentVersion" -ForegroundColor Yellow -NoNewline
        Write-Host " -> " -NoNewline
        Write-Host "v$LatestVersion" -ForegroundColor Green
    }
} else {
    Write-Host "`n[*] Installing version: " -NoNewline
    Write-Host "v$LatestVersion" -ForegroundColor Green
}

# --- 2. Environment Setup ---
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host "`n[!] Bun is not installed. Installing Bun for Windows..." -ForegroundColor Yellow
    $bunScript = Invoke-DownloadString -Uri 'https://bun.sh/install.ps1'
    Invoke-Expression "& { $bunScript }"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

$TempDir = Join-Path $InstallDir "temp_build_$LatestVersion"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir  | Out-Null

# --- 3. Download + Extract ---
Write-Host "`n[*] Downloading official CodeRabbit CLI (Linux Payload)..."
$ZipUrl  = "https://cli.coderabbit.ai/releases/latest/coderabbit-linux-x64.zip"
$ZipPath = Join-Path $TempDir "coderabbit-linux-x64.zip"

Invoke-DownloadFile -Uri $ZipUrl -Destination $ZipPath -DisplayName "Downloading CodeRabbit payload..."

Write-Host "`n[*] Extracting downloaded payload archive..."
Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force
$LinuxBinary = Join-Path $TempDir "coderabbit"

# --- 4. Decompile the Bun executable ---
Write-Host "`n[*] Unpacking CodeRabbit bundle natively..."
Set-Location $TempDir
bun install @shepherdjerred/bun-decompile --silent
$decompileOutput = bunx @shepherdjerred/bun-decompile $LinuxBinary 2>&1 | Out-String

$DecompiledDir = Join-Path $TempDir "decompiled\bundled"
if (-not (Test-Path $DecompiledDir)) {
    Write-Error "Failed to decompile the CodeRabbit binary."
}

# --- 5. Resolve dependencies and compile ---
Write-Host "`n[*] Compiling native Windows executable..."
Set-Location $DecompiledDir

# Detect actual entry point from decompiler output
$EntryPoint = $null
if ($decompileOutput -match "Entry point:\s*/(.+\.js)") {
    $candidate = $Matches[1].Trim()
    if (Test-Path (Join-Path $DecompiledDir $candidate)) {
        $EntryPoint = $candidate
    }
}
# Fallbacks in priority order
if (-not $EntryPoint) {
    Write-Host "  [~] Could not auto-detect entry point. Attempting fallbacks..." -ForegroundColor DarkYellow
    foreach ($name in @("cli.js", "index.js", "main.js")) {
        if (Test-Path (Join-Path $DecompiledDir $name)) { $EntryPoint = $name; break }
    }
}
if (-not $EntryPoint) {
    $EntryPoint = Get-ChildItem $DecompiledDir -Filter "*.js" -File |
                  Select-Object -First 1 -ExpandProperty Name
}
if (-not $EntryPoint) {
    Write-Error "Could not determine entry point JS file in decompiled output."
}

Write-Host "  [~] Using entry point: $EntryPoint" -ForegroundColor DarkYellow

bun install --silent
bun build $EntryPoint --compile --target=bun-windows-x64 --outfile=$ExePath

# --- 5a. Post-compile version verification ---
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ExePath)) {
    Write-Error "Compilation failed: bun exited with code $LASTEXITCODE and no executable was produced."
}

$CompiledVersion = (& $ExePath --version 2>&1).Trim()
if ($CompiledVersion -ne $LatestVersion) {
    Write-Host ""
    Write-Host "  [!] Version mismatch after compilation!" -ForegroundColor Red
    Write-Host "      Expected : v$LatestVersion"          -ForegroundColor Red
    Write-Host "      Got      : $CompiledVersion"         -ForegroundColor Red
    Write-Host ""
    Write-Host "  The temp build folder has been kept for debugging at:" -ForegroundColor DarkYellow
    Write-Host "  $TempDir"                                              -ForegroundColor DarkYellow
    Write-Host ""
    Write-Error "Installation aborted: compiled binary reported wrong version."
}

Copy-Item -Path $ExePath -Destination (Join-Path $BinDir "cr.exe") -Force

# --- 6. Add to PATH ---
Write-Host "`n[*] Adding executable to PATH..."
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $BinDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $BinDir } else { "$userPath;$BinDir" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:Path = "$env:Path;$BinDir"
}

# --- 7. Cleanup ---
Write-Host "`n[*] Cleaning up temporary files..."
Set-Location $env:USERPROFILE
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Success! CodeRabbit v$LatestVersion Installed " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nPlease restart your terminal, then run:"
Write-Host "  cr auth login" -ForegroundColor Cyan
