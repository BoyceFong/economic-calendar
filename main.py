"""Entry point for the Economic Calendar widget."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from typing import Any

import yaml


def setup_logging(log_dir: str = "data") -> logging.Logger:
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "widget.log")

    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.handlers.clear()

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)-7s] %(name)-12s | %(message)s",
        datefmt="%H:%M:%S",
    )

    ch = logging.StreamHandler(sys.stderr)
    ch.setLevel(logging.INFO)
    ch.setFormatter(fmt)
    root.addHandler(ch)

    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    root.addHandler(fh)

    return root


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def main() -> int:
    parser = argparse.ArgumentParser(description="Investing.com Economic Calendar Widget")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    args = parser.parse_args()

    logger = setup_logging()
    logger.info("=" * 60)
    logger.info("Economic Calendar Widget starting")
    logger.info("Python: %s", sys.executable)
    logger.info("Platform: %s", sys.platform)
    logger.info("=" * 60)

    config = load_config(args.config)

    cache_file = config["cache"]["file"]
    os.makedirs(os.path.dirname(os.path.abspath(cache_file)) or ".", exist_ok=True)
    state_file = config["notifications"]["state_file"]
    os.makedirs(os.path.dirname(os.path.abspath(state_file)) or ".", exist_ok=True)

    from fetcher import EconomicCalendarFetcher
    from notifier import NotificationDispatcher
    from scheduler import AppScheduler
    from state import NotifiedState

    fetcher = EconomicCalendarFetcher(config)
    state = NotifiedState(state_file)
    state.purge_older_than(days=30)
    notifier = NotificationDispatcher(config, state)

    try:
        from PyQt6.QtWidgets import QApplication
        from widget import EconomicCalendarWidget
    except ImportError as exc:
        logger.critical("PyQt6 not installed: %s", exc)
        return 1

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(True)

    widget = EconomicCalendarWidget(config)
    scheduler = AppScheduler(config, fetcher, notifier)

    # Connect scheduler signals to widget
    scheduler.signals.fetch_completed.connect(widget.on_fetch_completed)
    scheduler.signals.fetch_failed.connect(widget.on_fetch_failed)
    scheduler.signals.status_update.connect(widget.set_status)

    # Let widget trigger manual refreshes
    widget.set_scheduler(scheduler)

    widget.show()
    logger.info("Widget displayed")

    scheduler.start()
    refresh_min = config["data_source"].get("refresh_interval_minutes", 2)
    logger.info("Scheduler started (refresh every %d minutes)", refresh_min)

    exit_code = app.exec()
    logger.info("Application exiting with code %d", exit_code)
    scheduler.shutdown()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
