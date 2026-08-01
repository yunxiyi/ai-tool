# Agent Resource Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 跨 Codex/Claude Code/OpenCode 三平台的 skill/mcp/plugin 资源管理工具，支持 list（收集差异）和 install（自动安装）。

**Architecture:** Shell 脚本套件，manifest.toml 声明期望状态，每个平台一个适配器实现安装/收集逻辑。资源获取（git clone/go install 等）与平台配置分离。

**Tech Stack:** bash/zsh, python3 (tomllib 解析 TOML), jq 或 python3 操作 JSON

**Spec:** [docs/specs/2026-08-01-agent-resource-manager-design.md](file:///Users/huangrongchao/go/src/github.com/personal/zshrc/docs/specs/2026-08-01-agent-resource-manager-design.md)

## Global Constraints

- 只支持 Codex、Claude Code、OpenCode 三个平台，不支持 TRAE
- 首版实现 `list` + `install` 两个命令，`uninstall`/`update`/`doctor` 后续
- 幂等：重复运行 `install` 不报错、不重复安装
- 所有平台配置编辑用 python3（非 jq/sed），避免 JSON 格式破坏
- 所有脚本需兼容 bash 3.2+（macOS 默认）和 zsh

---

## File Structure

```
zshrc/
├── manage.sh                    # 主入口：CLI 解析 + dispatch
├── lib/
│   ├── common.sh                # 通用：log_info/log_error/die/detect_platforms
│   ├── manifest.sh              # 解析 manifest.toml → 各平台资源列表
│   ├── resource.sh              # 资源获取：local/git/go_install/npm_install/none/marketplace
│   └── platform/
│       ├── codex.sh             # Codex 适配器
│       ├── claude.sh            # Claude Code 适配器
│       └── opencode.sh          # OpenCode 适配器
├── manifest.toml                # 资源清单
└── tests/
    └── test_install.sh          # 幂等性测试
```

### Task 1: 基础框架 — common.sh + manage.sh 骨架

**Files:**
- Create: `lib/common.sh`
- Create: `manage.sh`

**Interfaces:**
- Produces:
  - `log_info(msg)` / `log_error(msg)` / `die(msg)` — 日志输出
  - `detect_platforms()` → 输出空格分隔的平台名，检测 `~/.codex/config.toml`、`~/.claude/settings.json`、`~/.config/opencode/opencode.json` 是否存在
  - `manage.sh` 骨架：`list` 和 `install` 命令的 dispatch

- [ ] **Step 1: 创建 `lib/common.sh`**

```bash
#!/usr/bin/env bash
# lib/common.sh — 通用工具函数

set -euo pipefail

# 彩色输出（macOS 兼容）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }
die()       { log_error "$*"; exit 1; }

# 检测已安装的平台
# 输出: 空格分隔的平台名列表（codex claude opencode）
detect_platforms() {
  local platforms=()
  [[ -f "$HOME/.codex/config.toml" ]] && platforms+=("codex")
  [[ -f "$HOME/.claude/settings.json" ]] && platforms+=("claude")
  [[ -f "$HOME/.config/opencode/opencode.json" ]] && platforms+=("opencode")
  echo "${platforms[@]}"
}

# 检测平台是否可用
has_platform() {
  local name="$1"
  detect_platforms | grep -qw "$name"
}

# 幂等检查：如果目标已存在则跳过
is_installed() {
  local platform="$1" type="$2" name="$3"
  # 由各平台适配器实现具体检查
  return 1
}
```

- [ ] **Step 2: 创建 `manage.sh` 骨架**

```bash
#!/usr/bin/env bash
# manage.sh — Agent Resource Manager 主入口
# Usage: ./manage.sh <command> [--platform <name>] [--type <skill|mcp|plugin>] [name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LIB_DIR="$SCRIPT_DIR/lib"

# 加载所有模块
source "$LIB_DIR/common.sh"
source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/resource.sh"

# 加载所有平台适配器
for platform in codex claude opencode; do
  adapter="$LIB_DIR/platform/${platform}.sh"
  [[ -f "$adapter" ]] && source "$adapter"
done

# 默认值
PLATFORM=""
RESOURCE_TYPE=""
RESOURCE_NAME=""

# 简化参数解析（支持 --platform / --type / 位置参数）
parse_args() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) PLATFORM="$2"; shift 2 ;;
      --type)     RESOURCE_TYPE="$2"; shift 2 ;;
      -h|--help)  usage; exit 0 ;;
      *)          args+=("$1"); shift ;;
    esac
  done
  COMMAND="${args[0]:-}"
  RESOURCE_NAME="${args[1]:-}"
}

usage() {
  cat <<'EOF'
Usage: ./manage.sh <command> [options] [name]

Commands:
  list             收集各平台已装资源 vs 清单差异
  install          安装所有缺失资源

Options:
  --platform <name>  限定平台 (codex|claude|opencode)
  --type <type>      限定资源类型 (skill|mcp|plugin)
  -h, --help         显示帮助
EOF
}

# 暂存函数（后续任务实现）
cmd_list()    { log_warn "list 命令将在后续任务中实现"; }
cmd_install() { log_warn "install 命令将在后续任务中实现"; }

main() {
  parse_args "$@"

  # 检测可用平台
  PLATFORMS=(${PLATFORM:-$(detect_platforms)})
  [[ ${#PLATFORMS[@]} -eq 0 ]] && die "未检测到任何支持的平台"

  # 加载 manifest
  load_manifest || die "无法加载 manifest.toml"

  case "$COMMAND" in
    list)
      cmd_list
      ;;
    install)
      cmd_install
      ;;
    "")
      usage
      ;;
    *)
      die "未知命令: $COMMAND"
      ;;
  esac
}

main "$@"
```

- [ ] **Step 3: 验证脚本可加载**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
# 暂时注释掉未创建的 source 行，只验证 common.sh 可加载
bash -c 'source lib/common.sh && detect_platforms'
```

Expected: 输出空格分隔的平台名（根据本机已装平台）

- [ ] **Step 4: Commit**

```bash
git add lib/common.sh manage.sh
git commit -m "feat: add common.sh and manage.sh skeleton"
```

---

### Task 2: Manifest 解析 — manifest.sh

**Files:**
- Create: `lib/manifest.sh`
- Create: `manifest.toml`

**Interfaces:**
- Consumes: 无
- Produces:
  - `load_manifest()` — 加载 `$SCRIPT_DIR/manifest.toml`，设置全局变量
  - `get_resources(platform, type)` → 输出该平台+类型的所有资源名（每行一个）
  - `get_resource(name, key)` → 输出指定资源指定字段的值
  - 全局变量 `MANIFEST_SKILLS`、`MANIFEST_MCPS`、`MANIFEST_PLUGINS`（关联数组，key=name, value=序列化的 source 信息）

- [ ] **Step 1: 创建 `manifest.sh` 用 python3 解析 toml**

```bash
#!/usr/bin/env bash
# lib/manifest.sh — 解析 manifest.toml

MANIFEST_PATH=""

load_manifest() {
  MANIFEST_PATH="${1:-$SCRIPT_DIR/manifest.toml}"
  [[ -f "$MANIFEST_PATH" ]] || die "manifest.toml 不存在: $MANIFEST_PATH"

  # 用 python3 的 tomllib（Python 3.11+）或 tomli 解析
  python3 -c "
import sys, json
try:
    import tomllib
    with open('$MANIFEST_PATH', 'rb') as f:
        data = tomllib.load(f)
except ImportError:
    import tomli
    with open('$MANIFEST_PATH', 'rb') as f:
        data = tomli.load(f)
print(json.dumps(data))
" 2>/dev/null || die "manifest.toml 解析失败，需要 Python 3.11+ 或 tomli 包"
}

# 获取某类型所有资源名
# get_resources <type: skill|mcp|plugin>
get_resources() {
  local type="$1"
  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
# TOML 段名: skills, mcp, plugins（mcp 不加 s）
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins'}
section = section_map.get('$type', '${type}s')
for key in data.get(section, {}):
    print(key)
"
}

# 获取资源指定字段
# get_resource_field <name> <field>
get_resource_field() {
  local name="$1" field="$2"
  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
for section in ['skills', 'mcp', 'plugins']:
    if name in data.get(section, {}):
        val = data[section]['$name']
        # 支持点号路径如 'source.type'
        parts = '$field'.split('.')
        for p in parts:
            val = val.get(p, {}) if isinstance(val, dict) else ''
        print(json.dumps(val) if isinstance(val, (dict, list)) else val)
        sys.exit(0)
print('')
" "$name"
}

# 加载时缓存到全局变量
MANIFEST_JSON=""
load_and_cache() {
  MANIFEST_JSON="$(load_manifest "$@")"
}
```

- [ ] **Step 2: 创建初始 `manifest.toml`**

```toml
# manifest.toml — Agent Resource Manager 资源清单
# 声明所有要管理的 skill/mcp/plugin

[skills.brainstorming]
source = { type = "local", path = "resources/skills/brainstorming" }

[skills.superpowers]
source = { type = "git", repo = "obra/superpowers", ref = "main", path = "skills/" }

[skills.andrej-karpathy-skills]
source = { type = "git", repo = "forrestchang/andrej-karpathy-skills", ref = "main" }

[mcp.codegraph]
command = "codegraph"
args = ["serve", "--mcp"]
install = { type = "none" }

[mcp.deepwiki]
url = "https://mcp.deepwiki.com/mcp"
install = { type = "none" }

[plugins.superpowers]
source = { type = "marketplace", name = "superpowers-marketplace", repo = "obra/superpowers-marketplace" }

[plugins.ralph-wiggum]
source = { type = "marketplace", name = "claude-code-plugins", repo = "anthropics/claude-code" }
```

- [ ] **Step 3: 验证 manifest 解析**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
source lib/manifest.sh
MANIFEST_PATH="manifest.toml"
MANIFEST_JSON="$(load_manifest)"
echo "$MANIFEST_JSON" | python3 -m json.tool
```

Expected: 输出 manifest.toml 的 JSON 表示

- [ ] **Step 4: Commit**

```bash
git add lib/manifest.sh manifest.toml
git commit -m "feat: add manifest parser and initial manifest.toml"
```

---

### Task 3: 资源获取 handler — resource.sh

**Files:**
- Create: `lib/resource.sh`

**Interfaces:**
- Consumes: `MANIFEST_JSON`（来自 manifest.sh），`SCRIPT_DIR`
- Produces:
  - `install_resource(name, type)` → 获取资源到本地缓存，返回缓存路径
  - `CACHE_DIR="$SCRIPT_DIR/.cache"` — 资源缓存目录

- [ ] **Step 1: 创建 `lib/resource.sh`**

```bash
#!/usr/bin/env bash
# lib/resource.sh — 资源获取 handler

CACHE_DIR="$SCRIPT_DIR/.cache"

# 获取单个资源到本地缓存
# install_resource <name> <type: skill|mcp|plugin>
# 输出: 缓存路径（如果适用）
install_resource() {
  local name="$1" type="$2"

  # 从 manifest 读 source 信息
  local source_type
  source_type=$(get_resource_field "$name" "source.type")
  [[ -z "$source_type" ]] && die "资源 $name 未找到 source.type"

  mkdir -p "$CACHE_DIR"

  case "$source_type" in
    local)
      local src_path
      src_path=$(get_resource_field "$name" "source.path")
      src_path="$SCRIPT_DIR/$src_path"
      if [[ -d "$src_path" ]]; then
        log_info "资源 $name 已存在: $src_path"
        echo "$src_path"
      else
        die "本地资源路径不存在: $src_path"
      fi
      ;;

    git)
      local repo ref subpath
      repo=$(get_resource_field "$name" "source.repo")
      ref=$(get_resource_field "$name" "source.ref")
      [[ -z "$ref" ]] && ref="main"
      subpath=$(get_resource_field "$name" "source.path")

      local dest="$CACHE_DIR/git/$name"
      if [[ -d "$dest/.git" ]]; then
        log_info "更新 git 仓库: $repo ($ref)"
        (cd "$dest" && git fetch origin && git checkout "$ref" && git pull) 2>/dev/null || true
      else
        log_info "克隆 git 仓库: $repo"
        git clone --depth 1 --branch "$ref" "https://github.com/$repo.git" "$dest"
      fi

      if [[ -n "$subpath" ]]; then
        echo "$dest/$subpath"
      else
        echo "$dest"
      fi
      ;;

    go_install)
      local go_path
      go_path=$(get_resource_field "$name" "install.path")
      log_info "安装 Go 二进制: $go_path"
      if command -v go &>/dev/null; then
        go install "$go_path"
      else
        die "Go 未安装，无法安装 $go_path"
      fi
      echo ""  # 无缓存路径
      ;;

    npm_install)
      local pkg
      pkg=$(get_resource_field "$name" "install.package")
      log_info "安装 npm 包: $pkg"
      npm install -g "$pkg"
      echo ""
      ;;

    none)
      log_info "资源 $name 无需安装（纯配置）"
      echo ""
      ;;

    marketplace)
      local mkt_name mkt_repo
      mkt_name=$(get_resource_field "$name" "source.name")
      mkt_repo=$(get_resource_field "$name" "source.repo")
      local dest="$HOME/.claude/plugins/marketplaces/$mkt_name"
      if [[ -d "$dest/.git" ]]; then
        log_info "更新 marketplace: $mkt_repo"
        (cd "$dest" && git pull) 2>/dev/null || true
      else
        log_info "克隆 marketplace: $mkt_repo"
        mkdir -p "$HOME/.claude/plugins/marketplaces"
        git clone --depth 1 "https://github.com/$mkt_repo.git" "$dest"
      fi
      echo "$dest"
      ;;

    *)
      die "不支持的 source.type: $source_type"
      ;;
  esac
}
```

- [ ] **Step 2: 验证脚本可加载**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
bash -c 'source lib/common.sh && source lib/manifest.sh && source lib/resource.sh && echo "resource.sh loaded OK"'
```

- [ ] **Step 3: Commit**

```bash
git add lib/resource.sh
git commit -m "feat: add resource install handler"
```

---

### Task 4: Codex 平台适配器

**Files:**
- Create: `lib/platform/codex.sh`

**Interfaces:**
- Consumes: `install_resource()`, `MANIFEST_JSON`
- Produces:
  - `codex_list_installed()` — 输出已装资源列表（每行: `type name version`）
  - `codex_install_skill(name)` — 创建软链到 `~/.codex/skills/`
  - `codex_install_mcp(name)` — 追加到 `~/.codex/config.toml`
  - `codex_install_plugin(name)` — 追加到 `~/.codex/config.toml`

- [ ] **Step 1: 创建 `lib/platform/codex.sh`**

```bash
#!/usr/bin/env bash
# lib/platform/codex.sh — Codex 平台适配器

CODEX_HOME="$HOME/.codex"
CODEX_CONFIG="$CODEX_HOME/config.toml"
CODEX_SKILLS_DIR="$CODEX_HOME/skills"

# 列出已安装资源
codex_list_installed() {
  # skills: 列出 ~/.codex/skills/ 下的软链/目录
  if [[ -d "$CODEX_SKILLS_DIR" ]]; then
    for d in "$CODEX_SKILLS_DIR"/*/; do
      [[ -d "$d" ]] && echo "skill $(basename "$d") installed"
    done
  fi

  # mcp: 从 config.toml 提取 [mcp_servers.*] 段
  if [[ -f "$CODEX_CONFIG" ]]; then
    python3 -c "
import configparser, sys
config = configparser.ConfigParser()
config.read('$CODEX_CONFIG')
for section in config.sections():
    if section.startswith('mcp_servers.'):
        name = section.split('.', 1)[1]
        print(f'mcp {name} installed')
    elif section.startswith('plugins.'):
        name = section.split('.', 1)[1]
        print(f'plugin {name} installed')
" 2>/dev/null || true
  fi
}

# 安装 skill
codex_install_skill() {
  local name="$1"
  local src
  src=$(install_resource "$name" "skill")
  [[ -z "$src" || ! -d "$src" ]] && die "skill $name 资源获取失败"

  mkdir -p "$CODEX_SKILLS_DIR"
  local link_path="$CODEX_SKILLS_DIR/$name"

  if [[ -L "$link_path" ]]; then
    local target
    target=$(readlink "$link_path")
    [[ "$target" == "$src" ]] && { log_info "skill $name 已安装"; return 0; }
    rm "$link_path"
  elif [[ -e "$link_path" ]]; then
    log_warn "skill $name 路径已存在但不是软链，跳过"
    return 1
  fi

  ln -sfn "$src" "$link_path"
  log_info "Codex: skill $name 已安装 ($src → $link_path)"
}

# 安装 mcp
codex_install_mcp() {
  local name="$1"
  local command args
  command=$(get_resource_field "$name" "command")
  args=$(get_resource_field "$name" "args")
  [[ -z "$command" ]] && die "mcp $name 缺少 command 字段"

  # 先 install_resource 获取二进制（如果 install.type 不是 none）
  install_resource "$name" "mcp" >/dev/null

  if grep -q "\[mcp_servers.$name\]" "$CODEX_CONFIG" 2>/dev/null; then
    log_info "mcp $name 已在 Codex 配置中"
    return 0
  fi

  cat >> "$CODEX_CONFIG" <<-EOF

[mcp_servers.$name]
type = "stdio"
command = "$command"
args = [$args]
EOF
  log_info "Codex: mcp $name 已配置"
}

# 安装 plugin
codex_install_plugin() {
  local name="$1"
  local mkt_name
  mkt_name=$(get_resource_field "$name" "source.name")

  install_resource "$name" "plugin" >/dev/null

  if grep -q "\[plugins.\"$name@$mkt_name\"\]" "$CODEX_CONFIG" 2>/dev/null; then
    log_info "plugin $name 已在 Codex 配置中"
    return 0
  fi

  cat >> "$CODEX_CONFIG" <<-EOF

[plugins."$name@$mkt_name"]
enabled = true
EOF
  log_info "Codex: plugin $name 已启用"
}
```

- [ ] **Step 2: 验证脚本语法**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
bash -c 'source lib/common.sh && source lib/manifest.sh && source lib/resource.sh && source lib/platform/codex.sh && echo "codex.sh loaded OK"'
```

- [ ] **Step 3: Commit**

```bash
git add lib/platform/codex.sh
git commit -m "feat: add Codex platform adapter"
```

---

### Task 5: Claude Code 平台适配器

**Files:**
- Create: `lib/platform/claude.sh`

**Interfaces:**
- Consumes: `install_resource()`, `MANIFEST_JSON`
- Produces:
  - `claude_list_installed()` — 输出已装资源列表
  - `claude_install_skill(name)` — 注册 marketplace + 启用 plugin
  - `claude_install_mcp(name)` — 编辑 mcp.json
  - `claude_install_plugin(name)` — 注册 marketplace + 启用 plugin

- [ ] **Step 1: 创建 `lib/platform/claude.sh`**

```bash
#!/usr/bin/env bash
# lib/platform/claude.sh — Claude Code 平台适配器

CLAUDE_HOME="$HOME/.claude"
CLAUDE_MCP_JSON="$CLAUDE_HOME/mcp.json"
CLAUDE_SETTINGS_JSON="$CLAUDE_HOME/settings.json"
CLAUDE_INSTALLED_PLUGINS="$CLAUDE_HOME/plugins/installed_plugins.json"

# 列出已安装资源
claude_list_installed() {
  # mcp: 从 mcp.json 的 mcpServers 提取
  if [[ -f "$CLAUDE_MCP_JSON" ]]; then
    python3 -c "
import json
with open('$CLAUDE_MCP_JSON') as f:
    data = json.load(f)
for name in data.get('mcpServers', {}):
    print(f'mcp {name} installed')
" 2>/dev/null || true
  fi

  # plugins: 从 settings.json 的 enabledPlugins 提取
  if [[ -f "$CLAUDE_SETTINGS_JSON" ]]; then
    python3 -c "
import json
with open('$CLAUDE_SETTINGS_JSON') as f:
    data = json.load(f)
for key in data.get('enabledPlugins', {}):
    print(f'plugin {key} installed')
" 2>/dev/null || true
  fi
}

# 安装 mcp
claude_install_mcp() {
  local name="$1"
  local command args
  command=$(get_resource_field "$name" "command")
  args=$(get_resource_field "$name" "args")
  [[ -z "$command" ]] && die "mcp $name 缺少 command 字段"

  install_resource "$name" "mcp" >/dev/null

  # 用 python3 编辑 mcp.json（安全追加，不破坏已有内容）
  python3 -c "
import json
with open('$CLAUDE_MCP_JSON') as f:
    cfg = json.load(f)
if '$name' in cfg.get('mcpServers', {}):
    print('already_installed')
else:
    cfg.setdefault('mcpServers', {})['$name'] = {
        'type': 'stdio',
        'command': '$command',
        'args': [$args]
    }
    with open('$CLAUDE_MCP_JSON', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('installed')
"

  local result=$?
  if [[ $result -eq 0 ]]; then
    log_info "Claude: mcp $name 已配置"
  fi
}

# 安装 plugin/skill（通过 marketplace 机制）
claude_install_plugin() {
  local name="$1"
  local mkt_name mkt_repo
  mkt_name=$(get_resource_field "$name" "source.name")
  mkt_repo=$(get_resource_field "$name" "source.repo")
  [[ -z "$mkt_name" || -z "$mkt_repo" ]] && die "plugin $name 缺少 marketplace 配置"

  install_resource "$name" "plugin" >/dev/null

  # 1. 将 marketplace 注册到 known_marketplaces.json
  local known_mkt="$CLAUDE_HOME/plugins/known_marketplaces.json"
  python3 -c "
import json
with open('$known_mkt') as f:
    mkt = json.load(f)
key = '$mkt_name'
if key not in mkt:
    mkt[key] = {
        'source': {'source': 'github', 'repo': '$mkt_repo'},
        'installLocation': '$HOME/.claude/plugins/marketplaces/$mkt_name',
        'lastUpdated': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'
    }
    with open('$known_mkt', 'w') as f:
        json.dump(mkt, f, indent=2)
" 2>/dev/null

  # 2. 注册到 installed_plugins.json
  local inst_plugins="$CLAUDE_INSTALLED_PLUGINS"
  python3 -c "
import json, os
os.makedirs(os.path.dirname('$inst_plugins'), exist_ok=True)
with open('$inst_plugins') as f:
    data = json.load(f)
key = '$name@$mkt_name'
if key not in data.get('plugins', {}):
    data.setdefault('plugins', {})[key] = [{
        'scope': 'user',
        'installPath': '$HOME/.claude/plugins/marketplaces/$mkt_name',
        'version': '1.0.0',
        'installedAt': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)',
        'lastUpdated': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'
    }]
    with open('$inst_plugins', 'w') as f:
        json.dump(data, f, indent=2)
" 2>/dev/null

  # 3. 启用插件
  python3 -c "
import json
with open('$CLAUDE_SETTINGS_JSON') as f:
    cfg = json.load(f)
key = '$name@$mkt_name'
if key not in cfg.get('enabledPlugins', {}):
    cfg.setdefault('enabledPlugins', {})[key] = True
    # 如果 marketplace 不在 extraKnownMarketplaces 中，添加
    cfg.setdefault('extraKnownMarketplaces', {})['$mkt_name'] = {
        'source': {'source': 'github', 'repo': '$mkt_repo'}
    }
    with open('$CLAUDE_SETTINGS_JSON', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('enabled')
else:
    print('already_enabled')
" 2>/dev/null

  log_info "Claude: plugin $name 已安装"
}

# 简化：skill 安装走同样的 marketplace 流程
claude_install_skill() { claude_install_plugin "$@"; }
```

- [ ] **Step 2: 验证脚本语法**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
bash -c 'source lib/common.sh && source lib/manifest.sh && source lib/resource.sh && source lib/platform/claude.sh && echo "claude.sh loaded OK"'
```

- [ ] **Step 3: Commit**

```bash
git add lib/platform/claude.sh
git commit -m "feat: add Claude Code platform adapter"
```

---

### Task 6: OpenCode 平台适配器

**Files:**
- Create: `lib/platform/opencode.sh`

**Interfaces:**
- Consumes: `install_resource()`, `MANIFEST_JSON`
- Produces:
  - `opencode_list_installed()` — 输出已装资源列表
  - `opencode_install_skill(name)` — 编辑 opencode.json 的 skills.paths
  - `opencode_install_mcp(name)` — 编辑 opencode.json 的 mcp 配置
  - `opencode_install_plugin(name)` — 编辑 opencode.json 的 plugin 配置

- [ ] **Step 1: 创建 `lib/platform/opencode.sh`**

```bash
#!/usr/bin/env bash
# lib/platform/opencode.sh — OpenCode 平台适配器

OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# 列出已安装资源
opencode_list_installed() {
  if [[ ! -f "$OPENCODE_CONFIG" ]]; then
    return
  fi

  python3 -c "
import json
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)

# skills: 检查 skills.paths
for p in cfg.get('skills', {}).get('paths', []):
    print(f'skill {p} installed')

# mcp: 检查 mcpServers
for name in cfg.get('mcpServers', {}):
    print(f'mcp {name} installed')

# plugins: 检查 plugins
for name in cfg.get('plugins', {}):
    print(f'plugin {name} installed')
" 2>/dev/null || true
}

# 安装 skill（编辑 skills.paths）
opencode_install_skill() {
  local name="$1"
  local src
  src=$(install_resource "$name" "skill")
  [[ -z "$src" ]] && die "skill $name 资源获取失败"

  python3 -c "
import json
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
cfg.setdefault('skills', {}).setdefault('paths', [])
if '$src' not in cfg['skills']['paths']:
    cfg['skills']['paths'].append('$src')
    with open('$OPENCODE_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('installed')
else:
    print('already_installed')
" 2>/dev/null

  log_info "OpenCode: skill $name 已配置 ($src)"
}

# 安装 mcp
opencode_install_mcp() {
  local name="$1"
  local command args
  command=$(get_resource_field "$name" "command")
  args=$(get_resource_field "$name" "args")
  [[ -z "$command" ]] && die "mcp $name 缺少 command 字段"

  install_resource "$name" "mcp" >/dev/null

  python3 -c "
import json
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
if '$name' in cfg.get('mcpServers', {}):
    print('already_installed')
else:
    cfg.setdefault('mcpServers', {})['$name'] = {
        'type': 'stdio',
        'command': '$command',
        'args': [$args]
    }
    with open('$OPENCODE_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('installed')
" 2>/dev/null

  log_info "OpenCode: mcp $name 已配置"
}

# 安装 plugin
opencode_install_plugin() {
  local name="$1"
  local mkt_name
  mkt_name=$(get_resource_field "$name" "source.name")

  install_resource "$name" "plugin" >/dev/null

  python3 -c "
import json
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
key = '$name@$mkt_name'
cfg.setdefault('plugins', {})[key] = {'enabled': True}
with open('$OPENCODE_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null

  log_info "OpenCode: plugin $name 已启用"
}
```

- [ ] **Step 2: 验证脚本语法**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
bash -c 'source lib/common.sh && source lib/manifest.sh && source lib/resource.sh && source lib/platform/opencode.sh && echo "opencode.sh loaded OK"'
```

- [ ] **Step 3: Commit**

```bash
git add lib/platform/opencode.sh
git commit -m "feat: add OpenCode platform adapter"
```

---

### Task 7: 主入口实现 — 完成 manage.sh 的 list 和 install 命令

**Files:**
- Modify: `manage.sh`

**Interfaces:**
- Consumes: 所有平台适配器的 `*_list_installed()` / `*_install_*()` 函数
- Produces: 完整的 CLI 命令

- [ ] **Step 1: 实现 `cmd_list()`**

在 `manage.sh` 中替换 `cmd_list()` 存根为完整实现：

```bash
# 列出所有平台已装 vs 清单差异
cmd_list() {
  local all_platforms=(${PLATFORMS[@]})
  local diff_output=""

  for platform in "${all_platforms[@]}"; do
    echo ""
    echo "=== ${platform^} ==="

    # 检查适配器是否可用
    local list_func="${platform}_list_installed"
    if ! declare -F "$list_func" &>/dev/null; then
      log_warn "平台 $platform 适配器未实现"
      continue
    fi

    # 收集已安装资源
    local installed=$($list_func 2>/dev/null || true)
    if [[ -z "$installed" ]]; then
      echo "  (无已安装资源)"
    else
      echo "$installed" | while IFS=' ' read -r type name status; do
        echo "  $type: $name ✓"
      done
    fi

    # 对比 manifest 差异
    local types=("skill" "mcp" "plugin")
    for t in "${types[@]}"; do
      local resources=($(get_resources "$t" 2>/dev/null || true))
      for r in "${resources[@]}"; do
        if ! echo "$installed" | grep -q "$t $r "; then
          diff_output+="  $platform/$t/$r: 清单有，未安装"$'\n'
        fi
      done
    done
  done

  if [[ -n "$diff_output" ]]; then
    echo ""
    echo "=== 差异对比 ==="
    echo "$diff_output"
  fi
}
```

- [ ] **Step 2: 实现 `cmd_install()`**

```bash
# 安装缺失资源
cmd_install() {
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})
  local count=0

  for platform in "${all_platforms[@]}"; do
    echo ""
    echo "=== 安装到 ${platform^} ==="

    local install_skill_func="${platform}_install_skill"
    local install_mcp_func="${platform}_install_mcp"
    local install_plugin_func="${platform}_install_plugin"

    for t in "${types[@]}"; do
      local resources=($(get_resources "$t" 2>/dev/null || true))

      # 如果指定了资源名，只安装指定的
      if [[ -n "$RESOURCE_NAME" ]]; then
        resources=($RESOURCE_NAME)
      fi

      for r in "${resources[@]}"; do
        # 检查是否已安装
        local installed=$(${platform}_list_installed 2>/dev/null | grep "^$t $r " || true)
        if [[ -n "$installed" ]]; then
          log_info "$platform/$t/$r 已安装，跳过"
          continue
        fi

        # 调对应的 install 函数
        local install_func="${platform}_install_${t}"
        if declare -F "$install_func" &>/dev/null; then
          if $install_func "$r"; then
            ((count++))
          fi
        else
          log_warn "$platform 不支持安装 $t"
        fi
      done
    done
  done

  echo ""
  log_info "安装完成，共处理 $count 个资源"
}
```

- [ ] **Step 3: 更新 manage.sh 的 `main()` 函数**

确保在 `main()` 中调用 `load_and_cache` 而非 `load_manifest`，且 `MANIFEST_JSON` 全局变量在子 shell 中可见：

```bash
main() {
  parse_args "$@"

  PLATFORMS=(${PLATFORM:-$(detect_platforms)})
  [[ ${#PLATFORMS[@]} -eq 0 ]] && die "未检测到任何支持的平台"

  # 加载 manifest
  load_and_cache
  [[ -z "$MANIFEST_JSON" ]] && die "无法加载 manifest.toml"

  case "$COMMAND" in
    list)
      cmd_list
      ;;
    install)
      cmd_install
      ;;
    "")
      usage
      ;;
    *)
      die "未知命令: $COMMAND"
      ;;
  esac
}
```

- [ ] **Step 4: 验证完整命令可用**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
./manage.sh list
```

Expected: 输出各平台已装资源 vs 清单差异（根据本机实际安装情况）

- [ ] **Step 5: Commit**

```bash
git add manage.sh
git commit -m "feat: implement list and install commands"
```

---

### Task 8: 测试 — 幂等性验证

**Files:**
- Create: `tests/test_install.sh`

- [ ] **Step 1: 创建测试脚本**

```bash
#!/usr/bin/env bash
# tests/test_install.sh — 测试 install 幂等性

set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 测试 1: list 命令 ==="
./manage.sh list
echo ""

echo "=== 测试 2: install 命令（幂等）==="
./manage.sh install
echo ""

echo "=== 测试 3: 重复安装（不报错）==="
./manage.sh install
echo ""

echo "=== 测试 4: 按平台过滤 ==="
for p in codex claude opencode; do
  echo "--- $p ---"
  ./manage.sh list --platform "$p" 2>/dev/null || echo "  (跳过或平台不存在)"
done
echo ""

echo "=== 测试 5: 按类型过滤 ==="
./manage.sh list --type skill
echo ""

echo "=== 测试 6: 按名称过滤 ==="
./manage.sh list --type mcp codegraph 2>/dev/null || true
echo ""

echo "=== 所有测试完成 ==="
```

- [ ] **Step 2: 运行测试**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
bash tests/test_install.sh
```

Expected: 所有测试通过，无报错

- [ ] **Step 3: Commit**

```bash
git add tests/test_install.sh
git commit -m "test: add install test script"
```

---

### Task 9: 整合验证 + 最终检查

- [ ] **Step 1: 完整运行一遍 list 和 install**

```bash
cd /Users/huangrongchao/go/src/github.com/personal/zshrc
echo "=== LIST ===" && ./manage.sh list
echo ""
echo "=== INSTALL ===" && ./manage.sh install
echo ""
echo "=== LIST AFTER INSTALL ===" && ./manage.sh list
```

- [ ] **Step 2: 检查各平台配置文件未被破坏**

```bash
echo "=== Codex config ===" && head -5 ~/.codex/config.toml
echo "=== Claude mcp.json ===" && python3 -m json.tool ~/.claude/mcp.json 2>/dev/null | head -10
echo "=== OpenCode config ===" && python3 -m json.tool ~/.config/opencode/opencode.json 2>/dev/null | head -10
```

- [ ] **Step 3: 最终 Commit**

```bash
git add -A
git commit -m "chore: final integration adjustments"
```