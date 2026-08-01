"""Scheduler using QTimer for reliable Qt-integrated periodic tasks.

Instead of relying on APScheduler (which can have integration issues), we use
QTimer directly for simplicity and reliability with the Qt event loop.
Fetch operations run in background threads to avoid blocking the UI.
"""

from __future__ import annotations

import logging
import threading
from typing import Any

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

from fetcher import EconomicCalendarFetcher
from notifier import NotificationDispatcher

logger = logging.getLogger(__name__)


class SchedulerSignals(QObject):
    """Signals emitted from background threads to safely update the UI."""
    fetch_completed = pyqtSignal(int)
    fetch_failed = pyqtSignal(str)
    status_update = pyqtSignal(str)


class AppScheduler(QObject):
    """Manages periodic data fetching and notification checks using QTimer."""

    def __init__(
        self,
        config: dict[str, Any],
        fetcher: EconomicCalendarFetcher,
        notifier: NotificationDispatcher,
    ) -> None:
        super().__init__()
        self.signals = SchedulerSignals()
        self._fetcher = fetcher
        self._notifier = notifier
        self._fetch_running = False

        refresh_minutes = int(config["data_source"].get("refresh_interval_minutes", 2))
        refresh_minutes = max(1, refresh_minutes)
        self._refresh_ms = refresh_minutes * 60 * 1000

        # Fetch timer - periodic data refresh (connection set up in start())
        self._fetch_timer = QTimer(self)
        self._fetch_initial = True

        # Notify timer - check every 60 seconds
        self._notify_timer = QTimer(self)
        self._notify_timer.timeout.connect(self._check_notifications)

        logger.info(
            "Scheduler configured: fetch every %dm, notify every 60s",
            refresh_minutes,
        )

    def _trigger_fetch(self) -> None:
        """Start a fetch in background thread (debounced)."""
        if self._fetch_running:
            logger.debug("Fetch already running, skipping")
            return
        self._fetch_running = True
        self.signals.status_update.emit("Fetching latest data...")
        logger.info("[scheduler] Starting background fetch")

        def _work():
            try:
                events = self._fetcher.fetch_and_cache()
                count = len(events)
                logger.info("[scheduler] Fetch completed: %d events", count)
                self.signals.fetch_completed.emit(count)
            except Exception as exc:
                logger.error("[scheduler] Fetch failed: %s", exc, exc_info=True)
                self.signals.fetch_failed.emit(str(exc))
            finally:
                self._fetch_running = False

        t = threading.Thread(target=_work, name="fetch-worker", daemon=True)
        t.start()

    def _check_notifications(self) -> None:
        """Run notification check - should be fast, run directly."""
        try:
            self._notifier.check_and_notify()
        except Exception as exc:
            logger.error("[scheduler] Notification check failed: %s", exc, exc_info=True)

    def _on_fetch_timer(self) -> None:
        """Handle fetch timer timeout - first run does initial fetch then switches to periodic."""
        if self._fetch_initial:
            self._fetch_initial = False
            self._trigger_fetch()
            self._fetch_timer.setSingleShot(False)
            self._fetch_timer.start(self._refresh_ms)
            logger.info("Periodic fetch started (%dms interval)", self._refresh_ms)
        else:
            self._trigger_fetch()

    def start(self) -> None:
        """Start all timers."""
        self._notify_timer.start(60_000)
        logger.info("Notification timer started (60s)")

        # First fetch after 3s to let UI appear
        self._fetch_initial = True
        self._fetch_timer.setSingleShot(True)
        self._fetch_timer.timeout.connect(self._on_fetch_timer)
        self._fetch_timer.start(3_000)
        logger.info("Initial fetch scheduled in 3s")

    def trigger_fetch_now(self) -> None:
        """Manually trigger an immediate fetch."""
        logger.info("[scheduler] Manual fetch triggered")
        self._trigger_fetch()

    def shutdown(self) -> None:
        """Stop all timers."""
        try:
            self._fetch_timer.stop()
            self._notify_timer.stop()
            logger.info("Scheduler stopped")
        except Exception:
            pass
