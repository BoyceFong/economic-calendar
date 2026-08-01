"""macOS login item management for auto-start on boot.

Uses AppleScript via ``osascript`` to add/remove the app from
System Events login items. This is the most compatible approach
across macOS versions and shows up in System Settings > Login Items.
"""

from __future__ import annotations

import logging
import subprocess
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

_APP_NAME = "EconomicCalendar"


def _app_bundle_path() -> str:
    """Return the path to the .app bundle (frozen) or the script dir (dev).

    In frozen mode: /path/to/EconomicCalendar.app
    In dev mode: the project directory (no .app bundle)
    """
    if getattr(sys, "frozen", False):
        # sys.executable = /path/to/EconomicCalendar.app/Contents/MacOS/EconomicCalendar
        exe = Path(sys.executable).resolve()
        # Walk up: MacOS -> Contents -> EconomicCalendar.app
        app_bundle = exe.parent.parent  # .app directory
        return str(app_bundle)
    # Dev mode: return project dir (auto-start won't work in dev, but won't crash)
    return str(Path(__file__).resolve().parent)


def is_autostart_enabled() -> bool:
    """Check if the app is in the user's login items."""
    try:
        result = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to get the name of every login item'],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            items = result.stdout.strip().split(", ")
            return _APP_NAME in items
    except Exception as exc:
        logger.warning("Failed to check login items: %s", exc)
    return False


def enable_autostart() -> bool:
    """Add the app to login items. Returns True on success."""
    if not getattr(sys, "frozen", False):
        logger.warning("Auto-start can only be enabled in packaged mode")
        return False

    app_path = _app_bundle_path()
    logger.info("Enabling auto-start for: %s", app_path)

    # Remove existing entry first (to avoid duplicates)
    disable_autostart()

    try:
        result = subprocess.run(
            ["osascript", "-e",
             f'tell application "System Events" to make login item at end '
             f'with properties {{path:"{app_path}", hidden:false}}'],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            logger.info("Auto-start enabled successfully")
            return True
        logger.error("osascript error: %s", result.stderr.strip())
    except Exception as exc:
        logger.error("Failed to enable auto-start: %s", exc)
    return False


def disable_autostart() -> bool:
    """Remove the app from login items. Returns True on success."""
    try:
        result = subprocess.run(
            ["osascript", "-e",
             f'tell application "System Events" to delete login item "{_APP_NAME}"'],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            logger.info("Auto-start disabled successfully")
            return True
        # Not found is OK (returncode != 0 but no real error)
        if "not exist" in result.stderr or "Can't get" in result.stderr:
            return True
        logger.warning("osascript warning: %s", result.stderr.strip())
    except Exception as exc:
        logger.error("Failed to disable auto-start: %s", exc)
    return False


def toggle_autostart() -> bool:
    """Toggle auto-start on/off. Returns the new state."""
    if is_autostart_enabled():
        disable_autostart()
        return False
    else:
        enable_autostart()
        return True
