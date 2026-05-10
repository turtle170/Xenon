# Xenon Installer Script - Resilient VHDX Edition
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
        $idx = $i + 1; $opt = $Options[$i]
        Write-Host "      [${idx}] ${opt}" -ForegroundColor Gray
    }
    Write-Host ''
    $Index = Read-Host '    Selection'
    return $Options[[int]${Index} - 1]
}

# --- 1. Hyper-V (Aggressive Detection) ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'
$hypervActive = $false
try {
    Get-VM -ErrorAction SilentlyContinue | Out-Null
    $hypervActive = $true
} catch {
    if (Get-Service vmms -ErrorAction SilentlyContinue) { $hypervActive = $true }
}
if (!$hypervActive) {
    $info = dism.exe /online /get-featureinfo /featurename:Microsoft-Hyper-V-All /english
    if ($info -match "State : Enabled") { $hypervActive = $true }
}
if (!$hypervActive) {
    Write-Host '    [!] Enabling Hyper-V Performance Layer...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Action required: Please reboot your PC and re-run this script.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Layer Active.'

# --- 2. Sandbox (Resilient Extraction) ---
Show-Step 'Provisioning High-Performance VHDX...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    $sourceUrl = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-azure-amd64.tar.xz'
    $tempTar = "${env:TEMP}\xenon-core.tar.xz"
    
    if (!(Test-Path ${tempTar})) {
        Write-Host '    [!] Fetching Virtual Core...' -ForegroundColor Gray
        Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    }
    
    Write-Host '    [!] Unpacking Hardware Image...' -ForegroundColor Gray
    # Try extraction with native tar
    try {
        tar -xf ${tempTar} -C VM --verbose
    } catch {
        Write-Host "    [!] Standard extraction failed. Trying secondary method..." -ForegroundColor Yellow
    }

    # Search for any disk image file (vhd, vhdx, or even raw to be safe)
    $diskFile = Get-ChildItem -Path VM -Recurse | Where-Object { $_.Name -match "\.(vhd|vhdx|raw)$" } | Select-Object -First 1
    
    if ($diskFile) {
        Write-Host "    [!] Detected core: $($diskFile.Name). Optimizing..." -ForegroundColor Gray
        if ($diskFile.Extension -eq ".vhdx") {
            Move-Item -Path $diskFile.FullName -Destination ${VHDXPath} -Force
        } else {
            # Convert VHD or RAW to VHDX
            # Note: Convert-VHD is part of Hyper-V module and very robust
            Convert-VHD -Path $diskFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
        }
    } else {
        $found = Get-ChildItem -Path VM -Recurse | Select-Object -ExpandProperty Name
        throw "Image mapping failed. Archive contents: $($found -join ', ')"
    }
    if (Test-Path ${tempTar}) { Remove-Item ${tempTar} }
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Configuring Performance VM...' -ForegroundColor Gray
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
}
Show-Success 'Sandbox Environment Active.'

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
$ApiKey = Read-Host "    Enter API Key for ${SelectedProvider}"

# --- 4. Finalize ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Building Xenon Engine...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via 'npm run tauri dev'."
