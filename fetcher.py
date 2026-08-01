"""Playwright-based scraper for investing.com economic calendar (2025+ datatable-v2 layout).

Verified DOM structure (2025-07-31):
  - Table class: datatable-v2_table (with Tailwind suffix)
  - Data rows: 9 <td> cells
    cell[0] = mobile combined (time + country code) - md:hidden
    cell[1] = time (desktop)
    cell[2] = country code (2-letter ISO, may be in img alt)
    cell[3] = event name (with <a> tag)
    cell[4] = importance (3 SVG stars; filled = opacity-60)
    cell[5] = actual value
    cell[6] = forecast value
    cell[7] = previous value
    cell[8] = hidden/extra (ignore)
  - Date separator rows: single <td colspan="8"> with text "Weekday, Month D, YYYY"
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import sys
import time
from datetime import datetime, timedelta
from typing import Any

from models import LOCAL_TZ, EconomicEvent, ImportanceLevel, events_to_json

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Country code -> currency mapping
# ---------------------------------------------------------------------------
COUNTRY_TO_CURRENCY: dict[str, str] = {
    "US": "USD", "EU": "EUR", "UK": "GBP", "JP": "JPY", "CN": "CNY",
    "DE": "EUR", "FR": "EUR", "IT": "EUR", "ES": "EUR", "NL": "EUR",
    "AT": "EUR", "BE": "EUR", "PT": "EUR", "FI": "EUR", "IE": "EUR",
    "SK": "EUR", "LU": "EUR", "GR": "EUR", "SI": "EUR", "CY": "EUR",
    "MT": "EUR", "EE": "EUR", "LV": "EUR", "LT": "EUR",
    "CA": "CAD", "AU": "AUD", "NZ": "NZD", "CH": "CHF",
    "KR": "KRW", "HK": "HKD", "SG": "SGD", "IN": "INR",
    "BR": "BRL", "ZA": "ZAR", "MX": "MXN", "RU": "RUB",
    "SE": "SEK", "NO": "NOK", "DK": "DKK", "PL": "PLN",
    "TR": "TRY", "TH": "THB", "ID": "IDR", "MY": "MYR",
    "PH": "PHP", "TW": "TWD", "VN": "VND", "SA": "SAR",
    "AE": "AED", "CL": "CLP", "CO": "COP", "PE": "PEN",
    "CZ": "CZK", "HU": "HUF", "RO": "RON", "IL": "ILS",
}

# ---------------------------------------------------------------------------
# JS extraction for datatable-v2
# ---------------------------------------------------------------------------
EXTRACT_JS = r"""
() => {
    const rows = [];
    const tables = document.querySelectorAll('table');
    if (!tables.length) return rows;

    // Find the calendar table
    let bestTable = null;
    let bestCount = 0;
    tables.forEach(t => {
        const c = t.querySelectorAll('tr').length;
        const isDataTable = t.className.includes('datatable-v2');
        if (isDataTable && c > bestCount) {
            bestCount = c;
            bestTable = t;
        }
    });
    if (!bestTable) {
        tables.forEach(t => {
            const c = t.querySelectorAll('tr').length;
            if (c > bestCount) {
                bestCount = c;
                bestTable = t;
            }
        });
    }
    if (!bestTable) return rows;

    let currentDate = '';
    const allRows = bestTable.querySelectorAll('tr');

    for (let ri = 0; ri < allRows.length; ri++) {
        const tr = allRows[ri];
        const tds = tr.querySelectorAll('td');

        // Date separator: single td with colspan
        if (tds.length === 1 && tds[0].getAttribute('colspan')) {
            const dateText = (tds[0].textContent || '').trim();
            if (dateText && /[A-Z][a-z]+,\s+[A-Z][a-z]+\s+\d{1,2},?\s+\d{4}/.test(dateText)) {
                currentDate = dateText;
            }
            continue;
        }

        if (tds.length < 8) continue;

        // Time: cell[1] (desktop) or cell[0] (mobile)
        let timeText = (tds[1]?.textContent || '').trim();
        if (!timeText || timeText.length < 4) {
            const mobileText = (tds[0]?.textContent || '').trim();
            const m = mobileText.match(/(\d{1,2}:\d{2})/);
            if (m) timeText = m[1];
        }
        if (timeText) {
            const tm = timeText.match(/(\d{1,2}:\d{2})/);
            if (tm) timeText = tm[1];
        }

        // Country code: cell[2] (desktop) - check img alt/text
        let countryCode = '';
        const ccCell = tds[2];
        if (ccCell) {
            // Check for img with alt/title
            const flagImg = ccCell.querySelector('img');
            if (flagImg) {
                countryCode = (flagImg.getAttribute('alt') || flagImg.getAttribute('title') || '').trim();
            }
            // Check text content
            if (!countryCode || countryCode.length !== 2) {
                const txt = (ccCell.textContent || '').trim();
                const mm = txt.match(/([A-Z]{2,3})/);
                if (mm) countryCode = mm[1];
            }
        }
        // Fallback to mobile cell
        if (!countryCode || countryCode.length < 2) {
            const mobileText = (tds[0]?.textContent || '').trim();
            const m = mobileText.match(/\d{1,2}:\d{2}\s*([A-Z]{2,3})/);
            if (m) countryCode = m[1];
        }
        if (countryCode === 'EUR') countryCode = 'EU';

        // Event name and URL from <a> in cell[3]
        const evCell = tds[3];
        let eventName = '';
        let eventUrl = '';
        const eventLink = evCell ? evCell.querySelector('a') : null;
        if (eventLink) {
            eventName = (eventLink.textContent || '').trim();
            eventUrl = eventLink.getAttribute('href') || '';
        }
        if (!eventName && evCell) {
            const fullText = (evCell.textContent || '').trim();
            const actIdx = fullText.search(/Act:|Forecast:|Previous:|Actual:/i);
            eventName = actIdx > 0 ? fullText.substring(0, actIdx).trim() : fullText;
        }
        eventName = eventName.replace(/\s+/g, ' ').trim();
        // Make URL absolute if relative
        if (eventUrl && !eventUrl.startsWith('http')) {
            eventUrl = 'https://www.investing.com' + (eventUrl.startsWith('/') ? '' : '/') + eventUrl;
        }

        // Importance: count filled (opacity-60) stars in cell[4]
        const impCell = tds[4];
        let bullCount = 0;
        if (impCell) {
            const svgs = impCell.querySelectorAll('svg');
            svgs.forEach(svg => {
                const cls = svg.getAttribute('class') || '';
                const parentCls = svg.parentElement ? (svg.parentElement.getAttribute('class') || '') : '';
                if (cls.includes('opacity-60') || parentCls.includes('opacity-60') ||
                    cls.includes('filled') || cls.includes('full')) {
                    bullCount++;
                }
            });
            // Fallback: check fill color
            if (bullCount === 0) {
                svgs.forEach(svg => {
                    const fill = svg.getAttribute('fill') || '';
                    if (fill && fill !== 'none' && fill !== 'transparent' && fill !== '#86868b' && fill !== 'gray') {
                        bullCount++;
                    }
                });
            }
        }
        // Mobile fallback
        if (bullCount === 0) {
            const mobileSvgs = tds[0].querySelectorAll('svg');
            mobileSvgs.forEach(svg => {
                const cls = svg.getAttribute('class') || '';
                if (cls.includes('opacity-60')) bullCount++;
            });
        }
        if (bullCount === 0) bullCount = 1;
        if (bullCount > 3) bullCount = 3;

        // Values
        const actual = (tds[5]?.textContent || '').trim() || null;
        const forecast = (tds[6]?.textContent || '').trim() || null;
        const previous = (tds[7]?.textContent || '').trim() || null;

        if (eventName && timeText && countryCode) {
            rows.push({
                date: currentDate,
                time: timeText,
                countryCode: countryCode,
                bull: bullCount,
                name: eventName,
                url: eventUrl,
                actual: actual,
                forecast: forecast,
                previous: previous,
            });
        }
    }
    return rows;
}
"""

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

DATE_HEADER_RE = re.compile(
    r"([A-Z][a-z]+),\s+([A-Z][a-z]+)\s+(\d{1,2}),?\s+(\d{4})"
)

MONTHS: dict[str, int] = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


def _parse_date_header(text: str) -> tuple[int, int, int] | None:
    m = DATE_HEADER_RE.search(text)
    if not m:
        return None
    _, month_name, day, year = m.groups()
    month_name = month_name.capitalize()
    if month_name not in MONTHS:
        return None
    return (int(year), MONTHS[month_name], int(day))


def _parse_time(text: str, year: int, month: int, day: int) -> datetime:
    text = text.strip()
    m = re.match(r"^(\d{1,2}):(\d{2})(?:\s*(AM|PM|am|pm))?", text)
    if not m:
        return datetime(year, month, day, 0, 0, tzinfo=LOCAL_TZ)
    hour = int(m.group(1))
    minute = int(m.group(2))
    ampm = (m.group(3) or "").upper()
    if ampm == "PM" and hour < 12:
        hour += 12
    elif ampm == "AM" and hour == 12:
        hour = 0
    return datetime(year, month, day, hour, minute, tzinfo=LOCAL_TZ)


def _make_event_id(row: dict[str, Any]) -> str:
    raw = f"{row.get('currency','')}|{row.get('name','')}|{row.get('date','')}|{row.get('time','')}"
    return hashlib.md5(raw.encode("utf-8")).hexdigest()[:12]


def _resolve_currency(row: dict[str, Any]) -> str:
    cc = (row.get("countryCode") or "").strip().upper()
    if cc:
        mapped = COUNTRY_TO_CURRENCY.get(cc)
        if mapped:
            return mapped
        if len(cc) == 3:
            return cc
        if cc == "EU":
            return "EUR"
    return cc or ""


def _parse_row(row: dict[str, Any]) -> EconomicEvent | None:
    currency = _resolve_currency(row)
    if not currency:
        return None
    date_str = row.get("date", "")
    time_str = row.get("time", "")
    ymd = _parse_date_header(date_str)
    if not ymd:
        return None
    year, month, day = ymd
    dt = _parse_time(time_str, year, month, day)
    name = (row.get("name") or "").strip()
    if not name:
        return None
    try:
        bull = int(row.get("bull") or 1)
    except (TypeError, ValueError):
        bull = 1
    return EconomicEvent(
        id=_make_event_id({**row, "currency": currency}),
        time=dt,
        currency=currency,
        importance=ImportanceLevel.from_bull_count(bull),
        name=name,
        actual=row.get("actual"),
        forecast=row.get("forecast"),
        previous=row.get("previous"),
        source_url=row.get("url", ""),
    )


class EconomicCalendarFetcher:
    def __init__(self, config: dict[str, Any]) -> None:
        self.url = config["data_source"]["url"]
        self.cache_file = config["cache"]["file"]
        self.currencies = {c.upper() for c in config["filters"].get("currencies", [])}
        self.min_importance = ImportanceLevel.from_label(
            config["filters"].get("min_importance", "low")
        )
        self.date_range_days = int(config["data_source"].get("date_range_days", 2))
        logger.info(
            "Fetcher initialized: url=%s currencies=%s min_imp=%s range=%dd",
            self.url, self.currencies or "ALL", self.min_importance.name, self.date_range_days,
        )

    def _passes_filters(self, event: EconomicEvent) -> bool:
        if self.currencies and event.currency.upper() not in self.currencies:
            return False
        if event.importance < self.min_importance:
            return False
        # Include from start of yesterday through N days ahead
        now = datetime.now(LOCAL_TZ)
        start = (now - timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        horizon = now.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=self.date_range_days)
        return start <= event.time <= horizon

    def fetch(self) -> list[EconomicEvent]:
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as exc:
            logger.error("playwright not installed: %s", exc)
            return []

        # Use bundled Playwright browsers when running from .app bundle
        import paths
        if paths.is_frozen():
            browsers_dir = paths.app_dir() / "playwright_browsers"
            if browsers_dir.exists():
                os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(browsers_dir)

        start = time.monotonic()
        events: list[EconomicEvent] = []

        try:
            logger.info("Launching headless Chromium...")
            with sync_playwright() as pw:
                browser = pw.chromium.launch(
                    headless=True,
                    args=[
                        "--disable-blink-features=AutomationControlled",
                        "--no-sandbox",
                        "--disable-dev-shm-usage",
                        "--disable-gpu",
                    ],
                )
                context = browser.new_context(
                    user_agent=USER_AGENT,
                    locale="en-US",
                    timezone_id="Asia/Shanghai",
                    viewport={"width": 1440, "height": 900},
                )
                context.route(
                    "**/*",
                    lambda route: (
                        route.abort()
                        if route.request.resource_type in {"image", "media"}
                        else route.continue_()
                    ),
                )
                page = context.new_page()

                logger.info("Navigating to %s ...", self.url)
                page.goto(self.url, wait_until="domcontentloaded", timeout=60_000)

                logger.info("Waiting for calendar table...")
                try:
                    page.wait_for_selector("table[class*='datatable-v2']", timeout=20_000)
                    logger.info("datatable-v2 found")
                except Exception:
                    logger.warning("datatable-v2 not found, waiting...")
                    page.wait_for_timeout(8000)

                # Dismiss cookie popups
                for sel in [
                    "#onetrust-accept-btn-handler",
                    "button[data-testid='uc-accept-all-button']",
                    "button.didomi-continue-without-agreeing",
                    "#sp-accept-all",
                ]:
                    try:
                        el = page.query_selector(sel)
                        if el and el.is_visible():
                            el.click(timeout=2_000)
                            logger.info("Dismissed dialog: %s", sel)
                            page.wait_for_timeout(500)
                    except Exception:
                        pass

                logger.info("Waiting for content render...")
                try:
                    page.wait_for_load_state("networkidle", timeout=15_000)
                except Exception:
                    page.wait_for_timeout(5000)

                page_title = page.title()
                table_count = page.evaluate("document.querySelectorAll('table').length")
                logger.info("Page ready: title='%s' tables=%d", page_title, table_count)

                logger.info("Extracting data with EXTRACT_JS...")
                raw_rows = page.evaluate(EXTRACT_JS)
                raw_count = len(raw_rows) if raw_rows else 0
                logger.info("Extracted %d raw rows", raw_count)

                if raw_rows and raw_count > 0:
                    for i, r in enumerate(raw_rows[:5]):
                        logger.debug("Row %d: date=%r time=%r cc=%r bull=%d name=%r url=%r",
                                    i, r.get('date'), r.get('time'), r.get('countryCode'),
                                    r.get('bull'), r.get('name','')[:40], r.get('url','')[:60])

                    parsed_count = 0
                    for raw in raw_rows:
                        parsed = _parse_row(raw)
                        if parsed is not None:
                            # Only fall back to base URL if JS didn't extract a specific event URL
                            if not parsed.source_url:
                                parsed.source_url = self.url
                            events.append(parsed)
                            parsed_count += 1
                    logger.info("Parsed %d valid events", parsed_count)

                # Save debug HTML if nothing found
                if not events:
                    debug_path = os.path.join(
                        os.path.dirname(self.cache_file) or ".", "debug_page.html"
                    )
                    os.makedirs(os.path.dirname(debug_path) or ".", exist_ok=True)
                    html = page.content()
                    with open(debug_path, "w", encoding="utf-8") as f:
                        f.write(html)
                    logger.warning("Saved debug HTML: %s (%d bytes)", debug_path, len(html))

                browser.close()
        except Exception as exc:
            logger.error("Fetch error: %s", exc, exc_info=True)
            return []

        total_parsed = len(events)
        logger.info("Events before filtering: %d", total_parsed)

        events = [e for e in events if self._passes_filters(e)]
        events.sort(key=lambda e: e.time)

        elapsed = time.monotonic() - start
        logger.info(
            "Fetch done: %d/%d events in %.1fs",
            len(events), total_parsed, elapsed,
        )
        if events:
            logger.info("First: %s %s", events[0].time, events[0].name[:40])
            logger.info("Last: %s %s", events[-1].time, events[-1].name[:40])
        return events

    def fetch_and_cache(self) -> list[EconomicEvent]:
        logger.info("Starting scheduled fetch...")
        events = self.fetch()
        if events:
            self._write_cache(events)
        else:
            logger.warning("Fetch returned 0 events, checking cache fallback...")
            cached = load_cached_events(self.cache_file)
            if cached:
                logger.info("Using %d cached events", len(cached))
                return cached
        return events

    def _write_cache(self, events: list[EconomicEvent]) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(self.cache_file)) or ".", exist_ok=True)
        envelope = events_to_json(events)
        tmp_path = self.cache_file + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as fh:
            json.dump(envelope, fh, indent=2, ensure_ascii=False)
        os.replace(tmp_path, self.cache_file)
        logger.info("Cache updated: %s (%d events)", self.cache_file, len(events))


def load_cached_events(cache_file: str) -> list[EconomicEvent]:
    if not os.path.exists(cache_file):
        return []
    try:
        with open(cache_file, "r", encoding="utf-8") as fh:
            envelope = json.load(fh)
        from models import events_from_json
        return events_from_json(envelope)
    except (json.JSONDecodeError, OSError, KeyError) as exc:
        logger.warning("Failed to read cache: %s", exc)
        return []


def _print_table(events: list[EconomicEvent]) -> None:
    if not events:
        print("(no events)")
        return
    headers = ["Time", "Cur", "Imp", "Event", "Actual", "Forecast", "Previous"]
    rows = []
    for e in events:
        rows.append([
            e.time.strftime("%m-%d %H:%M"),
            e.currency,
            e.importance.name,
            e.name[:55],
            e.actual or "",
            e.forecast or "",
            e.previous or "",
        ])
    widths = [max(len(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    print(fmt.format(*headers))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(fmt.format(*r))


def _main() -> int:
    parser = argparse.ArgumentParser(description="Investing.com economic calendar fetcher")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    parser.add_argument("--dry-run", action="store_true", help="Print events without caching")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(name)-10s | %(message)s",
        datefmt="%H:%M:%S",
    )

    import yaml
    with open(args.config, "r", encoding="utf-8") as fh:
        config = yaml.safe_load(fh)

    fetcher = EconomicCalendarFetcher(config)
    if args.dry_run:
        events = fetcher.fetch()
    else:
        events = fetcher.fetch_and_cache()
    print()
    _print_table(events)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
