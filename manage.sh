#!/usr/bin/env bash
# manage.sh — Agent Resource Manager 主入口
# Usage: ./manage.sh <command> [options] [key=value ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LIB_DIR="$SCRIPT_DIR/lib"

# 加载所有模块
source "$LIB_DIR/common.sh"
source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/resource.sh"

# 加载所有平台适配器
for platform in codex claude opencode trae; do
  adapter="$LIB_DIR/platform/${platform}.sh"
  [[ -f "$adapter" ]] && source "$adapter"
done

# 默认值
PLATFORM=""
RESOURCE_TYPE=""
RESOURCE_NAME=""
POSITIONAL_ARGS=()

# 解析命令行参数
parse_args() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) PLATFORM="$2"; shift 2 ;;
      --type)     RESOURCE_TYPE="$2"; shift 2 ;;
      --name)     RESOURCE_NAME="$2"; shift 2 ;;
      -h|--help)  usage; exit 0 ;;
      *)          args+=("$1"); shift ;;
    esac
  done
  COMMAND="${args[0]:-}"
  # 剩余参数：可能是资源名或 key=value 对
  POSITIONAL_ARGS=("${args[@]:1}")

  # 如果 --name 未设置，用第一个位置参数作为资源名
  if [[ -z "$RESOURCE_NAME" && ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    RESOURCE_NAME="${POSITIONAL_ARGS[0]}"
    POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:1}")
  fi
}

usage() {
  cat <<'EOF'
Usage: ./manage.sh <command> [options] [key=value ...]

命令:
  list             列出各平台已安装资源 vs 清单差异
  show             查看 manifest 清单内容
  collect          从各平台收集已装资源，写入 manifest
  install          安装 manifest 中缺失的资源
  uninstall        卸载已安装的资源
  add              添加资源到 manifest
  remove           从 manifest 移除资源
  update           更新 manifest 中资源的字段
  doctor           健康检查（平台配置、manifest 语法、资源完整性）

选项:
  --platform <name>   限定平台 (codex|claude|opencode|trae)
  --type <type>       限定资源类型 (skill|mcp|plugin)
  --name <name>       资源名
  -h, --help          显示帮助

示例:
  ./manage.sh list                    列出所有平台差异
  ./manage.sh list --platform trae     只看 TRAE
  ./manage.sh show                     查看所有 manifest
  ./manage.sh show --platform trae --type skill  查看 TRAE skill 声明
  ./manage.sh show --platform trae --type skill --name brainstorming  查看资源详情
  ./manage.sh collect                  收集已装资源到 manifest
  ./manage.sh install --platform trae  安装 TRAE 缺失资源
  ./manage.sh add --platform trae --type skill --name foo source.type=local source.path=skills/foo
  ./manage.sh remove --platform trae --type skill --name foo
  ./manage.sh update --platform trae --type skill --name foo source.type=git
EOF
}

# 列出所有平台已装 vs 清单差异
cmd_list() {
  local all_platforms=(${PLATFORMS[@]})
  local diff_output=""

  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    echo ""
    echo "=== $(tr '[:lower:]' '[:upper:]' <<<"${platform:0:1}")${platform:1} ==="

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
    local types=(${RESOURCE_TYPE:-skill mcp plugin})
    for t in "${types[@]}"; do
      export CURRENT_TYPE="$t"
      local resources_str
      resources_str="$(get_resources "$t" 2>/dev/null || true)"
      [[ -z "$resources_str" ]] && continue
      local resources=($resources_str)
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

# 查看 manifest 清单内容
cmd_show() {
  # 如果指定了 --name，显示资源详情
  if [[ -n "$RESOURCE_NAME" ]]; then
    [[ -n "$PLATFORM" ]] || die "show --name 需要 --platform 参数"
    [[ -n "$RESOURCE_TYPE" ]] || die "show --name 需要 --type 参数"
    export CURRENT_PLATFORM="$PLATFORM"
    export CURRENT_TYPE="$RESOURCE_TYPE"

    local fields
    fields="$(get_resource_all_fields "$RESOURCE_NAME" 2>/dev/null || true)"
    if [[ -z "$fields" ]]; then
      die "资源 $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME 未找到"
    fi

    echo ""
    echo "=== $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME ==="
    echo "$fields" | python3 -c "
import sys, json
data = json.load(sys.stdin)
def print_fields(d, prefix=''):
    for k, v in sorted(d.items()):
        key = f'{prefix}{k}'
        if isinstance(v, dict):
            print_fields(v, f'{key}.')
        elif isinstance(v, list):
            print(f'  {key} = {json.dumps(v)}')
        elif isinstance(v, bool):
            print(f'  {key} = {\"true\" if v else \"false\"}')
        else:
            print(f'  {key} = {v}')
print_fields(data)
"
    return
  fi

  # 无 --name 时列出所有资源名
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})

  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    echo ""
    echo "=== $(tr '[:lower:]' '[:upper:]' <<<"${platform:0:1}")${platform:1} ==="
    for t in "${types[@]}"; do
      export CURRENT_TYPE="$t"
      local resources_str
      resources_str="$(get_resources "$t" 2>/dev/null || true)"
      [[ -z "$resources_str" ]] && continue
      local resources=($resources_str)
      for r in "${resources[@]}"; do
        echo "  $t: $r"
      done
    done
  done
}

