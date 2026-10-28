# modules/Prerequisites.psm1
# 先决依赖检查、自愈与系统环境修复模块

Import-Module (Join-Path $PSScriptRoot "UI.psm1") -DisableNameChecking

function Refresh-EnvironmentVariables {
    # 重新加载 Machine 和 User 级别的 PATH 到当前进程
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $combined    = "$userPath;$machinePath"
    $env:PATH    = $combined
    Write-Info "已实时刷新当前会话环境变量 PATH"
}

function Get-PrerequisitesStatus {
    $status = @{
        NodeInstalled = $false
        NodeVersion   = $null
        NpmInstalled  = $false
        NpmVersion    = $null
        GitInstalled   = $false
        GitVersion    = $null
        NpmGlobalPath = $null
        NpmPathValid  = $false
        ExecutionPolicy = (Get-ExecutionPolicy -Scope Process)
    }

    # 1. 检查 Node.js
    try {
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $nodeVerRaw = (& node -v) 2>$null
            if ($nodeVerRaw -match "v?(\d+\.\d+\.\d+)") {
                $status.NodeInstalled = $true
                $status.NodeVersion = $matches[1]
            }
        }
    } catch {}

    # 2. 检查 npm
    try {
        $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $npmVerRaw = (& npm -v) 2>$null
            if ($npmVerRaw -match "(\d+\.\d+\.\d+)") {
                $status.NpmInstalled = $true
                $status.NpmVersion = $matches[1]
            }
        }
    } catch {}

    # 3. 检查 Git
    try {
        $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $gitVerRaw = (& git --version) 2>$null
            if ($gitVerRaw -match "(\d+\.\d+\.\d+)") {
                $status.GitInstalled = $true
                $status.GitVersion = $matches[1]
            }
        }
    } catch {}

    # 4. 检查 npm 全局路径与 PATH
    $npmGlobalDir = Join-Path $env:APPDATA "npm"
    if ($status.NpmInstalled) {
        try {
            $prefix = (& npm config get prefix) 2>$null
            if ($prefix -and (Test-Path $prefix)) {
                $npmGlobalDir = $prefix.Trim()
            }
        } catch {}
    }
    $status.NpmGlobalPath = $npmGlobalDir

    # 判断是否在当前进程 PATH 或用户级 PATH 中
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $processPath = $env:PATH
    if (($processPath -split ";" -contains $npmGlobalDir) -or ($userPath -split ";" -contains $npmGlobalDir)) {
        $status.NpmPathValid = $true
    } else {
        $status.NpmPathValid = $false
    }

    return $status
}

