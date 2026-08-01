"""Small JSON-backed store of already-notified event IDs."""

from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime
from typing import Any


class NotifiedState:
    """Tracks which event IDs have already triggered a notification.

    Stored as a dict ``{event_id: {"notified_at": iso8601}}`` so we can later
    purge old entries. Writes are atomic (temp file + rename) to avoid corruption
    if the process is killed mid-write.
    """

    def __init__(self, path: str) -> None:
        self.path = path
        self._state: dict[str, dict[str, str]] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.path):
            self._state = {}
            return
        try:
            with open(self.path, "r", encoding="utf-8") as fh:
                raw = json.load(fh)
            if isinstance(raw, dict):
                self._state = raw
            else:
                self._state = {}
        except (json.JSONDecodeError, OSError):
            self._state = {}

    def _save(self) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(self.path)) or ".", exist_ok=True)
        # Atomic write: write to a temp file in the same dir, then rename.
        fd, tmp_path = tempfile.mkstemp(
            prefix=".notified.",
            suffix=".json",
            dir=os.path.dirname(os.path.abspath(self.path)) or ".",
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(self._state, fh, indent=2, ensure_ascii=False)
            os.replace(tmp_path, self.path)
        except Exception:
            # Best-effort cleanup; failure to persist is non-fatal.
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    def is_notified(self, event_id: str) -> bool:
        return event_id in self._state

    def mark_notified(self, event_id: str, when: datetime | None = None) -> None:
        when = when or datetime.now()
        self._state[event_id] = {"notified_at": when.isoformat()}
        self._save()

    def purge_older_than(self, days: int) -> int:
        """Remove entries older than ``days`` days. Returns the count purged."""
        if days <= 0:
            return 0
        cutoff = datetime.now().timestamp() - days * 86400
        keep: dict[str, dict[str, str]] = {}
        purged = 0
        for eid, meta in self._state.items():
            try:
                ts = datetime.fromisoformat(meta["notified_at"]).timestamp()
            except (KeyError, ValueError):
                keep[eid] = meta
                continue
            if ts >= cutoff:
                keep[eid] = meta
            else:
                purged += 1
        if purged:
            self._state = keep
            self._save()
        return purged

    def as_dict(self) -> dict[str, Any]:
        return dict(self._state)
