# Xenon Installer Script - Aggressive Performance Edition
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
# Check 1: Can we run Get-VM?
try {
    Get-VM -ErrorAction SilentlyContinue | Out-Null
    $hypervActive = $true
} catch {
    # Check 2: Is the management service there?
    if (Get-Service vmms -ErrorAction SilentlyContinue) { $hypervActive = $true }
}

if (!$hypervActive) {
    # Final check: DISM
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
Show-Step 'Provisioning Debian 13 VHDX...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    $sourceUrl = 'https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-azure-amd64-daily.tar.xz'
    $tempTar = "${env:TEMP}\debian13.tar.xz"
    
    if (!(Test-Path ${tempTar})) {
        Write-Host '    [!] Fetching Core Image (700MB+)...' -ForegroundColor Gray
        Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    }
    
    Write-Host '    [!] Unpacking Virtual Disk...' -ForegroundColor Gray
    # We unpack and check for any file. Some 'tar' versions need specific flags.
    tar -xf ${tempTar} -C VM
    
    $vhdFile = Get-ChildItem -Path VM -Recurse -Include "*.vhd" | Select-Object -First 1
    if ($vhdFile) {
        Write-Host "    [!] Found: $($vhdFile.Name). Optimizing to VHDX..." -ForegroundColor Gray
        Convert-VHD -Path $vhdFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
    } else {
        # Debug: list what was actually in the tar
        $contents = tar -tf ${tempTar}
        throw "Extraction failed. The archive contained: ${contents}"
    }
    if (Test-Path ${tempTar}) { Remove-Item ${tempTar} }
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
}
Show-Success 'Sandbox Ready.'

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

# --- 4. Build ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Compiling Xenon Core...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "    Launch via 'npm run tauri dev'."
