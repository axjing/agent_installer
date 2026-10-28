# modules/AgentRegistry.psm1
# AI Agent 注册表与生命周期管理模块

Import-Module (Join-Path $PSScriptRoot "UI.psm1") -DisableNameChecking

$script:SupportedAgents = @{
    "openclaw" = @{
        Key          = "openclaw"
        DisplayName  = "OpenClaw"
        PackageName  = "openclaw@latest"
        Command      = "openclaw"
        Description  = "OpenClaw 全自主通用 AI Agent 引擎与终端 CLI"
        VersionArgs  = "--version"
        InstallExtra = @("--allow-scripts=openclaw")
    }
    "openai-codex" = @{
        Key          = "openai-codex"
        DisplayName  = "OpenAI Codex"
        PackageName  = "@openai/codex"
        Command      = "codex"
        Description  = "OpenAI 官方终端编程与代码生成 Agent CLI"
        VersionArgs  = "--version"
        InstallExtra = @()
    }
    "claude-code" = @{
        Key          = "claude-code"
        DisplayName  = "Claude Code"
        PackageName  = "@anthropic-ai/claude-code"
        Command      = "claude"
        Description  = "Anthropic 官方终端全自主代码研发 Agent CLI"
        VersionArgs  = "--version"
        InstallExtra = @()
    }
    "pi-agent" = @{
        Key          = "pi-agent"
        DisplayName  = "Pi Agent"
        PackageName  = "@earendil-works/pi-coding-agent"
        Command      = "pi"
        Description  = "Pi 极简高扩展终端编程 Agent & TUI"
        VersionArgs  = "--version"
        InstallExtra = @("--ignore-scripts")
    }
}

function Get-SupportedAgents {
    return $script:SupportedAgents
}

function Get-AgentInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentKey
    )

    if (-not $script:SupportedAgents.ContainsKey($AgentKey)) {
        Write-ErrorMsg "未知的 Agent 标识: $AgentKey"
        return $null
    }

    $meta = $script:SupportedAgents[$AgentKey]
    $cmdName = $meta.Command

    $installed = $false
    $version = $null

    try {
        $cmdObj = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($cmdObj) {
            $installed = $true
            # 运行版本参数探测
            $vOut = & $cmdName $meta.VersionArgs 2>$null
            if ($vOut) {
                $firstLine = ($vOut | Select-Object -First 1).ToString().Trim()
                if ($firstLine -match "(\d+\.\d+\.\d+[\w\.\-]*)") {
                    $version = $matches[1]
                } else {
                    $version = $firstLine
                }
            } else {
                $version = "已安装(版本未知)"
            }
        }
    } catch {
        # 若直接运行报错，尝试查 npm list -g
        try {
            $npmListRaw = & npm list -g --depth=0 $meta.PackageName.Split('@')[0] 2>$null
            if ($npmListRaw -match "@(\d+\.\d+\.\d+[\w\.\-]*)") {
                $installed = $true
                $version = $matches[1]
            }
        } catch {}
    }

    return @{
        Key         = $meta.Key
        DisplayName = $meta.DisplayName
        PackageName = $meta.PackageName
        Command     = $meta.Command
        Description = $meta.Description
        Installed   = $installed
        Version     = $version
    }
}

function Get-AllAgentStatus {
    $results = @()
    foreach ($key in $script:SupportedAgents.Keys) {
        $results += (Get-AgentInfo -AgentKey $key)
    }
    return $results
}

function Install-AgentPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentKey,
        [switch]$Force
    )

    if (-not $script:SupportedAgents.ContainsKey($AgentKey)) {
        Write-ErrorMsg "不支持安装指定的 Agent: $AgentKey"
        return $false
    }

    $agent = $script:SupportedAgents[$AgentKey]
    Write-Info "正在全局安装 $($agent.DisplayName) ($($agent.PackageName))..."

    $installArgs = @("install", "-g", $agent.PackageName)
    if ($Force) {
        $installArgs += "--force"
    }
    if ($agent.InstallExtra) {
        $installArgs += $agent.InstallExtra
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "npm.cmd"
        # 若找不到 npm.cmd 则回退到 npm
        $npmCmd = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
        if (-not $npmCmd) {
            $psi.FileName = "npm"
        }
        $psi.Arguments = $installArgs -join " "
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($proc.ExitCode -eq 0) {
            Write-Success "$($agent.DisplayName) 安装成功！"
            Write-Log -Message "[$($agent.Key)] 安装成功: $stdout" -Level "SUCCESS"
            return $true
        } else {
            Write-ErrorMsg "$($agent.DisplayName) 安装遇到非零退出代码 ($($proc.ExitCode))。"
            if ($stderr) {
                Write-WarnMsg "错误信息: $stderr"
                Write-Log -Message "[$($agent.Key)] 错误: $stderr" -Level "ERROR"
            }
            return $false
        }
    } catch {
        Write-ErrorMsg "安装过程发生异常: $_"
        return $false
    }
}

function Uninstall-AgentPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentKey
    )

    if (-not $script:SupportedAgents.ContainsKey($AgentKey)) {
        Write-ErrorMsg "未知的 Agent: $AgentKey"
        return $false
    }

    $agent = $script:SupportedAgents[$AgentKey]
    $pkgClean = $agent.PackageName.Split('@')[0]
    if ($agent.PackageName.StartsWith("@")) {
        $parts = $agent.PackageName.Split('@')
        $pkgClean = "@" + $parts[1]
    }

    Write-Info "正在卸载全局包: $pkgClean ($($agent.DisplayName))..."
    try {
        $output = & npm uninstall -g $pkgClean 2>&1
        Write-Success "$($agent.DisplayName) 卸载命令执行完毕。"
        return $true
    } catch {
        Write-ErrorMsg "卸载遇到错误: $_"
        return $false
    }
}

function Test-AgentCLI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentKey
    )

    $info = Get-AgentInfo -AgentKey $AgentKey
    if (-not $info.Installed) {
        Write-WarnMsg "$($info.DisplayName) 尚未安装或未在 PATH 中找到。"
        return $false
    }

    Write-Info "正在运行 $($info.DisplayName) ($($info.Command)) 联通性测试..."
    try {
        $out = & $info.Command --help 2>&1 | Select-Object -First 3
        Write-Success "$($info.DisplayName) CLI 响应正常！"
        return $true
    } catch {
        Write-ErrorMsg "$($info.DisplayName) 运行失败: $_"
        return $false
    }
}

Export-ModuleMember -Function Get-SupportedAgents, Get-AgentInfo, Get-AllAgentStatus, Install-AgentPackage, Uninstall-AgentPackage, Test-AgentCLI
