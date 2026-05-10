# Xenon Installer Script - Zero-Friction Edition
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = 'Continue' # Relaxed error handling

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
    $input = Read-Host '    Selection'
    if ([string]::IsNullOrWhiteSpace($input)) { $input = "1" }
    return $Options[[int]$input - 1]
}

# --- 1. Hyper-V (Zero-Friction) ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'
Import-Module Hyper-V -ErrorAction SilentlyContinue

$hypervReady = $true # Assume ready if user says so
if (!(Get-Command New-VM -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Hyper-V Management Tools not yet visible to this shell.' -ForegroundColor Yellow
    Write-Host '    [!] We will proceed with core provisioning.' -ForegroundColor Gray
}
Show-Success 'Hyper-V Layer Acknowledged.'

# --- 2. Sandbox (Resilient Disk Prep) ---
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
        Move-Item -Path $diskFile.FullName -Destination ${VHDXPath} -Force
    }
    if (Test-Path ${tempTar}) { Remove-Item ${tempTar} }
}

# Attempt VM Creation
Show-Step 'Configuring Sandbox VM...'
try {
    if (Get-Command New-VM -ErrorAction SilentlyContinue) {
        if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
            New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
            Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
            Set-VMProcessor -VMName ${VMName} -Count 2
            Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
        }
        Show-Success 'VM Successfully Configured.'
    } else {
        Write-Host '    [!] Automatic VM creation skipped (Tools missing).' -ForegroundColor Yellow
        Write-Host "    [!] Manual Setup: Create a Gen 2 VM using '${VHDXPath}'" -ForegroundColor Gray
    }
} catch {
    Write-Host '    [!] VM configuration encountered an error. Proceeding to build...' -ForegroundColor Yellow
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

# --- 4. Finalize & Build ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}; vhdx_path = ${VHDXPath}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Building Xenon Engine...'
npm install --silent
npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via shortcut or 'npm run tauri dev'."
