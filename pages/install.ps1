# Xenon Installer Script - Ultra Visuals & Neural Aware
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    
    # --- Advanced Terminal Graphics Detection ---
    $SupportsKitty = $false
    $SupportsSixel = $false
    
    if ($env:TERM_PROGRAM -eq "WezTerm" -or $env:TERM -match "kitty") {
        $SupportsKitty = $true
    }
    
    # Simple Sixel check (Optimistic for modern Windows Terminal / VT100)
    if ($env:WT_SESSION -ne $null) { $SupportsSixel = $true }

    $iconPath = "$env:TEMP\XenonIcon.png"
    if (!(Test-Path $iconPath)) {
        Invoke-WebRequest -Uri "https://xenonai.pages.dev/XenonIcon.png" -OutFile $iconPath
    }
    
    try {
        if ($SupportsKitty) {
            $bytes = [System.IO.File]::ReadAllBytes($iconPath)
            $base64 = [System.Convert]::ToBase64String($bytes)
            Write-Host "`e_Ga=T,f=100,a=T;$base64`e\" 
        } elseif ($SupportsSixel) {
            $bytes = [System.IO.File]::ReadAllBytes($iconPath)
            $base64 = [System.Convert]::ToBase64String($bytes)
            Write-Host "`e]1337;File=name=logo.png;inline=1;width=30;height=auto:$base64`a"
        } else {
            Write-Host "    [ X E N O N ]" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "    [ X E N O N ]" -ForegroundColor Cyan
    }

    Write-Host "`n    X E N O N : THE AUTONOMOUS AGENT" -ForegroundColor Cyan
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

# --- 1. Advanced Hardware Detection (VNNI Aware) ---
Show-Header
Show-Step "Scanning CPU for Neural Acceleration (VNNI)..."

$simdSource = @"
using System;
using System.Runtime.Intrinsics.X86;
public class CpuCheck {
    public static string GetSIMD() {
        if (Avx512F.IsSupported) return "avx512";
        if (Avx2.IsSupported) return "avx2";
        return "avx";
    }
    public static string GetVNNI() {
        bool avxVnni = false;
        bool avx512Vnni = false;
        try {
            var v2 = typeof(Avx).Assembly.GetType("System.Runtime.Intrinsics.X86.AvxVnni");
            if (v2 != null) avxVnni = (bool)v2.GetProperty("IsSupported").GetValue(null);
            var v512 = typeof(Avx).Assembly.GetType("System.Runtime.Intrinsics.X86.Avx512Vnni");
            if (v512 != null) avx512Vnni = (bool)v512.GetProperty("IsSupported").GetValue(null);
        } catch {}
        if (avx512Vnni) return "AVX-512 VNNI";
        if (avxVnni) return "AVX2-VNNI";
        return "Standard";
    }
}
"@
Add-Type -TypeDefinition $simdSource -ErrorAction SilentlyContinue
$SimdFeature = [CpuCheck]::GetSIMD()
$VnniFeature = [CpuCheck]::GetVNNI()
Show-Success "Detected: $SimdFeature with $VnniFeature acceleration."

# --- 2. Configuration Phase ---
$Providers = @{
    "OpenAI" = @{ url = "https://platform.openai.com/api-keys"; model = "gpt-4o" }
    "Anthropic" = @{ url = "https://console.anthropic.com/settings/keys"; model = "claude-3-5-sonnet-latest" }
    "Gemini" = @{ url = "https://aistudio.google.com/app/apikey"; model = "gemini-1.5-pro" }
    "DeepSeek" = @{ url = "https://platform.deepseek.com/api_keys"; model = "deepseek-chat" }
    "Llama (Local)" = @{ url = "https://github.com/ggerganov/llama.cpp"; model = "local" }
}

$ProviderKey = Get-ProviderSelection "Choose your LLM Brain:" $Providers
$ProviderInfo = $Providers[$ProviderKey]

$ApiKey = ""
if ($ProviderKey -ne "Llama (Local)") {
    Write-Host "`n  Get your API key at: $($ProviderInfo.url)" -ForegroundColor Cyan
    $valid = $false
    while (!$valid) {
        $ApiKey = Read-Host "  Enter your API Key"
        if ($ProviderKey -eq "Gemini") {
            if ($ApiKey -match "^AIza" -or $ApiKey -match "^AQ") { $valid = $true }
            else { Write-Host "  Invalid Gemini Key. Use AIza... or AQ..." -ForegroundColor Red }
        } else { $valid = $true }
    }
}

# --- 3. Browser Detection ---
Show-Step "Detecting Browsers for Data Import..."
$Browsers = @{"None" = "none"}
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"; "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Opera GX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $Browsers[$b] = $Paths[$b]; Write-Host "  [+] $b" -ForegroundColor Green } }
$SelectedBrowser = Get-ProviderSelection "Select Browser for Context Migration:" $Browsers

# --- 4. Environment Validation ---
Show-Step "Validating local toolchain..."
if (!(Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Error: Git required."; return }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { 
    Show-Step "Installing Rust Toolchain..."; irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y; Remove-Item ./rustup-init.exe; $env:Path += ";$HOME\.cargo\bin"
}
if (!(Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Error: Node.js required."; return }

# --- 5. Installation ---
Show-Step "Cloning Xenon..."
if (Test-Path "Xenon") { Set-Location Xenon; git pull } else { git clone https://github.com/turtle170/Xenon.git; Set-Location Xenon }

# --- 6. Hardware-Optimized Server Setup ---
Show-Step "Installing Optimized llama-server..."
mkdir -Force bin
$tag = "b4676"
$zipName = "llama-$tag-bin-win-$SimdFeature-x64.zip"
$url = "https://github.com/ggerganov/llama.cpp/releases/download/$tag/$zipName"
try {
    Invoke-WebRequest -Uri $url -OutFile "llama.zip"
    tar -xf "llama.zip" -C bin; Remove-Item "llama.zip"
    Show-Success "llama-server optimized for $VnniFeature installed."
} catch {
    Write-Host "  Failed to download server." -ForegroundColor Yellow
}

# --- 7. Python Environment Setup ---
Show-Step "Setting up dual-version embedded Python..."
./setup_python.ps1
Show-Success "Python environments ready."

# --- 8. Finalize ---
$Config = @{
    provider = $ProviderKey; api_key = $ApiKey; model = $ProviderInfo.model
    local_server = "http://localhost:8080"; import_browser = $SelectedBrowser
    simd = $SimdFeature; vnni = $VnniFeature
}
$Config | ConvertTo-Json | Set-Content "config.json"

Show-Step "Building Xenon Core..."
npm install --silent; npm run tauri build

$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName; $Shortcut.IconLocation = $TargetFile.FullName; $Shortcut.Save()
}

Show-Header
Show-Success "XENON INSTALLATION SUCCESSFUL"
Write-Host "`nReady to automate."
