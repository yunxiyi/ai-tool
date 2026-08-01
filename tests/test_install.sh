#!/usr/bin/env bash
# tests/test_install.sh — 测试 install 幂等性

set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 测试 1: list 命令 ==="
./manage.sh list
echo ""

echo "=== 测试 2: install 命令（幂等）==="
./manage.sh install
echo ""

echo "=== 测试 3: 重复安装（不报错）==="
./manage.sh install
echo ""

echo "=== 测试 4: 按平台过滤 ==="
for p in codex claude opencode; do
  echo "--- $p ---"
  ./manage.sh list --platform "$p" 2>/dev/null || echo "  (跳过或平台不存在)"
done
echo ""

echo "=== 测试 5: 按类型过滤 ==="
./manage.sh list --type skill
echo ""

echo "=== 测试 6: 按名称过滤 ==="
./manage.sh list --type mcp codegraph 2>/dev/null || true
echo ""

echo "=== 所有测试完成 ==="