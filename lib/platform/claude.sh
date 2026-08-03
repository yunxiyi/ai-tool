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

  # rules: 列出 ~/.claude/rules/ 下的文件
  if [[ -d "$CLAUDE_HOME/rules" ]]; then
    for f in "$CLAUDE_HOME/rules"/*; do
      [[ -f "$f" ]] && echo "rule $(basename "$f") installed"
    done
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
import json, os
try:
    with open('$CLAUDE_MCP_JSON') as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
    os.makedirs(os.path.dirname('$CLAUDE_MCP_JSON'), exist_ok=True)
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
import json, os
try:
    with open('$known_mkt') as f:
        mkt = json.load(f)
except FileNotFoundError:
    mkt = {}
    os.makedirs(os.path.dirname('$known_mkt'), exist_ok=True)
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
try:
    with open('$inst_plugins') as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
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
try:
    with open('$CLAUDE_SETTINGS_JSON') as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
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

# 卸载 mcp
claude_uninstall_mcp() {
  local name="$1"
  python3 -c "
import json, os
try:
    with open('$CLAUDE_MCP_JSON') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
import sys
if '$name' in cfg.get('mcpServers', {}):
    del cfg['mcpServers']['$name']
    with open('$CLAUDE_MCP_JSON', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' && log_info "Claude: mcp $name 已卸载" || log_info "Claude: mcp $name 未安装"
}

# 卸载 plugin
claude_uninstall_plugin() {
  local name="$1"
  local mkt_name
  mkt_name=$(get_resource_field "$name" "source.name")
  local key="$name@$mkt_name"

  # 从 settings.json 的 enabledPlugins 移除
  python3 -c "
import json, sys
try:
    with open('$CLAUDE_SETTINGS_JSON') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
removed = False
if '$key' in cfg.get('enabledPlugins', {}):
    del cfg['enabledPlugins']['$key']
    removed = True
if removed:
    with open('$CLAUDE_SETTINGS_JSON', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' && log_info "Claude: plugin $name 已卸载" || log_info "Claude: plugin $name 未安装"
}

# 简化：skill 卸载走同样的流程
claude_uninstall_skill() { claude_uninstall_plugin "$@"; }

# 描述 mcp 配置
claude_describe_mcp() {
  local name="$1"
  python3 -c "
import json, sys
try:
    with open('$CLAUDE_MCP_JSON') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)
entry = data.get('mcpServers', {}).get('$name')
if not entry:
    sys.exit(0)
cmd = entry.get('command', '')
print(f'command={cmd}')
_c = cmd.strip()
if _c.startswith('npx ') or _c.startswith('npx -y '):
    parts = _c.split()
    pkg = None
    for p in parts[1:]:
        if not p.startswith('-'):
            pkg = p
            break
    if pkg:
        print(f'source.type=npm_install')
        print(f'install.package={pkg}')
    else:
        print(f'source.type=local')
        print(f'source.path={cmd}')
elif _c.startswith('uvx ') or _c.startswith('uvx --'):
    parts = _c.split()
    pkg = None
    for p in parts[1:]:
        if not p.startswith('-'):
            pkg = p
            break
    if pkg:
        print(f'source.type=pip_install')
        print(f'install.package={pkg}')
    else:
        print(f'source.type=local')
        print(f'source.path={cmd}')
elif _c.startswith('go ') or _c.startswith('go-run '):
    print(f'source.type=local')
    print(f'source.path={cmd}')
else:
    print(f'source.type=local')
    print(f'source.path={cmd}')
args = entry.get('args')
if args is not None:
    print(f'args={json.dumps(args)}')
" 2>/dev/null
}

# 描述 plugin 配置
claude_describe_plugin() {
  local name="$1"
  python3 -c "
import json, sys
try:
    with open('$CLAUDE_INSTALLED_PLUGINS') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)
plugins = data.get('plugins', {})
# 插件名可能已含 @marketplace 后缀（如 superpowers@superpowers-marketplace）
# 先尝试精确匹配，再尝试前缀匹配
key = '$name'
mkt_name = None
if key in plugins:
    # key 本身就是完整名称，从 name 中提取 @ 后面的部分
    if '@' in key:
        mkt_name = key.split('@', 1)[1]
else:
    for k in plugins:
        if k.startswith(key + '@'):
            mkt_name = k.split('@', 1)[1]
            break
if not mkt_name:
    sys.exit(0)
try:
    with open('$CLAUDE_HOME/plugins/known_marketplaces.json') as f:
        mkt = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    mkt = {}
repo = mkt.get(mkt_name, {}).get('source', {}).get('repo', '')
print('source.type=marketplace')
print(f'source.name={mkt_name}')
print(f'source.repo={repo}')
" 2>/dev/null
}

# ===== Rule =====

CLAUDE_RULES_DIR="$CLAUDE_HOME/rules"

# 安装 rule
claude_install_rule() {
  local name="$1"
  local src
  src=$(install_resource "$name" "rule")
  [[ -z "$src" ]] && die "rule $name 资源获取失败"

  mkdir -p "$CLAUDE_RULES_DIR"
  local target="$CLAUDE_RULES_DIR/$name"
  if [[ -f "$target" ]]; then
    log_info "Claude: rule $name 已存在"
    return 0
  fi
  cp "$src" "$target"
  log_info "Claude: rule $name 已安装 ($src → $target)"
}

# 卸载 rule
claude_uninstall_rule() {
  local name="$1"
  local target="$CLAUDE_RULES_DIR/$name"
  if [[ -f "$target" ]]; then
    rm "$target"
    log_info "Claude: rule $name 已卸载"
  else
    log_info "Claude: rule $name 未安装"
  fi
}

# 描述 rule
claude_describe_rule() {
  local name="$1"
  local target="$CLAUDE_RULES_DIR/$name"
  if [[ -f "$target" ]]; then
    echo "source.type=local"
    echo "source.path=$target"
  fi
}