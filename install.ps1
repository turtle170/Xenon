# Xenon Installer Script - Rainbow Performance Edition (Fixed)
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    $HeaderText = "X E N O N"
    $Colors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
    
    Write-Host "    " -NoNewline
    for ($i = 0; $i -lt $HeaderText.Length; $i++) {
        $char = $HeaderText[$i]
        Write-Host $char -NoNewline -ForegroundColor $Colors[$i % $Colors.Count]
    }
    Write-Host " : THE AUTONOMOUS AGENT" -ForegroundColor Cyan
    Write-Host "---------------------------------------------" -ForegroundColor Gray
}

function Show-Step { param([string]$Message) Write-Host "`n[>] $Message" -ForegroundColor Yellow }
function Show-Success { param([string]$Message) Write-Host "[v] $Message" -ForegroundColor Green }

function Get-Selection {
    param([string]$Prompt, [string[]]$Options)
    Show-Header
    Write-Host "`n$Prompt`n" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $Index = Read-Host "  Select option (1-$($Options.Count))"
    return $Options[[int]$Index - 1]
}

# --- 1. Hyper-V Pre-flight ---
Show-Header
Show-Step "Validating Virtualization Layer..."
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if ($hyperv.State -ne 'Enabled') {
    Write-Host "  Enabling Hyper-V..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
    Write-Host "  Restart required. Please reboot and run again." -ForegroundColor Red
    return
}
Show-Success "Hyper-V Active."

# --- 2. Sandbox Setup ---
Show-Step "Provisioning Sandbox..."
$VMName = "XenonVM"
$VHDPath = "$PWD\VM\XenonDisk.vhdx"
if (!(Test-Path "VM")) { New-Item -ItemType Directory "VM" | Out-Null }
if (!(Test-Path $VHDPath)) {
    Write-Host "  Downloading Debian Root Image..." -ForegroundColor Gray
    $sourceUrl = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.vhdx"
    Invoke-WebRequest -Uri $sourceUrl -OutFile $VHDPath
}
if (!(Get-VM -Name $VMName -ErrorAction SilentlyContinue)) {
    New-VM -Name $VMName -MemoryStartupBytes 200MB -VHDPath $VHDPath -Generation 2 | Out-Null
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName $VMName -Count 2
}

# --- 3. Brain Configuration ---
Show-Step "Brain Selection"
$Providers = @{
    "OpenAI" = @("gpt-4o-mini", "gpt-4o", "gpt-4-turbo")
    "Anthropic" = @("claude-4.6-sonnet", "claude-3-5-sonnet-latest")
    "Gemini" = @("gemini-3-flash-preview", "gemini-1.5-pro")
    "DeepSeek" = @("deepseek-chat", "deepseek-coder")
    "Llama (Local)" = @("local-gguf")
}

$ProviderNames = $Providers.Keys | Sort-Object
$SelectedProvider = Get-Selection "Choose LLM Provider:" $ProviderNames
$SelectedModel = Get-Selection "Choose model for $SelectedProvider:" $Providers[$SelectedProvider]

$ApiKey = ""
if ($SelectedProvider -ne "Llama (Local)") {
    $ApiKey = Read-Host "  Enter API Key"
}

# --- 4. Context Migration ---
$Paths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"; "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
}
$BrowserOptions = @("None")
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $BrowserOptions += $b } }
$SelectedBrowser = Get-Selection "Migrate Browser Data:" $BrowserOptions

# --- 5. Build ---
$Config = @{
    provider = $SelectedProvider; model = $SelectedModel; api_key = $ApiKey
    vm_type = "Hyper-V"; vm_name = $VMName; import_browser = $SelectedBrowser
}
$Config | ConvertTo-Json | Set-Content "config.json"

Show-Step "Compiling Xenon..."
npm install --silent
npm run tauri build

Show-Header
Show-Success "XENON DEPLOYED"
Write-Host "`nProvider: $SelectedProvider"
Write-Host "Model: $SelectedModel"
