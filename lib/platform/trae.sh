#!/usr/bin/env bash
# lib/platform/trae.sh — TRAE 平台适配器
# 注意: TRAE 的 plugin 由 TRAE 自身管理，本适配器只做 list，不做 install

TRAE_HOME="$HOME/.trae-cn"
TRAE_SKILL_CONFIG="$TRAE_HOME/skill-config.json"
TRAE_PLUGIN_CONFIG="$TRAE_HOME/plugin-config.json"
TRAE_MCPS_DIR="$TRAE_HOME/mcps"
TRAE_SKILLS_DIR="$TRAE_HOME/skills"
TRAE_MANAGED_MCP_DIR="$TRAE_MCPS_DIR/s_managed"

# 列出已安装资源
trae_list_installed() {
  # skills: 从 skill-config.json 读取 managedSkills + builtinSkillStatus
  if [[ -f "$TRAE_SKILL_CONFIG" ]]; then
    python3 -c "
import json
with open('$TRAE_SKILL_CONFIG') as f:
    data = json.load(f)
for name in data.get('managedSkills', {}):
    print(f'skill {name} installed')
for name in data.get('builtinSkillStatus', {}):
    print(f'skill {name} installed')
" 2>/dev/null || true
  fi

  # skills: 补充 skills/ 目录中未在 skill-config.json 登记的
  if [[ -d "$TRAE_SKILLS_DIR" ]]; then
    python3 -c "
import json, os
try:
    with open('$TRAE_SKILL_CONFIG') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
known = set(cfg.get('managedSkills', {})) | set(cfg.get('builtinSkillStatus', {}))
for name in os.listdir('$TRAE_SKILLS_DIR'):
    d = os.path.join('$TRAE_SKILLS_DIR', name)
    if os.path.isdir(d) and name not in known:
        print(f'skill {name} installed')
" 2>/dev/null || true
  fi

  # mcps: 扫描 mcps 目录下的 SERVER_METADATA.json（去重）
  if [[ -d "$TRAE_MCPS_DIR" ]]; then
    python3 -c "
import os, json
mcps_dir = '$TRAE_MCPS_DIR'
seen = set()
for root, dirs, files in os.walk(mcps_dir):
    if 'SERVER_METADATA.json' in files:
        try:
            with open(os.path.join(root, 'SERVER_METADATA.json')) as f:
                meta = json.load(f)
            name = meta.get('server_name', '')
            if name and name not in seen:
                seen.add(name)
                print(f'mcp {name} installed')
        except Exception:
            pass
" 2>/dev/null || true
  fi

  # plugins: 从 plugin-config.json 读取（只列不装）
  if [[ -f "$TRAE_PLUGIN_CONFIG" ]]; then
    python3 -c "
import json
with open('$TRAE_PLUGIN_CONFIG') as f:
    data = json.load(f)
for name in data.get('plugins', {}):
    print(f'plugin {name} installed')
" 2>/dev/null || true
  fi
}

