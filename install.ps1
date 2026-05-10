# Xenon Installer Script - High-Performance VHDX Edition
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

if (Get-Command Get-VM -ErrorAction SilentlyContinue) { $hypervActive = $true }
if (!$hypervActive -and (Get-Service vmms -ErrorAction SilentlyContinue)) { $hypervActive = $true }
if (!$hypervActive) {
    $features = dism.exe /online /get-features /format:table
    if ($features -match "Microsoft-Hyper-V.*Enabled") { $hypervActive = $true }
}
if (!$hypervActive) {
    $sysInfo = Get-CimInstance Win32_ComputerSystem
    if ($sysInfo.HypervisorPresent) { $hypervActive = $true }
}

if (!$hypervActive) {
    Write-Host '    [!] Automated detection failed.' -ForegroundColor Yellow
    $choice = Read-Host '    [?] Force proceed? (y/N)'
    if ($choice -eq 'y') { $hypervActive = $true }
}

if (!$hypervActive) {
    Write-Host '    [!] Enabling Hyper-V Layer...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Reboot required.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Layer Active.'

# --- 2. Sandbox (Resilient VHDX) ---
Show-Step 'Provisioning Native VHDX Sandbox...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    # Using stable Debian 12 Azure image (guaranteed VHD format)
    $sourceUrl = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-azure-amd64.tar.xz'
    $tempTar = "${env:TEMP}\xenon-core.tar.xz"
    
    Write-Host '    [!] Fetching Virtual Core Image...' -ForegroundColor Gray
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    
    Write-Host '    [!] Unpacking Hardware Image...' -ForegroundColor Gray
    tar -xf ${tempTar} -C VM
    
    $diskFile = Get-ChildItem -Path VM -Recurse | Where-Object { $_.Extension -match "vhd|raw" } | Select-Object -First 1
    if ($diskFile) {
        Write-Host "    [!] Finalizing disk: $($diskFile.Name)..." -ForegroundColor Gray
        if (Get-Command Convert-VHD -ErrorAction SilentlyContinue) {
            Convert-VHD -Path $diskFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
        } else {
            # Fallback: Just move and rename if the conversion cmdlet is missing
            Move-Item -Path $diskFile.FullName -Destination ${VHDXPath} -Force
        }
    } else {
        throw "Failed to map disk image."
    }
    if (Test-Path ${tempTar}) { Remove-Item ${tempTar} }
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Configuring Gen 2 Performance VM...' -ForegroundColor Gray
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
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
