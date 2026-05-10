# Xenon Installer Script - Clean TUI Edition
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = 'Stop'

function Show-Header {
    Clear-Host
    $Colors = @('Red', 'Yellow', 'Green', 'Cyan', 'Blue', 'Magenta')
    $Box = @(
        '┌───────────────────────────────┐',
        '│            XENON              │',
        '└───────────────────────────────┘'
    )
    
    Write-Host ''
    for ($i = 0; $i -lt $Box.Count; $i++) {
        $Line = $Box[$i]
        $Color = $Colors[$i % $Colors.Count]
        Write-Host "    ${Line}" -ForegroundColor $Color
    }
    Write-Host ''
}

function Show-Step { param([string]$Message) Write-Host "[>] ${Message}" -ForegroundColor Gray }
function Show-Success { param([string]$Message) Write-Host "[v] ${Message}" -ForegroundColor Green }

function Get-Selection {
    param([string]$Prompt, [string[]]$Options)
    Show-Header
    Write-Host "  ${Prompt}:" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $idx = $i + 1
        $opt = $Options[$i]
        Write-Host "    ${idx}. ${opt}" -ForegroundColor Gray
    }
    Write-Host ''
    $Index = Read-Host '  Selection'
    return $Options[[int]${Index} - 1]
}

# --- 1. Hyper-V ---
Show-Header
Show-Step 'Checking Hyper-V Layer...'
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V'
if ($hyperv.State -ne 'Enabled') {
    Write-Host '  Enabling Hyper-V...' -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -NoRestart
    Write-Host '  Reboot required.' -ForegroundColor Red
    return
}
Show-Success 'Hyper-V Layer Active.'

# --- 2. VM ---
Show-Step 'Provisioning Sandbox...'
$VMName = 'XenonVM'
$VHDPath = "${PWD}\VM\XenonDisk.vhdx"
if (!(Test-Path 'VM')) { New-Item -ItemType Directory 'VM' | Out-Null }
if (!(Test-Path ${VHDPath})) {
    Write-Host '  Downloading Image...' -ForegroundColor Gray
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
$SelectedProvider = Get-Selection 'Provider' $ProviderNames
$SelectedModel = Get-Selection 'Model' $Providers[${SelectedProvider}]

$ApiKey = ''
if (${SelectedProvider} -ne 'Llama (Local)') {
    Write-Host ''
    $ApiKey = Read-Host "  API Key for ${SelectedProvider}"
}

# --- 4. Context ---
$Paths = @{
    'Chrome' = "${env:LOCALAPPDATA}\Google\Chrome\User Data"
    'Edge' = "${env:LOCALAPPDATA}\Microsoft\Edge\User Data"
    'Brave' = "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\User Data"
    'Opera' = "${env:APPDATA}\Opera Software\Opera Stable"
}
$BrowserOptions = @('None')
foreach ($b in $Paths.Keys) { if (Test-Path $Paths[$b]) { $BrowserOptions += $b } }
$SelectedBrowser = Get-Selection 'Browser Migration' $BrowserOptions

# --- 5. Finalize ---
$Config = @{
    provider = ${SelectedProvider}; model = ${SelectedModel}; api_key = ${ApiKey}
    vm_type = 'Hyper-V'; vm_name = ${VMName}; import_browser = ${SelectedBrowser}
}
$Config | ConvertTo-Json | Set-Content 'config.json'

Show-Step 'Building...'
npm install --silent; npm run tauri build

Show-Header
Show-Success 'XENON DEPLOYED'
Write-Host "  Launch from Desktop."
