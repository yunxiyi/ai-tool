# Agent Resource Manager — 设计文档

## 概述

跨 Agent 平台（Codex、Claude Code、OpenCode）的 skill/mcp/plugin 资源管理工具。
一个清单声明期望状态，自动完成收集（list）和安装（install）。

## 范围

| 平台 | skill | mcp | plugin |
|------|-------|-----|--------|
| **Codex** (`~/.codex/`) | ✅ 软链 | ✅ 追加 toml | ✅ 追加 toml |
| **Claude Code** (`~/.claude/`) | ✅ marketplace | ✅ 编辑 mcp.json | ✅ 编辑 settings.json + installed_plugins.json |
| **OpenCode** (`~/.config/opencode/`) | ✅ 编辑 json | ✅ 编辑 json | ⚠️ npm 机制 |

TRAE 不在本工具范围内。

## 目录结构

```
zshrc/
├── manage.sh                    # 主入口
├── lib/
│   ├── common.sh                # 日志/颜色/平台检测/幂等
│   ├── manifest.sh              # 解析 manifest.toml
│   ├── resource.sh              # 资源安装 handler（local/git/go_install/npm_install/none）
│   └── platform/
│       ├── codex.sh             # Codex 适配器
│       ├── claude.sh            # Claude Code 适配器
│       └── opencode.sh          # OpenCode 适配器
├── manifest.toml                # 清单：声明所有组件
├── resources/
│   ├── skills/                  # vendor 的 skill 源文件
│   ├── mcp/                     # mcp 元信息模板
│   └── plugins/                 # plugin 元信息模板
└── tests/
    └── test_install.sh
```

## 命令模型

```
./manage.sh <command> [--platform <name>] [--type <skill|mcp|plugin>] [name]
```

| 命令 | 功能 |
|------|------|
| `list` | 收集各平台已装资源 vs 清单差异 |
| `install` | 安装所有缺失资源 |
| `uninstall` | 卸载指定资源 |
| `update` | 更新已装资源 |
| `doctor` | 环境检查 |

可用参数：
- `--platform codex|claude|opencode` 限定单平台
- `--type skill|mcp|plugin` 限定资源类型
- 未指定则对所有已检测到的平台/类型操作

## 适配器契约

每个 `lib/platform/<name>.sh` 必须实现以下函数：

```
list_installed()       → 输出已装资源列表（每行: type name version）
install_skill(name)    → 将 skill 安装到该平台
install_mcp(name)      → 将 mcp server 配置到该平台
install_plugin(name)   → 将 plugin 安装到该平台
uninstall_skill(name)  → 从该平台卸载 skill
uninstall_mcp(name)    → 从该平台移除 mcp 配置
uninstall_plugin(name) → 从该平台卸载 plugin
```

## manifest.toml 格式

```toml
[skills.brainstorming]
source = { type = "local", path = "resources/skills/brainstorming" }

[skills.superpowers]
source = { type = "git", repo = "obra/superpowers", ref = "main", path = "skills/" }

[skills.andrej-karpathy-skills]
source = { type = "git", repo = "forrestchang/andrej-karpathy-skills", ref = "main" }

[mcp.codegraph]
command = "codegraph"
args = ["serve", "--mcp"]
install = { type = "go_install", path = "github.com/xyz/codegraph@latest" }

[mcp.deepwiki]
url = "https://mcp.deepwiki.com/mcp"
install = { type = "none" }

[mcp.node_repl]
command = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl"
args = []
install = { type = "none" }

[plugins.superpowers]
source = { type = "marketplace", name = "superpowers-marketplace", repo = "obra/superpowers-marketplace" }

[plugins.ralph-wiggum]
source = { type = "marketplace", name = "claude-code-plugins", repo = "anthropics/claude-code" }
```

## 资源安装 handler 体系

`lib/resource.sh` 按 source.type 分发到不同安装策略：

| source.type | 行为 | 说明 |
|-------------|------|------|
| `local` | 复制本地文件 | skills vendor 在仓库中，直接复制到目标 |
| `git` | `git clone` | 克隆仓库到缓存目录，可按 `ref` 指定分支/tag，按 `path` 取子目录 |
| `go_install` | `go install <path>` | `path` 是 Go module 路径（如 `github.com/xyz/codegraph@latest`），安装到 `$GOPATH/bin` 或 `$GOBIN` |
| `npm_install` | `npm install -g <pkg>` | 全局安装 npm 包 |
| `none` | 无操作，仅配置 | URL 型 mcp 服务（如 deepwiki），无需本地二进制 |
| `marketplace` | 克隆 marketplace 到缓存 | 专用于 Claude Code 的插件市场系统，克隆 repo 到 `~/.claude/plugins/marketplaces/<name>`，再写 `installed_plugins.json` 注册 |

安装流程分两步：
1. `install_resource()` → 获取资源（clone/下载/编译/无操作），缓存到本地
2. 调平台适配器 → 将缓存的资源配置到目标平台

## 各平台适配器实现要点

### Codex (`lib/platform/codex.sh`)

- **skill**: `ln -sfn <src> ~/.codex/skills/<name>`
- **mcp**: 追加 `[mcp_servers.<name>]` 段到 `~/.codex/config.toml`
- **plugin**: 追加 `[plugins."<name>@<marketplace>"]` 段到 `~/.codex/config.toml`

### Claude Code (`lib/platform/claude.sh`)

- **skill**: 通过 marketplace 机制，更新 `~/.claude/settings.json` 的 `enabledPlugins` + `extraKnownMarketplaces`，以及 `~/.claude/plugins/installed_plugins.json`
- **mcp**: 编辑 `~/.claude/mcp.json` 的 `mcpServers` 对象
- **plugin**: 同 skill，通过 marketplace 安装

### OpenCode (`lib/platform/opencode.sh`)

- **skill**: 编辑 `~/.config/opencode/opencode.json` 的 `skills.paths` 数组，或通过 plugin 方式注入（如 superpowers 的 `superpowers.js` 插件）
- **mcp**: 编辑 `~/.config/opencode/opencode.json` 的 mcp server 配置（需先确认 opencode.json schema 中 mcp 配置的字段名）
- **plugin**: npm 包机制，编辑 `~/.opencode/package.json` 添加依赖 + `npm install`，或通过 `~/.config/opencode/opencode.json` 的 plugin 配置注册

## list 输出格式

```
$ ./manage.sh list

Codex:
  skills:  super-ralph ✓
  mcp:     codegraph ✓, deepwiki ✓, node_repl ✓
  plugins: documents ✓, chrome ✓, pdf ✓

Claude Code:
  skills:  superpowers ✓, ralph-wiggum ✓, gopls-lsp ✓
  mcp:     codegraph ✓
  plugins: superpowers ✓, ralph-wiggum ✓

OpenCode:
  skills:  (via opencode.json skills.paths)
  mcp:     (via opencode.json)
  plugins: (npm)

=== 差异对比 ===
  codex/skill/superpowers:   清单有，未安装
  claude/mcp/deepwiki:       清单有，未安装
```

## 后续

- 首版实现：`list` + `install`（幂等）
- 后续：`update` + `uninstall` + `doctor`