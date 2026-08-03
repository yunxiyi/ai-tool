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

  # rules: 列出 ~/.codex/rules/ 下的 .rules 文件
  if [[ -d "$CODEX_HOME/rules" ]]; then
    for f in "$CODEX_HOME/rules"/*.rules; do
      [[ -f "$f" ]] && echo "rule $(basename "${f%.rules}") installed"
    done
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

  python3 -c "
with open('$CODEX_CONFIG', 'a') as f:
    f.write('''

[mcp_servers.$name]
type = \"stdio\"
command = \"$command\"
args = [$args]
''')
"
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

  python3 -c "
with open('$CODEX_CONFIG', 'a') as f:
    f.write('''

[plugins.\"$name@$mkt_name\"]
enabled = true
''')
"
  log_info "Codex: plugin $name 已启用"
}

# 卸载 skill
codex_uninstall_skill() {
  local name="$1"
  local link_path="$CODEX_SKILLS_DIR/$name"
  if [[ -L "$link_path" ]]; then
    rm "$link_path"
    log_info "Codex: skill $name 已卸载"
    return 0
  elif [[ -e "$link_path" ]]; then
    log_warn "skill $name 路径存在但不是软链，跳过"
    return 1
  else
    log_info "Codex: skill $name 未安装"
    return 0
  fi
}

# 卸载 mcp
codex_uninstall_mcp() {
  local name="$1"
  if ! grep -q "\[mcp_servers.$name\]" "$CODEX_CONFIG" 2>/dev/null; then
    log_info "Codex: mcp $name 未配置"
    return 0
  fi

  python3 -c "
import configparser, os
cfg = configparser.ConfigParser()
cfg.read('$CODEX_CONFIG')
section = 'mcp_servers.$name'
if cfg.remove_section(section):
    with open('$CODEX_CONFIG', 'w') as f:
        cfg.write(f)
    print('removed')
" 2>/dev/null
  log_info "Codex: mcp $name 已卸载"
}

# 卸载 plugin
codex_uninstall_plugin() {
  local name="$1"
  python3 -c "
import configparser, sys
cfg = configparser.ConfigParser()
cfg.read('$CODEX_CONFIG')
removed = False
for section in list(cfg.sections()):
    if section.startswith('plugins.') and '$name@' in section:
        cfg.remove_section(section)
        removed = True
if removed:
    with open('$CODEX_CONFIG', 'w') as f:
        cfg.write(f)
    print('removed')
" 2>/dev/null | grep -q 'removed' && log_info "Codex: plugin $name 已卸载" || log_info "Codex: plugin $name 未安装"
}

# 描述 skill — 输出 key=value 行
codex_describe_skill() {
  local name="$1"
  local link_path="$CODEX_SKILLS_DIR/$name"
  if [[ -L "$link_path" ]]; then
    local target
    target=$(readlink "$link_path")
    echo "source.type=local"
    echo "source.path=$target"
  elif [[ -d "$link_path" ]]; then
    echo "source.type=local"
    echo "source.path=$link_path"
  fi
}

# 描述 mcp — 输出 key=value 行
codex_describe_mcp() {
  local name="$1"
  python3 -c "
import configparser, json, ast, sys
cfg = configparser.ConfigParser()
cfg.read('$CODEX_CONFIG')
section = 'mcp_servers.$name'
if cfg.has_section(section):
    command = cfg.get(section, 'command')
    args_str = cfg.get(section, 'args')
    try:
        args_list = ast.literal_eval(args_str)
        args_json = json.dumps(args_list)
    except Exception:
        args_json = '[]'
    print(f'command={command}')
    print(f'args={args_json}')
    _c = command.strip()
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
            print(f'source.path={command}')
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
            print(f'source.path={command}')
    elif _c.startswith('go ') or _c.startswith('go-run '):
        print(f'source.type=local')
        print(f'source.path={command}')
    else:
        print(f'source.type=local')
        print(f'source.path={command}')
" 2>/dev/null || true
}

# 描述 plugin — 输出 key=value 行
codex_describe_plugin() {
  local name="$1"
  python3 -c "
import configparser, sys, json
cfg = configparser.ConfigParser()
cfg.read('$CODEX_CONFIG')
for section in cfg.sections():
    if section.startswith('plugins.') and '\"$name@' in section:
        after_at = section.split('@', 1)[1]
        marketplace = after_at.rstrip('\"')
        print('source.type=marketplace')
        print(f'source.name={marketplace}')
        break
" 2>/dev/null || true
}

# ===== Rule =====

CODEX_RULES_DIR="$CODEX_HOME/rules"

# 安装 rule
codex_install_rule() {
  local name="$1"
  local src
  src=$(install_resource "$name" "rule")
  [[ -z "$src" ]] && die "rule $name 资源获取失败"

  mkdir -p "$CODEX_RULES_DIR"
  local target="$CODEX_RULES_DIR/$name.rules"
  if [[ -f "$target" ]]; then
    log_info "Codex: rule $name 已存在"
    return 0
  fi
  cp "$src" "$target"
  log_info "Codex: rule $name 已安装 ($src → $target)"
}

# 卸载 rule
codex_uninstall_rule() {
  local name="$1"
  local target="$CODEX_RULES_DIR/$name.rules"
  if [[ -f "$target" ]]; then
    rm "$target"
    log_info "Codex: rule $name 已卸载"
  else
    log_info "Codex: rule $name 未安装"
  fi
}

# 描述 rule
codex_describe_rule() {
  local name="$1"
  local target="$CODEX_RULES_DIR/$name"
  # Codex 的 rule 文件是 .rules 后缀
  if [[ -f "$target.rules" ]]; then
    echo "source.type=local"
    echo "source.path=$target.rules"
  elif [[ -f "$target" ]]; then
    echo "source.type=local"
    echo "source.path=$target"
  fi
}