# 安装 skill
trae_install_skill() {
  local name="$1"
  local src
  src=$(install_resource "$name" "skill")
  [[ -z "$src" || ! -d "$src" ]] && die "skill $name 资源获取失败"

  # 复制 skill 到 TRAE skills 目录
  mkdir -p "$TRAE_SKILLS_DIR"
  local target="$TRAE_SKILLS_DIR/$name"
  if [[ -d "$target" ]]; then
    log_info "TRAE: skill $name 已安装 ($target)"
  else
    cp -R "$src" "$target"
    log_info "TRAE: skill $name 已安装 ($src → $target)"
  fi

  # 注册到 skill-config.json 的 managedSkills
  python3 -c "
import json, os
cfg_path = '$TRAE_SKILL_CONFIG'
os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
try:
    with open(cfg_path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
if '$name' not in cfg.get('managedSkills', {}):
    cfg.setdefault('managedSkills', {})['$name'] = 'marketplace'
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
" 2>/dev/null
}

# 安装 mcp
trae_install_mcp() {
  local name="$1"
  local command url args
  command=$(get_resource_field "$name" "command")
  url=$(get_resource_field "$name" "url")
  args=$(get_resource_field "$name" "args")
  [[ -z "$command" && -z "$url" ]] && die "mcp $name 缺少 command 或 url 字段"

  # 先获取二进制（如果 install.type 不是 none）
  install_resource "$name" "mcp" >/dev/null

  # 创建 managed MCP 目录
  local mcp_server_dir="$TRAE_MANAGED_MCP_DIR/solo_agent_lite/$name"
  mkdir -p "$mcp_server_dir"

  # 检查是否已安装
  if [[ -f "$mcp_server_dir/SERVER_METADATA.json" ]]; then
    log_info "TRAE: mcp $name 已安装"
    return 0
  fi

  # 写入 SERVER_METADATA.json
  if [[ -n "$command" ]]; then
    python3 -c "
import json
with open('$mcp_server_dir/SERVER_METADATA.json', 'w') as f:
    json.dump({'server_name': '$name', 'description': None, 'command': '$command', 'args': [$args]}, f, indent=2)
" 2>/dev/null
    log_info "TRAE: mcp $name 已配置 (command: $command)"
  else
    python3 -c "
import json
with open('$mcp_server_dir/SERVER_METADATA.json', 'w') as f:
    json.dump({'server_name': '$name', 'description': None, 'url': '$url'}, f, indent=2)
" 2>/dev/null
    log_info "TRAE: mcp $name 已配置 (url: $url)"
  fi
}

# 卸载 skill
trae_uninstall_skill() {
  local name="$1"

  # 从 skill-config.json 的 managedSkills 移除
  python3 -c "
import json, sys
try:
    with open('$TRAE_SKILL_CONFIG') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print('not_found')
    sys.exit(0)
if '$name' in cfg.get('managedSkills', {}):
    del cfg['managedSkills']['$name']
    with open('$TRAE_SKILL_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('removed')
else:
    print('not_found')
" 2>/dev/null | grep -q 'removed' || true

  # 删除 skills/ 目录下的对应目录
  local target="$TRAE_SKILLS_DIR/$name"
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    log_info "TRAE: skill $name 已卸载"
  else
    log_info "TRAE: skill $name 未安装"
  fi
}

# 卸载 mcp
trae_uninstall_mcp() {
  local name="$1"
  local mcp_server_dir="$TRAE_MANAGED_MCP_DIR/solo_agent_lite/$name"

  if [[ -d "$mcp_server_dir" ]]; then
    rm -rf "$mcp_server_dir"

    # 清理空目录
    rmdir "$TRAE_MANAGED_MCP_DIR/solo_agent_lite" 2>/dev/null || true
    rmdir "$TRAE_MANAGED_MCP_DIR" 2>/dev/null || true

    log_info "TRAE: mcp $name 已卸载"
  else
    log_info "TRAE: mcp $name 未安装"
  fi
}

# 描述 skill 的安装信息
trae_describe_skill() {
  local name="$1"

  # 检查是否为 builtin skill（无需安装）
  if [[ -f "$TRAE_SKILL_CONFIG" ]]; then
    python3 -c "
import json
with open('$TRAE_SKILL_CONFIG') as f:
    data = json.load(f)
if '$name' in data.get('builtinSkillStatus', {}):
    print('install.type=none')
" 2>/dev/null || true
  fi

  # 检查本地目录是否存在
  local dir="$TRAE_SKILLS_DIR/$name"
  if [[ -d "$dir" ]]; then
    echo "source.type=local"
    echo "source.path=$dir"
  fi
}

# 描述 mcp 的安装信息
trae_describe_mcp() {
  local name="$1"

  if [[ -d "$TRAE_MCPS_DIR" ]]; then
    python3 -c "
import os, json
name = '$name'
mcps_dir = '$TRAE_MCPS_DIR'
for root, dirs, files in os.walk(mcps_dir):
    if 'SERVER_METADATA.json' in files:
        try:
            with open(os.path.join(root, 'SERVER_METADATA.json')) as f:
                meta = json.load(f)
            if meta.get('server_name') == name:
                if meta.get('command'):
                    print(f'command={meta[\"command\"]}')
                if meta.get('args') is not None:
                    print(f'args={json.dumps(meta[\"args\"])}')
                if meta.get('url'):
                    print(f'url={meta[\"url\"]}')
                print(f'source.type=local')
                print(f'source.path={root}')
                break
        except Exception:
            pass
" 2>/dev/null || true
  fi
}

# 描述 plugin 的安装信息
trae_describe_plugin() {
  local name="$1"
  # TRAE 插件由 TRAE 自身管理，无需安装
  echo "install.type=none"
}