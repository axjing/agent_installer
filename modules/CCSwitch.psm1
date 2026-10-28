# modules/CCSwitch.psm1
# CC Switch (farion1231/cc-switch) 集成、检测与安装管理模块

Import-Module (Join-Path $PSScriptRoot "UI.psm1") -DisableNameChecking

$script:CCSwitchRepo = "farion1231/cc-switch"
$script:PossibleExePaths = @(
    (Join-Path $env:LOCALAPPDATA "Programs\cc-switch\CC Switch.exe"),
    (Join-Path $env:ProgramFiles "CC Switch\CC Switch.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "CC Switch\CC Switch.exe"),
    (Join-Path $env:USERPROFILE "AppData\Local\cc-switch\CC Switch.exe")
)

function Get-CCSwitchConfigDir {
    $dir = Join-Path $env:USERPROFILE ".cc-switch"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-CCSwitchStatus {
    $result = @{
        Installed = $false
        Path      = $null
        ConfigDir = (Get-CCSwitchConfigDir)
        HasConfig = $false
    }

    # 1. 检查环境变量命令
    $cmd = Get-Command "cc-switch" -ErrorAction SilentlyContinue
    if ($cmd) {
        $result.Installed = $true
        $result.Path = $cmd.Source
    } else {
        # 2. 检查常见安装绝对路径
        foreach ($p in $script:PossibleExePaths) {
            if ($p -and (Test-Path $p)) {
                $result.Installed = $true
                $result.Path = $p
                break
            }
        }
    }

    # 3. 检查配置目录状态
    if (Test-Path (Join-Path $result.ConfigDir "cc-switch.db")) {
        $result.HasConfig = $true
    }

    return $result
}

function Install-CCSwitch {
    param([string]$DownloadUrl)

    Write-Info "正在准备安装 CC Switch (多 Agent 模型统一路由器)..."

    $status = Get-CCSwitchStatus
    if ($status.Installed) {
        Write-Success "CC Switch 已经安装在: $($status.Path)"
        return $true
    }

    $tempDir = Join-Path $env:TEMP "cc-switch-installer"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    $installerFile = $null

    if (-not $DownloadUrl) {
        Write-Info "正在从 GitHub 查询 CC Switch 最新 Release..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $headers = @{ "User-Agent" = "agent-installer-ps" }
            $apiUrl = "https://api.github.com/repos/$script:CCSwitchRepo/releases/latest"
            $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop

            # 寻找 Windows 安装包 (.msi 或 .exe)
            $asset = $releaseInfo.assets | Where-Object { $_.name -match "x64.*(setup\.exe|\.msi)" -or $_.name -match "setup\.exe" -or $_.name -match "\.msi" } | Select-Object -First 1
            if ($asset) {
                $DownloadUrl = $asset.browser_download_url
                $installerFile = Join-Path $tempDir $asset.name
                Write-Info "发现最新版本安装包: $($asset.name)"
            }
        } catch {
            Write-WarnMsg "通过 GitHub API 获取最新版本失败: $_"
        }
    }

    if (-not $DownloadUrl) {
        Write-WarnMsg "由于网络或 GitHub API 速率限制，无法自动拉取下载链接。"
        Write-Info "请前往官方地址下载安装 CC Switch: https://github.com/$script:CCSwitchRepo/releases 或 https://ccswitch.io"
        return $false
    }

    if (-not $installerFile) {
        $fileName = [System.IO.Path]::GetFileName($DownloadUrl)
        $installerFile = Join-Path $tempDir $fileName
    }

    Write-Info "开始下载 CC Switch: $DownloadUrl"
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerFile -UseBasicParsing
        Write-Success "安装文件下载成功: $installerFile"

        Write-Info "正在启动安装程序..."
        if ($installerFile.EndsWith(".msi")) {
            Start-Process msiexec.exe -ArgumentList "/i `"$installerFile`" /qn" -Wait
        } else {
            Start-Process -FilePath $installerFile -ArgumentList "/S /SILENT" -Wait
        }

        # 重新检测
        Start-Sleep -Seconds 2
        $newStatus = Get-CCSwitchStatus
        if ($newStatus.Installed) {
            Write-Success "CC Switch 安装成功！"
            return $true
        } else {
            Write-Info "已执行安装包，若为交互式安装，请完成安装向导即可。"
            return $true
        }
    } catch {
        Write-ErrorMsg "下载或安装 CC Switch 失败: $_"
        return $false
    }
}

function Start-CCSwitchApp {
    $status = Get-CCSwitchStatus
    if ($status.Installed -and (Test-Path $status.Path)) {
        Write-Info "正在拉起 CC Switch 客户端..."
        Start-Process -FilePath $status.Path
        return $true
    } else {
        Write-WarnMsg "未找到 CC Switch 可执行文件，请先安装。"
        return $false
    }
}

Export-ModuleMember -Function Get-CCSwitchConfigDir, Get-CCSwitchStatus, Install-CCSwitch, Start-CCSwitchApp
