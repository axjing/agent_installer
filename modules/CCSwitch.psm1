# modules/CCSwitch.psm1
# CC Switch (farion1231/cc-switch) 集成、五重全域智能检测与生命周期管理模块

Import-Module (Join-Path $PSScriptRoot "UI.psm1") -DisableNameChecking

$script:CCSwitchRepo = "farion1231/cc-switch"

function Get-CCSwitchConfigDir {
    $dir = Join-Path $env:USERPROFILE ".cc-switch"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Find-CCSwitchExecutable {
    <#
    .SYNOPSIS
        在任何 Windows 10+ 机器上全域检索 CC Switch 可执行文件路径
        支持进程、PATH、开始菜单/桌面快捷方式解析、注册表 Uninstall 项及常用矩阵扫描
    #>

    # 1. 进程探针（若正在运行，直接精确定位运行中实例的绝对路径）
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "cc.*switch|^cc-switch$" }
        foreach ($p in $procs) {
            if ($p.Path -and (Test-Path $p.Path)) {
                return $p.Path
            }
        }
    } catch {}

    # 2. PATH 环境变量探针
    $cmdCandidates = @("cc-switch.exe", "cc-switch", "CC Switch.exe", "CC Switch", "ccswitch.exe")
    foreach ($cand in $cmdCandidates) {
        try {
            $cmd = Get-Command $cand -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
                return $cmd.Source
            }
        } catch {}
    }

    # 3. 开始菜单与桌面快捷方式解析探针 (覆盖用户自定义盘符与任意安装路径)
    $shortcutDirs = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:PUBLIC "Desktop")
    )

    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($sDir in $shortcutDirs) {
            if (-not (Test-Path $sDir)) { continue }
            $lnks = Get-ChildItem -Path $sDir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match "cc.*switch|ccswitch"
            }
            foreach ($lnk in $lnks) {
                try {
                    $target = $wsh.CreateShortcut($lnk.FullName).TargetPath
                    if ($target -and (Test-Path $target) -and ($target.EndsWith(".exe"))) {
                        return $target
                    }
                } catch {}
            }
        }
    } catch {}

    # 4. Windows 注册表 Uninstall 卸载信息探针 (覆盖 64位/32位/当前用户)
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    try {
        $installedApps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match "CC Switch|cc-switch|ccswitch" -or $_.PSChildName -match "cc-switch|CC Switch"
        }
        foreach ($app in $installedApps) {
            # 从 DisplayIcon 提取（通常指向 exe）
            if ($app.DisplayIcon) {
                $iconPath = $app.DisplayIcon.Trim('"').Split(',')[0]
                if ($iconPath.EndsWith(".exe") -and (Test-Path $iconPath)) {
                    return $iconPath
                }
            }
            # 从 InstallLocation 递归查找 exe
            if ($app.InstallLocation -and (Test-Path $app.InstallLocation)) {
                $exe = Get-ChildItem -Path $app.InstallLocation -Filter "*.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match "cc.*switch" } | Select-Object -First 1
                if ($exe) {
                    return $exe.FullName
                }
            }
        }
    } catch {}

    # 5. 全盘常用安装目录与二进制命名矩阵扫描 (涵盖空格与连字符的全部排列)
    $baseDirs = @(
        $env:LOCALAPPDATA,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:APPDATA,
        "C:", "D:", "E:"
    )
    $subDirs = @(
        "Programs\CC Switch",
        "Programs\cc-switch",
        "CC Switch",
        "cc-switch"
    )
    $exeNames = @(
        "cc-switch.exe",
        "CC Switch.exe",
        "ccswitch.exe"
    )

    foreach ($b in $baseDirs) {
        if (-not $b -or -not (Test-Path $b)) { continue }
        foreach ($s in $subDirs) {
            $folder = Join-Path $b $s
            if (-not (Test-Path $folder)) { continue }
            foreach ($e in $exeNames) {
                $candidate = Join-Path $folder $e
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

function Get-CCSwitchStatus {
    $result = @{
        Installed = $false
        Path      = $null
        ConfigDir = (Get-CCSwitchConfigDir)
        HasConfig = $false
    }

    $foundPath = Find-CCSwitchExecutable
    if ($foundPath) {
        $result.Installed = $true
        $result.Path      = $foundPath
    }

    # 检查配置目录与数据库
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
            Write-Success "CC Switch 安装成功！路径: $($newStatus.Path)"
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
        Write-Info "正在拉起 CC Switch 客户端 ($($status.Path))..."
        Start-Process -FilePath $status.Path
        return $true
    } else {
        Write-WarnMsg "未找到 CC Switch 可执行文件，请先安装。"
        return $false
    }
}

Export-ModuleMember -Function Get-CCSwitchConfigDir, Get-CCSwitchStatus, Find-CCSwitchExecutable, Install-CCSwitch, Start-CCSwitchApp
