#!/usr/bin/env bash
# 使用项目 venv 内的 Python 运行 widget,绝不触碰系统全局 Python。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

if [ ! -x ".venv/bin/python" ]; then
  echo "ERROR: .venv not found. Run 'bash setup.sh' first." >&2
  exit 1
fi

exec .venv/bin/python main.py "$@"
