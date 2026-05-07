# Xenon Installer Script
# Use: irm https://xenonai.pages.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Show-Header {
    Clear-Host
    $Cyan = [ConsoleColor]::Cyan
    $Gray = [ConsoleColor]::Gray
    $White = [ConsoleColor]::White
    
    Write-Host @"
 ██╗  ██╗███████╗███╗   ██╗ ██████╗ ███╗   ██╗
 ╚██╗██╔╝██╔════╝████╗  ██║██╔═══██╗████╗  ██║
  ╚███╔╝ █████╗  ██╔██╗ ██║██║   ██║██╔██╗ ██║
  ██╔██╗ ██╔══╝  ██║╚██╗██║██║   ██║██║╚██╗██║
 ██╔╝ ██╗███████╗██║ ╚████║╚██████╔╝██║ ╚████║
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝
    Autonomous Self-Editing Agent Framework
"@ -ForegroundColor $Cyan
    Write-Host "---------------------------------------------" -ForegroundColor $Gray
}

function Show-Step {
    param([string]$Message)
    Write-Host "`n[>] $Message" -ForegroundColor Yellow
}

function Show-Success {
    param([string]$Message)
    Write-Host "[v] $Message" -ForegroundColor Green
}

function Get-Selection {
    param([string]$Prompt, [string[]]$Options)
    Show-Header
    Write-Host "`n$Prompt`n" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $Selection = Read-Host "  Select option (1-$($Options.Count))"
    return $Options[$Selection - 1]
}

Show-Header

# 1. Configuration Phase
Show-Step "Configuration Phase"
$Provider = Get-Selection "Choose your LLM Provider:" @("OpenAI", "Anthropic", "Gemini", "DeepSeek", "Llama (Local)")

$ApiKey = ""
$GgufPath = ""

if ($Provider -eq "Llama (Local)") {
    $GgufPath = Read-Host "  Enter full path to your .GGUF model file"
} else {
    $ApiKey = Read-Host "  Enter your API Key for $Provider"
}

$Browser = Get-Selection "Select browser to import data from:" @("Chrome", "Edge", "Firefox", "None")

Show-Header
Show-Step "Validating Environment..."

# 2. Dependency Checks
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Git required." -ForegroundColor Red; return
}
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
    Show-Step "Installing Rust..."
    irm https://sh.rustup.rs -OutFile rustup-init.exe
    ./rustup-init.exe -y; Remove-Item ./rustup-init.exe
    $env:Path += ";$HOME\.cargo\bin"
}
if (!(Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Node.js required." -ForegroundColor Red; return
}

# 3. Installation
Show-Step "Cloning Xenon..."
$RepoUrl = "https://github.com/turtle170/Xenon.git"
if (Test-Path "Xenon") {
    Set-Location Xenon; git pull
} else {
    git clone $RepoUrl; Set-Location Xenon
}

# 4. Save Configuration
Show-Step "Saving Configuration..."
$Config = @{
    provider = $Provider
    api_key = $ApiKey
    model = if ($Provider -eq "OpenAI") { "gpt-4o" } else { "default" }
    local_server = if ($Provider -eq "Llama (Local)") { "http://localhost:8080" } else { $null }
    gguf_path = $GgufPath
    import_browser = $Browser
}
$Config | ConvertTo-Json | Set-Content "config.json"

# 5. Build
Show-Step "Building Xenon... (Sit tight, Rust is thinking)"
npm install --silent
npm run tauri build

# 6. Shortcut and Packaging
Show-Step "Creating Desktop Shortcut..."
$TargetFile = Get-ChildItem -Path "src-tauri\target\release\xenon.exe" -Recurse | Select-Object -First 1
if ($TargetFile) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$HOME\Desktop\Xenon.lnk")
    $Shortcut.TargetPath = $TargetFile.FullName
    $Shortcut.WorkingDirectory = $TargetFile.DirectoryName
    $Shortcut.IconLocation = $TargetFile.FullName
    $Shortcut.Save()
    Show-Success "Shortcut created on Desktop."
}

Show-Header
Show-Success "XENON INSTALLATION COMPLETE"
Write-Host "`nConfiguration saved to: $(Get-Location)\config.json"
Write-Host "Your agent is ready to launch from the Desktop shortcut."
Write-Host "Browser data from $Browser will be imported on first run.`n" -ForegroundColor Cyan
