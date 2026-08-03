#!/usr/bin/env bash
# lib/manifest.sh — 解析 manifest/{platform}/{type}.toml，提供 CRUD

MANIFEST_DIR=""

# 加载所有 manifest 文件，构建嵌套 JSON
# 输出: { "platform": { "skills": { "name": {fields...} }, "mcp": {...}, "plugins": {...} } }
load_manifest() {
  local manifest_dir="${1:-$SCRIPT_DIR/manifest}"
  [[ -d "$manifest_dir" ]] || mkdir -p "$manifest_dir"

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

result = {}
base = '$manifest_dir'
for platform_dir in sorted(os.listdir(base)):
    platform_path = os.path.join(base, platform_dir)
    if not os.path.isdir(platform_path):
        continue
    result[platform_dir] = {}
    for toml_file in sorted(glob.glob(os.path.join(platform_path, '*.toml'))):
        try:
            data = parse_toml(toml_file)
            for section, entries in data.items():
                if section not in result[platform_dir]:
                    result[platform_dir][section] = {}
                for name, fields in entries.items():
                    result[platform_dir][section][name] = fields
        except Exception as e:
            print(f'warning: 解析 {toml_file} 失败: {e}', file=sys.stderr)
print(json.dumps(result))
" 2>/dev/null || die "manifest 解析失败"
}

# 获取某平台某类型所有资源名
# 依赖 CURRENT_PLATFORM 环境变量
get_resources() {
  local type="$1"
  local platform="${CURRENT_PLATFORM:-}"
  [[ -z "$platform" ]] && die "get_resources: CURRENT_PLATFORM 未设置"

  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins', 'rule': 'rules'}
section = section_map.get('$type', '${type}s')
for key in data.get('$platform', {}).get(section, {}):
    print(key)
"
}

# 获取资源指定字段
# 依赖 CURRENT_PLATFORM 和 CURRENT_TYPE 环境变量
get_resource_field() {
  local name="$1" field="$2"
  local platform="${CURRENT_PLATFORM:-}"
  local type="${CURRENT_TYPE:-}"
  [[ -z "$platform" ]] && die "get_resource_field: CURRENT_PLATFORM 未设置"
  [[ -z "$type" ]] && die "get_resource_field: CURRENT_TYPE 未设置"

  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins', 'rule': 'rules'}
section = section_map.get('$type', '${type}s')
val = data.get('$platform', {}).get(section, {}).get('$name', {})
if not val:
    print('')
    sys.exit(0)
parts = '$field'.split('.')
for p in parts:
    val = val.get(p, {}) if isinstance(val, dict) else ''
print(json.dumps(val) if isinstance(val, (dict, list)) and len(val) > 0 else ('' if isinstance(val, (dict, list)) else val))
"
}

