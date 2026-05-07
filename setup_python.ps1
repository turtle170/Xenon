# Xenon Python Setup Script
# Downloads embeddable Python for Windows

$ErrorActionPreference = "Stop"

$python_stable_url = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-embed-amd64.zip"
$python_latest_url = "https://www.python.org/ftp/python/3.13.1/python-3.13.1-embed-amd64.zip"

mkdir -Force vendor/python/stable
mkdir -Force vendor/python/latest

Write-Host "Downloading Python 3.10 (Stable)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $python_stable_url -OutFile stable.zip
tar -xf stable.zip -C vendor/python/stable
Remove-Item stable.zip

Write-Host "Downloading Python 3.13 (Latest)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $python_latest_url -OutFile latest.zip
tar -xf latest.zip -C vendor/python/latest
Remove-Item latest.zip

# Enable site-packages in ._pth files
foreach ($dir in @("vendor/python/stable", "vendor/python/latest")) {
    $pth = Get-ChildItem $dir -Filter "*._pth"
    if ($pth) {
        $content = Get-Content $pth.FullName
        $content = $content -replace "#import site", "import site"
        Set-Content $pth.FullName $content
    }
}

# Install pip logic would go here (download get-pip.py and run with embedded python)
Write-Host "Downloading get-pip.py..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile get-pip.py
./vendor/python/latest/python.exe get-pip.py
./vendor/python/stable/python.exe get-pip.py
Remove-Item get-pip.py

Write-Host "Python environments ready." -ForegroundColor Green
