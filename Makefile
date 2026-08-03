SHELL := /usr/bin/env bash
.PHONY: help list show install uninstall collect test clean

# 可选参数，通过 make VAR=val 传入
PLATFORM ?=
TYPE     ?=
NAME     ?=

# 将可选参数拼成 manage.sh 的 --flags
_mk_args = $(if $(PLATFORM),--platform $(PLATFORM)) $(if $(TYPE),--type $(TYPE)) $(if $(NAME),--name $(NAME))

help:           ## 显示帮助
	@echo "Usage: make <target> [PLATFORM=...] [TYPE=...] [NAME=...]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Options:"
	@echo "  PLATFORM=trae   限定平台 (codex|claude|opencode|trae)"
	@echo "  TYPE=skill      限定资源类型 (skill|mcp|plugin|rule)"
	@echo "  NAME=foo        限定资源名"
	@echo ""
	@echo "Examples:"
	@echo "  make list                列出所有平台资源差异"
	@echo "  make show                查看 manifest 清单"
	@echo "  make install             安装所有缺失资源"
	@echo "  make collect             收集已装资源到 manifest"
	@echo "  make uninstall           卸载已安装的资源"
	@echo "  make list PLATFORM=trae  仅列出 TRAE 平台"
	@echo "  make install TYPE=mcp    仅安装 MCP 资源"

list:           ## 列出各平台已装资源 vs 清单差异
	./manage.sh list $(_mk_args)

show:           ## 查看 manifest 清单内容
	./manage.sh show $(_mk_args)

install:        ## 安装所有缺失资源
	./manage.sh install $(_mk_args)

collect:        ## 从各平台收集已装资源，写入 manifest
	./manage.sh collect $(_mk_args)

uninstall:       ## 卸载已安装的资源
	./manage.sh uninstall $(_mk_args)

doctor:          ## 健康检查
	./manage.sh doctor $(_mk_args)

status:          ## 全局资源状态概览
	./manage.sh status $(_mk_args)

test:           ## 运行幂等性测试
	bash tests/test_install.sh

clean:          ## 清理缓存（.cache 目录）
	rm -rf .cache
	@echo "✓ 缓存已清理"