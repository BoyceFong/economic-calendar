"""Data models for economic calendar events."""

from __future__ import annotations

import zoneinfo
from dataclasses import asdict, dataclass
from datetime import datetime
from enum import IntEnum
from typing import Any


class ImportanceLevel(IntEnum):
    """Importance of an economic event, mirroring investing.com's bull-icon scale."""

    LOW = 1
    MEDIUM = 2
    HIGH = 3

    @classmethod
    def from_label(cls, label: str) -> "ImportanceLevel":
        """Parse a case-insensitive label ('low'/'medium'/'high') into the enum."""
        return cls[label.strip().upper()]

    @classmethod
    def from_bull_count(cls, count: int) -> "ImportanceLevel":
        """Map a count of bull icons (1-3) on investing.com to an importance level."""
        if count >= 3:
            return cls.HIGH
        if count == 2:
            return cls.MEDIUM
        return cls.LOW


# Local timezone for the user (Asia/Shanghai per environment).
# Investing.com times are rendered in the viewer's local timezone; we normalize
# everything to this tz for sorting and notification scheduling.
LOCAL_TZ = zoneinfo.ZoneInfo("Asia/Shanghai")


@dataclass
class EconomicEvent:
    """A single row from the investing.com economic calendar."""

    id: str
    time: datetime
    currency: str
    importance: ImportanceLevel
    name: str
    actual: str | None = None
    forecast: str | None = None
    previous: str | None = None
    # Extra metadata kept for debugging / future use
    source_url: str = ""

    def is_high_impact(self) -> bool:
        return self.importance is ImportanceLevel.HIGH

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["time"] = self.time.isoformat()
        d["importance"] = int(self.importance)
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "EconomicEvent":
        time_str: str = d["time"]
        # Support both ISO with tz and naive ISO strings (assume LOCAL_TZ).
        try:
            dt = datetime.fromisoformat(time_str)
        except ValueError:
            dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S")
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=LOCAL_TZ)
        return cls(
            id=d["id"],
            time=dt,
            currency=d["currency"],
            importance=ImportanceLevel(int(d["importance"])),
            name=d["name"],
            actual=d.get("actual"),
            forecast=d.get("forecast"),
            previous=d.get("previous"),
            source_url=d.get("source_url", ""),
        )


def events_to_json(events: list[EconomicEvent]) -> dict[str, Any]:
    """Serialize a list of events to the on-disk cache envelope."""
    return {
        "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
        "events": [e.to_dict() for e in events],
    }


def events_from_json(envelope: dict[str, Any]) -> list[EconomicEvent]:
    """Deserialize the on-disk cache envelope back into a list of events."""
    return [EconomicEvent.from_dict(item) for item in envelope.get("events", [])]
