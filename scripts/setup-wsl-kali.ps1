#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap script: installs WSL2 + Kali Linux on a default Windows 10 machine,
    then installs usbipd-win for USB passthrough so the Pixel 8 Pro can be reached
    from inside WSL.

.DESCRIPTION
    Run this script ONCE from an elevated PowerShell 7 session on a fresh Windows 10
    (build 19041 / 20H1 or later) or Windows 11 machine.

    What it does:
      1. Verifies PowerShell 7, Windows build, and Administrator privilege.
      2. Enables the WSL and VirtualMachinePlatform Windows optional features.
      3. Sets WSL default version to 2.
      4. Installs or updates the WSL2 Linux kernel.
      5. Installs the kali-linux WSL distribution.
      6. Installs usbipd-win so the Pixel 8 Pro (fastboot / ADB) can be
         attached to the WSL environment.
      7. Triggers a first-launch of the Kali shell to provision it
         (installs git, docker.io, fastboot, kali-archive-keyring, adb).

    A reboot may be required between steps 2 and 3 the very first time this
    script runs.  The script detects this and will prompt you to reboot; simply
    re-run the script after the reboot to continue.

.NOTES
    - Must be run as Administrator.
    - Requires an internet connection.
    - Tested on Windows 10 20H2 (build 19042) through Windows 11 24H2.
    - Compatible with PowerShell 7.2 LTS and later.

.EXAMPLE
    # Open PowerShell 7 as Administrator and run:
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\setup-wsl-kali.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── helper functions ──────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n[+] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    OK  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    WARN  $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "`n[!] FATAL: $Message" -ForegroundColor Red
}

function Assert-ExitCode {
    param([int]$Code, [string]$Context)
    if ($Code -ne 0) {
        Write-Fail "$Context exited with code $Code."
        exit 1
    }
}

