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

# 列出所有平台已装 vs 清单差异
cmd_list() {
  local all_platforms=(${PLATFORMS[@]})
  local diff_output=""

  for platform in "${all_platforms[@]}"; do
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

# 安装缺失资源
cmd_install() {
  local all_platforms=(${PLATFORMS[@]})
  local types=(${RESOURCE_TYPE:-skill mcp plugin})
  local count=0

  for platform in "${all_platforms[@]}"; do
    echo ""
    echo "=== 安装到 $(tr '[:lower:]' '[:upper:]' <<<"${platform:0:1}")${platform:1} ==="

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

main() {
  parse_args "$@"

  # 检测可用平台
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

main "$@"