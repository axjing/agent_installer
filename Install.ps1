<#
.SYNOPSIS
    Install.ps1 - agent-installer 快速一键自动化部署器
.DESCRIPTION
    自动完成 Windows 环境准备、Node.js 运行时校验、npm PATH 自动修复、主流 AI Agent 全局安装与路由初始化。
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [string]$NpmRegistryUrl = "https://registry.npmmirror.com/",
    [string]$DefaultProvider = "anthropic-official"
)

$ErrorActionPreference = "Continue"

# 载入本地模块
$ModulesPath = Join-Path $PSScriptRoot "modules"
Import-Module (Join-Path $ModulesPath "UI.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "Prerequisites.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "AgentRegistry.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "CCSwitch.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "ConfigManager.psm1") -DisableNameChecking -Force

Show-Banner
Write-Info ">>> 正在启动 agent-installer 初始化部署向导..."

# 1. 确保权限与策略
Ensure-ExecutionPolicy

# 2. 检查基础环境
$prereqs = Get-PrerequisitesStatus
if (-not $prereqs.NodeInstalled -or -not $prereqs.NpmInstalled) {
    Write-WarnMsg "未检测到 Node.js 运行时！"
    Write-Info "正在启动多通道全自动安装 Node.js LTS (Winget -> 官方MSI -> 免提权便携版)..."
    $installedNode = Install-NodeJsAuto
    if (-not $installedNode) {
        Write-ErrorMsg "自动安装失败，请检查网络后重新运行本脚本，或前往 https://nodejs.org 手动下载安装。"
        exit 1
    }
} else {
    Write-Success "检测到 Node.js: v$($prereqs.NodeVersion), npm: v$($prereqs.NpmVersion)"
}

# 3. 检查并自动修复 npm 全局 PATH
if (-not $prereqs.NpmPathValid) {
    Write-Info "检测到 npm 全局包路径未在用户 PATH 中，正在自动修复..."
    Repair-NpmGlobalPath -NpmGlobalDir $prereqs.NpmGlobalPath
} else {
    Write-Success "npm 全局 bin 目录已包含在当前 PATH 中。"
}

# 4. 配置 npm 镜像源（默认国内极速）
if ($NpmRegistryUrl) {
    Write-Info "配置 npm 镜像源为: $NpmRegistryUrl"
    Set-NpmRegistry -RegistryUrl $NpmRegistryUrl | Out-Null
}

# 5. 自动安装 4 款主流 AI Agent
Write-Info ">>> 开始安装 4 款主流 AI Agent (OpenClaw, OpenAI Codex, Claude Code, Pi Agent)..."
$supported = Get-SupportedAgents
foreach ($k in $supported.Keys) {
    $info = Get-AgentInfo -AgentKey $k
    if ($info.Installed) {
        Write-Info "$($info.DisplayName) 已安装 ($($info.Version))，跳过。"
    } else {
        Install-AgentPackage -AgentKey $k | Out-Null
    }
}

# 6. 初始化默认模型路由
Write-Info ">>> 初始化默认模型厂商路由为: $DefaultProvider"
Set-ProviderRoute -ProviderKey $DefaultProvider | Out-Null

# 7. 检测 CC Switch
$cc = Get-CCSwitchStatus
if (-not $cc.Installed) {
    Write-Info "提示: CC Switch 尚未安装。您可随时在 agent-installer 控制台菜单中一键安装 CC Switch 桌面端。"
}

Write-Success "`n========================================================"
Write-Success " agent-installer 初始化部署全部顺利完成！"
Write-Success " 您可以随时在当前目录执行 .\agent-installer.ps1 打开控制台。"
Write-Success "========================================================`n"

if (-not $Quiet) {
    Write-Host "按任意键进入管理控制台..." -ForegroundColor Cyan
    $null = [System.Console]::ReadKey()
    & (Join-Path $PSScriptRoot "agent-installer.ps1")
}
