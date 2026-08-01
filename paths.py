"""Resolve resource and data paths for both dev and packaged (.app) modes.

When running from source (dev):
  - config.yaml, source files are in the project directory
  - data/ is in the project directory

When running from a PyInstaller .app bundle:
  - Bundled resources (config.yaml) are in sys._MEIPASS or alongside the executable
  - User data (cache, state, logs) must go to ~/Library/Application Support/EconomicCalendar/
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

APP_NAME = "EconomicCalendar"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / APP_NAME
LOGS_DIR = Path.home() / "Library" / "Logs" / APP_NAME


def is_frozen() -> bool:
    """True when running inside a PyInstaller bundle."""
    return getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS")


def bundle_dir() -> Path:
    """Directory containing bundled read-only resources (config.yaml, etc.).

    In dev mode: the project source directory.
    In frozen mode: sys._MEIPASS (PyInstaller's temp extraction dir).
    """
    if is_frozen():
        return Path(sys._MEIPASS)  # type: ignore[attr-defined]
    return Path(__file__).resolve().parent


def app_dir() -> Path:
    """Directory of the running .app bundle (frozen) or project dir (dev).

    In frozen mode: the .app/Contents/MacOS/ directory.
    """
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def resource_path(*parts: str) -> str:
    """Absolute path to a bundled read-only resource."""
    return str(bundle_dir().joinpath(*parts))


def data_dir() -> Path:
    """Writable directory for user data (cache, state).

    In dev mode: <project>/data/
    In frozen mode: ~/Library/Application Support/EconomicCalendar/
    """
    if is_frozen():
        d = APP_SUPPORT_DIR
    else:
        d = Path(__file__).resolve().parent / "data"
    d.mkdir(parents=True, exist_ok=True)
    return d


def log_dir() -> Path:
    """Writable directory for log files."""
    if is_frozen():
        d = LOGS_DIR
    else:
        d = Path(__file__).resolve().parent / "data"
    d.mkdir(parents=True, exist_ok=True)
    return d


def config_path() -> str:
    """Path to config.yaml.

    In frozen mode, check user's Application Support first (for overrides),
    then fall back to the bundled default config.
    """
    if is_frozen():
        user_config = APP_SUPPORT_DIR / "config.yaml"
        if user_config.exists():
            return str(user_config)
        return resource_path("config.yaml")
    return str(Path(__file__).resolve().parent / "config.yaml")


def cache_path() -> str:
    """Path to the cache JSON file."""
    return str(data_dir() / "cache.json")


def state_path() -> str:
    """Path to the notified-state JSON file."""
    return str(data_dir() / "notified.json")


def log_path() -> str:
    """Path to the widget log file."""
    return str(log_dir() / "widget.log")


def ensure_user_config() -> None:
    """Copy bundled config.yaml to user's Application Support on first run.

    This allows users to edit config without modifying the .app bundle.
    """
    if not is_frozen():
        return
    user_config = APP_SUPPORT_DIR / "config.yaml"
    if not user_config.exists():
        bundled = Path(resource_path("config.yaml"))
        if bundled.exists():
            APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
            user_config.write_text(bundled.read_text(encoding="utf-8"), encoding="utf-8")
