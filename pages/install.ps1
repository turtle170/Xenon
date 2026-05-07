# Xenon Installer Script
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

Write-Host "--- Xenon Installation Starting ---" -ForegroundColor Cyan

# Check for Rust
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Rust not found. Installing Rustup..." -ForegroundColor Yellow
    irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y
    Remove-Item ./rustup-init.exe
    $env:Path += ";$HOME\.cargo\bin"
}

# Check for Node.js
if (!(Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js not found. Please install Node.js from https://nodejs.org/" -ForegroundColor Red
    return
}

Write-Host "Cloning Xenon repository..." -ForegroundColor Cyan
if (Test-Path "Xenon") {
    Write-Host "Xenon directory already exists. Updating..." -ForegroundColor Yellow
    cd Xenon
    git pull
} else {
    git clone https://github.com/YourUsername/Xenon.git
    cd Xenon
}

Write-Host "Installing dependencies..." -ForegroundColor Cyan
npm install

Write-Host "Building Xenon..." -ForegroundColor Cyan
npm run tauri build

Write-Host "--- Xenon Installed! ---" -ForegroundColor Green
Write-Host "Run 'npm run tauri dev' to start."
