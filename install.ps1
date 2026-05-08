# Xenon Installer Script - Native Hyper-V Performance & Model Selection
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
    Write-Host "`n    X E N O N : NATIVE HYPER-V PERFORMANCE" -ForegroundColor Cyan
    Write-Host "---------------------------------------------" -ForegroundColor Gray
}

function Show-Step { param([string]$Message) Write-Host "`n[>] $Message" -ForegroundColor Yellow }
function Show-Success { param([string]$Message) Write-Host "[v] $Message" -ForegroundColor Green }

function Get-Selection {
    param([string]$Prompt, [string[]]$Options)
    Write-Host "`n$Prompt`n" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $Index = Read-Host "  Select option (1-$($Options.Count))"
    return $Options[$Index - 1]
}

# --- 1. Hyper-V Pre-flight ---
Show-Header
Show-Step "Checking for Hyper-V Capabilities..."
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if ($hyperv.State -ne 'Enabled') {
    Write-Host "  Hyper-V is not enabled. Attempting to enable (Requires Reboot)..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
    Write-Host "  Hyper-V enabled. Please restart your PC and run this installer again." -ForegroundColor Red
    return
}
Show-Success "Hyper-V is active."

# --- 2. VM Provisioning ---
Show-Step "Provisioning Native Debian VM Sandbox..."
$VMName = "XenonVM"
$VHDPath = "$PWD\VM\XenonDisk.vhdx"
if (!(Test-Path "VM")) { New-Item -ItemType Directory "VM" }

if (!(Test-Path $VHDPath)) {
    Write-Host "  Downloading High-Performance Debian Root Image..." -ForegroundColor Gray
    $sourceUrl = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.vhdx"
    Invoke-WebRequest -Uri $sourceUrl -OutFile $VHDPath
}

if (!(Get-VM -Name $VMName -ErrorAction SilentlyContinue)) {
    Write-Host "  Creating VM with Dynamic Memory (200MB - 4GB)..." -ForegroundColor Gray
    New-VM -Name $VMName -MemoryStartupBytes 200MB -VHDPath $VHDPath -Generation 2
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName $VMName -Count 2
    Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
    Show-Success "Native VM '$VMName' created."
}

# --- 3. Provider & Model Configuration ---
Show-Step "Brain Configuration"
$Providers = @{
    "OpenAI" = @("gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo")
    "Anthropic" = @("claude-3-5-sonnet-latest", "claude-3-opus-latest", "claude-3-haiku-latest")
    "Gemini" = @("gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro")
    "DeepSeek" = @("deepseek-chat", "deepseek-coder")
    "Llama (Local)" = @("local-gguf")
}

$ProviderNames = $Providers.Keys | Sort-Object
$SelectedProvider = Get-Selection "Choose your LLM Provider:" $ProviderNames
$SelectedModel = Get-Selection "Choose model for $SelectedProvider:" $Providers[$SelectedProvider]

$ApiKey = ""
if ($SelectedProvider -ne "Llama (Local)") {
    $ApiKey = Read-Host "  Enter your API Key for $SelectedProvider"
}

# --- 4. Browser Selection ---
Show-Step "Detecting Browsers..."
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"; "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Opera GX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}
$BrowserOptions = @("None")
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $BrowserOptions += $b } }
$SelectedBrowser = Get-Selection "Select Browser for Context Migration:" $BrowserOptions

# --- 5. Save Configuration ---
$Config = @{
    provider = $SelectedProvider
    model = $SelectedModel
    api_key = $ApiKey
    vm_type = "Hyper-V"
    vm_name = $VMName
    import_browser = $SelectedBrowser
}
$Config | ConvertTo-Json | Set-Content "config.json"

# --- 6. Build ---
Show-Step "Building Xenon Core..."
npm install --silent
npm run tauri build

$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName; $Shortcut.IconLocation = $TargetFile.FullName; $Shortcut.Save()
}

Show-Header
Show-Success "XENON DEPLOYED SUCCESSFULLY"
Write-Host "`nProvider: $SelectedProvider"
Write-Host "Model: $SelectedModel"
Write-Host "Storage: VHDX / Hyper-V Native"
Write-Host "`nReady to automate."
