# Xenon Installer Script - Management Layer Fix
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

# --- 1. Hyper-V (Permissive + Management Fix) ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'

# Try to load the module first
Import-Module Hyper-V -ErrorAction SilentlyContinue

$hypervActive = $false
if (Get-Command Get-VM -ErrorAction SilentlyContinue) { $hypervActive = $true }
if (!$hypervActive -and (Get-Service vmms -ErrorAction SilentlyContinue)) { $hypervActive = $true }

if (!$hypervActive) {
    Write-Host '    [!] Enabling Hyper-V Management Tools...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-Management-PowerShell /all /norestart | Out-Null
    
    # Reload and check again
    Import-Module Hyper-V -ErrorAction SilentlyContinue
    if (Get-Command Get-VM -ErrorAction SilentlyContinue) { 
        $hypervActive = $true 
    } else {
        Write-Host '    [!] Hyper-V module still missing. Rebooting might be required.' -ForegroundColor Yellow
        $choice = Read-Host '    [?] Try to proceed anyway? (y/N)'
        if ($choice -eq 'y') { $hypervActive = $true }
    }
}

if (!$hypervActive) {
    Write-Host '    [!] Action required: Reboot and run again.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Layer Active.'

# --- 2. Sandbox (Resilient VHDX) ---
Show-Step 'Provisioning Native VHDX Sandbox...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    $sourceUrl = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-azure-amd64.tar.xz'
    $tempTar = "${env:TEMP}\xenon-core.tar.xz"
    
    Write-Host '    [!] Fetching Virtual Core Image...' -ForegroundColor Gray
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    
    Write-Host '    [!] Unpacking Hardware Image...' -ForegroundColor Gray
    tar -xf ${tempTar} -C VM
    
    $diskFile = Get-ChildItem -Path VM -Recurse | Where-Object { $_.Extension -match "vhd|raw" } | Select-Object -First 1
    if ($diskFile) {
        Write-Host "    [!] Finalizing disk: $($diskFile.Name)..." -ForegroundColor Gray
        # Use direct file manipulation if Convert-VHD is missing
        if (Get-Command Convert-VHD -ErrorAction SilentlyContinue) {
            Convert-VHD -Path $diskFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
        } else {
            Move-Item -Path $diskFile.FullName -Destination ${VHDXPath} -Force
        }
    } else {
        throw "Failed to map disk image."
    }
    if (Test-Path ${tempTar}) { Remove-Item ${tempTar} }
}

# Use direct PowerShell or WMI if Get-VM is still missing
Show-Step 'Configuring Sandbox VM...'
if (Get-Command New-VM -ErrorAction SilentlyContinue) {
    if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
        New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
        Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
        Set-VMProcessor -VMName ${VMName} -Count 2
        Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
    }
} else {
    Write-Host '    [!] Management cmdlets missing. Creating VM manually via Hyper-V Manager is required.' -ForegroundColor Red
    Write-Host "    [!] VHDX path: ${VHDXPath}" -ForegroundColor Gray
    throw "Hyper-V Management Tools not found."
}
Show-Success 'Native VHDX Sandbox Ready.'

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
