#!/usr/bin/env bash
# lib/common.sh — 通用工具函数

set -euo pipefail

# 彩色输出（macOS 兼容）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}✓${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }
die()       { log_error "$*"; exit 1; }

# 检测已安装的平台
# 输出: 空格分隔的平台名列表（codex claude opencode trae）
detect_platforms() {
  local platforms=()
  [[ -f "$HOME/.codex/config.toml" ]] && platforms+=("codex")
  [[ -f "$HOME/.claude/settings.json" ]] && platforms+=("claude")
  [[ -f "$HOME/.config/opencode/opencode.json" ]] && platforms+=("opencode")
  [[ -f "$HOME/.trae-cn/skill-config.json" ]] && platforms+=("trae")
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