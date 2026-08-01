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