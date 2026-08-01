"""Advance-notification dispatcher using macOS ``terminal-notifier``."""

from __future__ import annotations

import logging
import shutil
import subprocess
from datetime import datetime, timedelta
from typing import Any

from fetcher import load_cached_events
from models import LOCAL_TZ, ImportanceLevel
from state import NotifiedState

logger = logging.getLogger(__name__)


class NotificationDispatcher:
    """Scans cached events and fires a native macOS notification ahead of time.

    De-duplication is handled by ``NotifiedState``: once an event ID has fired,
    it won't fire again — even across restarts.
    """

    def __init__(self, config: dict[str, Any], state: NotifiedState) -> None:
        n_cfg = config.get("notifications", {})
        self.enabled: bool = bool(n_cfg.get("enabled", True))
        self.lead_time: timedelta = timedelta(
            minutes=int(n_cfg.get("lead_time_minutes", 15))
        )
        self.min_importance = ImportanceLevel.from_label(
            n_cfg.get("min_importance", "high")
        )
        self.sound: str = n_cfg.get("sound", "default")
        self.cache_file: str = config["cache"]["file"]
        self.state = state
        self._notifier_path: str | None = shutil.which("terminal-notifier")

        if not self.enabled:
            logger.info("Notifications disabled by config")
        elif self._notifier_path is None:
            logger.warning(
                "terminal-notifier not found on PATH; "
                "install with: brew install terminal-notifier"
            )
        else:
            logger.info("Notifier ready: %s (threshold=%s, lead=%dm)",
                        self._notifier_path, self.min_importance.name,
                        int(self.lead_time.total_seconds() / 60))

    def check_and_notify(self, now: datetime | None = None) -> int:
        """Fire notifications for events due within the lead window.

        Returns the number of notifications actually sent.
        """
        if not self.enabled:
            return 0
        if self._notifier_path is None:
            return 0

        now = now or datetime.now(LOCAL_TZ)
        if now.tzinfo is None:
            now = now.replace(tzinfo=LOCAL_TZ)

        events = load_cached_events(self.cache_file)
        eligible = 0
        sent = 0
        for event in events:
            if event.importance < self.min_importance:
                continue
            delta = event.time - now
            if delta.total_seconds() < 0:
                continue
            if delta > self.lead_time:
                continue
            if self.state.is_notified(event.id):
                continue

            eligible += 1
            minutes_left = max(1, int(round(delta.total_seconds() / 60)))
            title = f"Economic Event: {event.currency} {event.name}"
            parts = [f"Starts in {minutes_left} min"]
            if event.forecast:
                parts.append(f"Forecast: {event.forecast}")
            if event.previous:
                parts.append(f"Previous: {event.previous}")
            message = " — ".join(parts)

            if self._fire(title, message, group=event.id):
                self.state.mark_notified(event.id, when=now)
                sent += 1
                logger.info("Notification sent: %s %s (%dm)",
                            event.currency, event.name, minutes_left)

        if sent:
            logger.info("Sent %d notification(s) (%d eligible events scanned)",
                        sent, eligible)
        return sent

    def _fire(self, title: str, message: str, group: str) -> bool:
        cmd = [
            self._notifier_path,
            "-title", title,
            "-message", message,
            "-sound", self.sound,
            "-group", group,
        ]
        try:
            subprocess.run(
                cmd,
                check=False,
                capture_output=True,
                timeout=10,
            )
            return True
        except FileNotFoundError:
            self._notifier_path = None
            logger.warning("terminal-notifier disappeared; disabling")
            return False
        except subprocess.TimeoutExpired:
            logger.warning("terminal-notifier timed out")
            return False
        except Exception as exc:
            logger.error("Failed to fire notification: %s", exc)
            return False