# 安装缺失资源
cmd_install() {
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})
  local count=0

  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    echo ""
    echo "=== 安装到 $(tr '[:lower:]' '[:upper:]' <<<"${platform:0:1}")${platform:1} ==="

    local install_skill_func="${platform}_install_skill"
    local install_mcp_func="${platform}_install_mcp"
    local install_plugin_func="${platform}_install_plugin"

    for t in "${types[@]}"; do
      export CURRENT_TYPE="$t"
      local resources_str
      resources_str="$(get_resources "$t" 2>/dev/null || true)"
      [[ -z "$resources_str" && -z "$RESOURCE_NAME" ]] && continue
      local resources=($resources_str)

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

# 从各平台收集已装资源，写入 manifest/{platform}/{type}.toml
cmd_collect() {
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})
  local total=0

  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    local list_func="${platform}_list_installed"
    declare -F "$list_func" &>/dev/null || continue

    local added=0
    while IFS=' ' read -r type name status; do
      # 过滤类型
      local matched=false
      for t in "${types[@]}"; do
        [[ "$type" == "$t" ]] && { matched=true; break; }
      done
      if ! $matched; then continue; fi

      export CURRENT_TYPE="$type"

      # 检查是否已在 manifest 中
      if get_resources "$type" 2>/dev/null | grep -qx "$name"; then
        continue
      fi

      # 获取描述字段（自动识别 source.type、command 等）
      local describe_func="${platform}_describe_${type}"
      local describe_args=()
      if declare -F "$describe_func" &>/dev/null; then
        while IFS= read -r line; do
          [[ -n "$line" ]] && describe_args+=("$line")
        done < <($describe_func "$name" 2>/dev/null || true)
      fi

      # 写入 manifest（含自动识别的字段）
      if [[ ${#describe_args[@]} -gt 0 ]]; then
        add_manifest_entry "$platform" "$type" "$name" "${describe_args[@]}"
      else
        add_manifest_entry "$platform" "$type" "$name"
      fi
      echo "  + $platform/$type/$name"
      ((added++))
    done < <($list_func 2>/dev/null || true)

    [[ "$added" -gt 0 ]] && echo ""
    ((total+=added))
  done

  if [[ "$total" -eq 0 ]]; then
    log_info "所有已安装资源已在 manifest 中"
  else
    log_info "已将 $total 个资源添加到 manifest"
  fi
}

# 卸载资源
cmd_uninstall() {
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})
  local count=0

  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    echo ""
    echo "=== 从 $(tr '[:lower:]' '[:upper:]' <<<"${platform:0:1}")${platform:1} 卸载 ==="

    for t in "${types[@]}"; do
      export CURRENT_TYPE="$t"
      local resources_str
      resources_str="$(get_resources "$t" 2>/dev/null || true)"
      [[ -z "$resources_str" && -z "$RESOURCE_NAME" ]] && continue
      local resources=($resources_str)

      # 如果指定了资源名，只卸载指定的
      if [[ -n "$RESOURCE_NAME" ]]; then
        resources=($RESOURCE_NAME)
      fi

      for r in "${resources[@]}"; do
        # 检查是否已安装
        local installed=$(${platform}_list_installed 2>/dev/null | grep "^$t $r " || true)
        if [[ -z "$installed" ]]; then
          log_info "$platform/$t/$r 未安装，跳过"
          continue
        fi

        local uninstall_func="${platform}_uninstall_${t}"
        if declare -F "$uninstall_func" &>/dev/null; then
          if $uninstall_func "$r"; then
            ((count++))
          fi
        else
          log_warn "$platform 不支持卸载 $t"
        fi
      done
    done
  done

  echo ""
  log_info "卸载完成，共处理 $count 个资源"
}

