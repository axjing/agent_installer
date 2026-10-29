# tests/agent-installer.Tests.ps1
# Pester automated test suite for agent-installer

$Script:RootPath = Split-Path $PSScriptRoot -Parent
$Script:ModulesPath = Join-Path $Script:RootPath "modules"

Describe "1. Module Loading and Integrity" {
    It "All core modules should import successfully" {
        $modules = @("UI.psm1", "Prerequisites.psm1", "AgentRegistry.psm1", "CCSwitch.psm1", "ConfigManager.psm1")
        foreach ($m in $modules) {
            $mPath = Join-Path $Script:ModulesPath $m
            (Test-Path $mPath) | Should Be $true
            { Import-Module $mPath -DisableNameChecking -Force } | Should Not Throw
        }
    }
}

Describe "2. Configuration Verification" {
    It "providers.json is valid and contains standard presets" {
        $pPath = Join-Path $Script:RootPath "config\providers.json"
        (Test-Path $pPath) | Should Be $true
        $content = Get-Content $pPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $content.providers | Should Not BeNullOrEmpty
        ($content.providers.PSObject.Properties.Name -contains "anthropic-official") | Should Be $true
        ($content.providers.PSObject.Properties.Name -contains "openai-official") | Should Be $true
        ($content.providers.PSObject.Properties.Name -contains "deepseek") | Should Be $true
        ($content.providers.PSObject.Properties.Name -contains "siliconflow") | Should Be $true
    }

    It "settings.json is valid and readable" {
        $sPath = Join-Path $Script:RootPath "config\settings.json"
        (Test-Path $sPath) | Should Be $true
        $content = Get-Content $sPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $content.activeProvider | Should Not BeNullOrEmpty
    }
}

Describe "3. Agent Registry Specifications" {
    It "Supports all four required AI agents" {
        $supported = Get-SupportedAgents
        ($supported.Count -ge 4) | Should Be $true
        $supported.ContainsKey("openclaw") | Should Be $true
        $supported.ContainsKey("openai-codex") | Should Be $true
        $supported.ContainsKey("claude-code") | Should Be $true
        $supported.ContainsKey("pi-agent") | Should Be $true
    }

    It "Matches each agent with correct executable command" {
        $supported = Get-SupportedAgents
        $supported["openclaw"].Command | Should Be "openclaw"
        $supported["openai-codex"].Command | Should Be "codex"
        $supported["claude-code"].Command | Should Be "claude"
        $supported["pi-agent"].Command | Should Be "pi"
    }
}

Describe "4. Prerequisites and Self-healing" {
    It "Correctly detects system Node.js and npm runtime" {
        $prereqs = Get-PrerequisitesStatus
        $prereqs | Should Not BeNullOrEmpty
        $prereqs.NodeInstalled | Should Be $true
        $prereqs.NpmInstalled | Should Be $true
        $prereqs.NpmGlobalPath | Should Not BeNullOrEmpty
    }

    It "Ensure-AllPrerequisites verifies and readies environment" {
        $ok = Ensure-AllPrerequisites
        $ok | Should Be $true
    }
}

Describe "5. Unified Routing and Configuration Injection" {
    It "Switches route to DeepSeek and injects all configurations" {
        $res = Set-ProviderRoute -ProviderKey "deepseek" -ApiKey "sk-test-token-123456" -Scope "Process"
        $res | Should Be $true

        # Verify environment variables
        $env:ANTHROPIC_BASE_URL | Should Be "https://api.deepseek.com"
        $env:ANTHROPIC_API_KEY | Should Be "sk-test-token-123456"
        $env:OPENAI_BASE_URL | Should Be "https://api.deepseek.com/v1"

        # Verify Claude Code settings
        $claudeSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
        (Test-Path $claudeSettingsPath) | Should Be $true
        $claudeJson = Get-Content $claudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $claudeJson.baseUrl | Should Be "https://api.deepseek.com"

        # Verify OpenAI Codex settings
        $codexPath = Join-Path $env:USERPROFILE ".codex\config.json"
        (Test-Path $codexPath) | Should Be $true
        $codexJson = Get-Content $codexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $codexJson.baseUrl | Should Be "https://api.deepseek.com/v1"

        # Verify OpenClaw settings
        $openclawPath = Join-Path $env:USERPROFILE ".openclaw\config.json"
        (Test-Path $openclawPath) | Should Be $true

        # Verify Pi Agent settings
        $piPath = Join-Path $env:USERPROFILE ".pi\agent\config.json"
        (Test-Path $piPath) | Should Be $true

        # Verify CC Switch metadata
        $ccActive = Join-Path (Get-CCSwitchConfigDir) "active_route.json"
        (Test-Path $ccActive) | Should Be $true
        $ccJson = Get-Content $ccActive -Raw -Encoding UTF8 | ConvertFrom-Json
        $ccJson.activeProviderId | Should Be "deepseek"
    }

    It "Switches back to Anthropic Official cleanly" {
        $res = Set-ProviderRoute -ProviderKey "anthropic-official" -Scope "Process"
        $res | Should Be $true
        $active = Get-ActiveProviderInfo
        $active.Key | Should Be "anthropic-official"
    }
}