# 写入 TOML 段
_write_toml_section() {
  local file="$1" section="$2" name="$3"
  shift 3
  # section → TOML 段名：skill→skills, mcp→mcp, plugin→plugins
  local section_name
  case "$section" in
    mcp) section_name="mcp" ;;
    *)   section_name="${section}s" ;;
  esac
  # 确保文件存在且有换行
  [[ -f "$file" ]] && [[ "$(tail -c1 "$file")" != "" ]] && echo "" >> "$file"
  # TOML 裸键只允许 A-Za-z0-9_-，含特殊字符时加引号
  if [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "[$section_name.$name]" >> "$file"
  else
    echo "[$section_name.\"$name\"]" >> "$file"
  fi
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    # 如果值是 JSON 对象，直接写入；否则加引号
    if [[ "$val" == \{* ]] || [[ "$val" == \[* ]]; then
      echo "$key = $val" >> "$file"
    else
      echo "$key = \"$val\"" >> "$file"
    fi
  done
  echo "" >> "$file"
}

# 添加资源到 manifest
add_manifest_entry() {
  local platform="$1" type="$2" name="$3"
  shift 3
  local file="$MANIFEST_DIR/$platform/$type.toml"
  mkdir -p "$(dirname "$file")"
  _write_toml_section "$file" "$type" "$name" "$@"
  # 重新加载
  MANIFEST_JSON="$(load_manifest)"
}

# 从 manifest 移除资源
remove_manifest_entry() {
  local platform="$1" type="$2" name="$3"
  local file="$MANIFEST_DIR/$platform/$type.toml"
  [[ -f "$file" ]] || return 0

  python3 -c "
import sys, json, os

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

file = '$file'
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins', 'rule': 'rules'}
section = section_map.get('$type', '${type}s')
name = '$name'

try:
    data = parse_toml(file)
except Exception:
    sys.exit(0)

if section not in data or name not in data.get(section, {}):
    sys.exit(0)

del data[section][name]

# 重写文件
import re
bare_key = re.compile(r'^[A-Za-z0-9_-]+$')
def quote_key(k):
    return k if bare_key.match(k) else json.dumps(k)
with open(file, 'w') as f:
    for sec_name, entries in data.items():
        for n, fields in entries.items():
            f.write(f'[{sec_name}.{quote_key(n)}]\\n')
            write_toml_fields(f, '', fields)
            f.write('\\n')
" 2>/dev/null || true

  # 重新加载
  MANIFEST_JSON="$(load_manifest)"
}

# 更新 manifest 中资源的字段
update_manifest_entry() {
  local platform="$1" type="$2" name="$3" field="$4" value="$5"
  local file="$MANIFEST_DIR/$platform/$type.toml"
  [[ -f "$file" ]] || die "manifest 文件不存在: $file"

  python3 -c "
import sys, json, os

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

file = '$file'
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins', 'rule': 'rules'}
section = section_map.get('$type', '${type}s')
name = '$name'
field = '$field'
value = '$value'

try:
    data = parse_toml(file)
except Exception as e:
    print(f'解析失败: {e}', file=sys.stderr)
    sys.exit(1)

if section not in data or name not in data.get(section, {}):
    print(f'资源 {name} 不存在', file=sys.stderr)
    sys.exit(1)

# 支持点号路径如 'source.type'
parts = field.split('.')
target = data[section][name]
for p in parts[:-1]:
    if p not in target:
        target[p] = {}
    target = target[p]
target[parts[-1]] = value

# 重写文件
import re
bare_key = re.compile(r'^[A-Za-z0-9_-]+$')
def quote_key(k):
    return k if bare_key.match(k) else json.dumps(k)
with open(file, 'w') as f:
    for sec_name, entries in data.items():
        for n, fields in entries.items():
            f.write(f'[{sec_name}.{quote_key(n)}]\\n')
            write_toml_fields(f, '', fields)
            f.write('\\n')
" 2>/dev/null || die "更新 manifest 失败"

  # 重新加载
  MANIFEST_JSON="$(load_manifest)"
}

# 获取资源所有字段（JSON 格式）
# 依赖 CURRENT_PLATFORM 和 CURRENT_TYPE 环境变量
get_resource_all_fields() {
  local name="$1"
  local platform="${CURRENT_PLATFORM:-}"
  local type="${CURRENT_TYPE:-}"
  [[ -z "$platform" ]] && die "get_resource_all_fields: CURRENT_PLATFORM 未设置"
  [[ -z "$type" ]] && die "get_resource_all_fields: CURRENT_TYPE 未设置"

  python3 -c "
import sys, json
data = json.loads('$MANIFEST_JSON')
section_map = {'skill': 'skills', 'mcp': 'mcp', 'plugin': 'plugins', 'rule': 'rules'}
section = section_map.get('$type', '${type}s')
val = data.get('$platform', {}).get(section, {}).get('$name', {})
if not val:
    sys.exit(0)
print(json.dumps(val, indent=2))
"
}

# 加载时缓存到全局变量
MANIFEST_JSON=""
load_and_cache() {
  local manifest_dir="${1:-$SCRIPT_DIR/manifest}"
  MANIFEST_DIR="$manifest_dir"
  MANIFEST_JSON="$(load_manifest "$manifest_dir")"
}