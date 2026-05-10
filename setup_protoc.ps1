# Xenon Protoc Setup Script
# Downloads protoc for Windows

$ErrorActionPreference = "Stop"

$protoc_url = "https://github.com/protocolbuffers/protobuf/releases/download/v29.1/protoc-29.1-win64.zip"

mkdir -Force vendor/protoc

Write-Host "Downloading Protoc..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $protoc_url -OutFile protoc.zip
tar -xf protoc.zip -C vendor/protoc
Remove-Item protoc.zip

Write-Host "Protoc environment ready." -ForegroundColor Green
