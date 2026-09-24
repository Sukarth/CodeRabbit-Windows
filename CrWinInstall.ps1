<#
.SYNOPSIS
Unofficial Native Windows Installer & Updater for CodeRabbit CLI

.DESCRIPTION
Downloads the official Linux binary, decompiles the JavaScript bundle,
and cross-compiles it into a native Windows executable (coderabbit.exe).
#>

$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
} catch {
    # TLS 1.3 not available on this .NET version; TLS 1.2 will be used
}

# ---------------------------------------------------------------------------
# Download Helpers
# ---------------------------------------------------------------------------

function Invoke-DownloadString {
    param([string]$Uri)

    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        try {
            $curlOutput = [System.Collections.Generic.List[string]]::new()
            & curl.exe -fsL $Uri 2>&1 | ForEach-Object { if ($_ -is [string]) { $curlOutput.Add($_) } }
            if ($LASTEXITCODE -eq 0 -and $curlOutput.Count -gt 0) {
                return ($curlOutput -join "`n").Trim()
            }
        } catch {
            Write-Host "  [~] curl.exe failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if (Get-Command bun -ErrorAction SilentlyContinue) {
        try {
            $jsUri = $Uri -replace '\\', '\\\\' -replace "'", "\'"
            $bunOutput = [System.Collections.Generic.List[string]]::new()
            & bun -e "fetch('$jsUri').then(r=>r.text()).then(t=>process.stdout.write(t))" 2>&1 | ForEach-Object { if ($_ -is [string]) { $bunOutput.Add($_) } }
            if ($LASTEXITCODE -eq 0 -and $bunOutput.Count -gt 0) {
                return ($bunOutput -join "`n").Trim()
            }
        } catch {
            Write-Host "  [~] bun fetch failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop
        $content = $response.Content
        if ($content -is [byte[]]) {
            $content = [System.Text.Encoding]::UTF8.GetString($content)
        }
        return $content.Trim()
    } catch {
        Write-Host "  [~] Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    throw "All download methods failed for: $Uri"
}

function Invoke-DownloadFile {
    param([string]$Uri, [string]$Destination, [string]$DisplayName = "Downloading...")

    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        try {
            $curlErrorOutput = [System.Collections.Generic.List[string]]::new()
            $null = & curl.exe -fsL -o $Destination $Uri 2>&1 | ForEach-Object { $curlErrorOutput.Add($_) }
            if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
            if ($curlErrorOutput.Count -gt 0) {
                Write-Host "  [~] curl.exe error: $($curlErrorOutput -join ' ')" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "  [~] curl.exe failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

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

    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Uri -Destination $Destination -DisplayName $DisplayName -ErrorAction Stop
        if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
    } catch {
        Write-Host "  [~] BITS transfer failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) { return }
    } catch {
        Write-Host "  [~] Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    throw "All download methods failed for: $Uri -> $Destination"
}

# ---------------------------------------------------------------------------

# Returns "" for any exe that cannot report a version. Under Windows
# PowerShell 5.1 with ErrorActionPreference = 'Stop', a native command that
# writes to stderr or fails to start throws instead of returning, which would
# abort the script before a broken install could be replaced.
function Get-ExeVersion {
    param([string]$Path)

    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Path --version 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return "$output".Trim()
    } catch {
        return ""
    }
}

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
    $CurrentVersion = Get-ExeVersion -Path $ExePath

    if (-not $CurrentVersion) {
        Write-Host "Existing install is broken (no version reported). Reinstalling " -NoNewline
        Write-Host "v$LatestVersion" -ForegroundColor Green
    } elseif ($CurrentVersion -eq $LatestVersion) {
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

    $bunScriptPath = Join-Path $env:TEMP "bun-install-$([guid]::NewGuid()).ps1"
    try {
        Invoke-DownloadFile -Uri 'https://bun.sh/install.ps1' -Destination $bunScriptPath -DisplayName "Downloading Bun installer..."

        $actualHash = (Get-FileHash -Path $bunScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host "  [~] Bun installer SHA-256: $actualHash" -ForegroundColor DarkYellow

        $expectedHash = $env:CODE_RABBIT_BUN_INSTALL_SHA256
        if ($expectedHash) {
            if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
                throw "Bun installer checksum mismatch.`n  Expected: $($expectedHash.ToLowerInvariant())`n  Actual:   $actualHash`nRefusing to execute unverified installer."
            }
            Write-Host "  [+] Bun installer checksum verified." -ForegroundColor Green
        } else {
            Write-Host "  [!] No expected SHA-256 pinned (set `$env:CODE_RABBIT_BUN_INSTALL_SHA256 to enforce safety tracking)." -ForegroundColor DarkYellow
            $confirmation = Read-Host "      Are you sure you want to execute this unverified installer script from bun.sh? (Y/N)"
            if ($confirmation -notmatch '^[Yy]') {
                throw "Installation aborted: User declined executing the unverified Bun installer script."
            }
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bunScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "Bun installer exited with code $LASTEXITCODE"
        }
    } finally {
        if (Test-Path $bunScriptPath) { Remove-Item -Path $bunScriptPath -Force -ErrorAction SilentlyContinue }
    }

    $freshUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $freshMachinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    foreach ($pathSegment in (($freshUserPath -split ';') + ($freshMachinePath -split ';'))) {
        if (-not [string]::IsNullOrWhiteSpace($pathSegment) -and ($env:Path -split ';') -notcontains $pathSegment) {
            $env:Path = "$env:Path;$pathSegment"
        }
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        throw "Bun installation completed but 'bun' command is not available on PATH."
    }
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

$OriginalLocation = Get-Location

try {
    # --- 4. Decompile Binary ---
    Write-Host "`n[*] Unpacking CodeRabbit bundle natively..."
    Set-Location $TempDir
    $DecompiledDir = Join-Path $TempDir "decompiled"

    # $TempDir survives a re-run for the same version, so clear any previous
    # output first; otherwise a failed decompile leaves stale files that pass
    # the checks below and get compiled instead.
    if (Test-Path $DecompiledDir) {
        Remove-Item -Path $DecompiledDir -Recurse -Force
    }

    # Replaces @andrewgross/bun-decompile@0.1.1, which on Bun 1.4 payloads
    # writes an empty index.js and exits 0: it assumes module contents follow
    # the path, but 1.4 stores them first (the metadata pointers are absolute)
    # and encodes them as UTF-16LE. Only the ELF .bun section with the 32-byte
    # Offsets struct and 52-byte module records is supported; anything else
    # throws rather than producing a bad build.
    $ExtractorPath = Join-Path $TempDir "extract-bun-payload.js"
    Set-Content -Path $ExtractorPath -Encoding ASCII -Value @'
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { resolve, relative, isAbsolute, dirname, sep } from "path";

const [binaryPath, outDir] = process.argv.slice(2);
const buf = readFileSync(binaryPath);
const bin = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

if (bin.getUint32(0, true) !== 0x464c457f) throw new Error("not an ELF binary");
const shoff = Number(bin.getBigUint64(40, true));
const shentsize = bin.getUint16(58, true);
const shnum = bin.getUint16(60, true);
const strHdr = shoff + bin.getUint16(62, true) * shentsize;
const strTab = Number(bin.getBigUint64(strHdr + 24, true));
let section;
for (let i = 0; i < shnum && !section; i++) {
  const sh = shoff + i * shentsize;
  const nameAt = strTab + bin.getUint32(sh, true);
  if (buf.toString("latin1", nameAt, nameAt + 5) === ".bun\0") {
    section = { offset: Number(bin.getBigUint64(sh + 24, true)), size: Number(bin.getBigUint64(sh + 32, true)) };
  }
}
if (!section) throw new Error("no .bun section in binary");

const TRAILER = "\n---- Bun! ----\n";
const trailerAt = section.size - TRAILER.length;
if (buf.toString("latin1", section.offset + trailerAt, section.offset + section.size) !== TRAILER) {
  throw new Error(".bun section is missing the Bun trailer");
}
const v = new DataView(buf.buffer, buf.byteOffset + section.offset, section.size);

const OFFSETS_SIZE = 32, CHUNK_SIZE = 52;
const st = trailerAt - OFFSETS_SIZE;
const byteCount = v.getUint32(st, true);
const metaOffset = v.getUint32(st + 8, true);
const metaLength = v.getUint32(st + 12, true);
const entryId = v.getUint32(st + 16, true);
const modulesStart = st - byteCount;
if (modulesStart < 0 || metaLength === 0 || metaLength % CHUNK_SIZE !== 0 || entryId >= metaLength / CHUNK_SIZE) {
  throw new Error("unrecognised Bun payload layout");
}

const slice = (off, len) => {
  if (off + len > byteCount) throw new Error(`module pointer ${off}+${len} is outside the payload`);
  const start = section.offset + modulesStart + off;
  return buf.subarray(start, start + len);
};
const ENCODINGS = { 0: "binary", 1: "latin1", 2: "utf16le" };

for (let i = 0; i < metaLength / CHUNK_SIZE; i++) {
  const m = modulesStart + metaOffset + i * CHUNK_SIZE;
  const path = slice(v.getUint32(m, true), v.getUint32(m + 4, true)).toString("utf8");
  if (!path.startsWith("/$bunfs/root/")) throw new Error(`unexpected module path: ${path}`);
  const raw = slice(v.getUint32(m + 8, true), v.getUint32(m + 12, true));
  if (raw.length === 0) throw new Error(`module ${path} is empty`);
  const encoding = ENCODINGS[v.getUint8(m + 48)];
  if (!encoding) throw new Error(`module ${path} has unsupported encoding ${v.getUint8(m + 48)}`);
  const rel = i === entryId ? "index.js" : path.slice("/$bunfs/root/".length);
  const root = resolve(outDir);
  const dest = resolve(root, rel);
  const inside = relative(root, dest);
  if (!inside || inside === ".." || inside.startsWith(".." + sep) || isAbsolute(inside)) {
    throw new Error(`module path escapes the output directory: ${path}`);
  }
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, encoding === "binary" ? raw : raw.toString(encoding));
  console.log(`  ${rel} (${raw.length} bytes, ${encoding})`);
}
'@

    $decompileOutput = bun $ExtractorPath $LinuxBinary $DecompiledDir 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        Write-Host $decompileOutput
        Write-Error "Bundle extraction exited with code $LASTEXITCODE."
    }
    Write-Host $decompileOutput -ForegroundColor DarkGray

    # --- Process Locking Validation ---
    $runningProcesses = Get-Process -Name "cr", "coderabbit" -ErrorAction SilentlyContinue
    if ($runningProcesses) {
        Write-Host "`n[!] Found active CodeRabbit CLI instances running in the background." -ForegroundColor Yellow
        $killChoice = Read-Host "Would you like to attempt to close these running processes to avoid file locking errors? (Y/N)"
        if ($killChoice -match '^[Yy]') {
            Write-Host "  [*] Stopping active CodeRabbit processes..." -ForegroundColor DarkYellow
            $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        } else {
            Write-Host "  [~] Proceeding without closing. Note: Compilation or swapping may fail if files are locked." -ForegroundColor DarkYellow
        }
    }

    # --- 5. Compile Native Binary ---
    Write-Host "`n[*] Compiling native Windows executable..."
    Set-Location $DecompiledDir

    # The extractor always writes the entry module as index.js. Every other .js
    # file in the output is a bundled chunk; picking one by size or name would
    # compile an arbitrary dependency into coderabbit.exe, so fail instead of guessing.
    $EntryPoint = "index.js"
    $EntryFile = Join-Path $DecompiledDir $EntryPoint
    if (-not (Test-Path $EntryFile) -or (Get-Item $EntryFile).Length -eq 0) {
        Write-Error "Decompiled output has no usable $EntryPoint entry point; refusing to guess one. Inspect $DecompiledDir."
    }

    Write-Host "  [~] Using entry point: $EntryPoint" -ForegroundColor DarkYellow

    if (Test-Path (Join-Path $DecompiledDir "package.json")) {
        bun install --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Error "bun install failed with exit code $LASTEXITCODE."
        }
    }
    bun build $EntryPoint --compile --target=bun-windows-x64 --outfile=$ExePath

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ExePath)) {
        Write-Error "Compilation failed: bun exited with code $LASTEXITCODE and no executable was produced."
    }

    $CompiledVersion = Get-ExeVersion -Path $ExePath
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

} finally {
    Set-Location $OriginalLocation
}

# --- 6. Path Configuration ---
Write-Host "`n[*] Adding executable to PATH..."
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

$normalizedBinDir = $BinDir.TrimEnd('\')
$pathEntries = if (-not [string]::IsNullOrWhiteSpace($userPath)) { 
    ($userPath -split ';') | ForEach-Object { $_.TrimEnd('\') } 
} else { @() }

if ($pathEntries -notcontains $normalizedBinDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $BinDir } else { "$userPath;$BinDir" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:Path = "$env:Path;$BinDir"
}

# --- 7. Cleanup ---
Write-Host "`n[*] Cleaning up temporary files..."
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Success! CodeRabbit v$LatestVersion Installed " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nPlease restart your terminal, then run:"
Write-Host "  cr auth login" -ForegroundColor Cyan
