<#
.SYNOPSIS
    agent-installer - Windows 主流 AI Agent 自动化安装与 CC Switch 统一厂商路由调度中心
.DESCRIPTION
    专注为 Windows 运维与开发者提供一站式 AI Coding Agent (OpenClaw, OpenAI Codex, Claude Code, Pi Agent) 
    生命周期管理，深度集成 CC Switch 实现跨 Agent 的大模型厂商路由即时切换。
.EXAMPLE
    .\agent-installer.ps1
    启动交互式 TUI 仪表板与操作菜单。
.EXAMPLE
    .\agent-installer.ps1 -InstallAll
    静默安装全部受管 AI Agent。
.EXAMPLE
    .\agent-installer.ps1 -SwitchProvider deepseek -ApiKey "sk-xxxx"
    将全部 Agent 路由统一切换为 DeepSeek 并更新环境变量与配置文件。
#>

[CmdletBinding()]
param(
    [switch]$InstallAll,
    [switch]$Install,
    [string[]]$Agents,
    [string]$Uninstall,
    [string]$SwitchProvider,
    [string]$ApiKey,
    [string]$BaseUrl,
    [switch]$Doctor,
    [string]$SetRegistry,
    [switch]$LaunchCCSwitch,
    [switch]$NonInteractive
)

# 确保脚本执行安全策略
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# 载入各核心功能模块
$ModulesPath = Join-Path $PSScriptRoot "modules"
Import-Module (Join-Path $ModulesPath "UI.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "Prerequisites.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "AgentRegistry.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "CCSwitch.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModulesPath "ConfigManager.psm1") -DisableNameChecking -Force

# 自动确保进程级 ExecutionPolicy
Ensure-ExecutionPolicy

# ----------------- 命令行参数快速路由处理 -----------------

# 1. 运行 Doctor 诊断
if ($Doctor) {
    Write-Info "正在执行系统健康与环境诊断..."
    $prereq = Get-PrerequisitesStatus
    $cc = Get-CCSwitchStatus
    $agentList = Get-AllAgentStatus
    $active = Get-ActiveProviderInfo

    Show-Banner
    Show-StatusTable -Agents $agentList -Prereqs $prereq -CCSwitchStatus $cc -ActiveProviderName "$($active.Name) ($($active.Key))"

    if (-not $prereq.NpmPathValid) {
        Write-WarnMsg "检测到 npm 全局路径尚未加入用户 PATH，正在自动修复..."
        Repair-NpmGlobalPath -NpmGlobalDir $prereq.NpmGlobalPath
    } else {
        Write-Success "系统环境健康度良好！"
    }
    return
}

# 2. 切换 npm 镜像源
if ($SetRegistry) {
    Set-NpmRegistry -RegistryUrl $SetRegistry
    return
}

# 3. 启动 CC Switch
if ($LaunchCCSwitch) {
    Start-CCSwitchApp
    return
}

# 4. 切换模型厂商路由
if ($SwitchProvider) {
    Set-ProviderRoute -ProviderKey $SwitchProvider -ApiKey $ApiKey -CustomBaseUrl $BaseUrl
    return
}

# 5. 卸载特定 Agent
if ($Uninstall) {
    Uninstall-AgentPackage -AgentKey $Uninstall
    return
}

# 6. 静默一键安装全部 Agent
if ($InstallAll) {
    Write-Info ">>> 正在执行一键批量安装全部受管 AI Agent..."
    $prereqs = Get-PrerequisitesStatus
    if (-not $prereqs.NodeInstalled -or -not $prereqs.NpmInstalled) {
        Write-WarnMsg "未检测到 Node.js 运行时，正在启动自动安装通道..."
        $installed = Install-NodeJsAuto
        if (-not $installed) {
            Write-ErrorMsg "Node.js 自动安装未完成，请手动前往 https://nodejs.org 安装后重试。"
            return
        }
        $prereqs = Get-PrerequisitesStatus
    }

    if (-not $prereqs.NpmPathValid) {
        Repair-NpmGlobalPath -NpmGlobalDir $prereqs.NpmGlobalPath
    }

    $allAgents = Get-SupportedAgents
    foreach ($key in $allAgents.Keys) {
        Install-AgentPackage -AgentKey $key
    }
    Write-Success "全部 AI Agent 安装流程执行完毕！"
    return
}

# 7. 自选安装 Agent
if ($Install -and $Agents) {
    foreach ($ag in $Agents) {
        Install-AgentPackage -AgentKey $ag.Trim()
    }
    return
}

# ----------------- 交互式控制台主循环 -----------------

function Refresh-Dashboard {
    $prereq = Get-PrerequisitesStatus
    $cc = Get-CCSwitchStatus
    $agentList = Get-AllAgentStatus
    $active = Get-ActiveProviderInfo

    Show-Banner
    Show-StatusTable -Agents $agentList -Prereqs $prereq -CCSwitchStatus $cc -ActiveProviderName "$($active.Name) ($($active.Key))"
    Show-Menu
}

