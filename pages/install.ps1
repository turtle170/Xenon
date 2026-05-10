# Xenon Installer Script - Block TUI Edition
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# --- 0. Admin Elevation ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '    [!] Administrative permissions required for Hyper-V management.' -ForegroundColor Red
    Write-Host '    [!] Please run your terminal as Administrator.' -ForegroundColor Yellow
    Write-Host ''
    return
}

function Show-Header {
    Clear-Host
    $Logo = @(
        '  ██   ██ ███████ ███    ██  ██████  ███    ██',
        '   ██ ██  ██      ████   ██ ██    ██ ████   ██',
        '    ███   █████   ██ ██  ██ ██    ██ ██ ██  ██',
        '   ██ ██  ██      ██  ██ ██ ██    ██ ██  ██ ██',
        '  ██   ██ ███████ ██   ████  ██████  ██   ████'
    )
    
    Write-Host ''
    foreach ($line in $Logo) {
        Write-Host "    ${line}" -ForegroundColor Cyan
    }
    Write-Host "`n    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
}

function Show-Step { param([string]$Message) Write-Host "    [>] ${Message}" -ForegroundColor Gray }
function Show-Success { param([string]$Message) Write-Host "    [v] ${Message}" -ForegroundColor Green }

function Get-Selection {
    param([string]$Prompt, [string[]]$Options)
    Show-Header
    Write-Host "    ${Prompt}:" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $idx = $i + 1
        $opt = $Options[$i]
        Write-Host "      [${idx}] ${opt}" -ForegroundColor Gray
    }
    Write-Host ''
    $Index = Read-Host '    Selection'
    return $Options[[int]${Index} - 1]
}

# --- 1. Hyper-V ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V'
if ($hyperv.State -ne 'Enabled') {
    Write-Host '    [!] Enabling Hyper-V Performance Layer...' -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -NoRestart | Out-Null
    Write-Host '    [!] Reboot required. Run this script again after restart.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Active.'

# --- 2. Sandbox ---
Show-Step 'Provisioning Native Sandbox...'
$VMName = 'XenonVM'
$VHDPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }
if (!(Test-Path ${VHDPath})) {
    Write-Host '    [!] Downloading Debian Image...' -ForegroundColor Gray
    $sourceUrl = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.vhdx'
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${VHDPath}
}
if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
}

# --- 3. Configuration ---
$Providers = @{
    'OpenAI' = @('gpt-4o-mini', 'gpt-4o', 'gpt-4-turbo')
    'Anthropic' = @('claude-4.6-sonnet', 'claude-3-5-sonnet-latest')
    'Gemini' = @('gemini-3-flash-preview', 'gemini-1.5-pro')
    'DeepSeek' = @('deepseek-chat', 'deepseek-coder')
    'Llama (Local)' = @('local-gguf')
}
$ProviderNames = $Providers.Keys | Sort-Object
$SelectedProvider = Get-Selection 'B R A I N' $ProviderNames
$SelectedModel = Get-Selection 'M O D E L' $Providers[${SelectedProvider}]

$ApiKey = ''
if (${SelectedProvider} -ne 'Llama (Local)') {
    Write-Host ''
    $ApiKey = Read-Host "    Enter API Key for ${SelectedProvider}"
}

# --- 4. Context ---
$Paths = @{
    'Chrome' = "${env:LOCALAPPDATA}\Google\Chrome\User Data"
    'Edge' = "${env:LOCALAPPDATA}\Microsoft\Edge\User Data"
    'Brave' = "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\User Data"
}
$BrowserOptions = @('None')
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $BrowserOptions += $b } }
$SelectedBrowser = Get-Selection 'C O N T E X T' $BrowserOptions

# --- 5. Save & Compile ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}; import_browser = ${SelectedBrowser}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Building Project...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via shortcut or 'npm run tauri dev'."
