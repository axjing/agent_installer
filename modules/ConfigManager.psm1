# modules/ConfigManager.psm1
# 统一模型厂商路由配置管理与多 Agent 注入同步模块

Import-Module (Join-Path $PSScriptRoot "UI.psm1") -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "CCSwitch.psm1") -DisableNameChecking

$script:ConfigDir = Join-Path $PSScriptRoot "..\config"
$script:ProvidersFile = Join-Path $script:ConfigDir "providers.json"
$script:SettingsFile = Join-Path $script:ConfigDir "settings.json"

function Get-ProvidersConfig {
    if (-not (Test-Path $script:ProvidersFile)) {
        Write-ErrorMsg "找不到厂商配置文件: $script:ProvidersFile"
        return $null
    }
    try {
        $content = Get-Content $script:ProvidersFile -Raw -Encoding UTF8
        return (ConvertFrom-Json $content)
    } catch {
        Write-ErrorMsg "解析 providers.json 失败: $_"
        return $null
    }
}

function Get-SettingsConfig {
    if (-not (Test-Path $script:SettingsFile)) {
        return @{
            activeProvider  = "anthropic-official"
            npmRegistry     = "https://registry.npmjs.org/"
            autoSyncEnv     = $true
            syncScope       = "User"
            installedAgents = @()
        }
    }
    try {
        $content = Get-Content $script:SettingsFile -Raw -Encoding UTF8
        return (ConvertFrom-Json $content)
    } catch {
        return @{
            activeProvider  = "anthropic-official"
            npmRegistry     = "https://registry.npmjs.org/"
            autoSyncEnv     = $true
            syncScope       = "User"
            installedAgents = @()
        }
    }
}

function Save-SettingsConfig {
    param([Parameter(Mandatory = $true)]$Settings)

    try {
        $json = $Settings | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($script:SettingsFile, $json, [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        Write-ErrorMsg "保存 settings.json 失败: $_"
        return $false
    }
}

function Set-EnvironmentVarSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Scope = "User"
    )

    # 1. 设置当前进程
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")

    # 2. 设置用户永久环境变量
    if ($Scope -eq "User" -or $Scope -eq "Both") {
        try {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
        } catch {
            Write-WarnMsg "设置用户永久环境变量 $Name 失败: $_"
        }
    }
}

