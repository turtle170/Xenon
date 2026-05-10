# Xenon Installer Script - Debian 13 High-Performance VHDX Edition (Extraction Fix)
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

# --- 1. Hyper-V ---
Show-Header
Show-Step 'Validating Hyper-V Layer...'
if (!(Get-Service vmms -ErrorAction SilentlyContinue)) {
    Write-Host '    [!] Enabling Hyper-V Layer...' -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart | Out-Null
    Write-Host '    [!] Reboot required. Run script again after restart.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Active.'

# --- 2. Sandbox ---
Show-Step 'Provisioning Debian 13 VHDX...'
$VMName = 'XenonVM'
$VHDXPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }

if (!(Test-Path ${VHDXPath})) {
    Write-Host '    [!] Downloading High-Performance Core...' -ForegroundColor Gray
    $sourceUrl = 'https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-azure-amd64-daily.tar.xz'
    $tempTar = "${env:TEMP}\debian13.tar.xz"
    Invoke-WebRequest -Uri ${sourceUrl} -OutFile ${tempTar}
    
    if ((Get-Item ${tempTar}).Length -lt 100MB) {
        throw "Download failed or incomplete (File too small)."
    }

    Write-Host '    [!] Finalizing VHDX...' -ForegroundColor Gray
    # Force extraction and list files for debugging
    tar -xf ${tempTar} -C VM --verbose
    
    $vhdFile = Get-ChildItem -Path VM -Filter "*.*" | Where-Object { $_.Extension -match "vhd" } | Select-Object -First 1
    
    if ($vhdFile) {
        Write-Host "    [!] Found disk: $($vhdFile.Name). Converting..." -ForegroundColor Gray
        Convert-VHD -Path $vhdFile.FullName -DestinationPath ${VHDXPath} -DeleteSource
    } else {
        $files = Get-ChildItem -Path VM | Select-Object -ExpandProperty Name
        throw "Failed to find VHD. Found files: $($files -join ', ')"
    }
    Remove-Item ${tempTar}
}

if (!(Get-VM -Name ${VMName} -ErrorAction SilentlyContinue)) {
    New-VM -Name ${VMName} -MemoryStartupBytes 200MB -VHDPath ${VHDXPath} -Generation 2 | Out-Null
    Set-VMMemory -VMName ${VMName} -DynamicMemoryEnabled $true -MinimumBytes 200MB -MaximumBytes 4GB
    Set-VMProcessor -VMName ${VMName} -Count 2
    Set-VMFirmware -VMName ${VMName} -EnableSecureBoot Off
}
Show-Success "Sandbox Ready."

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

# --- 4. Context Migration ---
$Paths = @{
    'Chrome' = "${env:LOCALAPPDATA}\Google\Chrome\User Data"
    'Edge' = "${env:LOCALAPPDATA}\Microsoft\Edge\User Data"
    'Brave' = "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\User Data"
}
$BrowserOptions = @('None')
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $BrowserOptions += $b } }
$SelectedBrowser = Get-Selection 'C O N T E X T' $BrowserOptions

# --- 5. Build ---
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
