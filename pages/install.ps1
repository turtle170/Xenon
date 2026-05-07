# Xenon Installer Script - Hardware-Aware Edition
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    $Colors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
    $Dragon = @(
        "           _,---._      /|",
        "        ,-'       `-._ / |",
        "      ,'  X E N O N   `  |",
        "     /                \  |",
        "    /       ,_     ,_  \ |",
        "   |       /  `   /  `  ||",
        "   |       \__/   \__/  ||",
        "   \           _        /|",
        "    \         (_)      / |",
        "     `.              ,'  |",
        "       `-._      _.-'    |",
        "           `----'        |"
    )
    for ($i = 0; $i -lt $Dragon.Count; $i++) {
        Write-Host $Dragon[$i] -ForegroundColor $Colors[$i % $Colors.Count]
    }
    Write-Host "`n    X E N O N : AUTONOMOUS AGENT FRAMEWORK" -ForegroundColor Cyan
    Write-Host "---------------------------------------------" -ForegroundColor Gray
}

function Show-Step { param([string]$Message) Write-Host "`n[>] $Message" -ForegroundColor Yellow }
function Show-Success { param([string]$Message) Write-Host "[v] $Message" -ForegroundColor Green }

function Get-ProviderSelection {
    param([string]$Prompt, [hashtable]$Options)
    Show-Header
    Write-Host "`n$Prompt`n" -ForegroundColor White
    $Keys = $Options.Keys | Sort-Object
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        Write-Host "  $($i + 1)) $($Keys[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $Index = Read-Host "  Select option (1-$($Keys.Count))"
    return $Keys[$Index - 1]
}

# --- 1. Hardware Detection ---
Show-Header
Show-Step "Detecting Hardware Capabilities..."

$cpuInfo = Get-CimInstance Win32_Processor
Write-Host "  CPU: $($cpuInfo.Name)" -ForegroundColor Gray

# Detect SIMD via inline C#
$simdSource = @"
using System;
using System.Runtime.Intrinsics.X86;
public class CpuCheck {
    public static string GetSIMD() {
        if (Avx512F.IsSupported) return "avx512";
        if (Avx2.IsSupported) return "avx2";
        if (Avx.IsSupported) return "avx";
        return "no-avx";
    }
}
"@
Add-Type -TypeDefinition $simdSource
$SimdFeature = [CpuCheck]::GetSIMD()
Show-Success "Detected SIMD: $SimdFeature"

# --- 2. Configuration Phase ---
$Providers = @{
    "OpenAI" = @{ url = "https://platform.openai.com/api-keys"; model = "gpt-4o" }
    "Anthropic" = @{ url = "https://console.anthropic.com/settings/keys"; model = "claude-3-5-sonnet-latest" }
    "Gemini" = @{ url = "https://aistudio.google.com/app/apikey"; model = "gemini-1.5-pro" }
    "DeepSeek" = @{ url = "https://platform.deepseek.com/api_keys"; model = "deepseek-chat" }
    "Llama (Local)" = @{ url = "https://github.com/ggerganov/llama.cpp"; model = "local" }
}

$ProviderKey = Get-ProviderSelection "Choose your LLM Provider:" $Providers
$ProviderInfo = $Providers[$ProviderKey]

$ApiKey = ""
$GgufPath = ""

if ($ProviderKey -eq "Llama (Local)") {
    $GgufPath = Read-Host "  Enter full path to your .GGUF model file (leave blank to just install server)"
} else {
    Write-Host "`n  Get your API key at: $($ProviderInfo.url)" -ForegroundColor Cyan
    $valid = $false
    while (!$valid) {
        $ApiKey = Read-Host "  Enter your API Key"
        if ($ProviderKey -eq "Gemini") {
            if ($ApiKey -match "^AIza" -or $ApiKey -match "^AQ") { $valid = $true }
            else { Write-Host "  Invalid Gemini Key. Try again." -ForegroundColor Red }
        } else { $valid = $true }
    }
}

# --- 3. Browser Detection ---
Show-Step "Detecting Browsers..."
$Browsers = @{"None" = "none"}
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"; "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Opera GX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $Browsers[$b] = $Paths[$b]; Write-Host "  [+] $b" -ForegroundColor Green } }
$SelectedBrowser = Get-ProviderSelection "Select browser to import data from:" $Browsers

# --- 4. Environment Validation ---
Show-Header
Show-Step "Validating dependencies..."
if (!(Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Error: Git required."; return }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { 
    Show-Step "Installing Rust..."; irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y; Remove-Item ./rustup-init.exe; $env:Path += ";$HOME\.cargo\bin"
}
if (!(Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Error: Node.js required."; return }

# --- 5. Installation ---
Show-Step "Cloning Xenon..."
if (Test-Path "Xenon") { Set-Location Xenon; git pull } else { git clone https://github.com/turtle170/Xenon.git; Set-Location Xenon }

# --- 6. Llama Server Setup ---
if ($ProviderKey -eq "Llama (Local)" -or $SimdFeature -ne "no-avx") {
    Show-Step "Installing hardware-optimized llama-server ($SimdFeature)..."
    mkdir -Force bin
    # We use a recent stable tag
    $tag = "b4676"
    $zipName = "llama-$tag-bin-win-$SimdFeature-x64.zip"
    if ($SimdFeature -eq "no-avx") { $zipName = "llama-$tag-bin-win-noavx-x64.zip" }
    
    $url = "https://github.com/ggerganov/llama.cpp/releases/download/$tag/$zipName"
    Write-Host "  Downloading from: $url" -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $url -OutFile "llama.zip"
        tar -xf "llama.zip" -C bin
        Remove-Item "llama.zip"
        Show-Success "llama-server installed in bin/"
    } catch {
        Write-Host "  Failed to download optimized server. Skipping local setup." -ForegroundColor Yellow
    }
}

# --- 7. Finalize ---
$Config = @{
    provider = $ProviderKey; api_key = $ApiKey; model = $ProviderInfo.model
    local_server = "http://localhost:8080"; gguf_path = $GgufPath; import_browser = $SelectedBrowser
    simd = $SimdFeature
}
$Config | ConvertTo-Json | Set-Content "config.json"

Show-Step "Building Xenon..."
npm install --silent; npm run tauri build

$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName; $Shortcut.IconLocation = $TargetFile.FullName; $Shortcut.Save()
    Show-Success "Shortcut created."
}

Show-Header
Show-Success "XENON INSTALLATION SUCCESSFUL"
Write-Host "`nHardware: $SimdFeature optimized"
Write-Host "Launch Xenon from Desktop."
