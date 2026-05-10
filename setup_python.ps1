# Xenon Python Setup Script - Build-Ready Edition
# Downloads Python with .lib files for Rust linking

$ErrorActionPreference = "Stop"

mkdir -Force vendor/python/latest
mkdir -Force vendor/python/stable

# Use NuGet for latest to get .lib files (required for build)
Write-Host "Downloading Python 3.13.1 (Latest) via NuGet..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/python/3.13.1" -OutFile latest.nupkg
Expand-Archive latest.nupkg -DestinationPath vendor/python/latest -Force
Remove-Item latest.nupkg

# Use Embeddable for stable (runtime only)
Write-Host "Downloading Python 3.10.11 (Stable)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.10.11/python-3.10.11-embed-amd64.zip" -OutFile stable.zip
Expand-Archive stable.zip -DestinationPath vendor/python/stable -Force
Remove-Item stable.zip

# Enable site-packages
foreach ($dir in @("vendor/python/stable", "vendor/python/latest")) {
    $pth = Get-ChildItem $dir -Filter "*._pth"
    if ($pth) {
        $content = Get-Content $pth.FullName
        $content = $content -replace "#import site", "import site"
        Set-Content $pth.FullName $content
    }
}

# Install pip for both
Write-Host "Downloading get-pip.py..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile get-pip.py
./vendor/python/latest/tools/python.exe get-pip.py
./vendor/python/stable/python.exe get-pip.py
Remove-Item get-pip.py

Write-Host "Python build-ready environment ready." -ForegroundColor Green
