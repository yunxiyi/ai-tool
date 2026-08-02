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
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
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
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
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
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
key = '$name@$mkt_name'
cfg.setdefault('plugins', {})[key] = {'enabled': True}
with open('$OPENCODE_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null

  log_info "OpenCode: plugin $name 已启用"
}

# 卸载 skill
opencode_uninstall_skill() {
  local name="$1"
  local src
  src=$(get_resource_field "$name" "source.path")
  if [[ -z "$src" ]]; then
    src=$(get_resource_field "$name" "source.type") 2>/dev/null || true
    [[ "$src" == "local" ]] && src=$(get_resource_field "$name" "source.path") || src=""
  fi
  [[ -z "$src" ]] && src="$name"

  python3 -c "
import json
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
import sys
paths = cfg.get('skills', {}).get('paths', [])
if '$src' in paths:
    cfg['skills']['paths'].remove('$src')
    with open('$OPENCODE_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' && log_info "OpenCode: skill $name 已卸载" || log_info "OpenCode: skill $name 未安装"
}

# 卸载 mcp
opencode_uninstall_mcp() {
  local name="$1"
  python3 -c "
import json, sys
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
if '$name' in cfg.get('mcpServers', {}):
    del cfg['mcpServers']['$name']
    with open('$OPENCODE_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' && log_info "OpenCode: mcp $name 已卸载" || log_info "OpenCode: mcp $name 未安装"
}

# 卸载 plugin
opencode_uninstall_plugin() {
  local name="$1"
  local mkt_name
  mkt_name=$(get_resource_field "$name" "source.name")
  local key="$name@$mkt_name"

  python3 -c "
import json, sys
try:
    with open('$OPENCODE_CONFIG') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
if '$key' in cfg.get('plugins', {}):
    del cfg['plugins']['$key']
    with open('$OPENCODE_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' && log_info "OpenCode: plugin $name 已卸载" || log_info "OpenCode: plugin $name 未安装"
}

# 描述 skill
opencode_describe_skill() {
  local name="$1"
  [[ -z "$name" || ! -f "$OPENCODE_CONFIG" ]] && return

  python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
n = '$name'
for p in cfg.get('skills', {}).get('paths', []):
    if p == n or p.endswith('/' + n):
        print('source.type=local')
        print(f'source.path={p}')
        sys.exit(0)
" 2>/dev/null
}

# 描述 mcp
opencode_describe_mcp() {
  local name="$1"
  [[ -z "$name" || ! -f "$OPENCODE_CONFIG" ]] && return

  python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
s = cfg.get('mcpServers', {}).get('$name')
if s:
    print(f'command={s.get(\"command\", \"\")}')
    print(f'args={json.dumps(s.get(\"args\", []))}')
" 2>/dev/null
}

# 描述 plugin
opencode_describe_plugin() {
  local name="$1"
  [[ -z "$name" || ! -f "$OPENCODE_CONFIG" ]] && return

  python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    cfg = json.load(f)
n = '$name'
for key in cfg.get('plugins', {}):
    if key.startswith(n + '@'):
        mkt = key.split('@', 1)[1]
        print('source.type=marketplace')
        print(f'source.name={mkt}')
        sys.exit(0)
" 2>/dev/null
}