# Xenon Installer Script - Debian 13 High-Performance VHDX Edition
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# --- 0. Admin Elevation ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '    [!] Administrative permissions required.' -ForegroundColor Red
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
    foreach ($line in $Logo) { Write-Host "    ${line}" -ForegroundColor Cyan }
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

# --- 1. Hyper-V (DISM) ---
Show-Header
Show-Step 'Validating Hyper-V Performance Layer...'
$hypervInfo = dism.exe /online /get-featureinfo /featurename:Microsoft-Hyper-V /english
if ($hypervInfo -notmatch "State : Enabled") {
    Write-Host '    [!] Enabling Hyper-V...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Reboot required. Run script again after restart.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Active.'

# --- 2. Sandbox (Debian 13 VHDX) ---
Show-Step 'Provisioning Debian 13 VHDX Sandbox...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    Write-Host '    [!] Fetching Debian 13 High-Performance Core...' -ForegroundColor Gray
    # We use the Trixie (Debian 13) Daily Azure VHD as it's the closest to a direct VHDX
    $sourceUrl = 'https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-azure-amd64-daily.tar.xz'
    $tempTar = "${env:TEMP}\debian13.tar.xz"
    
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    
    Write-Host '    [!] Converting to Native VHDX...' -ForegroundColor Gray
    tar -xf ${tempTar} -C VM
    $vhdFile = Get-ChildItem -Path VM -Filter "*.vhd" | Select-Object -First 1
    if ($vhdFile) {
        # Convert VHD to VHDX for maximum performance and features
        Convert-VHD -Path $vhdFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
    } else {
        throw "Extraction failed: No VHD found in archive."
    }
    Remove-Item ${tempTar}
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Creating Gen 2 Performance VM...' -ForegroundColor Gray
    # Debian 13 Cloud images are UEFI/Gen 2 ready
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off # Required for some cloud images
    Show-Success "Debian 13 VHDX Sandbox Ready."
}

# --- 3. Configuration ---
$Providers = @{
    'OpenAI' = @('gpt-4o-mini', 'gpt-4o')
    'Anthropic' = @('claude-4.6-sonnet', 'claude-3-5-sonnet-latest')
    'Gemini' = @('gemini-3-flash-preview', 'gemini-1.5-pro')
    'DeepSeek' = @('deepseek-chat', 'deepseek-coder')
}
$ProviderNames = $Providers.Keys | Sort-Object
$SelectedProvider = Get-Selection 'B R A I N' $ProviderNames
$SelectedModel = Get-Selection 'M O D E L' $Providers[${SelectedProvider}]
$ApiKey = Read-Host "    Enter API Key"

# --- 4. Build ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Finalizing Build...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED (DEBIAN 13 VHDX)'
Write-Host "    System is active."
