#!/usr/bin/env bash
#
# 博客发布：构建 → 自检 → rsync 到服务器 → 线上抽查
#
#   npm run deploy          # 正常发布
#   bash scripts/deploy.sh  # 等价
#
# 可直接用环境变量覆盖，便于临时指向别处：
#   REMOTE=root@1.2.3.4 REMOTE_DIR=/tmp/x bash scripts/deploy.sh
set -euo pipefail

REMOTE="${REMOTE:-root@58.87.89.167}"
REMOTE_DIR="${REMOTE_DIR:-/opt/app/public}"
SITE_URL="${SITE_URL:-https://zhengw-tech.com}"
BUILD_DIR="${BUILD_DIR:-public}"
# 自检下限：正常构建约 280+ 个 html，低于这个数说明构建残缺
MIN_HTML="${MIN_HTML:-250}"

info() { printf '==> %s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

build() {
  info "清理并构建"
  npx hexo clean >/dev/null
  npx hexo g | tail -1
}

# 自检：产物不合理就立刻停，绝不进入 rsync（--delete 会清空生产目录）
check_build() {
  local dir="$1" html_count zero_count
  [[ -f "$dir/index.html" ]] || die "自检失败：$dir/index.html 不存在"
  [[ -f "$dir/404.html" ]] || die "自检失败：$dir/404.html 不存在"
  html_count=$(find "$dir" -name '*.html' | wc -l | tr -d ' ')
  [[ "$html_count" -ge "$MIN_HTML" ]] || die "自检失败：只有 ${html_count} 个 html（少于 ${MIN_HTML}）"
  zero_count=$(find "$dir" -name '*.html' -size 0 | wc -l | tr -d ' ')
  [[ "$zero_count" -eq 0 ]] || die "自检失败：有 ${zero_count} 个 0 字节 html（hexo g 撞上 hexo s？）"
  info "自检通过：${html_count} 个 html，0 个 0 字节文件"
}

sync_site() {
  info "同步到 $REMOTE:$REMOTE_DIR"
  rsync -az --delete --delete-excluded \
    --exclude '._*' --exclude '.DS_Store' \
    "$BUILD_DIR/" "$REMOTE:$REMOTE_DIR/"
}

# 线上抽查：状态码不符就报错退出（发布看起来成功但线上是坏的最坑）
verify_online() {
  local path code body
  info "线上抽查 $SITE_URL"
  for path in "/" "/tags/" "/archives/" "/images/favicon.ico" "/atom.xml"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 20 "$SITE_URL$path")
    [[ "$code" == "200" ]] || die "抽查失败：${SITE_URL}${path} 返回 ${code}（期望 200）"
  done

  body=$(mktemp)
  code=$(curl -s -o "$body" -w '%{http_code}' --max-time 20 "$SITE_URL/__deploy_check_no_such_path__")
  [[ "$code" == "404" ]] || { rm -f "$body"; die "抽查失败：不存在地址返回 ${code}（期望 404）"; }
  grep -q 'error-content' "$body" || { rm -f "$body"; die "抽查失败：404 页不是主题化页面（/404.html 没生效）"; }
  rm -f "$body"
  info "抽查通过：5 个页面 200，不存在地址返回主题化 404"
}

main() {
  if [[ -n "$(git status --porcelain)" ]]; then
    printf '⚠ 工作区有未提交改动，这些内容会被一起发布上线\n'
  fi
  build
  check_build "$BUILD_DIR"
  sync_site
  verify_online
  info "发布完成：$SITE_URL"
}

# 被 source 时只暴露函数，便于单独验证 check_build
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
