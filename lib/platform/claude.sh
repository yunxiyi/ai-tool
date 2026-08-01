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