# 添加资源到 manifest
cmd_add() {
  [[ -n "$PLATFORM" ]] || die "add 需要 --platform 参数"
  [[ -n "$RESOURCE_TYPE" ]] || die "add 需要 --type 参数"
  [[ -n "$RESOURCE_NAME" ]] || die "add 需要 --name 参数"

  # 检查是否已存在
  export CURRENT_PLATFORM="$PLATFORM"
  export CURRENT_TYPE="$RESOURCE_TYPE"
  if get_resources "$RESOURCE_TYPE" 2>/dev/null | grep -qx "$RESOURCE_NAME"; then
    die "资源 $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME 已存在"
  fi

  add_manifest_entry "$PLATFORM" "$RESOURCE_TYPE" "$RESOURCE_NAME" "${POSITIONAL_ARGS[@]}"
  log_info "已添加 $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME"
}

# 从 manifest 移除资源
cmd_remove() {
  [[ -n "$PLATFORM" ]] || die "remove 需要 --platform 参数"
  [[ -n "$RESOURCE_TYPE" ]] || die "remove 需要 --type 参数"
  [[ -n "$RESOURCE_NAME" ]] || die "remove 需要 --name 参数"

  remove_manifest_entry "$PLATFORM" "$RESOURCE_TYPE" "$RESOURCE_NAME"
  log_info "已移除 $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME"
}

# 更新 manifest 字段
cmd_update() {
  [[ -n "$PLATFORM" ]] || die "update 需要 --platform 参数"
  [[ -n "$RESOURCE_TYPE" ]] || die "update 需要 --type 参数"
  [[ -n "$RESOURCE_NAME" ]] || die "update 需要 --name 参数"
  [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]] || die "update 需要 key=value 参数"

  for kv in "${POSITIONAL_ARGS[@]}"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    update_manifest_entry "$PLATFORM" "$RESOURCE_TYPE" "$RESOURCE_NAME" "$key" "$val"
  done
  log_info "已更新 $PLATFORM/$RESOURCE_TYPE/$RESOURCE_NAME"
}

# 迁移旧 manifest.toml 到新目录结构
migrate_old_manifest() {
  local old_manifest="$SCRIPT_DIR/manifest.toml"
  [[ -f "$old_manifest" ]] || return 0

  log_info "检测到旧版 manifest.toml，正在迁移到 manifest/ 目录..."

  # 解析旧文件并写入所有平台
  local platforms=(codex claude opencode trae)
  local section_map='{"skill":"skills","mcp":"mcp","plugin":"plugins"}'

  python3 -c "
import sys, json, os, glob

try:
    import tomllib
    def parse_toml(path):
        with open(path, 'rb') as f:
            return tomllib.load(f)
except ImportError:
    import tomli
    def parse_toml(path):
        with open(path, 'rb') as f:
            return tomli.load(f)

def write_toml_fields(f, prefix, fields):
    for k, v in fields.items():
        if isinstance(v, dict):
            write_toml_fields(f, f'{prefix}{k}.', v)
        elif isinstance(v, list):
            f.write(f'{prefix}{k} = {json.dumps(v)}\\n')
        elif isinstance(v, bool):
            f.write(f'{prefix}{k} = {\"true\" if v else \"false\"}\\n')
        else:
            f.write(f'{prefix}{k} = {json.dumps(str(v))}\\n')

old_file = '$old_manifest'
manifest_dir = '$SCRIPT_DIR/manifest'
platforms = ['codex', 'claude', 'opencode', 'trae']

try:
    data = parse_toml(old_file)
except Exception as e:
    print(f'解析旧 manifest 失败: {e}', file=sys.stderr)
    sys.exit(1)

for platform in platforms:
    for section, section_name in [('skill', 'skills'), ('mcp', 'mcp'), ('plugin', 'plugins')]:
        if section_name not in data:
            continue
        entries = data[section_name]
        if not entries:
            continue
        toml_file = os.path.join(manifest_dir, platform, f'{section}.toml')
        os.makedirs(os.path.dirname(toml_file), exist_ok=True)

        # 检查是否已有内容，避免重复
        if os.path.exists(toml_file) and os.path.getsize(toml_file) > 0:
            continue

        with open(toml_file, 'w') as f:
            for name, fields in entries.items():
                f.write(f'[{section_name}.{name}]\\n')
                write_toml_fields(f, '', fields)
                f.write('\\n')
        print(f'  {platform}/{section}: {len(entries)} 个资源')
" 2>/dev/null || die "迁移失败"

  # 备份后删除旧文件
  mv "$old_manifest" "${old_manifest}.bak"
  log_info "迁移完成，旧文件已备份为 manifest.toml.bak"
}

