#!/usr/bin/env bash
# ============================================================
# EconomicCalendar 一键打包安装脚本
# 用法: bash build.sh
# 流程: venv → 依赖 → Chromium → PyInstaller打包 → 安装到/Applications → 去隔离 → 启动
# 严格遵守"不污染系统全局Python": 所有 pip/python 调用都在 .venv 内
# ============================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# ---- 颜色输出 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}==>${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}  !${NC} $*"; }
fail()  { echo -e "${RED}  ✗${NC} $*" >&2; }

APP_NAME="EconomicCalendar"
APP_BUNDLE="${APP_NAME}.app"
SPEC_FILE="${APP_NAME}.spec"
INSTALL_DIR="/Applications"
BUILT_APP="dist/${APP_BUNDLE}"
INSTALL_PATH="${INSTALL_DIR}/${APP_BUNDLE}"

# ============================================================
# 1. 虚拟环境
# ============================================================
info "检查 Python 虚拟环境"
if [ ! -x ".venv/bin/python" ]; then
  echo "    创建 .venv..."
  python3 -m venv .venv
fi
PY=".venv/bin/python"
PIP=".venv/bin/python -m pip"
ok "venv 就绪 ($($PY --version 2>&1))"

# ============================================================
# 2. 安装依赖
# ============================================================
info "安装 Python 依赖"
$PIP install --upgrade pip --quiet
$PIP install -r requirements.txt --quiet
$PIP install pyinstaller --quiet
ok "依赖安装完成"

# ============================================================
# 3. 安装 Playwright Chromium
# ============================================================
info "确保 Playwright Chromium 浏览器已安装"
$PY -m playwright install chromium 2>&1 | grep -v '^$' || true
ok "Chromium 就绪"

# ============================================================
# 4. 清理旧构建产物
# ============================================================
info "清理旧构建产物"
rm -rf build/ dist/
ok "已清理"

# ============================================================
# 5. PyInstaller 打包
# ============================================================
info "开始打包 ${APP_BUNDLE} (可能需要几分钟)"
.venv/bin/pyinstaller "$SPEC_FILE" --noconfirm 2>&1 | tail -5

if [ ! -d "$BUILT_APP" ]; then
  fail "PyInstaller 打包失败!"
  exit 1
fi
ok "PyInstaller 打包完成"

# ============================================================
# 6. 复制 Playwright Chromium 到 .app 内部
# ============================================================
info "复制 Chromium 浏览器到 app bundle"
BROWSERS_SRC="$HOME/Library/Caches/ms-playwright"
BROWSERS_DEST="${BUILT_APP}/Contents/MacOS/playwright_browsers"

if [ -d "$BROWSERS_SRC" ]; then
  mkdir -p "$BROWSERS_DEST"
  for d in "$BROWSERS_SRC"/chromium*; do
    if [ -d "$d" ]; then
      cp -R "$d" "$BROWSERS_DEST/$(basename "$d")"
    fi
  done
  ok "Chromium 已嵌入 ($(ls "$BROWSERS_DEST" | wc -l | tr -d ' ') 个目录)"
else
  warn "未找到 Playwright 浏览器，数据抓取功能将不可用"
fi

BUILT_SIZE=$(du -sh "$BUILT_APP" | cut -f1)
ok "构建完成: ${BUILT_APP} (${BUILT_SIZE})"

# ============================================================
# 7. 安装到 /Applications (失败则降级到 ~/Applications)
# ============================================================
install_app() {
  local src="$1"
  local dest_dir="$2"
  local dest_path="${dest_dir}/${APP_BUNDLE}"

  # 关闭正在运行的旧实例
  osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
  sleep 1

  # 替换旧版本
  if [ -d "$dest_path" ]; then
    rm -rf "$dest_path"
  fi
  cp -R "$src" "$dest_dir/"
  return $?
}

info "安装 ${APP_BUNDLE}"
INSTALLED_PATH=""
if install_app "$BUILT_APP" "$INSTALL_DIR" 2>/dev/null; then
  INSTALLED_PATH="$INSTALL_PATH"
  ok "已安装到 ${INSTALLED_PATH}"
else
  warn "无法写入 /Applications (需要管理员权限)，尝试 ~/Applications..."
  USER_APPS="$HOME/Applications"
  mkdir -p "$USER_APPS"
  if install_app "$BUILT_APP" "$USER_APPS" 2>/dev/null; then
    INSTALLED_PATH="${USER_APPS}/${APP_BUNDLE}"
    ok "已安装到 ${INSTALLED_PATH}"
  else
    warn "自动安装失败，应用已构建在: ${BUILT_APP}"
    echo ""
    echo -e "  ${BOLD}请手动安装:${NC}"
    echo -e "    1. 在 Finder 中打开: ${PROJECT_DIR}/dist/"
    echo -e "    2. 将 ${APP_BUNDLE} 拖到 /Applications 文件夹"
    echo ""
    INSTALLED_PATH="$BUILT_APP"
  fi
fi

# ============================================================
# 8. 去除 macOS 隔离标记 (避免"无法打开"提示)
# ============================================================
info "去除隔离标记 (quarantine)"
xattr -cr "$INSTALLED_PATH" 2>/dev/null || true
ok "隔离标记已清除"

# ============================================================
# 9. 启动应用
# ============================================================
info "启动 ${APP_NAME}"
open "$INSTALLED_PATH"
ok "应用已启动 — 检查桌面/屏幕边缘"

# ============================================================
# 10. 完成提示
# ============================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ 安装完成!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  应用位置:  ${INSTALLED_PATH}"
echo -e "  应用大小:  ${BUILT_SIZE}"
echo -e "  数据目录:  ~/Library/Application Support/EconomicCalendar/"
echo -e "  日志文件:  ~/Library/Logs/EconomicCalendar/widget.log"
echo ""
echo -e "  ${BOLD}开启开机自启动:${NC}"
echo -e "    右键点击 widget → Launch at Login: Off → 点击切换为 On"
echo ""
echo -e "  ${BOLD}首次启动注意:${NC}"
echo -e "    如果 macOS 仍提示无法打开，请前往:"
echo -e "    系统设置 → 隐私与安全性 → 点击「仍要打开」"
echo ""
