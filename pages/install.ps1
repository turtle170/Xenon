# Xenon Installer Script - Block TUI Edition (Fix VHDX Source)
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
$hypervInfo = dism.exe /online /get-featureinfo /featurename:Microsoft-Hyper-V /english
$isEnabled = $hypervInfo -match "State : Enabled"

if (!$isEnabled) {
    Write-Host '    [!] Enabling Hyper-V...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Reboot required. Run this script again after restart.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Active.'

# --- 2. Sandbox ---
Show-Step 'Provisioning Native Sandbox...'
$VMName = 'XenonVM'
$VHDPath = "${PWD}\VM\XenonDisk.vhd"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDPath})) {
    Write-Host '    [!] Downloading Debian Cloud Image (VHD)...' -ForegroundColor Gray
    $sourceUrl = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-azure-amd64.tar.xz'
    $tempTar = "${env:TEMP}\debian.tar.xz"
    
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    
    Write-Host '    [!] Extracting disk image...' -ForegroundColor Gray
    # Windows 11 tar supports .tar.xz
    tar -xf ${tempTar} -C VM
    
    $extractedVhd = Get-ChildItem -Path VM -Filter "*.vhd" | Select-Object -First 1
    if ($extractedVhd) {
        Move-Item -Path $extractedVhd.FullName -Destination ${VHDPath} -Force
    } else {
        throw "Could not find extracted VHD in VM directory."
    }
    Remove-Item ${tempTar}
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Creating VM with Dynamic Memory...' -ForegroundColor Gray
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDPath} -Generation 1 | Out-Null
    # Note: Cloud VHDs are often Generation 1 (BIOS) compatible for Azure. 
    # If the image supports UEFI, we use Gen 2, but Gen 1 is safer for the Azure VHD.
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Show-Success "VM Created with VHD storage."
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

# --- 5. Finalize ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}; import_browser = ${SelectedBrowser}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Building Project...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via 'npm run tauri dev'."