function Sync-ClaudeCodeConfig {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Scope = "User"
    )

    # 1. 环境变量同步
    if ($BaseUrl) {
        Set-EnvironmentVarSafe -Name "ANTHROPIC_BASE_URL" -Value $BaseUrl -Scope $Scope
    }
    if ($ApiKey) {
        Set-EnvironmentVarSafe -Name "ANTHROPIC_API_KEY" -Value $ApiKey -Scope $Scope
        Set-EnvironmentVarSafe -Name "ANTHROPIC_AUTH_TOKEN" -Value $ApiKey -Scope $Scope
    }

    # 2. 写入 Claude Code 官方配置目录 ~/.claude/settings.json 与 ~/.claude.json
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $claudeSettingsPath = Join-Path $claudeDir "settings.json"
    $claudeSettings = @{}
    if (Test-Path $claudeSettingsPath) {
        try {
            $claudeSettings = (Get-Content $claudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {}
    }

    # 注入/更新 BaseUrl
    if ($BaseUrl) {
        $claudeSettings | Add-Member -NotePropertyName "baseUrl" -NotePropertyValue $BaseUrl -Force
        $claudeSettings | Add-Member -NotePropertyName "anthropicBaseUrl" -NotePropertyValue $BaseUrl -Force
    }

    try {
        $json = $claudeSettings | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($claudeSettingsPath, $json, [System.Text.Encoding]::UTF8)
        Write-Info "已同步更新 Claude Code 配置: $claudeSettingsPath"
    } catch {
        Write-WarnMsg "写入 Claude Code settings.json 遇到警告: $_"
    }
}

function Sync-OpenAICodexConfig {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$Scope = "User"
    )

    # 1. 环境变量
    if ($BaseUrl) {
        Set-EnvironmentVarSafe -Name "OPENAI_BASE_URL" -Value $BaseUrl -Scope $Scope
    }
    if ($ApiKey) {
        Set-EnvironmentVarSafe -Name "OPENAI_API_KEY" -Value $ApiKey -Scope $Scope
    }

    # 2. 写入 ~/.codex/config.json
    $codexDir = Join-Path $env:USERPROFILE ".codex"
    if (-not (Test-Path $codexDir)) {
        New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
    }
    $codexConfigPath = Join-Path $codexDir "config.json"
    $codexObj = @{}
    if (Test-Path $codexConfigPath) {
        try {
            $codexObj = (Get-Content $codexConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {}
    }

    if ($BaseUrl) { $codexObj | Add-Member -NotePropertyName "baseUrl" -NotePropertyValue $BaseUrl -Force }
    if ($ApiKey) { $codexObj | Add-Member -NotePropertyName "apiKey" -NotePropertyValue $ApiKey -Force }
    if ($Model) { $codexObj | Add-Member -NotePropertyName "model" -NotePropertyValue $Model -Force }

    try {
        $json = $codexObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($codexConfigPath, $json, [System.Text.Encoding]::UTF8)
        Write-Info "已同步更新 OpenAI Codex 配置: $codexConfigPath"
    } catch {
        Write-WarnMsg "写入 Codex config.json 警告: $_"
    }
}

function Sync-OpenClawConfig {
    param(
        [string]$GatewayUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$Scope = "User"
    )

    # 1. 环境变量
    if ($GatewayUrl) {
        Set-EnvironmentVarSafe -Name "OPENCLAW_GATEWAY_URL" -Value $GatewayUrl -Scope $Scope
    }
    if ($ApiKey) {
        Set-EnvironmentVarSafe -Name "OPENCLAW_API_KEY" -Value $ApiKey -Scope $Scope
    }

    # 2. 写入 ~/.openclaw/config.json
    $openclawDir = Join-Path $env:USERPROFILE ".openclaw"
    if (-not (Test-Path $openclawDir)) {
        New-Item -ItemType Directory -Path $openclawDir -Force | Out-Null
    }
    $cfgPath = Join-Path $openclawDir "config.json"
    $cfgObj = @{}
    if (Test-Path $cfgPath) {
        try { $cfgObj = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }

    if ($GatewayUrl) { $cfgObj | Add-Member -NotePropertyName "gatewayUrl" -NotePropertyValue $GatewayUrl -Force }
    if ($ApiKey) { $cfgObj | Add-Member -NotePropertyName "apiKey" -NotePropertyValue $ApiKey -Force }
    if ($Model) { $cfgObj | Add-Member -NotePropertyName "model" -NotePropertyValue $Model -Force }

    try {
        $json = $cfgObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cfgPath, $json, [System.Text.Encoding]::UTF8)
        Write-Info "已同步更新 OpenClaw 配置: $cfgPath"
    } catch {
        Write-WarnMsg "写入 OpenClaw config.json 警告: $_"
    }
}

function Sync-PiAgentConfig {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Provider,
        [string]$Model,
        [string]$Scope = "User"
    )

    if ($BaseUrl) {
        Set-EnvironmentVarSafe -Name "PI_BASE_URL" -Value $BaseUrl -Scope $Scope
    }

    # 写入 ~/.pi/agent/config.json
    $piDir = Join-Path $env:USERPROFILE ".pi\agent"
    if (-not (Test-Path $piDir)) {
        New-Item -ItemType Directory -Path $piDir -Force | Out-Null
    }
    $cfgPath = Join-Path $piDir "config.json"
    $cfgObj = @{}
    if (Test-Path $cfgPath) {
        try { $cfgObj = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }

    if ($BaseUrl) { $cfgObj | Add-Member -NotePropertyName "baseUrl" -NotePropertyValue $BaseUrl -Force }
    if ($ApiKey) { $cfgObj | Add-Member -NotePropertyName "apiKey" -NotePropertyValue $ApiKey -Force }
    if ($Provider) { $cfgObj | Add-Member -NotePropertyName "provider" -NotePropertyValue $Provider -Force }
    if ($Model) { $cfgObj | Add-Member -NotePropertyName "model" -NotePropertyValue $Model -Force }

    try {
        $json = $cfgObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cfgPath, $json, [System.Text.Encoding]::UTF8)
        Write-Info "已同步更新 Pi Agent 配置: $cfgPath"
    } catch {
        Write-WarnMsg "写入 Pi Agent config.json 警告: $_"
    }
}

function Set-ProviderRoute {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderKey,
        [string]$ApiKey,
        [string]$CustomBaseUrl,
        [string]$Scope = "User"
    )

    $providersCfg = Get-ProvidersConfig
    if (-not $providersCfg.providers.PSObject.Properties[$ProviderKey]) {
        Write-ErrorMsg "未知的模型厂商路由标识: $ProviderKey"
        Write-Info "支持的厂商标识: $($providersCfg.providers.PSObject.Properties.Name -join ', ')"
        return $false
    }

    $provider = $providersCfg.providers.$ProviderKey
    Write-Info "正在切换并同步大模型厂商路由为: $($provider.name) [$ProviderKey]"

    # 1. Claude Code 同步
    $claudeBaseUrl = if ($CustomBaseUrl) { $CustomBaseUrl } else { $provider.claudeCode.baseUrl }
    Sync-ClaudeCodeConfig -BaseUrl $claudeBaseUrl -ApiKey $ApiKey -Scope $Scope

    # 2. OpenAI Codex 同步
    $codexBaseUrl = if ($CustomBaseUrl) { $CustomBaseUrl } else { $provider.openaiCodex.baseUrl }
    $codexModel = $provider.openaiCodex.model
    Sync-OpenAICodexConfig -BaseUrl $codexBaseUrl -ApiKey $ApiKey -Model $codexModel -Scope $Scope

    # 3. OpenClaw 同步
    $openclawUrl = if ($CustomBaseUrl) { $CustomBaseUrl } else { $provider.openclaw.gatewayUrl }
    $openclawModel = $provider.openclaw.model
    Sync-OpenClawConfig -GatewayUrl $openclawUrl -ApiKey $ApiKey -Model $openclawModel -Scope $Scope

    # 4. Pi Agent 同步
    $piBaseUrl = if ($CustomBaseUrl) { $CustomBaseUrl } else { $provider.piAgent.baseUrl }
    $piModel = $provider.piAgent.model
    $piProv = $provider.piAgent.provider
    Sync-PiAgentConfig -BaseUrl $piBaseUrl -ApiKey $ApiKey -Provider $piProv -Model $piModel -Scope $Scope

    # 5. CC Switch 对接与持久化联动
    $ccSwitchDir = Get-CCSwitchConfigDir
    $ccActiveRouteFile = Join-Path $ccSwitchDir "active_route.json"
    $activeRecord = @{
        activeProviderId = $ProviderKey
        providerName     = $provider.name
        baseUrl          = $claudeBaseUrl
        hasApiKey        = [bool]$ApiKey
        updatedAt        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    try {
        $json = $activeRecord | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($ccActiveRouteFile, $json, [System.Text.Encoding]::UTF8)
        Write-Info "已同步 CC Switch 路由元数据: $ccActiveRouteFile"
    } catch {}

    # 6. 保存 settings.json
    $settings = Get-SettingsConfig
    $settings.activeProvider = $ProviderKey
    Save-SettingsConfig -Settings $settings | Out-Null

    Write-Success ">> 厂商路由已成功切换为 [$($provider.name)]！所有受管 Agent 配置及环境变量已完成统一热生效。"
    return $true
}

function Get-ActiveProviderInfo {
    $settings = Get-SettingsConfig
    $key = $settings.activeProvider
    $providers = Get-ProvidersConfig
    if ($providers -and $providers.providers.PSObject.Properties[$key]) {
        return @{
            Key  = $key
            Name = $providers.providers.$key.name
            Desc = $providers.providers.$key.description
        }
    }
    return @{
        Key  = $key
        Name = $key
        Desc = "当前激活厂商"
    }
}

Export-ModuleMember -Function Get-ProvidersConfig, Get-SettingsConfig, Save-SettingsConfig, Set-ProviderRoute, Get-ActiveProviderInfo
