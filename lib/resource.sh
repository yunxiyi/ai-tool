#!/usr/bin/env bash
# lib/resource.sh — 资源获取 handler

CACHE_DIR="$SCRIPT_DIR/.cache"

# 获取单个资源到本地缓存
# install_resource <name> <type: skill|mcp|plugin>
# 输出: 缓存路径（如果适用）
install_resource() {
  local name="$1" type="$2"

  # 从 manifest 读 source 信息
  local source_type
  source_type=$(get_resource_field "$name" "source.type")
  [[ -z "$source_type" ]] && die "资源 $name 未找到 source.type"

  mkdir -p "$CACHE_DIR"

  case "$source_type" in
    local)
      local src_path
      src_path=$(get_resource_field "$name" "source.path")
      [[ -z "$src_path" ]] && die "资源 $name 缺少 source.path"
      src_path="$SCRIPT_DIR/$src_path"
      if [[ -d "$src_path" ]]; then
        log_info "资源 $name 已存在: $src_path"
        echo "$src_path"
      else
        die "本地资源路径不存在: $src_path"
      fi
      ;;

    git)
      local repo ref subpath
      repo=$(get_resource_field "$name" "source.repo")
      ref=$(get_resource_field "$name" "source.ref")
      [[ -z "$ref" ]] && ref="main"
      subpath=$(get_resource_field "$name" "source.path")

      local dest="$CACHE_DIR/git/$name"
      if [[ -d "$dest/.git" ]]; then
        log_info "更新 git 仓库: $repo ($ref)"
        (cd "$dest" && git fetch origin && git checkout "$ref") || true
      else
        log_info "克隆 git 仓库: $repo"
        git clone --depth 1 --branch "$ref" "https://github.com/$repo.git" "$dest"
      fi

      if [[ -n "$subpath" ]]; then
        echo "$dest/$subpath"
      else
        echo "$dest"
      fi
      ;;

    go_install)
      local go_path
      go_path=$(get_resource_field "$name" "install.path")
      log_info "安装 Go 二进制: $go_path"
      if command -v go &>/dev/null; then
        go install "$go_path"
      else
        die "Go 未安装，无法安装 $go_path"
      fi
      echo ""  # 无缓存路径
      ;;

    npm_install)
      local pkg
      pkg=$(get_resource_field "$name" "install.package")
      log_info "安装 npm 包: $pkg"
      npm install -g "$pkg"
      echo ""
      ;;

    none)
      log_info "资源 $name 无需安装（纯配置）"
      echo ""
      ;;

    marketplace)
      local mkt_name mkt_repo
      mkt_name=$(get_resource_field "$name" "source.name")
      mkt_repo=$(get_resource_field "$name" "source.repo")
      local dest="$HOME/.claude/plugins/marketplaces/$mkt_name"
      if [[ -d "$dest/.git" ]]; then
        log_info "更新 marketplace: $mkt_repo"
        (cd "$dest" && git pull) 2>/dev/null || true
      else
        log_info "克隆 marketplace: $mkt_repo"
        mkdir -p "$HOME/.claude/plugins/marketplaces"
        git clone --depth 1 "https://github.com/$mkt_repo.git" "$dest"
      fi
      echo "$dest"
      ;;

    *)
      die "不支持的 source.type: $source_type"
      ;;
  esac
}