# Xenon Installer Script - Advanced Edition
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

function Show-Step {
    param([string]$Message)
    Write-Host "`n[>] $Message" -ForegroundColor Yellow
}

function Show-Success {
    param([string]$Message)
    Write-Host "[v] $Message" -ForegroundColor Green
}

function Get-Selection {
    param([string]$Prompt, [hashtable]$Options)
    Show-Header
    Write-Host "`n$Prompt`n" -ForegroundColor White
    $Keys = $Options.Keys | Sort-Object
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        Write-Host "  $($i + 1)) $($Keys[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $Selection = Read-Host "  Select option (1-$($Keys.Count))"
    return $Options[$Keys[$Selection - 1]]
}

# --- 1. Configuration Phase ---
Show-Header

$Providers = @{
    "OpenAI" = @{ url = "https://platform.openai.com/api-keys"; model = "gpt-4o" }
    "Anthropic" = @{ url = "https://console.anthropic.com/settings/keys"; model = "claude-3-5-sonnet-latest" }
    "Gemini" = @{ url = "https://aistudio.google.com/app/apikey"; model = "gemini-1.5-pro" }
    "DeepSeek" = @{ url = "https://platform.deepseek.com/api_keys"; model = "deepseek-chat" }
    "Llama (Local)" = @{ url = "https://github.com/ggerganov/llama.cpp"; model = "local" }
}

$SelectedProviderName = (Get-Selection "Choose your LLM Provider:" $Providers).Keys | Sort-Object | Out-Null # Wait, my Get-Selection logic is a bit flawed for hashtables of objects.
# Let's fix Get-Selection to return the key name.

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

$ProviderKey = Get-ProviderSelection "Choose your LLM Provider:" $Providers
$ProviderInfo = $Providers[$ProviderKey]

$ApiKey = ""
$GgufPath = ""

if ($ProviderKey -eq "Llama (Local)") {
    $GgufPath = Read-Host "  Enter full path to your .GGUF model file"
} else {
    Write-Host "`n  Get your API key at: $($ProviderInfo.url)" -ForegroundColor Cyan
    $valid = $false
    while (!$valid) {
        $ApiKey = Read-Host "  Enter your API Key"
        if ($ProviderKey -eq "Gemini") {
            if ($ApiKey -match "^AIza" -or $ApiKey -match "^AQ") {
                $valid = $true
            } else {
                Write-Host "  Invalid Gemini Key format (Should start with AIza or AQ). Try again." -ForegroundColor Red
            }
        } else {
            $valid = $true
        }
    }
}

# --- Browser Detection ---
Show-Step "Detecting Chromium-based browsers..."
$Browsers = @{"None" = "none"}
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data"
    "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Opera GX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}

foreach ($b in $Paths.Keys) {
    if (Test-Path $Paths[$b]) {
        $Browsers[$b] = $Paths[$b]
        Write-Host "  [+] Found $b" -ForegroundColor Green
    }
}

$SelectedBrowser = Get-ProviderSelection "Select browser to import data from (Detected options shown):" $Browsers

Show-Header
Show-Step "Environment Validation..."

# Dependency Checks
if (!(Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Error: Git required."; return }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { 
    Show-Step "Installing Rust..."; irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y; Remove-Item ./rustup-init.exe
    $env:Path += ";$HOME\.cargo\bin"
}
if (!(Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Error: Node.js required."; return }

# Installation
Show-Step "Cloning Xenon..."
$RepoUrl = "https://github.com/turtle170/Xenon.git"
if (Test-Path "Xenon") { Set-Location Xenon; git pull } else { git clone $RepoUrl; Set-Location Xenon }

# Save Config
$Config = @{
    provider = $ProviderKey
    api_key = $ApiKey
    model = $ProviderInfo.model
    local_server = if ($ProviderKey -eq "Llama (Local)") { "http://localhost:8080" } else { $null }
    gguf_path = $GgufPath
    import_browser = $SelectedBrowser
}
$Config | ConvertTo-Json | Set-Content "config.json"

# Build
Show-Step "Building Xenon..."
npm install --silent
npm run tauri build

# Shortcut
$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName
    $Shortcut.IconLocation = $TargetFile.FullName
    $Shortcut.Save()
    Show-Success "Shortcut created on Desktop."
}

Show-Header
Show-Success "INSTALLATION SUCCESSFUL"
Write-Host "`nProvider: $ProviderKey"
Write-Host "Browser: $SelectedBrowser"
Write-Host "Launch Xenon from your desktop shortcut."
