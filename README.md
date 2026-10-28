# agent-installer: Windows 主流 AI Agent 自动化安装与 CC Switch 统一路由调度中心

`agent-installer` 是一款专为 Windows 开发者与运维工程师打造的生产级 PowerShell 工具套件。一键全自动安装并管理主流 AI Coding Agent（**OpenClaw**、**OpenAI Codex**、**Claude Code**、**Pi Agent**），并深度联动 **CC Switch** 实现全套 Agent 的大模型厂商路由一处切换、全端即时热生效。

---

## 🌟 核心特性

- 🤖 **主流 AI Agent 矩阵支持**：
  - **OpenClaw** (`openclaw`)：全自主通用 Agent 引擎与网关
  - **OpenAI Codex** (`@openai/codex` -> `codex`)：OpenAI 官方终端编程与代码生成 Agent
  - **Claude Code** (`@anthropic-ai/claude-code` -> `claude`)：Anthropic 官方终端全自主代码研发 Agent
  - **Pi Agent** (`@earendil-works/pi-coding-agent` -> `pi`)：极简高扩展终端编程 Agent & TUI
- 🔀 **CC Switch 深度联动 & 统一模型路由**：
  - “**一处切换，四端齐通**”：通过命令行或菜单一键将厂商路由（官方、DeepSeek、SiliconFlow 硅基流动、OpenRouter、自建 OneAPI/NewAPI）同步注入到 Claude Code、Codex、OpenClaw、Pi Agent 对应配置体系与 Windows 环境变量。
  - 自动探测并一键部署开源管理神器 **CC Switch**（`farion1231/cc-switch`）桌面客户端。
- 🛠️ **Windows 环境工程自愈与 Node.js 兜底安装**：
  - **三级故障自动转移（Failover）安装 Node.js**：若目标机未装 Node.js 或安装失败，脚本将按顺序自动降级重试：
    1. **Tier 1 (首选 Winget)**：调用官方包管理器 `winget install OpenJS.NodeJS.LTS` 静默安装；
    2. **Tier 2 (官方/镜像源 MSI 无人值守)**：从国内 npmmirror 镜像或 Node.js 官网拉取最新 LTS MSI 安装包，使用 `msiexec /i ... /qn` 静默安装；
    3. **Tier 3 (免提权绿色便携版 Portable Zip)**：在受限、无管理员提权或组策略拦截的环境下，自动下载免安装版解压至 `%LOCALAPPDATA%\Programs\nodejs` 并自动注入用户 PATH，彻底免管理员权限可用！
  - 彻底根治 Windows 下常见“npm 全局安装后命令找不到”的痛点：自动将 `%APPDATA%\npm` 安全注入系统用户级与当前会话 `PATH`。
  - 支持一键切换国内极速 npm 镜像源（npmmirror 淘宝镜像、腾讯云镜像）。
- 💻 **双模兼容 & 极简体验**：
  - 完美兼容 **Windows PowerShell 5.1** 与 **PowerShell 7+ (Core)**。
  - ANSI 彩色终端仪表板、动态菜单交互，兼具完整的免交互命令行参数批量运维能力。

---

## 🏗️ 架构与路由注入原理

```text
agent-installer/
├── agent-installer.ps1          # 主入口控制台 CLI（日常运维、路由切换、状态看板）
├── Install.ps1                  # 本地/离线环境全自动一键安装脚本
├── bootstrap.ps1                # 极简网络远程引导脚本 (支持单行命令无痛启动)
├── config/
│   ├── providers.json           # 预设厂商模型与端点模板 (Anthropic/OpenAI/DeepSeek等)
│   └── settings.json            # 工具全局偏好设置
├── modules/
│   ├── UI.psm1                  # 终端控制、彩色格式化、TUI 交互菜单与日志系统
│   ├── Prerequisites.psm1       # 依赖检测（Node.js/npm/Git）、自动修复与 PATH 注入
│   ├── AgentRegistry.psm1       # 4大 Agent 的元定义、安装、升级、自检、卸载
│   ├── CCSwitch.psm1            # CC Switch 安装包拉取、安装与状态探测
│   └── ConfigManager.psm1       # 路由配置解析、各 Agent 配置文件写入与环境变量同步
├── tests/
│   └── agent-installer.Tests.ps1 # Pester 自动化测试套件
└── README.md                    # 项目文档
```

### 统一厂商路由注入映射表

