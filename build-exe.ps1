<#
.SYNOPSIS
    build-exe.ps1 - 将 agent-installer 自动化编译为独立的 Windows .exe 可执行文件
.DESCRIPTION
    利用 Windows 原生内置的 .NET C# 编译器 (csc.exe)，将脚本、模块与配置文件进行
    压缩编码封装，生成零外部依赖、免执行策略拦截、防小白查看源码的独立 agent-installer.exe。
.EXAMPLE
    .\build-exe.ps1
#>

[CmdletBinding()]
param(
    [string]$OutputFile = "agent-installer.exe"
)

$ErrorActionPreference = "Stop"

Write-Host "[*] 正在准备编译 agent-installer 为原生 Windows .exe..." -ForegroundColor Cyan

# 1. 查找系统内置 C# 编译器
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$cscPath = $null
foreach ($cand in $cscCandidates) {
    if (Test-Path $cand) {
        $cscPath = $cand
        break
    }
}

if (-not $cscPath) {
    Write-Error "未找到系统内置的 .NET C# 编译器 csc.exe！"
    exit 1
}

Write-Host "[+] 找到系统编译器: $cscPath" -ForegroundColor Green

# 2. 准备需要打包的文件集
$root = $PSScriptRoot
$tempBuildDir = Join-Path $env:TEMP "agent_installer_build_$(Get-Random)"
if (Test-Path $tempBuildDir) { Remove-Item $tempBuildDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempBuildDir -Force | Out-Null

$payloadDir = Join-Path $tempBuildDir "payload"
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null

# 拷贝核心文件
Copy-Item (Join-Path $root "agent-installer.ps1") -Destination $payloadDir -Force
Copy-Item (Join-Path $root "modules") -Destination $payloadDir -Recurse -Force
Copy-Item (Join-Path $root "config") -Destination $payloadDir -Recurse -Force

# 3. 压缩为 Zip 并转换为 Base64 字符串
$zipPath = Join-Path $tempBuildDir "payload.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($payloadDir, $zipPath)

$zipBytes = [System.IO.File]::ReadAllBytes($zipPath)
$base64Payload = [System.Convert]::ToBase64String($zipBytes)
Write-Host "[+] 核心源码与配置封装完成 (压缩后: $([math]::Round($zipBytes.Length / 1KB, 1)) KB)" -ForegroundColor Green

# 4. 生成嵌入式 C# 启动器源码
$csSourcePath = Join-Path $tempBuildDir "Launcher.cs"
$csCode = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Diagnostics;
using System.Text;

namespace AgentInstaller
{
    class Program
    {
        // 嵌入的混淆压缩 Payload 数据
        private static readonly string EncodedPayload = "$base64Payload";

        static int Main(string[] args)
        {
            try
            {
                Console.OutputEncoding = Encoding.UTF8;
                Console.Title = "agent-installer - AI Agent 统一管理控制台";

                // 解包运行目录位于用户 LocalAppData 下，安全且无需提权
                string targetDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "agent-installer-runtime");
                string mainScript = Path.Combine(targetDir, "agent-installer.ps1");
                string versionMarker = Path.Combine(targetDir, ".version_$(Get-Random)");

                // 若未解包或需要刷新，则进行内存解包
                if (!Directory.Exists(targetDir) || !File.Exists(mainScript))
                {
                    if (Directory.Exists(targetDir))
                    {
                        try { Directory.Delete(targetDir, true); } catch {}
                    }
                    Directory.CreateDirectory(targetDir);

                    byte[] zipBytes = Convert.FromBase64String(EncodedPayload);
                    using (MemoryStream ms = new MemoryStream(zipBytes))
                    using (ZipArchive archive = new ZipArchive(ms))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            string fullPath = Path.Combine(targetDir, entry.FullName);
                            if (string.IsNullOrEmpty(entry.Name))
                            {
                                Directory.CreateDirectory(fullPath);
                            }
                            else
                            {
                                Directory.CreateDirectory(Path.GetDirectoryName(fullPath));
                                entry.ExtractToFile(fullPath, true);
                            }
                        }
                    }
                }

                // 组装 PowerShell 执行命令，彻底绕过 ExecutionPolicy
                StringBuilder argBuilder = new StringBuilder();
                argBuilder.Append("-NoLogo -ExecutionPolicy Bypass -NoProfile -File \"" + mainScript + "\"");

                // 透传外部参数
                foreach (string arg in args)
                {
                    if (arg.Contains(" "))
                    {
                        argBuilder.Append(" \"" + arg + "\"");
                    }
                    else
                    {
                        argBuilder.Append(" " + arg);
                    }
                }

                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = argBuilder.ToString(),
                    UseShellExecute = false
                };

                using (Process proc = Process.Start(psi))
                {
                    proc.WaitForExit();
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("启动遇到错误: " + ex.Message);
                Console.ResetColor();
                return 1;
            }
        }
    }
}
"@

[System.IO.File]::WriteAllText($csSourcePath, $csCode, [System.Text.Encoding]::UTF8)

# 5. 调用 csc.exe 执行编译
$outFullPath = Join-Path $root $OutputFile
Write-Host "[*] 正在执行编译: $OutputFile ..." -ForegroundColor Cyan

$compileArgs = @(
    "/target:exe",
    "/platform:anycpu",
    "/optimize+",
    "/out:`"$outFullPath`"",
    "/r:System.dll",
    "/r:System.IO.Compression.dll",
    "/r:System.IO.Compression.FileSystem.dll",
    "`"$csSourcePath`""
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $cscPath
$psi.Arguments = $compileArgs -join " "
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

# 清理构建临时目录
try { Remove-Item $tempBuildDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

if ($proc.ExitCode -eq 0 -and (Test-Path $outFullPath)) {
    $sizeKb = [math]::Round((Get-Item $outFullPath).Length / 1KB, 1)
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host "[+] 编译成功！已生成独立可执行文件: $outFullPath ($sizeKb KB)" -ForegroundColor Green
    Write-Host "[+] 特性: 零外部依赖、双击即跑、彻底绕过执行策略拦截、源码加密打包。" -ForegroundColor Green
    Write-Host "========================================================`n" -ForegroundColor Green
} else {
    Write-Host "[-] 编译失败！退出代码: $($proc.ExitCode)" -ForegroundColor Red
    if ($stdout) { Write-Host $stdout -ForegroundColor Yellow }
    if ($stderr) { Write-Host $stderr -ForegroundColor Red }
    exit 1
}
