#!/usr/bin/env bash
# One-shot bootstrap for the Investing.com Economic Calendar Mac Widget.
# 严格遵守"不污染系统全局 Python":所有 pip/python 调用都显式指向 .venv。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "==> Creating Python virtual environment at .venv"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

# 直接使用 venv 内的解释器,不依赖 source activate
# (避免子 shell 退出后 venv 失效,也避免任何全局污染)
PIP=".venv/bin/python -m pip"
PY=".venv/bin/python"

echo "==> Upgrading pip"
$PIP install --upgrade pip >/dev/null

echo "==> Installing Python dependencies"
$PIP install -r requirements.txt

echo "==> Installing Playwright Chromium browser"
$PY -m playwright install chromium

echo "==> Checking for terminal-notifier"
if ! command -v terminal-notifier >/dev/null 2>&1; then
  echo "    terminal-notifier is NOT installed."
  echo "    Install it with:  brew install terminal-notifier"
  echo "    (The widget will still run without it; notifications will be skipped.)"
else
  echo "    terminal-notifier: $(command -v terminal-notifier)"
fi

echo "==> Ensuring data/ directory exists"
mkdir -p data

# 确保 run.sh 可执行
chmod +x run.sh 2>/dev/null || true

echo ""
echo "Bootstrap complete. Run the widget with:"
echo "    ./run.sh"
echo "    (or: .venv/bin/python main.py)"
