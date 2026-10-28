<#
.SYNOPSIS
    bootstrap.ps1 - agent-installer 极简网络远程引导脚本
.DESCRIPTION
    支持单行 PowerShell 远程拉取并全自动启动部署:
    irm https://raw.githubusercontent.com/username/agent-installer/main/bootstrap.ps1 | iex
#>

$TargetDir = Join-Path $env:USERPROFILE "agent-installer"
Write-Host "[*] 正在准备 agent-installer 环境..." -ForegroundColor Cyan

# 确保 ExecutionPolicy
try {
    if ((Get-ExecutionPolicy -Scope Process) -in @("Restricted", "Undefined")) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
    }
} catch {}

if (Test-Path (Join-Path $PSScriptRoot "Install.ps1")) {
    & (Join-Path $PSScriptRoot "Install.ps1")
    return
}

# 若为远程单行管道调用
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$RepoUrl = "https://github.com/example/agent-installer.git"
$git = Get-Command "git" -ErrorAction SilentlyContinue

if ($git) {
    Write-Host "[*] 正在通过 Git 克隆 agent-installer 到: $TargetDir" -ForegroundColor Cyan
    & git clone $RepoUrl $TargetDir
} else {
    Write-Host "[*] 正在拉取 agent-installer 源码包..." -ForegroundColor Cyan
    $zipUrl = "https://github.com/example/agent-installer/archive/refs/heads/main.zip"
    $tempZip = Join-Path $env:TEMP "agent-installer.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath (Join-Path $env:TEMP "agent-installer-extract") -Force
    Copy-Item -Path (Join-Path $env:TEMP "agent-installer-extract\agent-installer-main\*") -Destination $TargetDir -Recurse -Force
}

Set-Location $TargetDir
& (Join-Path $TargetDir "Install.ps1")