function Repair-NpmGlobalPath {
    param([string]$NpmGlobalDir)

    if (-not $NpmGlobalDir) {
        $NpmGlobalDir = Join-Path $env:APPDATA "npm"
    }

    if (-not (Test-Path $NpmGlobalDir)) {
        try {
            New-Item -ItemType Directory -Path $NpmGlobalDir -Force | Out-Null
            Write-Info "已自动创建 npm 全局目录: $NpmGlobalDir"
        } catch {
            Write-WarnMsg "创建 npm 全局目录失败: $_"
        }
    }

    # 检查并注入当前进程 PATH
    if ($env:PATH -split ";" -notcontains $NpmGlobalDir) {
        $env:PATH = "$NpmGlobalDir;$env:PATH"
        Write-Info "已将 $NpmGlobalDir 临时注入当前终端会话 PATH"
    }

    # 检查并注入系统用户级 PATH
    try {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $pathList = $userPath -split ";" | Where-Object { $_ -ne "" }
        if ($pathList -notcontains $NpmGlobalDir) {
            $newUserPath = "$userPath;$NpmGlobalDir"
            [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
            Write-Success "成功将 $NpmGlobalDir 写入 Windows 用户永久环境变量 PATH！"
            return $true
        } else {
            Write-Info "用户环境变量 PATH 中已存在 $NpmGlobalDir"
            return $true
        }
    } catch {
        Write-ErrorMsg "写入用户环境变量 PATH 失败: $_"
        return $false
    }
}

function Install-NodeJsAuto {
    [CmdletBinding()]
    param(
        [string]$PreferredVersion = "v20.18.0",
        [switch]$ForcePortable
    )

    Write-Info ">>> 正在启动 Node.js 多通道自动化故障转移安装流程..."

    # 架构判断 (x64 / arm64 / x86)
    $arch = if ([System.Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -match "ARM64") { "arm64" } else { "x64" }
    } else {
        "x86"
    }

    $tempDir = Join-Path $env:TEMP "nodejs-installer"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    # ==========================================
    # 策略 1: Windows 官方包管理器 Winget 安装
    # ==========================================
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($winget -and (-not $ForcePortable)) {
        Write-Info "[策略 1/3] 检测到 Windows 包管理器 winget，尝试静默部署 Node.js LTS..."
        try {
            $proc = Start-Process winget -ArgumentList "install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Refresh-EnvironmentVariables
                $st = Get-PrerequisitesStatus
                if ($st.NodeInstalled) {
                    Write-Success "通过 winget 成功自动安装 Node.js (v$($st.NodeVersion))！"
                    return $true
                }
            } else {
                Write-WarnMsg "winget 返回代码 $($proc.ExitCode)，自动无缝降级到策略 2 (MSI 官方静默安装)..."
            }
        } catch {
            Write-WarnMsg "调用 winget 遇到异常: $_，自动降级到策略 2..."
        }
    } else {
        Write-Info "系统未检测到 winget 或指定了降级模式，直接进入策略 2 (MSI 安装包自动化下载)..."
    }

    # ==========================================
    # 策略 2: 官方 / 镜像源 MSI 静默安装包下载
    # ==========================================
    $msiFileName = "node-$PreferredVersion-$arch.msi"
    $msiDest = Join-Path $tempDir $msiFileName

    # 提供多镜像源轮询（国内 npmmirror 镜像优先，保障速度）
    $msiUrls = @(
        "https://npmmirror.com/mirrors/node/$PreferredVersion/$msiFileName",
        "https://nodejs.org/dist/$PreferredVersion/$msiFileName"
    )

    $downloadSuccess = $false
    foreach ($url in $msiUrls) {
        Write-Info "[策略 2/3] 正在从高速镜像下载 MSI 安装包: $url"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $msiDest -UseBasicParsing -TimeoutSec 30
            if (Test-Path $msiDest) {
                $downloadSuccess = $true
                Write-Success "MSI 安装包下载成功 ($((Get-Item $msiDest).Length / 1MB | ForEach-Object { '{0:N1} MB' -f $_ }))"
                break
            }
        } catch {
            Write-WarnMsg "下载 $url 失败，尝试下一节点..."
        }
    }

    if ($downloadSuccess) {
        Write-Info "正在执行 MSI 后台静默无人值守安装 (无需手动点击)..."
        try {
            $msiArgs = "/i `"$msiDest`" /qn /norestart"
            $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                # 检查默认安装路径
                $stdPath = if ($arch -eq "x64") { Join-Path $env:ProgramFiles "nodejs" } else { Join-Path ${env:ProgramFiles(x86)} "nodejs" }
                if ($env:PATH -split ";" -notcontains $stdPath) {
                    $env:PATH = "$stdPath;$env:PATH"
                }
                Refresh-EnvironmentVariables
                $st = Get-PrerequisitesStatus
                if ($st.NodeInstalled) {
                    Write-Success "MSI 静默安装成功！已成功配置 Node.js (v$($st.NodeVersion))！"
                    return $true
                }
            } else {
                Write-WarnMsg "MSI 安装退出代码为 $($p.ExitCode)，可能需要管理员权限或受组策略拦截，自动降级到策略 3 (免提权绿色便携版)..."
            }
        } catch {
            Write-WarnMsg "启动 msiexec 异常: $_，自动降级到策略 3..."
        }
    }

    # ==========================================
    # 策略 3: 绿色免提权便携版 (Portable Zip)
    # ==========================================
    Write-Info "[策略 3/3] 正在使用免提权便携版 (Portable Zip) 自愈方案..."
    $zipFileName = "node-$PreferredVersion-win-$arch.zip"
    $zipDest = Join-Path $tempDir $zipFileName
    $portableTargetDir = Join-Path $env:LOCALAPPDATA "Programs\nodejs"

    $zipUrls = @(
        "https://npmmirror.com/mirrors/node/$PreferredVersion/$zipFileName",
        "https://nodejs.org/dist/$PreferredVersion/$zipFileName"
    )

    $zipDownloadSuccess = $false
    foreach ($zUrl in $zipUrls) {
        Write-Info "正在拉取便携版运行时: $zUrl"
        try {
            Invoke-WebRequest -Uri $zUrl -OutFile $zipDest -UseBasicParsing -TimeoutSec 40
            if (Test-Path $zipDest) {
                $zipDownloadSuccess = $true
                break
            }
        } catch {}
    }

    if ($zipDownloadSuccess) {
        try {
            Write-Info "正在解压并部署便携版至: $portableTargetDir"
            if (Test-Path $portableTargetDir) {
                Remove-Item -Path $portableTargetDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Path $portableTargetDir -Force | Out-Null

            $unzipTemp = Join-Path $tempDir "unpacked"
            if (Test-Path $unzipTemp) { Remove-Item $unzipTemp -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -Path $zipDest -DestinationPath $unzipTemp -Force

            $extractedDir = Get-ChildItem -Path $unzipTemp | Select-Object -First 1
            Copy-Item -Path (Join-Path $extractedDir.FullName "*") -Destination $portableTargetDir -Recurse -Force

            # 注入用户环境变量 PATH
            $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -split ";" -notcontains $portableTargetDir) {
                [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$portableTargetDir", "User")
            }
            $env:PATH = "$portableTargetDir;$env:PATH"

            Refresh-EnvironmentVariables
            $st = Get-PrerequisitesStatus
            if ($st.NodeInstalled) {
                Write-Success "免提权便携版 Node.js 部署成功！版本: v$($st.NodeVersion)"
                return $true
            }
        } catch {
            Write-ErrorMsg "便携版解压部署失败: $_"
        }
    }

    Write-ErrorMsg "三级自愈安装通道均未成功，请检查网络连接或前往 https://nodejs.org 手动下载安装。"
    return $false
}

# 保留向后兼容别名
function Install-NodeJsWithWinget {
    return (Install-NodeJsAuto)
}

function Get-NpmRegistry {
    try {
        $registry = (& npm config get registry) 2>$null
        return $registry.Trim()
    } catch {
        return "https://registry.npmjs.org/"
    }
}

function Set-NpmRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryUrl
    )

    try {
        & npm config set registry $RegistryUrl
        Write-Success "已成功将 npm 镜像源切换为: $RegistryUrl"
        return $true
    } catch {
        Write-ErrorMsg "切换 npm 镜像源失败: $_"
        return $false
    }
}

function Ensure-ExecutionPolicy {
    try {
        $current = Get-ExecutionPolicy -Scope Process
        if ($current -in @("Restricted", "Undefined")) {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
            Write-Info "已将当前进程 ExecutionPolicy 调整为 RemoteSigned"
        }
    } catch {}
}

Export-ModuleMember -Function Get-PrerequisitesStatus, Repair-NpmGlobalPath, Install-NodeJsAuto, Install-NodeJsWithWinget, Refresh-EnvironmentVariables, Get-NpmRegistry, Set-NpmRegistry, Ensure-ExecutionPolicy
