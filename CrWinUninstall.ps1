<#
.SYNOPSIS
Uninstaller for CodeRabbit CLI Windows Port
#>

$ErrorActionPreference = 'Stop'

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

Write-Host ""
Write-Host ""
Write-Host "        ============================================" -ForegroundColor Red
Write-Host "          Uninstalling CodeRabbit CLI Windows Port"   -ForegroundColor Red
Write-Host "        ============================================" -ForegroundColor Red

# Strict confirmation loop
$confirmation = ""
while ($confirmation -notmatch "^(y|yes|n|no)$") {
    $confirmation = Read-Host "`nAre you sure you want to completely uninstall the CodeRabbit CLI? (y/n)"
}

if ($confirmation -match "^(n|no)$") {
    Write-Host "Uninstallation aborted by user." -ForegroundColor Yellow
    exit
}

Write-Host "`nProceeding with uninstallation..." -ForegroundColor Cyan

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\CodeRabbit"
$BinDir     = Join-Path $InstallDir "bin"

# 1. Remove the directory safely
if (Test-Path $InstallDir) {
    Write-Host "[*] Removing CodeRabbit CLI files..."
    
    # Force kill and wait for OS handle release
    $runningProcesses = Get-Process -Name "cr", "coderabbit" -ErrorAction SilentlyContinue
    if ($runningProcesses) {
        $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    
    try {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "    Files deleted successfully." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Failed to delete installation directory: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "        Please close any applications using the files and try again." -ForegroundColor Yellow
    }
} else {
    Write-Host "[*] CodeRabbit CLI is not installed in the default location." -ForegroundColor Yellow
}

# 2. Clean up Environment PATH
Write-Host "[*] Cleaning up Environment PATH..."
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $pathArray = $userPath -split ';'
    
    # Normalize paths to handle trailing slashes during comparison
    $normalizedBinDir = $BinDir.TrimEnd('\')
    $newPathArray = $pathArray | Where-Object { 
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd('\') -ne $normalizedBinDir 
    }

    if ($pathArray.Count -ne $newPathArray.Count) {
        $newPath = $newPathArray -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        
        # Also sync current active session PATH
        $env:Path = ($env:Path -split ';' | Where-Object { $_.TrimEnd('\') -ne $normalizedBinDir }) -join ';'
        Write-Host "    PATH variable cleaned." -ForegroundColor Green
    } else {
        Write-Host "    PATH variable was already clean." -ForegroundColor Green
    }
}

# 3. Clean up auth tokens
$ConfigDir = Join-Path $env:APPDATA "CodeRabbit"
if (Test-Path $ConfigDir) {
    Write-Host "`n[*] Found stored CodeRabbit authentication tokens."
    
    $deleteTokens = ""
    while ($deleteTokens -notmatch "^(y|yes|n|no)$") {
        $deleteTokens = Read-Host "    Do you want to delete your saved login session? (y/n)"
    }
    
    if ($deleteTokens -match "^(y|yes)$") {
        try {
            Remove-Item -Path $ConfigDir -Recurse -Force
            Write-Host "    Authentication data deleted." -ForegroundColor Green
        } catch {
            Write-Host "    [!] Could not delete configuration directory: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    Authentication data kept." -ForegroundColor Yellow
    }
}

Write-Host "`nUninstallation complete. Please restart your terminal to fully clear remaining cache." -ForegroundColor Green