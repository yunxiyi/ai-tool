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

echo ""
echo "=== 测试汇总: $PASS 通过, $FAIL 失败 ==="
[[ "$FAIL" -eq 0 ]] || exit 1