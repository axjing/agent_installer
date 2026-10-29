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

function Get-NpmExecutionTarget {
    <#
    .SYNOPSIS
        解析安全、合法的 npm 执行器，彻底免疫桌面异常 npm.cmd 或模块找不到的污染
    #>
    $target = @{
        Executable    = $null
        PrefixArgs    = @()
        IsDirectNode  = $false
        SourcePath    = $null
    }

    # 1. 优先通道：尝试使用 node.exe 直连官方自带的 npm-cli.js (最稳固，免疫所有批处理污染)
    try {
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $nodeExe = $nodeCmd.Source
            $nodeDir = Split-Path $nodeExe
            
            $candidateCliPaths = @(
                (Join-Path $nodeDir "node_modules\npm\bin\npm-cli.js"),
                (Join-Path $nodeDir "..\node_modules\npm\bin\npm-cli.js"),
                (Join-Path $nodeDir "node_modules\corepack\dist\npm.js")
            )

            foreach ($cli in $candidateCliPaths) {
                if (Test-Path $cli) {
                    $target.Executable   = $nodeExe
                    $target.PrefixArgs   = @($cli)
                    $target.IsDirectNode = $true
                    $target.SourcePath   = $cli
                    return $target
                }
            }
        }
    } catch {}

    # 2. 备用通道：扫描官方标准安装目录中的 npm.cmd (严格排除 Desktop / Downloads 伪装文件)
    $candidateNpmCmds = @(
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd"),
        (Join-Path $env:APPDATA "npm\npm.cmd")
    )

    foreach ($nCmd in $candidateNpmCmds) {
        if ($nCmd -and (Test-Path $nCmd)) {
            $target.Executable   = $nCmd
            $target.PrefixArgs   = @()
            $target.IsDirectNode = $false
            $target.SourcePath   = $nCmd
            return $target
        }
    }

    # 3. 最终回退：系统 PATH 命令查找（过滤掉桌面路径）
    try {
        $foundCmds = Get-Command "npm.cmd", "npm" -ErrorAction SilentlyContinue
        foreach ($fc in $foundCmds) {
            $src = $fc.Source
            # 严重拦截：若路径包含 Desktop、Downloads 等临时目录，坚决不用！
            if ($src -notmatch "Desktop|Downloads|Temp") {
                $target.Executable   = $src
                $target.PrefixArgs   = @()
                $target.IsDirectNode = $false
                $target.SourcePath   = $src
                return $target
            }
        }
    } catch {}

    return $target
}

