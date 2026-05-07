# Xenon Installer Script
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    Write-Host @"
 ██╗  ██╗███████╗███╗   ██╗ ██████╗ ███╗   ██╗
 ╚██╗██╔╝██╔════╝████╗  ██║██╔═══██╗████╗  ██║
  ╚███╔╝ █████╗  ██╔██╗ ██║██║   ██║██╔██╗ ██║
  ██╔██╗ ██╔══╝  ██║╚██╗██║██║   ██║██║╚██╗██║
 ██╔╝ ██╗███████╗██║ ╚████║╚██████╔╝██║ ╚████║
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝
    Autonomous Self-Editing Agent Framework
"@ -ForegroundColor Cyan
    Write-Host "---------------------------------------------" -ForegroundColor Gray
}

function Show-Step {
    param([string]$Message)
    Write-Host "`n[>] $Message" -ForegroundColor Yellow
}

function Show-Success {
    param([string]$Message)
    Write-Host "[v] $Message" -ForegroundColor Green
}

Show-Header

# 1. Check for Git
Show-Step "Checking for Git..."
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Git is required. Install it from https://git-scm.com/" -ForegroundColor Red
    return
}
Show-Success "Git found."

# 2. Check for Rust
Show-Step "Checking for Rust..."
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Rust not found. Installing Rustup..." -ForegroundColor Yellow
    irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y
    Remove-Item ./rustup-init.exe
    $env:Path += ";$HOME\.cargo\bin"
}
Show-Success "Rust ready."

# 3. Check for Node.js
Show-Step "Checking for Node.js..."
if (!(Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Node.js is required. Install it from https://nodejs.org/" -ForegroundColor Red
    return
}
Show-Success "Node.js ready."

# 4. Clone Repository
Show-Step "Cloning Xenon repository from turtle170/Xenon..."
$RepoUrl = "https://github.com/turtle170/Xenon.git"
if (Test-Path "Xenon") {
    Write-Host "Directory 'Xenon' exists. Updating..." -ForegroundColor Gray
    Set-Location Xenon
    git pull
} else {
    git clone $RepoUrl
    Set-Location Xenon
}
Show-Success "Repository cloned."

# 5. Install Dependencies
Show-Step "Installing NPM dependencies..."
npm install --silent
Show-Success "NPM dependencies installed."

# 6. Build
Show-Step "Building Xenon binary (this may take a few minutes)..."
npm run tauri build
Show-Success "Build complete."

Show-Header
Show-Success "XENON INSTALLATION SUCCESSFUL"
Write-Host "`nTo start Xenon:" -ForegroundColor White
Write-Host "  cd Xenon" -ForegroundColor Gray
Write-Host "  npm run tauri dev" -ForegroundColor Gray
Write-Host "`nEnjoy your autonomous agent.`n" -ForegroundColor Cyan
