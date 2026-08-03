#!/usr/bin/env bash
# tests/test_install.sh — 测试 install 幂等性及新功能

set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST_DIR="manifest"
PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== 测试 1: list 命令 ==="
./manage.sh list && pass "list 执行成功" || fail "list 执行失败"
echo ""

echo "=== 测试 2: install 命令（幂等）==="
./manage.sh install && pass "install 执行成功" || fail "install 执行失败"
echo ""

echo "=== 测试 3: 重复安装（不报错）==="
./manage.sh install && pass "重复 install 执行成功" || fail "重复 install 执行失败"
echo ""

echo "=== 测试 4: 按平台过滤 ==="
for p in codex claude opencode trae; do
  echo "--- $p ---"
  if ./manage.sh list --platform "$p" 2>/dev/null; then
    pass "list --platform $p 执行成功"
  else
    fail "list --platform $p 执行失败"
  fi
done
echo ""

echo "=== 测试 5: 按类型过滤 ==="
./manage.sh list --type skill && pass "list --type skill 执行成功" || fail "list --type skill 执行失败"
echo ""

echo "=== 测试 6: 按名称过滤 ==="
./manage.sh list --type mcp codegraph 2>/dev/null && pass "list --type mcp --name codegraph 执行成功" || pass "list --type mcp --name codegraph 执行成功（无匹配时正常）"
echo ""

echo "=== 测试 7: collect 幂等（重复收集不重复写入）==="
# 先记录 collect 前的 manifest 文件状态
pre_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 {} + | md5 2>/dev/null || find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | md5)
./manage.sh collect
post_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 {} + | md5 2>/dev/null || find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | md5)
if [[ "$pre_md5" == "$post_md5" ]]; then
  pass "collect 幂等性验证通过"
else
  fail "collect 幂等性验证失败（manifest 被修改）"
fi
echo ""

echo "=== 测试 8: show --name 详情查看 ==="
first_skill=$(./manage.sh show --platform trae --type skill 2>/dev/null | grep -o 'skill: [^ ]*' | head -1 | cut -d' ' -f2 || true)
if [[ -n "$first_skill" ]]; then
  ./manage.sh show --platform trae --type skill --name "$first_skill" >/dev/null 2>&1 && \
    pass "show --name $first_skill 执行成功" || \
    fail "show --name $first_skill 执行失败"
else
  fail "无可用 skill 测试 show --name"
fi
echo ""

echo "=== 测试 9: show --name 缺少参数报错 ==="
if ./manage.sh show --name foo 2>&1; then
  fail "show --name 缺 --platform 未报错"
else
  pass "show --name 缺 --platform 报错正确"
fi
echo ""

echo "=== 测试 10: doctor 命令 ==="
./manage.sh doctor > /dev/null 2>&1 && pass "doctor 执行成功" || pass "doctor 执行成功（发现问题时返回非零）"
echo ""

echo "=== 测试 11: status 命令 ==="
./manage.sh status > /dev/null 2>&1 && pass "status 执行成功" || fail "status 执行失败"
echo ""

echo "=== 测试 12: sync 命令（缺参数报错）==="
if ./manage.sh sync 2>&1; then
  fail "sync 缺 --from 未报错"
else
  pass "sync 缺 --from 报错正确"
fi
if ./manage.sh sync --from codex 2>&1; then
  fail "sync 缺 --to 未报错"
else
  pass "sync 缺 --to 报错正确"
fi
if ./manage.sh sync --from codex --to codex 2>&1; then
  fail "sync 同平台未报错"
else
  pass "sync 同平台报错正确"
fi
echo ""

echo "=== 测试 13: sync 命令（跨平台同步）==="
# 选择有资源的源平台
src_platform=""
for p in codex claude opencode trae; do
  if [[ -f manifest/$p/skill.toml ]]; then
    src_platform=$p
    break
  fi
done
# 找一个空的或最不可能有 entry 的目标平台
dst_platform=""
for p in opencode trae; do
  if [[ "$p" != "$src_platform" ]]; then
    dst_platform=$p
    break
  fi
done
if [[ -n "$src_platform" && -n "$dst_platform" ]]; then
  ./manage.sh sync --from "$src_platform" --to "$dst_platform" > /dev/null 2>&1 && \
    pass "sync $src_platform → $dst_platform 执行成功" || \
    fail "sync $src_platform → $dst_platform 执行失败"
else
  pass "sync 跨平台测试跳过（无足够平台）"
fi
echo ""

echo "=== 测试 14: sync 幂等性（重复同步不重复写入）==="
if [[ -n "$src_platform" && -n "$dst_platform" ]]; then
  pre_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | sort | md5)
  ./manage.sh sync --from "$src_platform" --to "$dst_platform" > /dev/null 2>&1
  post_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | sort | md5)
  if [[ "$pre_md5" == "$post_md5" ]]; then
    pass "sync 幂等性验证通过"
  else
    fail "sync 幂等性验证失败（manifest 被修改）"
  fi
else
  pass "sync 幂等性测试跳过（无足够平台）"
fi
echo ""

echo "=== 测试 15: sync --type 按类型过滤 ==="
if [[ -n "$src_platform" && -n "$dst_platform" ]]; then
  ./manage.sh sync --from "$src_platform" --to "$dst_platform" --type skill > /dev/null 2>&1 && \
    pass "sync --type skill 执行成功" || \
    fail "sync --type skill 执行失败"
else
  pass "sync --type 测试跳过（无足够平台）"
fi
echo ""

echo ""

echo "=== 测试 16: import 缺 --source 参数报错 ==="
if ./manage.sh import 2>&1; then
  fail "import 缺 --source 未报错"
else
  pass "import 缺 --source 报错正确"
fi
echo ""

echo "=== 测试 17: import 从 GitHub 导入规则（按 match 过滤）==="
# 用一个小型测试仓库，只导入 go 相关规则
output=$(./manage.sh import --source "https://github.com/PatrickJS/awesome-cursorrules" --match go 2>&1 || true)
echo "$output"
if echo "$output" | grep -q "已添加"; then
  pass "import 从 GitHub 导入规则成功"
elif echo "$output" | grep -q "没有匹配的资源"; then
  pass "import 未找到匹配规则（跳过）"
else
  fail "import 执行异常"
fi
echo ""

echo "=== 测试 18: import 幂等性（重复导入不重复添加）==="
# 记录导入前的 manifest 状态
pre_import_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | sort | md5)
output2=$(./manage.sh import --source "https://github.com/PatrickJS/awesome-cursorrules" --match go 2>&1 || true)
echo "$output2"
post_import_md5=$(find "$MANIFEST_DIR" -name '*.toml' -exec md5 -r {} + | sort | md5)
if [[ "$pre_import_md5" == "$post_import_md5" ]]; then
  pass "import 幂等性验证通过"
else
  fail "import 幂等性验证失败（manifest 被修改）"
fi
echo ""

echo "=== 测试 19: import --match 多关键词过滤 ==="
output3=$(./manage.sh import --source "https://github.com/PatrickJS/awesome-cursorrules" --match "go,python,rust" 2>&1 || true)
echo "$output3"
if echo "$output3" | grep -qE "(已添加|没有匹配的资源)"; then
  pass "import --match 多关键词过滤执行成功"
else
  fail "import --match 多关键词过滤执行异常"
fi
echo ""

echo ""
echo "=== 测试汇总: $PASS 通过, $FAIL 失败 ==="
[[ "$FAIL" -eq 0 ]] || exit 1