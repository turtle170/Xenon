# Xenon Installer Script - Direct VHDX Edition (LTSC-Ready)
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
    $input = Read-Host '    Selection'
    if ([string]::IsNullOrWhiteSpace($input)) { $input = "1" }
    return $Options[[int]$input - 1]
}

# --- 1. Hyper-V (Permissive Detection) ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'

$hypervActive = $false

# A. Check Hyper-V Cmdlets
if (Get-Command Get-VM -ErrorAction SilentlyContinue) { $hypervActive = $true }

# B. Check Virtual Machine Management Service
if (!$hypervActive -and (Get-Service vmms -ErrorAction SilentlyContinue)) { $hypervActive = $true }

# C. Check DISM Enabled Features (Broad Search)
if (!$hypervActive) {
    $features = dism.exe /online /get-features /format:table
    if ($features -match "Microsoft-Hyper-V.*Enabled") { $hypervActive = $true }
}

# D. Check Hypervisor Presence (WMI)
if (!$hypervActive) {
    $sysInfo = Get-CimInstance Win32_ComputerSystem
    if ($sysInfo.HypervisorPresent) { $hypervActive = $true }
}

if (!$hypervActive) {
    Write-Host '    [!] Automated detection failed.' -ForegroundColor Yellow
    Write-Host '    [!] If you have already enabled Hyper-V/Virtualization, we can proceed.' -ForegroundColor Gray
    $choice = Read-Host '    [?] Force proceed anyway? (y/N)'
    if ($choice -eq 'y') { 
        $hypervActive = $true 
        Write-Host '    [+] Overriding detection...' -ForegroundColor Cyan
    }
}

if (!$hypervActive) {
    Write-Host '    [!] Enabling Hyper-V Layer via DISM...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Reboot required. Run script again after restart.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Layer Active.'

# --- 2. Sandbox (Native VHDX) ---
Show-Step 'Provisioning Native VHDX Sandbox...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    # Use Vagrant Cloud direct VHDX (Debian 12 Stable)
    $sourceUrl = 'https://vagrantcloud.com/debian/boxes/bookworm64/versions/12.20240424.1/providers/hyperv.box'
    $tempBox = "${env:TEMP}\xenon-core.box"
    
    if (!(Test-Path ${tempBox})) {
        Write-Host '    [!] Fetching Native VHDX Image (700MB+)...' -ForegroundColor Gray
        Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempBox}
    }
    
    Write-Host '    [!] Extracting Hardware Image...' -ForegroundColor Gray
    tar -xf ${tempBox} -C VM
    
    $vhdxFile = Get-ChildItem -Path VM -Recurse -Include "*.vhdx" | Select-Object -First 1
    if ($vhdxFile) {
        Move-Item -Path $vhdxFile.FullName -Destination ${VHDXPath} -Force
    } else {
        throw "Native VHDX not found in downloaded image."
    }
    if (Test-Path ${tempBox}) { Remove-Item ${tempBox} }
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Configuring Gen 2 VM...' -ForegroundColor Gray
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
}
Show-Success 'Native VHDX Sandbox Active.'

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
Write-Host ''
$ApiKey = Read-Host "    Enter API Key for ${SelectedProvider}"

# --- 4. Save & Build ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Compiling Xenon Engine...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via 'npm run tauri dev'."