# 健康检查
cmd_doctor() {
  local issues=0
  local all_platforms=(${PLATFORMS[@]})

  echo ""
  echo "=== 平台配置检查 ==="
  local platform_configs=(
    "codex:$HOME/.codex/config.toml"
    "claude:$HOME/.claude/settings.json"
    "opencode:$HOME/.config/opencode/opencode.json"
    "trae:$HOME/.trae-cn/skill-config.json"
  )
  for pc in "${platform_configs[@]}"; do
    local p="${pc%%:*}"
    local cfg="${pc#*:}"
    if has_platform "$p"; then
      if [[ -f "$cfg" ]]; then
        echo "  ✅ $p: 配置文件存在"
      else
        echo "  ⚠️  $p: 检测到但配置文件不存在 ($cfg)"
        ((issues++))
      fi
    else
      echo "  ⏭️  $p: 未安装"
    fi
  done

  echo ""
  echo "=== manifest 文件检查 ==="
  local toml_files=($(find "$MANIFEST_DIR" -name '*.toml' 2>/dev/null || true))
  if [[ ${#toml_files[@]} -eq 0 ]]; then
    echo "  ⚠️  manifest 目录为空"
    ((issues++))
  else
    echo "  共 ${#toml_files[@]} 个 TOML 文件"
    for f in "${toml_files[@]}"; do
      # 用 python3 验证 TOML 语法
      if python3 -c "
try:
    import tomllib
    def parse_toml(path):
        with open(path, 'rb') as f:
            return tomllib.load(f)
except ImportError:
    import tomli
    def parse_toml(path):
        with open(path, 'rb') as f:
            return tomli.load(f)
parse_toml('$f')
print('ok')
" 2>/dev/null | grep -q ok; then
        :  # 语法正确
      else
        echo "  ❌ 语法错误: $f"
        ((issues++))
      fi
    done
    echo "  ✅ 所有 TOML 文件语法正确"
  fi

  echo ""
  echo "=== 资源完整性检查 ==="
  for platform in "${all_platforms[@]}"; do
    export CURRENT_PLATFORM="$platform"
    for t in skill mcp plugin; do
      export CURRENT_TYPE="$t"
      local resources_str
      resources_str="$(get_resources "$t" 2>/dev/null || true)"
      [[ -z "$resources_str" ]] && continue
      local resources=($resources_str)
      for r in "${resources[@]}"; do
        # 检查是否有 source.type（纯配置资源可跳过）
        local st
        st=$(get_resource_field "$r" "source.type" 2>/dev/null || true)
        local it
        it=$(get_resource_field "$r" "install.type" 2>/dev/null || true)
        if [[ -z "$st" && "$it" != "none" ]]; then
          echo "  ⚠️  $platform/$t/$r: 缺少 source.type"
          ((issues++))
        fi
      done
    done
  done

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    log_info "未发现任何问题"
  else
    log_warn "发现 $issues 个问题"
  fi
  return "$issues"
}

main() {
  parse_args "$@"

  # 检测可用平台
  PLATFORMS=(${PLATFORM:-$(detect_platforms)})
  [[ ${#PLATFORMS[@]} -eq 0 ]] && die "未检测到任何支持的平台"

  # 迁移旧 manifest（仅首次运行）
  migrate_old_manifest

  # 加载 manifest
  load_and_cache
  [[ -z "$MANIFEST_JSON" ]] && die "无法加载 manifest"

  case "$COMMAND" in
    list)
      cmd_list
      ;;
    show)
      cmd_show
      ;;
    install)
      cmd_install
      ;;
    collect)
      cmd_collect
      ;;
    uninstall)
      cmd_uninstall
      ;;
    add)
      cmd_add
      ;;
    remove)
      cmd_remove
      ;;
    update)           cmd_update      ;;
  doctor)           cmd_doctor      ;;
  "")
      usage
      ;;
    *)
      die "未知命令: $COMMAND"
      ;;
  esac
}

main "$@"