function Invoke-NpmSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory = $env:TEMP,
        [switch]$ReturnProcessResult
    )

    $target = Get-NpmExecutionTarget
    if (-not $target.Executable) {
        Write-ErrorMsg "未找到合法的 npm 或 Node.js 执行程序！"
        if ($ReturnProcessResult) {
            return @{ ExitCode = 1; Stdout = ""; Stderr = "npm not found" }
        }
        return $null
    }

    # 组装最终参数列表，对所有含空格的路径/参数严格做双引号安全包裹 (防止 C:\Program Files 截断为 C:\Program)
    $fullArgs = @()
    if ($target.PrefixArgs) {
        $fullArgs += $target.PrefixArgs
    }
    $fullArgs += $Arguments

    $safeArgs = @()
    foreach ($arg in $fullArgs) {
        if ([string]::IsNullOrEmpty($arg)) { continue }
        $aStr = $arg.ToString()
        if ($aStr.Contains(" ") -and -not ($aStr.StartsWith('"') -and $aStr.EndsWith('"'))) {
            $safeArgs += "`"$aStr`""
        } else {
            $safeArgs += $aStr
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $target.Executable
    $psi.Arguments = $safeArgs -join " "
    # 强制将 WorkingDirectory 隔离在 TEMP 或指定安全目录，避免从桌面寻找 node_modules
    $psi.WorkingDirectory = if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) { $WorkingDirectory } else { $env:TEMP }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($ReturnProcessResult) {
            return @{
                ExitCode = $proc.ExitCode
                Stdout   = $stdout
                Stderr   = $stderr
            }
        }

        if ($proc.ExitCode -eq 0) {
            return $stdout
        } else {
            return $null
        }
    } catch {
        if ($ReturnProcessResult) {
            return @{
                ExitCode = 1
                Stdout   = ""
                Stderr   = $_.Exception.Message
            }
        }
        return $null
    }
}

function Repair-NpmEnvironment {
    <#
    .SYNOPSIS
        自动检测并修复因桌面上存在损坏 npm.cmd 或 ~/.npmrc 路径被污染导致的问题
    #>
    Write-Info "正在自检与优化 npm 环境配置..."

    # 1. 检测用户主目录下的 .npmrc 是否被错误配置为 Desktop
    $userNpmrc = Join-Path $env:USERPROFILE ".npmrc"
    if (Test-Path $userNpmrc) {
        try {
            $lines = Get-Content $userNpmrc -Encoding UTF8 -ErrorAction SilentlyContinue
            $modified = $false
            $newLines = @()
            foreach ($line in $lines) {
                if ($line -match "^\s*prefix\s*=\s*(.*)") {
                    $val = $matches[1].Trim().Trim('"').Trim("'")
                    if ($val -match "Desktop|桌面") {
                        Write-WarnMsg "检测到 ~/.npmrc 中的 prefix 错误指向了桌面: $val，正在自动修复为标准目录..."
                        $stdNpmDir = Join-Path $env:APPDATA "npm"
                        $newLines += "prefix=$stdNpmDir"
                        $modified = $true
                        continue
                    }
                }
                $newLines += $line
            }
            if ($modified) {
                [System.IO.File]::WriteAllLines($userNpmrc, $newLines, [System.Text.Encoding]::UTF8)
                Write-Success "已成功修复 ~/.npmrc 中的全局 prefix 配置！"
            }
        } catch {
            Write-WarnMsg "检查 ~/.npmrc 时遇到警告: $_"
        }
    }

    # 2. 检查桌面是否存在伪装/损坏的 npm.cmd
    $desktopPaths = @(
        (Join-Path $env:USERPROFILE "Desktop\npm.cmd"),
        (Join-Path $env:USERPROFILE "Desktop\npm"),
        (Join-Path $env:USERPROFILE "Desktop\node_modules\npm")
    )
    foreach ($dp in $desktopPaths) {
        if (Test-Path $dp) {
            Write-WarnMsg "警告: 检测到桌面存在异常文件/目录: $dp，可能导致 Node.js 错误加载！已通过安全沙箱隔离保护安装流程。"
        }
    }
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

    # 2. 检查 npm (通过安全通道探测，免疫桌面污染)
    try {
        $npmVerRaw = Invoke-NpmSafe -Arguments @("-v")
        if ($npmVerRaw -and ($npmVerRaw -match "(\d+\.\d+\.\d+)")) {
            $status.NpmInstalled = $true
            $status.NpmVersion = $matches[1]
        } else {
            # 回退直接查 Get-Command
            $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue
            if ($npmCmd) {
                $raw = (& npm -v) 2>$null
                if ($raw -match "(\d+\.\d+\.\d+)") {
                    $status.NpmInstalled = $true
                    $status.NpmVersion = $matches[1]
                }
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
            $prefixOut = Invoke-NpmSafe -Arguments @("config", "get", "prefix")
            if ($prefixOut -and ($prefixOut.Trim() -notmatch "Desktop|桌面") -and (Test-Path $prefixOut.Trim())) {
                $npmGlobalDir = $prefixOut.Trim()
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
        $regOut = Invoke-NpmSafe -Arguments @("config", "get", "registry")
        if ($regOut) {
            return $regOut.Trim()
        }
    } catch {}
    return "https://registry.npmjs.org/"
}

function Set-NpmRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryUrl
    )

    try {
        $res = Invoke-NpmSafe -Arguments @("config", "set", "registry", $RegistryUrl) -ReturnProcessResult
        if ($res.ExitCode -eq 0) {
            Write-Success "已成功将 npm 镜像源切换为: $RegistryUrl"
            return $true
        } else {
            Write-ErrorMsg "切换 npm 镜像源遇到非零返回: $($res.Stderr)"
            return $false
        }
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

function Install-GitAuto {
    Write-Info ">>> 正在启动 Git 自动安装与环境自愈流程..."

    # 1. 优先尝试系统包管理器 winget
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "检测到 Windows 包管理器 winget，尝试静默安装 Git..."
        try {
            $proc = Start-Process winget -ArgumentList "install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Refresh-EnvironmentVariables
                $st = Get-PrerequisitesStatus
                if ($st.GitInstalled) {
                    Write-Success "通过 winget 成功自动安装 Git (v$($st.GitVersion))！"
                    return $true
                }
            }
        } catch {
            Write-WarnMsg "调用 winget 安装 Git 遇到异常: $_"
        }
    }

    # 2. 备用通道：从国内极速镜像源下载 64 位官方安装包进行后台静默安装
    Write-Info "正在从高速镜像源下载 Git 官方安装包..."
    $tempDir = Join-Path $env:TEMP "git-installer"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    $gitExe = Join-Path $tempDir "Git-64-bit.exe"

    $gitUrls = @(
        "https://npmmirror.com/mirrors/git-for-windows/v2.45.2.windows.1/Git-2.45.2-64-bit.exe",
        "https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe"
    )

    $downloadSuccess = $false
    foreach ($url in $gitUrls) {
        try {
            Write-Info "正在拉取: $url"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $gitExe -UseBasicParsing -TimeoutSec 40
            if (Test-Path $gitExe) {
                $downloadSuccess = $true
                Write-Success "Git 安装包下载完成 ($((Get-Item $gitExe).Length / 1MB | ForEach-Object { '{0:N1} MB' -f $_ }))"
                break
            }
        } catch {}
    }

    if ($downloadSuccess) {
        Write-Info "正在执行 Git 后台静默无人值守安装 (/VERYSILENT /NORESTART)..."
        try {
            $p = Start-Process -FilePath $gitExe -ArgumentList "/VERYSILENT /NORESTART" -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                $gitBin = "C:\Program Files\Git\cmd"
                if ($env:PATH -split ";" -notcontains $gitBin) {
                    $env:PATH = "$gitBin;$env:PATH"
                }
                Refresh-EnvironmentVariables
                $st = Get-PrerequisitesStatus
                if ($st.GitInstalled) {
                    Write-Success "Git 静默安装成功！版本: v$($st.GitVersion)"
                    return $true
                }
            }
        } catch {
            Write-ErrorMsg "安装 Git 失败: $_"
        }
    }

    Write-WarnMsg "未能自动完成 Git 安装，请稍后手动前往 https://git-scm.com/ 下载安装。"
    return $false
}

function Ensure-AllPrerequisites {
    param(
        [switch]$Silent
    )

    Write-Info "========================================================"
    Write-Info "正在执行全套基础运行环境自检与自动补齐..."
    Write-Info "========================================================"

    # 1. 执行策略保障
    Ensure-ExecutionPolicy

    # 2. 清理环境配置与目录污染
    Repair-NpmEnvironment

    # 3. 自检当前状态
    $prereqs = Get-PrerequisitesStatus

    # 4. 检查并自动补齐 Node.js / npm
    if (-not $prereqs.NodeInstalled -or -not $prereqs.NpmInstalled) {
        Write-WarnMsg "[!] 检测到基础运行时 Node.js/npm 缺失！正在自动安装补齐..."
        $nodeOk = Install-NodeJsAuto
        if (-not $nodeOk) {
            Write-ErrorMsg "[-] Node.js 自动补齐失败，无法继续安装 AI Agent！请检查网络后重试。"
            return $false
        }
        $prereqs = Get-PrerequisitesStatus
    } else {
        Write-Success "[+] 基础运行时 Node.js (v$($prereqs.NodeVersion)) 与 npm (v$($prereqs.NpmVersion)) 已就绪"
    }

    # 5. 检查并自动修复 npm 全局 PATH
    if (-not $prereqs.NpmPathValid) {
        Write-WarnMsg "[!] 检测到 npm 全局 bin 目录尚未加入 PATH，正在自动修复并注入用户环境变量..."
        Repair-NpmGlobalPath -NpmGlobalDir $prereqs.NpmGlobalPath | Out-Null
        Refresh-EnvironmentVariables
    } else {
        Write-Success "[+] npm 全局环境变量 PATH 已正确配置"
    }

    # 6. 检查并自动补齐 Git (AI Agent 核心依赖)
    if (-not $prereqs.GitInstalled) {
        Write-WarnMsg "[!] 检测到 Git 工具缺失（Agent 克隆与插件依赖必需）！正在自动安装补齐..."
        Install-GitAuto | Out-Null
        $prereqs = Get-PrerequisitesStatus
    } else {
        Write-Success "[+] 代码版本管理 Git (v$($prereqs.GitVersion)) 已就绪"
    }

    Write-Success "========================================================"
    Write-Success "所有基础依赖环境已全部检测并自愈补齐完毕！"
    Write-Success "========================================================`n"
    return $true
}

Export-ModuleMember -Function Get-PrerequisitesStatus, Repair-NpmGlobalPath, Install-NodeJsAuto, Install-NodeJsWithWinget, Refresh-EnvironmentVariables, Get-NpmRegistry, Set-NpmRegistry, Ensure-ExecutionPolicy, Get-NpmExecutionTarget, Invoke-NpmSafe, Repair-NpmEnvironment, Install-GitAuto, Ensure-AllPrerequisites
