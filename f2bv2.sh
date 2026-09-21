#!/bin/bash
# 1Panel v2 入口：站点日志在 /opt/1panel/www/sites/*/log
# 实际逻辑在同目录 f2b.sh，会自动探测；找不到 v2 目录时回退到 v1。
set -euo pipefail
export PANEL_FLAVOR="${PANEL_FLAVOR:-v2}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
if [ -f "$SCRIPT_DIR/f2b.sh" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/f2b.sh"
    f2b_main
    exit 0
fi
# 只下了这一份时，从仓库拉取公共脚本
tmp=$(mktemp /root/f2b.XXXXXX.sh)
if curl -fsSL -o "$tmp" https://raw.githubusercontent.com/chrimast/docker/main/f2b.sh; then
    chmod 700 "$tmp"
    # shellcheck source=/dev/null
    . "$tmp"
    f2b_main
    rm -f "$tmp"
else
    echo "错误: 找不到 f2b.sh，且无法从 GitHub 下载" >&2
    rm -f "$tmp"
    exit 1
fi
