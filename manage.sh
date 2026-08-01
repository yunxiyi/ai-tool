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