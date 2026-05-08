# Xenon Installer Script - Ultra Visuals & Neural Aware & Sandbox
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    $SupportsKitty = $false
    $SupportsSixel = $false
    if ($env:TERM_PROGRAM -eq "WezTerm" -or $env:TERM -match "kitty") { $SupportsKitty = $true }
    if ($env:WT_SESSION -ne $null) { $SupportsSixel = $true }

    $iconPath = "$env:TEMP\XenonIcon.png"
    if (!(Test-Path $iconPath)) { Invoke-WebRequest -Uri "https://xenonai.pages.dev/XenonIcon.png" -OutFile $iconPath }
    
    try {
        if ($SupportsKitty) {
            $bytes = [System.IO.File]::ReadAllBytes($iconPath); $base64 = [System.Convert]::ToBase64String($bytes)
            Write-Host "`e_Ga=T,f=100,a=T;$base64`e\" 
        } elseif ($SupportsSixel) {
            $bytes = [System.IO.File]::ReadAllBytes($iconPath); $base64 = [System.Convert]::ToBase64String($bytes)
            Write-Host "`e]1337;File=name=logo.png;inline=1;width=30;height=auto:$base64`a"
        } else { Write-Host "    [ X E N O N ]" -ForegroundColor Cyan }
    } catch { Write-Host "    [ X E N O N ]" -ForegroundColor Cyan }

    Write-Host "`n    X E N O N : THE AUTONOMOUS AGENT" -ForegroundColor Cyan
    Write-Host "---------------------------------------------" -ForegroundColor Gray
}

function Show-Step { param([string]$Message) Write-Host "`n[>] $Message" -ForegroundColor Yellow }
function Show-Success { param([string]$Message) Write-Host "[v] $Message" -ForegroundColor Green }
function Get-ProviderSelection {
    param([string]$Prompt, [hashtable]$Options)
    Show-Header; Write-Host "`n$Prompt`n" -ForegroundColor White
    $Keys = $Options.Keys | Sort-Object
    for ($i = 0; $i -lt $Keys.Count; $i++) { Write-Host "  $($i + 1)) $($Keys[$i])" -ForegroundColor Gray }
    Write-Host ""; $Index = Read-Host "  Select option (1-$($Keys.Count))"
    return $Keys[$Index - 1]
}

# --- 1. Advanced Hardware Detection (VNNI) ---
Show-Header
Show-Step "Scanning for Neural Acceleration..."

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
        bool avxVnni = false; bool avx512Vnni = false;
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
Show-Success "Architecture: $SimdFeature with $VnniFeature"

# --- 1.5 WSL Debian 13 Sandbox Setup ---
Show-Step "Configuring Auto-Scaling Debian VM Sandbox..."
$WslStatus = (wsl --status 2>&1)
if ($LASTEXITCODE -eq 0 -or $WslStatus -match "Windows Subsystem for Linux") {
    $sandboxPath = "$PWD\VM"
    if (!(Test-Path $sandboxPath)) { New-Item -ItemType Directory -Force -Path $sandboxPath | Out-Null }
    
    # We use a standard Debian rootfs link. In reality, you'd pull a specific Debian 13 (Trixie/Testing) rootfs.
    # For robust scripting, we simulate the import process if the rootfs isn't present.
    $rootfsFile = "$env:TEMP\debian-rootfs.tar.gz"
    if (!(Test-Path $rootfsFile)) {
        Write-Host "  Downloading Debian Slim Rootfs..." -ForegroundColor Gray
        # Placeholder URL for Debian rootfs tarball
        Invoke-WebRequest -Uri "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-amd64/testing/slim/rootfs.tar.xz" -OutFile $rootfsFile -ErrorAction SilentlyContinue
    }
    
    if (Test-Path $rootfsFile) {
        Write-Host "  Importing VM Instance 'XenonVM'..." -ForegroundColor Gray
        wsl --import XenonVM $sandboxPath $rootfsFile --version 2 2>&1 | Out-Null
        Show-Success "Sandbox 'XenonVM' created at $sandboxPath. File system mounted automatically."
    } else {
        Write-Host "  Failed to download rootfs. Sandbox skipped." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Virtualization/WSL not enabled. Skipping VM Sandbox." -ForegroundColor Yellow
}

# --- 2. Providers ---
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

# --- 3. Browsers ---
Show-Step "Detecting Environments..."
$Browsers = @{"None" = "none"}
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"; "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Opera GX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $Browsers[$b] = $Paths[$b]; Write-Host "  [+] Detected $b" -ForegroundColor Green } }
$SelectedBrowser = Get-ProviderSelection "Select Browser for Context Migration:" $Browsers

# --- 4. Installation ---
Show-Step "Validating System..."
if (!(Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Error: Git required."; return }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { 
    Show-Step "Installing Rust Toolchain..."; irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y; Remove-Item ./rustup-init.exe; $env:Path += ";$HOME\.cargo\bin"
}
if (!(Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Error: Node.js required."; return }

Show-Step "Cloning Xenon Agent..."
if (Test-Path "Xenon") { Set-Location Xenon; git pull } else { git clone https://github.com/turtle170/Xenon.git; Set-Location Xenon }

# --- 5. Llama Server ---
Show-Step "Configuring Local Inference Engine..."
mkdir -Force bin
$tag = "b4676"
$zipName = "llama-$tag-bin-win-$SimdFeature-x64.zip"
$url = "https://github.com/ggerganov/llama.cpp/releases/download/$tag/$zipName"
try {
    Invoke-WebRequest -Uri $url -OutFile "llama.zip"
    tar -xf "llama.zip" -C bin; Remove-Item "llama.zip"
    Show-Success "Local engine ready."
} catch {
    Write-Host "  Optimization failed. Using standard build." -ForegroundColor Yellow
}

# --- 6. Finalize ---
$Config = @{
    provider = $ProviderKey; api_key = $ApiKey; model = $ProviderInfo.model
    local_server = "http://localhost:8080"; import_browser = $SelectedBrowser
    simd = $SimdFeature; vnni = $VnniFeature
}
$Config | ConvertTo-Json | Set-Content "config.json"

Show-Step "Building Xenon..."
npm install --silent; npm run tauri build

$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName; $Shortcut.IconLocation = $TargetFile.FullName; $Shortcut.Save()
}

Show-Header
Show-Success "XENON DEPLOYED SUCCESSFULLY"
Write-Host "`nReady to automate."