| Agent | 核心 CLI 命令 | 配置文件位置 | 关键环境变量 / 配置键 |
| :--- | :--- | :--- | :--- |
| **Claude Code** | `claude` | `~/.claude/settings.json`<br/>`~/.claude.json` | `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` |
| **OpenAI Codex** | `codex` | `~/.codex/config.json` | `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `model` |
| **OpenClaw** | `openclaw` | `~/.openclaw/config.json` | `OPENCLAW_GATEWAY_URL`, `OPENCLAW_API_KEY` |
| **Pi Agent** | `pi` | `~/.pi/agent/config.json` | `PI_BASE_URL`, `OPENAI_BASE_URL`, `model` |
| **CC Switch** | `cc-switch` | `~/.cc-switch/active_route.json` | 桌面管理面板 + 规则仓库联动 |

---

## 🚀 快速上手

### 1. 本地一键安装

在项目根目录下打开 PowerShell 执行：

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\Install.ps1
```

向导将自动执行：
1. 校验并自愈 Node.js、npm 与 Git 环境；
2. 校验并自动修复 npm 全局 PATH 环境变量；
3. 全自动并发/批量安装 4 款主流 AI Agent；
4. 初始化默认厂商路由并启动控制台。

### 2. 启动交互式控制台

```powershell
.\agent-installer.ps1
```

控制台将呈现系统状态总览与 4 款 Agent 的安装版本矩阵，输入数字即可执行相应操作：
- `1`: 一键全自动安装所有 AI Agent
- `2`: 自选安装 / 升级特定 AI Agent
- `3`: 切换大模型厂商路由 (统一多端同步)
- `4`: 一键安装 / 启动 CC Switch 桌面控制中心
- `5`: 环境 Doctor 诊断与自愈修复
- `6`: 切换 npm 镜像源 (国内极速镜像源 / 官方源)
- `7`: 卸载指定 Agent
- `0`: 退出工具

---

## ⚙️ 命令行静默参数用法（自动化脚本运维）

`agent-installer.ps1` 支持直接传入参数进行免交互批量执行：

```powershell
# 1. 运行环境与 Agent 健康自检诊断 (Doctor)
.\agent-installer.ps1 -Doctor

# 2. 静默批量安装全部 4 款 AI Agent
.\agent-installer.ps1 -InstallAll

# 3. 指定安装特定 Agent (如 Claude Code 和 Pi Agent)
.\agent-installer.ps1 -Install -Agents "claude-code", "pi-agent"

# 4. 统一切换大模型厂商路由 (例: 切换至 DeepSeek)
.\agent-installer.ps1 -SwitchProvider deepseek -ApiKey "sk-your-deepseek-key"

# 5. 统一切换到自建 OneAPI / NewAPI 中转站
.\agent-installer.ps1 -SwitchProvider custom-relay -BaseUrl "http://192.168.1.100:3000/v1" -ApiKey "sk-relay-key"

# 6. 一键切换国内极速 npm 镜像源
.\agent-installer.ps1 -SetRegistry "https://registry.npmmirror.com/"

# 7. 拉起 CC Switch 桌面端
.\agent-installer.ps1 -LaunchCCSwitch
```

---

## 📦 一键编译生成独立 EXE 可执行文件

本项目提供了一个零依赖、利用 Windows 自带编译器的一键打包脚本 [`build-exe.ps1`](file:///D:/CODE/agent_installer/build-exe.ps1)：

```powershell
.\build-exe.ps1
```

- **零外部依赖**：调用系统自带的 `csc.exe` 编译，不依赖任何第三方加壳或打包软件。
- **源码与配置加密封装**：所有核心脚本、模块与 JSON 配置被压缩编码封入 PE 二进制中，防止小白用户随意窥探或误改。
- **单文件便携运行**：生成体积仅约 **50 KB** 的 [`agent-installer.exe`](file:///D:/CODE/agent_installer/agent-installer.exe)，双击直接启动控制台，彻底免除 Windows PowerShell 执行策略限制！
- **完整参数透传**：支持所有 CLI 命令行参数，如 `.\agent-installer.exe -Doctor`、`.\agent-installer.exe -SwitchProvider deepseek` 等。

---

## 🧪 自动化测试验证

项目内置 Pester 单元与集成测试套件：

```powershell
powershell -ExecutionPolicy Bypass -Command "Invoke-Pester .\tests\agent-installer.Tests.ps1"
```

测试覆盖：
- 模块载入与语法完整性
- 预设厂商配置文件（`providers.json` / `settings.json`）格式校验
- 4 款 Agent 注册表元数据与命令绑定
- 运行时依赖探针与自愈逻辑
- 统一厂商路由切换与各 Agent 配置目录 / 环境变量注入下发

---

## 📄 开源许可证

MIT License.