while ($true) {
    Refresh-Dashboard
    $choice = Read-Host "请输入操作选项 (0-7)"

    switch ($choice.Trim()) {
        "1" {
            Write-Info "开始批量安装全部 AI Agent..."
            $prereq = Get-PrerequisitesStatus
            if (-not $prereq.NpmPathValid) {
                Repair-NpmGlobalPath -NpmGlobalDir $prereq.NpmGlobalPath
            }
            $allAgents = Get-SupportedAgents
            foreach ($k in $allAgents.Keys) {
                Install-AgentPackage -AgentKey $k
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "2" {
            Write-Host "`n支持的 Agent 列表:" -ForegroundColor Cyan
            $supported = Get-SupportedAgents
            $idx = 1
            $keyMap = @{}
            foreach ($k in $supported.Keys) {
                $keyMap[$idx] = $k
                Write-Host "  [$idx] $($supported[$k].DisplayName) ($($supported[$k].PackageName))"
                $idx++
            }
            $subChoice = Read-Host "请选择要安装/更新的 Agent 编号 (输入数字，多个可用逗号隔开)"
            $selectedIdxs = $subChoice -split ","
            foreach ($item in $selectedIdxs) {
                $num = 0
                if ([int]::TryParse($item.Trim(), [ref]$num) -and $keyMap.ContainsKey($num)) {
                    Install-AgentPackage -AgentKey $keyMap[$num]
                }
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "3" {
            Write-Host "`n可用的大模型厂商预设路由:" -ForegroundColor Cyan
            $cfg = Get-ProvidersConfig
            $pIdx = 1
            $pMap = @{}
            foreach ($prop in $cfg.providers.PSObject.Properties) {
                $pMap[$pIdx] = $prop.Name
                Write-Host ("  [{0}] {1,-24} : {2}" -f $pIdx, $prop.Value.name, $prop.Value.description)
                $pIdx++
            }
            $pChoice = Read-Host "请选择目标厂商编号"
            $pNum = 0
            if ([int]::TryParse($pChoice.Trim(), [ref]$pNum) -and $pMap.ContainsKey($pNum)) {
                $selectedKey = $pMap[$pNum]
                $keyInput = Read-Host "请输入 API Key (若保留现有或已在环境设置可直接回车)"
                $urlInput = Read-Host "请输入自定义 Base URL (若使用厂商默认请直接回车)"
                Set-ProviderRoute -ProviderKey $selectedKey -ApiKey $keyInput -CustomBaseUrl $urlInput
            } else {
                Write-WarnMsg "输入无效编号。"
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "4" {
            $cc = Get-CCSwitchStatus
            if ($cc.Installed) {
                Write-Info "CC Switch 已经安装，正在拉起程序..."
                Start-CCSwitchApp
            } else {
                Write-Info "开始自动下载并安装 CC Switch..."
                Install-CCSwitch
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "5" {
            Write-Info "运行环境 Doctor 诊断与自愈修复..."
            $prereq = Get-PrerequisitesStatus
            if (-not $prereq.NodeInstalled) {
                Write-WarnMsg "Node.js 未检测到，正在启动多通道自动自愈安装..."
                Install-NodeJsAuto
            }
            if (-not $prereq.NpmPathValid) {
                Write-Info "正在修复 npm 全局 PATH 环境变量..."
                Repair-NpmGlobalPath -NpmGlobalDir $prereq.NpmGlobalPath
            } else {
                Write-Success "npm 全局目录已正确配置在环境变量中。"
            }
            Write-Success "诊断与自愈修复流程完成！"
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "6" {
            Write-Host "`n当前 npm 镜像源: $(Get-NpmRegistry)" -ForegroundColor Cyan
            Write-Host "  1. 切换为 淘宝/npmmirror 极速镜像 (推荐国内网络)"
            Write-Host "  2. 切换为 官方源 (https://registry.npmjs.org/)"
            Write-Host "  3. 切换为 腾讯云镜像"
            $mChoice = Read-Host "请选择镜像编号 (1-3)"
            switch ($mChoice) {
                "1" { Set-NpmRegistry -RegistryUrl "https://registry.npmmirror.com/" }
                "2" { Set-NpmRegistry -RegistryUrl "https://registry.npmjs.org/" }
                "3" { Set-NpmRegistry -RegistryUrl "https://mirrors.cloud.tencent.com/npm/" }
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "7" {
            Write-Host "`n请选择要卸载的 Agent:" -ForegroundColor Cyan
            $supported = Get-SupportedAgents
            $idx = 1
            $keyMap = @{}
            foreach ($k in $supported.Keys) {
                $keyMap[$idx] = $k
                Write-Host "  [$idx] $($supported[$k].DisplayName)"
                $idx++
            }
            $delChoice = Read-Host "请输入要卸载的编号"
            $dNum = 0
            if ([int]::TryParse($delChoice.Trim(), [ref]$dNum) -and $keyMap.ContainsKey($dNum)) {
                Uninstall-AgentPackage -AgentKey $keyMap[$dNum]
            }
            Write-Host "`n按任意键返回主菜单..." -ForegroundColor Gray
            $null = [System.Console]::ReadKey()
        }
        "0" {
            Write-Info "已退出 agent-installer。祝编码愉快！"
            break
        }
        default {
            Write-WarnMsg "无效选项，请输入 0-7 之间的数字。"
            Start-Sleep -Seconds 1
        }
    }
}