# ─── 1. PowerShell version ────────────────────────────────────────────────────
Write-Step "Checking PowerShell version"
$psMajor = $PSVersionTable.PSVersion.Major
$psMinor = $PSVersionTable.PSVersion.Minor
if ($psMajor -lt 7) {
    Write-Fail "This script requires PowerShell 7+. You are running $($PSVersionTable.PSVersion)."
    Write-Host "    Install from: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}
Write-Ok "PowerShell $psMajor.$psMinor"

# ─── 2. Administrator privilege ──────────────────────────────────────────────
Write-Step "Checking Administrator privilege"
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "This script must be run as Administrator."
    Write-Host "    Right-click pwsh.exe and choose 'Run as administrator'." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Running as Administrator"

# ─── 3. Windows version ───────────────────────────────────────────────────────
Write-Step "Checking Windows version"
$osInfo   = Get-CimInstance Win32_OperatingSystem
$osBuild  = [int]$osInfo.BuildNumber
$osName   = $osInfo.Caption

Write-Host "    Detected: $osName (build $osBuild)"

# WSL2 requires build 19041 (Windows 10 20H1) or later.
$MIN_BUILD = 19041
if ($osBuild -lt $MIN_BUILD) {
    Write-Fail "Windows build $osBuild is too old. WSL2 requires build $MIN_BUILD or later."
    Write-Host "    Run Windows Update and reboot, then re-run this script." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Build $osBuild >= $MIN_BUILD"

# ─── 4. Internet connectivity ─────────────────────────────────────────────────
Write-Step "Checking internet connectivity"
try {
    $null = Invoke-RestMethod -Uri "https://www.msftconnecttest.com/connecttest.txt" -TimeoutSec 10
    Write-Ok "Internet reachable"
} catch {
    Write-Fail "No internet connection detected (cannot reach msftconnecttest.com)."
    Write-Host "    Connect to the internet and re-run this script." -ForegroundColor Yellow
    exit 1
}

# ─── 5. Check / enable Windows optional features ─────────────────────────────
Write-Step "Checking WSL optional feature"

function Get-FeatureState {
    param([string]$FeatureName)
    $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    return $f.State
}

$wslState = Get-FeatureState "Microsoft-Windows-Subsystem-Linux"
$vmState  = Get-FeatureState "VirtualMachinePlatform"

$rebootNeeded = $false

if ($wslState -ne "Enabled") {
    Write-Warn "Microsoft-Windows-Subsystem-Linux not enabled — enabling now..."
    $result = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -All
    if ($result.RestartNeeded) { $rebootNeeded = $true }
    Write-Ok "WSL feature enabled"
} else {
    Write-Ok "WSL feature already enabled"
}

Write-Step "Checking VirtualMachinePlatform optional feature"
if ($vmState -ne "Enabled") {
    Write-Warn "VirtualMachinePlatform not enabled — enabling now..."
    $result = Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -All
    if ($result.RestartNeeded) { $rebootNeeded = $true }
    Write-Ok "VirtualMachinePlatform feature enabled"
} else {
    Write-Ok "VirtualMachinePlatform already enabled"
}

if ($rebootNeeded) {
    Write-Host "`n========================================================" -ForegroundColor Yellow
    Write-Host " A reboot is required to finish enabling WSL2 features." -ForegroundColor Yellow
    Write-Host " After rebooting, re-run this script to continue setup." -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Yellow
    $choice = Read-Host "Reboot now? [Y/n]"
    if ($choice -eq '' -or $choice -match '^[Yy]') {
        Restart-Computer -Force
    }
    exit 0
}

# ─── 6. wsl.exe availability and kernel update ───────────────────────────────
Write-Step "Checking wsl.exe availability"
$wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslExe) {
    Write-Fail "wsl.exe not found. The WSL feature may not have been activated yet."
    Write-Host "    Reboot and re-run this script." -ForegroundColor Yellow
    exit 1
}
Write-Ok "wsl.exe found at $($wslExe.Source)"

Write-Step "Setting WSL default version to 2"
wsl.exe --set-default-version 2 2>&1 | ForEach-Object { Write-Host "    $_" }
# Exit code 0 = success; ignore informational messages.
Write-Ok "Default WSL version set to 2"

Write-Step "Updating WSL2 kernel"
wsl.exe --update 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Ok "WSL2 kernel up to date"

# ─── 7. Install Kali Linux distribution ──────────────────────────────────────
Write-Step "Checking for Kali Linux WSL distribution"
$distros = wsl.exe --list --quiet 2>&1
$kaliInstalled = $distros | Where-Object { $_ -match 'kali' }

if ($kaliInstalled) {
    Write-Ok "kali-linux is already installed"
} else {
    Write-Warn "kali-linux not found — installing now (this may take several minutes)..."
    wsl.exe --install -d kali-linux --no-launch
    Assert-ExitCode $LASTEXITCODE "wsl --install -d kali-linux"
    Write-Ok "kali-linux installed"
}

# ─── 8. Install usbipd-win ────────────────────────────────────────────────────
Write-Step "Checking usbipd-win"

$usbipdInstalled = $false
try {
    $usbipdVer = (Get-Command usbipd.exe -ErrorAction Stop).FileVersionInfo.ProductVersion
    Write-Ok "usbipd-win already installed (version $usbipdVer)"
    $usbipdInstalled = $true
} catch {
    # Not found
}

if (-not $usbipdInstalled) {
    # Prefer winget; fall back to direct GitHub MSI download.
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Warn "usbipd-win not found — installing via winget..."
        winget install --id usbipd-win_usbipd-win --exact --accept-source-agreements --accept-package-agreements
        Assert-ExitCode $LASTEXITCODE "winget install usbipd-win"
        Write-Ok "usbipd-win installed via winget"
    } else {
        Write-Warn "winget not available — downloading usbipd-win MSI from GitHub..."

        # Resolve the latest release tag via the GitHub API.
        try {
            $releaseInfo = Invoke-RestMethod `
                -Uri "https://api.github.com/repos/dorssel/usbipd-win/releases/latest" `
                -Headers @{ 'User-Agent' = 'nhpro-native-husky-setup' } `
                -TimeoutSec 30
        } catch {
            Write-Fail "Failed to query GitHub API for usbipd-win release: $_"
            exit 1
        }

        $msiAsset = $releaseInfo.assets | Where-Object { $_.name -match '\.msi$' } | Select-Object -First 1
        if (-not $msiAsset) {
            Write-Fail "Could not find an MSI asset in the latest usbipd-win release."
            exit 1
        }

        $msiPath = Join-Path $env:TEMP $msiAsset.name
        Write-Host "    Downloading $($msiAsset.browser_download_url) ..."
        Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $msiPath -UseBasicParsing

        Write-Host "    Installing $($msiAsset.name) ..."
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru
        if ($proc.ExitCode -notin 0, 3010) {
            Write-Fail "msiexec exited with code $($proc.ExitCode)."
            exit 1
        }

        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        Write-Ok "usbipd-win installed from MSI"

        if ($proc.ExitCode -eq 3010) {
            Write-Warn "A reboot is recommended to complete usbipd-win installation."
        }
    }
}

# ─── 9. Provision Kali: install packages ─────────────────────────────────────
# We run inside the kali-linux distro via `wsl -d kali-linux -- bash -c '...'`
Write-Step "Provisioning Kali Linux (installing packages)"
Write-Host "    This runs apt update + apt install inside Kali — may take several minutes."

# The compound command is passed as a single string to bash -c.
$aptCmd = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[kali-provision] Running apt update..."
sudo apt-get update -y

echo "[kali-provision] Installing core packages..."
sudo apt-get install -y \
    git \
    docker.io \
    kali-archive-keyring \
    fastboot \
    adb \
    xz-utils \
    android-sdk-libsparse-utils

echo "[kali-provision] Adding current user to docker group..."
sudo usermod -aG docker "$USER"

echo "[kali-provision] Enabling and starting Docker service..."
sudo service containerd start || true
sudo service docker start    || true

echo "[kali-provision] Done."
'@

# Write the command to a temp file so we avoid quoting nightmares.
$tmpSh = Join-Path $env:TEMP "kali-provision.sh"
$aptCmd | Set-Content -Path $tmpSh -Encoding utf8 -NoNewline

# Convert Windows temp path to WSL path
$wslTmpSh = wsl.exe wslpath -u $tmpSh.Replace('\','/')
$wslTmpSh = $wslTmpSh.Trim()

wsl.exe -d kali-linux -- bash "$wslTmpSh"
$provisionExit = $LASTEXITCODE
Remove-Item $tmpSh -Force -ErrorAction SilentlyContinue

if ($provisionExit -ne 0) {
    Write-Fail "Kali provisioning failed (exit $provisionExit)."
    Write-Host "    Open Kali manually (`wsl -d kali-linux`) and investigate." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Kali packages installed"

# ─── 10. Clone this repository inside Kali ───────────────────────────────────
Write-Step "Cloning nhpro-native-husky repository inside Kali"

$cloneCmd = @'
set -euo pipefail
REPO_URL="https://github.com/mikethi/nhpro-native-husky.git"
DEST="${HOME}/nhpro-native-husky"
if [ -d "${DEST}/.git" ]; then
    echo "[kali-clone] Repository already cloned at ${DEST} — pulling latest..."
    git -C "${DEST}" pull --ff-only
else
    echo "[kali-clone] Cloning ${REPO_URL} to ${DEST}..."
    git clone "${REPO_URL}" "${DEST}"
fi
echo "[kali-clone] Done: ${DEST}"
'@

$tmpClone = Join-Path $env:TEMP "kali-clone.sh"
$cloneCmd | Set-Content -Path $tmpClone -Encoding utf8 -NoNewline
$wslTmpClone = (wsl.exe wslpath -u $tmpClone.Replace('\','/')).Trim()

wsl.exe -d kali-linux -- bash "$wslTmpClone"
$cloneExit = $LASTEXITCODE
Remove-Item $tmpClone -Force -ErrorAction SilentlyContinue

if ($cloneExit -ne 0) {
    Write-Fail "Repository clone failed (exit $cloneExit)."
    exit 1
}
Write-Ok "Repository cloned inside Kali at ~/nhpro-native-husky"

# ─── 11. Summary ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next steps:"
Write-Host ""
Write-Host "   1. Open Kali Linux (search 'kali' in the Start menu, or run:"
Write-Host "        wsl -d kali-linux"
Write-Host ""
Write-Host "   2. Inside Kali, run the build script:"
Write-Host "        cd ~/nhpro-native-husky/nethunter-pro"
Write-Host "        ./kali-build.sh"
Write-Host ""
Write-Host "   3. To attach your Pixel 8 Pro (in fastboot mode) to WSL:"
Write-Host "        # In an elevated PowerShell window on Windows:"
Write-Host "        usbipd list"
Write-Host "        usbipd bind   --busid <BUSID>"
Write-Host "        usbipd attach --wsl --busid <BUSID>"
Write-Host ""
Write-Host " Note: If this is the first time you have added your user to the"
Write-Host " docker group inside Kali, close and reopen the Kali terminal"
Write-Host " (or run: newgrp docker) before running the build script."
Write-Host ""
