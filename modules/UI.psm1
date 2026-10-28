# modules/UI.psm1
# UI / TUI 渲染与终端交互模块

$script:LogFile = Join-Path $PSScriptRoot "..\agent-installer.log"

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
    Write-Log -Message $Message -Level "INFO"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
    Write-Log -Message $Message -Level "SUCCESS"
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
    Write-Log -Message $Message -Level "WARN"
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
    Write-Log -Message $Message -Level "ERROR"
}

function Show-Banner {
    try {
        if ([System.Environment]::UserInteractive -and -not [System.Console]::IsOutputRedirected) {
            Clear-Host
        }
    } catch {}

    $banner = @"
========================================================================
    ___                    __     ____           __        ____         
   /   | ____ ____  ____  / /_   /  _/___  _____/ /_____ _/ / /__  _____
  / /| |/ __ `/ _ \/ __ \/ __/   / // __ \/ ___/ __/ __ `/ / / _ \/ ___/
 / ___ / /_/ /  __/ / / / /_   _/ // / / (__  ) /_/ /_/ / / /  __/ /    
/_/  |_\__, /\___/_/ /_/\__/  /___/_/ /_/____/\__/\__,_/_/_/\___/_/     
      /____/                                                            
      Windows AI Agent 一键部署与 CC Switch 统一厂商路由调度中心
========================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
}

function Show-StatusTable {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Agents,
        [hashtable]$Prereqs,
        [hashtable]$CCSwitchStatus,
        [string]$ActiveProviderName
    )

    Write-Host "`n+----------------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "|                           系统与基础环境状态                         |" -ForegroundColor White
    Write-Host "+----------------------------------------------------------------------+" -ForegroundColor DarkGray

    $nodeStr = if ($Prereqs.NodeInstalled) { "v$($Prereqs.NodeVersion) [OK]" } else { "未安装 [缺失]" }
    $nodeColor = if ($Prereqs.NodeInstalled) { "Green" } else { "Red" }

    $npmStr  = if ($Prereqs.NpmInstalled)  { "v$($Prereqs.NpmVersion) [OK]" } else { "未安装 [缺失]" }
    $npmColor = if ($Prereqs.NpmInstalled) { "Green" } else { "Red" }

    $gitStr  = if ($Prereqs.GitInstalled)  { "v$($Prereqs.GitVersion) [OK]" } else { "未安装 [缺失]" }
    $gitColor = if ($Prereqs.GitInstalled) { "Green" } else { "Yellow" }

    $pathStr = if ($Prereqs.NpmPathValid)  { "已包含于 PATH [OK]" } else { "未加入 PATH [需修复]" }
    $pathColor = if ($Prereqs.NpmPathValid) { "Green" } else { "Yellow" }

    $ccStr   = if ($CCSwitchStatus.Installed) { "已安装 ($($CCSwitchStatus.Path))" } else { "未检测到 (可一键部署)" }
    $ccColor = if ($CCSwitchStatus.Installed) { "Green" } else { "Yellow" }

    Write-Host ("  Node.js   : " + $nodeStr) -ForegroundColor $nodeColor
    Write-Host ("  npm       : " + $npmStr) -ForegroundColor $npmColor
    Write-Host ("  Git       : " + $gitStr) -ForegroundColor $gitColor
    Write-Host ("  npm PATH  : " + $pathStr) -ForegroundColor $pathColor
    Write-Host ("  CC Switch : " + $ccStr) -ForegroundColor $ccColor
    Write-Host ("  当前生效路由 : " + $ActiveProviderName) -ForegroundColor Magenta

    Write-Host "`n+----------------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "|                      受管 AI Agent 状态总览                          |" -ForegroundColor White
    Write-Host "+---------------------+------------------+----------------+------------+" -ForegroundColor DarkGray
    Write-Host "| Agent 名称          | 状态             | 当前版本       | 绑定 CLI   |" -ForegroundColor White
    Write-Host "+---------------------+------------------+----------------+------------+" -ForegroundColor DarkGray

    foreach ($agent in $Agents) {
        $statusStr = if ($agent.Installed) { "已安装" } else { "未安装" }
        $color = if ($agent.Installed) { "Green" } else { "Gray" }
        $verStr = if ($agent.Installed -and $agent.Version) { $agent.Version } else { if ($agent.Installed) { "已就绪" } else { "--" } }
        $cliStr = $agent.Command

        $line = "| {0,-19} | {1,-16} | {2,-14} | {3,-10} |" -f $agent.DisplayName, $statusStr, $verStr, $cliStr
        Write-Host $line -ForegroundColor $color
    }
    Write-Host "+---------------------+------------------+----------------+------------+" -ForegroundColor DarkGray
}

function Show-Menu {
    Write-Host "`n[操作菜单 - 请输入编号并回车]:" -ForegroundColor Cyan
    Write-Host "  1. 一键全自动安装所有 AI Agent (OpenClaw, Codex, Claude Code, Pi Agent)"
    Write-Host "  2. 自选安装 / 升级特定 AI Agent"
    Write-Host "  3. 切换大模型厂商路由 (对接 CC Switch / 统一多端同步)"
    Write-Host "  4. 一键安装 / 启动 CC Switch 桌面控制中心"
    Write-Host "  5. 环境 Doctor 诊断与自动修复 (修复 npm 路径/权限/依赖)"
    Write-Host "  6. 切换 npm 镜像源 (国内极速镜像源 / 官方源)"
    Write-Host "  7. 卸载 AI Agent"
    Write-Host "  0. 退出工具"
    Write-Host ""
}

Export-ModuleMember -Function Write-Log, Write-Info, Write-Success, Write-WarnMsg, Write-ErrorMsg, Show-Banner, Show-StatusTable, Show-Menu
