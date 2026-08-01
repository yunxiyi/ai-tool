#!/usr/bin/env bash
# lib/manifest.sh — 解析 manifest.toml

MANIFEST_PATH=""

load_manifest() {
  MANIFEST_PATH="${1:-$SCRIPT_DIR/manifest.toml}"
  [[ -f "$MANIFEST_PATH" ]] || die "manifest.toml 不存在: $MANIFEST_PATH"

  # 用 python3 的 tomllib（Python 3.11+）或 tomli 解析
  python3 -c "
import sys, json
try:
    import tomllib
    with open('$MANIFEST_PATH', 'rb') as f:
        data = tomllib.load(f)
except ImportError:
    import tomli
    with open('$MANIFEST_PATH', 'rb') as f:
        data = tomli.load(f)
print(json.dumps(data))
" 2>/dev/null || die "manifest.toml 解析失败，需要 Python 3.11+ 或 tomli 包"
}

# 获取某类型所有资源名
# get_resources <type: skill|mcp|plugin>
get_resources() {
  local type="$1"
  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
# TOML 段名: skills, mcp, plugins（mcp 不加 s）
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins'}
section = section_map.get('$type', '${type}s')
for key in data.get(section, {}):
    print(key)
"
}

# 获取资源指定字段
# get_resource_field <name> <field>
get_resource_field() {
  local name="$1" field="$2"
  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
for section in ['skills', 'mcp', 'plugins']:
    if name in data.get(section, {}):
        val = data[section]['$name']
        # 支持点号路径如 'source.type'
        parts = '$field'.split('.')
        for p in parts:
            val = val.get(p, {}) if isinstance(val, dict) else ''
        print(json.dumps(val) if isinstance(val, (dict, list)) else val)
        sys.exit(0)
print('')
" "$name"
}

# 加载时缓存到全局变量
MANIFEST_JSON=""
load_and_cache() {
  MANIFEST_JSON="$(load_manifest "$@")"
}