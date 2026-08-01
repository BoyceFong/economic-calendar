"""Economic Calendar desktop widget.

A clean macOS-style card with rounded corners, opaque background, and
properly clipped children. Single-layer architecture (no inner QFrame).
"""

from __future__ import annotations

import logging
import math
from datetime import datetime
from typing import Any

from PyQt6.QtCore import QPointF, QRect, QRectF, Qt, QTimer, QSize, QEvent, QUrl
from PyQt6.QtGui import (
    QAction,
    QBrush,
    QColor,
    QDesktopServices,
    QFont,
    QFontMetrics,
    QIcon,
    QMouseEvent,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
    QRegion,
    QTextOption,
)
from PyQt6.QtWidgets import (
    QFrame,
    QHeaderView,
    QLabel,
    QMenu,
    QStyledItemDelegate,
    QStyleOptionViewItem,
    QTableWidget,
    QTableWidgetItem,
    QWidget,
    QApplication,
)

from fetcher import load_cached_events
from models import LOCAL_TZ, ImportanceLevel

logger = logging.getLogger(__name__)

COLUMNS = ["TIME", "CUR", "IMP", "EVENT", "ACTUAL", "FORECAST", "PREVIOUS"]
# Fixed column widths — measured from actual content to guarantee no truncation
# TIME: 5-char time "15:30" + pad
# CUR:  flag emoji + 2-char country code + pad
# IMP:  centered dot icon
# ACTUAL/FORECAST/PREVIOUS: numeric values like "6,738B", "2.993M" + header text
COL_WIDTHS = [60, 64, 50, 0, 76, 86, 80]
_EVENT_MIN_WIDTH = 80
# Sum of fixed column widths
_FIXED_COLS_SUM = sum(w for w in COL_WIDTHS if w > 0)

_CORNER_RADIUS = 14
_MARGIN = 14
_TITLE_AREA_H = 44

_TEXT_PRIMARY = QColor(29, 29, 31)
_TEXT_SECONDARY = QColor(60, 60, 67)
_TEXT_TERTIARY = QColor(142, 142, 147)
_GREEN = QColor(52, 199, 89)
_RED = QColor(255, 59, 48)
_BLUE = QColor(0, 122, 255)  # Apple system blue for NOW indicator

_IMP_LOW = QColor(180, 180, 185)
_IMP_MED = QColor(255, 149, 0)
_IMP_HIGH = QColor(255, 59, 48)

_ROW_HEIGHT_SINGLE = 40
_ROW_HEIGHT_DOUBLE = 62
_ROW_HEIGHT_TRIPLE = 86

_BG_CARD = QColor(250, 250, 252)
_BG_ROW_ALT = QColor(246, 246, 249)
_BG_HIGH = QColor(255, 237, 237)
_BG_HOVER = QColor(229, 229, 234)
_BG_HIGH_HOVER = QColor(255, 222, 222)
_LINE = QColor(0, 0, 0, 14)

# Currency code → (flag emoji, country code)
_CURRENCY_TO_FLAG: dict[str, tuple[str, str]] = {
    "USD": ("🇺🇸", "US"),
    "EUR": ("🇪🇺", "EU"),
    "GBP": ("🇬🇧", "UK"),
    "JPY": ("🇯🇵", "JP"),
    "CNY": ("🇨🇳", "CN"),
    "CAD": ("🇨🇦", "CA"),
    "AUD": ("🇦🇺", "AU"),
    "NZD": ("🇳🇿", "NZ"),
    "CHF": ("🇨🇭", "CH"),
    "KRW": ("🇰🇷", "KR"),
    "HKD": ("🇭🇰", "HK"),
    "SGD": ("🇸🇬", "SG"),
    "INR": ("🇮🇳", "IN"),
    "BRL": ("🇧🇷", "BR"),
    "ZAR": ("🇿🇦", "ZA"),
    "MXN": ("🇲🇽", "MX"),
    "RUB": ("🇷🇺", "RU"),
    "SEK": ("🇸🇪", "SE"),
    "NOK": ("🇳🇴", "NO"),
    "DKK": ("🇩🇰", "DK"),
    "PLN": ("🇵🇱", "PL"),
    "TRY": ("🇹🇷", "TR"),
    "THB": ("🇹🇭", "TH"),
    "IDR": ("🇮🇩", "ID"),
    "MYR": ("🇲🇾", "MY"),
    "PHP": ("🇵🇭", "PH"),
    "TWD": ("🇹🇼", "TW"),
    "VND": ("🇻🇳", "VN"),
    "SAR": ("🇸🇦", "SA"),
    "AED": ("🇦🇪", "AE"),
    "CLP": ("🇨🇱", "CL"),
    "COP": ("🇨🇴", "CO"),
    "PEN": ("🇵🇪", "PE"),
    "CZK": ("🇨🇿", "CZ"),
    "HUF": ("🇭🇺", "HU"),
    "RON": ("🇷🇴", "RO"),
    "ILS": ("🇮🇱", "IL"),
}


def _flag_and_code(currency: str) -> str:
    """Return '🇺🇸 US' style label for a currency code."""
    info = _CURRENCY_TO_FLAG.get(currency.upper())
    if info:
        return f"{info[0]} {info[1]}"
    # Fallback: show currency code without flag
    return f"  {currency}"


def _try_float(text: str | None) -> float | None:
    if not text:
        return None
    try:
        return float(text.strip().rstrip("%").replace(",", ""))
    except ValueError:
        return None


def _make_star_path(cx: float, cy: float, r: float) -> QPainterPath:
    """Create a 5-point star path centered at (cx, cy) with radius r."""
    path = QPainterPath()
    for i in range(10):
        angle = -math.pi / 2 + i * math.pi / 5
        radius = r if i % 2 == 0 else r * 0.4
        x = cx + radius * math.cos(angle)
        y = cy + radius * math.sin(angle)
        if i == 0:
            path.moveTo(x, y)
        else:
            path.lineTo(x, y)
    path.closeSubpath()
    return path


def _make_stars_pixmap(level: ImportanceLevel, star_size: int = 13, gap: int = 2) -> QPixmap:
    """Create a pixmap with 1-3 filled stars showing importance level.

    Uses the same color scheme as investing.com:
      - 1 star (LOW): gray
      - 2 stars (MEDIUM): orange
      - 3 stars (HIGH): red
    """
    count = int(level)  # 1, 2, or 3
    color = _IMP_HIGH if level is ImportanceLevel.HIGH else (
        _IMP_MED if level is ImportanceLevel.MEDIUM else _IMP_LOW
    )
    total_w = count * star_size + (count - 1) * gap
    pm = QPixmap(total_w, star_size)
    pm.fill(Qt.GlobalColor.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(color)
    r = star_size / 2.0 - 1
    for i in range(count):
        cx = r + 1 + i * (star_size + gap)
        cy = star_size / 2.0
        path = _make_star_path(cx, cy, r)
        p.drawPath(path)
    p.end()
    return pm


class EventRowDelegate(QStyledItemDelegate):
    """Paints row backgrounds, wrapped text, and the 'NOW' indicator.

    All backgrounds are fully opaque — critical to prevent ghosting.
    EVENT column text wraps to at most 2 lines.
    """

    def __init__(self, table: QTableWidget) -> None:
        super().__init__(table)
        self._table = table
        self._hover_row: int = -1
        self._now_row: int = -1
        self._now_y: float = 0.0  # y-offset within the row for the NOW line
        # Cache for text wrap measurement
        self._row_heights: dict[int, int] = {}

    def set_hover(self, row: int) -> None:
        if row != self._hover_row:
            self._hover_row = row
            self._table.viewport().update()

    def set_now(self, row: int, y: float) -> None:
        if row != self._now_row or abs(y - self._now_y) > 0.5:
            self._now_row = row
            self._now_y = y
            self._table.viewport().update()

    def clear_now(self) -> None:
        if self._now_row != -1:
            self._now_row = -1
            self._table.viewport().update()

    def invalidate_heights(self) -> None:
        self._row_heights.clear()

    def sizeHint(self, opt: QStyleOptionViewItem, idx: QModelIndex) -> QSize:
        row = idx.row()
        col = idx.column()
        if col == 3 and row in self._row_heights:
            return QSize(opt.rect.width(), self._row_heights[row])
        return super().sizeHint(opt, idx)

    def paint(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        row = idx.row()
        col = idx.column()

        # ── Opaque background ──
        bg = self._bg_for_row(row)
        painter.fillRect(opt.rect, bg)

        # ── Bottom separator line ──
        painter.setPen(QPen(_LINE, 1))
        by = opt.rect.bottom()
        painter.drawLine(opt.rect.left(), by, opt.rect.right(), by)

        # ── Text / icon ──
        if col == 3:
            # EVENT column: draw with word wrap (no default paint)
            self._paint_event_text(painter, opt, idx)
        elif col == 1:
            # CUR column: custom paint flag+code (no default paint)
            self._paint_cur_text(painter, opt, idx)
        elif col == 2:
            # IMP column: custom center the dot icon (no default paint)
            self._paint_imp_dot(painter, opt, idx)
        elif col == 0:
            # TIME column: custom paint to guarantee no elision
            self._paint_time_text(painter, opt, idx)
        else:
            # Numeric columns (ACTUAL, FORECAST, PREVIOUS): custom paint, right-aligned
            self._paint_num_text(painter, opt, idx)

        # ── NOW indicator — drawn in LAST column so it overpaints all columns ──
        # Col 6 (PREVIOUS) is the last column painted in each row, so drawing here
        # ensures the full-width blue line + pill appear on top of every column.
        if col == 6 and row == self._now_row:
            self._draw_now(painter, opt.rect)

    # ── Custom cell painters ─────────────────────────────────────

    def _paint_event_text(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        text = idx.data(Qt.ItemDataRole.DisplayRole) or ""
        painter.save()
        painter.setClipRect(opt.rect)
        font = QFont(self._table.font())
        painter.setFont(font)
        painter.setPen(_TEXT_PRIMARY)
        pad = 8
        # Vertical padding (6px top/bottom) to prevent text from looking cramped,
        # especially when wrapping to 2-3 lines.
        text_rect = opt.rect.adjusted(pad, 6, -pad, -6)
        to = QTextOption()
        to.setWrapMode(QTextOption.WrapMode.WordWrap)
        to.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
        painter.drawText(QRectF(text_rect), text, to)
        painter.restore()

    def _paint_cur_text(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        text = idx.data(Qt.ItemDataRole.DisplayRole) or ""
        painter.save()
        painter.setClipRect(opt.rect)
        font = QFont(self._table.font())
        font.setWeight(QFont.Weight.DemiBold)
        painter.setFont(font)
        painter.setPen(_TEXT_PRIMARY)
        # Center the flag+code text
        to = QTextOption()
        to.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignHCenter)
        painter.drawText(QRectF(opt.rect), text, to)
        painter.restore()

    def _paint_imp_dot(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        """Center the importance stars icon in the cell."""
        icon = idx.data(Qt.ItemDataRole.DecorationRole)
        if icon is None:
            return
        painter.save()
        pm = icon.pixmap(QSize(48, 16))
        r = opt.rect
        x = r.x() + (r.width() - pm.width()) // 2
        y = r.y() + (r.height() - pm.height()) // 2
        painter.drawPixmap(x, y, pm)
        painter.restore()

    def _paint_time_text(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        """Draw TIME column text — left-aligned, no elision, secondary color."""
        text = idx.data(Qt.ItemDataRole.DisplayRole) or ""
        painter.save()
        font = idx.data(Qt.ItemDataRole.FontRole) or QFont(self._table.font())
        painter.setFont(font)
        brush = idx.data(Qt.ItemDataRole.ForegroundRole)
        if brush is not None and isinstance(brush, QBrush):
            painter.setPen(brush.color())
        else:
            painter.setPen(_TEXT_SECONDARY)
        pad = 8
        text_rect = opt.rect.adjusted(pad, 0, -pad, 0)
        to = QTextOption()
        to.setWrapMode(QTextOption.WrapMode.NoWrap)
        to.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
        painter.drawText(QRectF(text_rect), text, to)
        painter.restore()

    def _paint_num_text(self, painter: QPainter, opt: QStyleOptionViewItem, idx: QModelIndex) -> None:
        """Draw numeric columns (ACTUAL/FORECAST/PREVIOUS) — right-aligned, no elision."""
        text = idx.data(Qt.ItemDataRole.DisplayRole) or ""
        painter.save()
        font = idx.data(Qt.ItemDataRole.FontRole) or QFont(self._table.font())
        painter.setFont(font)
        brush = idx.data(Qt.ItemDataRole.ForegroundRole)
        if brush is not None and isinstance(brush, QBrush):
            painter.setPen(brush.color())
        else:
            painter.setPen(_TEXT_TERTIARY)
        pad = 8
        text_rect = opt.rect.adjusted(pad, 0, -pad, 0)
        to = QTextOption()
        to.setWrapMode(QTextOption.WrapMode.NoWrap)
        to.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight)
        painter.drawText(QRectF(text_rect), text, to)
        painter.restore()

    # ── Background ────────────────────────────────────────────────

    def _bg_for_row(self, row: int) -> QColor:
        high_map = getattr(self._table, '_high_rows', {})
        high = high_map.get(row, False)
        if row == self._hover_row:
            return _BG_HIGH_HOVER if high else _BG_HOVER
        if high:
            return _BG_HIGH
        return _BG_ROW_ALT if row % 2 == 1 else _BG_CARD

    # ── NOW indicator (blue pill + line) ─────────────────────────

    def _draw_now(self, painter: QPainter, cell: QRect) -> None:
        """Draw the NOW indicator (blue pill + full-width line) on the viewport.
        Called from col 6 (last column) so the overlay paints on top of all columns.
        """
        vp = self._table.viewport()
        y = cell.top() + self._now_y
        pill_h = 18
        pill_w = 42
        pill_r = 9
        pill_x = 6  # offset from left edge of viewport
        pill_y = int(y) - pill_h // 2

        painter.save()
        # Expand clip to full viewport width so we can draw across all columns
        painter.setClipRect(QRect(0, cell.top(), vp.width(), cell.height()))
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # 1. Draw the full blue line across the entire viewport width (under the pill)
        line_pen = QPen(_BLUE, 1.5)
        painter.setPen(line_pen)
        painter.drawLine(0, int(y), vp.width(), int(y))

        # 2. Draw blue pill background (on top of the line) at left edge
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(_BLUE)
        pill_rect = QRectF(pill_x, pill_y, pill_w, pill_h)
        path = QPainterPath()
        path.addRoundedRect(pill_rect, pill_r, pill_r)
        painter.drawPath(path)

        # 3. Draw "NOW" text in white on the pill
        painter.setPen(QColor(255, 255, 255))
        now_font = QFont(self._table.font())
        now_font.setBold(True)
        now_font.setPointSize(8)
        painter.setFont(now_font)
        painter.drawText(pill_rect, Qt.AlignmentFlag.AlignCenter, "NOW")

        painter.restore()


class EconomicCalendarWidget(QWidget):
    """Main economic calendar widget — frameless rounded card."""

    def __init__(self, config: dict[str, Any]) -> None:
        super().__init__()
        logger.info("Initializing widget")
        self.config = config
        wc = config["widget"]
        g = wc["geometry"]
        self._scheduler = None
        self._always_on_top = bool(wc.get("always_on_top", False))

        self._events: list = []
        self._hover_row: int = -1
        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.timeout.connect(self.persist_geometry)

        # Auto-hide scrollbar timer
        self._scroll_hide_timer = QTimer(self)
        self._scroll_hide_timer.setSingleShot(True)
        self._scroll_hide_timer.timeout.connect(self._hide_scrollbars)

        # Row height recalculation timer (debounced on resize)
        self._row_height_timer = QTimer(self)
        self._row_height_timer.setSingleShot(True)
        self._row_height_timer.timeout.connect(self._recalc_row_heights)

        self._filters = {
            "currencies": set(),
            "min_importance": ImportanceLevel.LOW,
        }
        self._scrollbars_visible = False

        flags = Qt.WindowType.FramelessWindowHint
        if self._always_on_top:
            flags |= Qt.WindowType.WindowStaysOnTopHint
        self.setWindowFlags(flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)

        self.font_family = wc.get("font_family", ".AppleSystemUIFont")
        self.font_size = int(wc.get("font_size", 12))
        self.cache_file = config["cache"]["file"]

        self.setGeometry(g["x"], g["y"], g["width"], g["height"])
        # Min width = fixed columns + EVENT minimum + margins (14 each side)
        min_w = _FIXED_COLS_SUM + _EVENT_MIN_WIDTH + _MARGIN * 2
        self.setMinimumSize(min_w, 300)

        self._build_ui()

        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self.refresh)
        self._refresh_timer.start(10_000)

        self._now_timer = QTimer(self)
        self._now_timer.timeout.connect(self._update_now)
        self._now_timer.start(30_000)

        QTimer.singleShot(150, self.refresh)

    def set_scheduler(self, sched) -> None:
        self._scheduler = sched

    # ── UI ───────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # No QLayout on self — manual positioning to avoid layout artifacts.
        self._title_label = QLabel("Economic Calendar", self)
        self._title_label.setStyleSheet(
            "color: #1d1d1f; font-weight: 600; font-size: 16px; background: transparent;"
        )
        self._title_label.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)

        self._title_count = QLabel("", self)
        self._title_count.setStyleSheet(
            "color: #8e8e93; font-size: 14px; background: transparent;"
        )
        self._title_count.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        self._title_count.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)

        self._sep = QFrame(self)
        self._sep.setFrameShape(QFrame.Shape.HLine)
        self._sep.setStyleSheet(
            "background-color: rgba(0,0,0,14); border: none; max-height:1px; min-height:1px;"
        )
        self._sep.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)

        self._build_table()

        self._status = QLabel("Initializing…", self)
        self._status.setStyleSheet(
            "color: #8e8e93; font-size: 11px; background: transparent;"
        )
        self._status.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)

        self._update_geometry()

    def _build_table(self) -> None:
        self.table = QTableWidget(0, len(COLUMNS), self)
        t = self.table

        t.setHorizontalHeaderLabels(COLUMNS)
        t.verticalHeader().setVisible(False)
        t.setSelectionMode(QTableWidget.SelectionMode.NoSelection)
        t.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        t.setShowGrid(False)
        t.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        t.setAlternatingRowColors(False)
        t.setSortingEnabled(False)
        t.setFrameShape(QFrame.Shape.NoFrame)
        t.setWordWrap(True)
        # Disable text elision — never truncate with "..."
        t.setTextElideMode(Qt.TextElideMode.ElideNone)

        # Viewport: opaque background
        vp = t.viewport()
        vp.setStyleSheet(
            f"background-color: rgb({_BG_CARD.red()},{_BG_CARD.green()},{_BG_CARD.blue()});"
            "border: none;"
        )

        # Delegate
        self._delegate = EventRowDelegate(t)
        t.setItemDelegate(self._delegate)
        t._high_rows = {}

        # Column sizing strategy:
        # - Fixed columns (TIME, CUR, IMP, ACTUAL, FORECAST, PREVIOUS): Fixed mode
        #   → exact width, never compressed or stretched
        # - EVENT column: Interactive mode, width is manually set to fill remaining
        #   space (see _layout_columns()). This guarantees fixed columns never
        #   get truncated regardless of window size.
        for i, w in enumerate(COL_WIDTHS):
            if w > 0:
                t.setColumnWidth(i, w)
                t.horizontalHeader().setSectionResizeMode(i, QHeaderView.ResizeMode.Fixed)
            else:
                t.horizontalHeader().setSectionResizeMode(i, QHeaderView.ResizeMode.Interactive)
                t.setColumnWidth(i, _EVENT_MIN_WIDTH)
        # Global minimum section size (smallest column is IMP at 36px)
        t.horizontalHeader().setMinimumSectionSize(30)
        t.horizontalHeader().setStretchLastSection(False)

        # Row heights
        vh = t.verticalHeader()
        vh.setDefaultSectionSize(_ROW_HEIGHT_SINGLE)
        vh.setMinimumSectionSize(_ROW_HEIGHT_SINGLE)
        vh.setMaximumSectionSize(_ROW_HEIGHT_TRIPLE)

        # Header
        hh = t.horizontalHeader()
        hh.setFixedHeight(30)
        hh.setStyleSheet(f"""
            QHeaderView::section {{
                background-color: rgb({_BG_CARD.red()},{_BG_CARD.green()},{_BG_CARD.blue()});
                color: #8e8e93;
                padding: 0 6px;
                border: none;
                border-bottom: 1px solid rgba(0,0,0,14);
                font-weight: 600;
                font-size: 10px;
            }}
        """)
        hh.setDefaultAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)

        # Table stylesheet — scrollbars hidden by default (width:0), shown on scroll
        self._apply_table_stylesheet(hide_scrollbars=True)

        f = QFont(self.font_family, self.font_size)
        t.setFont(f)

        vp.installEventFilter(self)

        # Connect scrollbars for auto-hide
        t.verticalScrollBar().valueChanged.connect(self._on_scroll)
        t.horizontalScrollBar().valueChanged.connect(self._on_scroll)

    def _apply_table_stylesheet(self, hide_scrollbars: bool) -> None:
        """Apply stylesheet with scrollbars visible or hidden."""
        sb_width = "0px" if hide_scrollbars else "5px"
        sb_margin = "0px" if hide_scrollbars else "1px"
        sb_handle_bg = "transparent" if hide_scrollbars else "rgba(0,0,0,18)"
        sb_handle_bg_hover = "transparent" if hide_scrollbars else "rgba(0,0,0,38)"
        h_sb_height = "0px" if hide_scrollbars else "5px"

        self.table.setStyleSheet(f"""
            QTableWidget {{
                background-color: rgb({_BG_CARD.red()},{_BG_CARD.green()},{_BG_CARD.blue()});
                color: #1d1d1f;
                border: none;
                outline: none;
                gridline-color: transparent;
                font-family: "{self.font_family}";
                font-size: {self.font_size}px;
            }}
            QTableWidget QTableCornerButton::section {{
                background: transparent;
                border: none;
            }}
            QTableWidget::item {{
                padding: 0 8px;
            }}
            QTableWidget::item:selected {{
                background: transparent;
                color: inherit;
            }}
            QScrollBar:vertical {{
                background: transparent;
                width: {sb_width};
                margin: {sb_margin};
            }}
            QScrollBar::handle:vertical {{
                background: {sb_handle_bg};
                border-radius: 2px;
                min-height: 30px;
            }}
            QScrollBar::handle:vertical:hover {{
                background: {sb_handle_bg_hover};
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height:0; background:none; border:none;
            }}
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{
                background: none;
            }}
            QScrollBar:horizontal {{
                background: transparent;
                height: {h_sb_height};
                margin: {sb_margin};
            }}
            QScrollBar::handle:horizontal {{
                background: {sb_handle_bg};
                border-radius: 2px;
                min-width: 30px;
            }}
            QScrollBar::handle:horizontal:hover {{
                background: {sb_handle_bg_hover};
            }}
            QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
                width:0; background:none; border:none;
            }}
            QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {{
                background: none;
            }}
        """)
        self._scrollbars_visible = not hide_scrollbars

    def _on_scroll(self) -> None:
        """Show scrollbars when scrolling, auto-hide after 1.5s of inactivity."""
        if not self._scrollbars_visible:
            self._apply_table_stylesheet(hide_scrollbars=False)
        self._scroll_hide_timer.start(1500)

    def _hide_scrollbars(self) -> None:
        if self._scrollbars_visible:
            self._apply_table_stylesheet(hide_scrollbars=True)

    def _layout_columns(self, table_w: int) -> None:
        """Force fixed columns to their exact widths; EVENT gets remaining space.

        This is called on every resize/geometry update to guarantee that
        fixed-width columns (TIME, CUR, IMP, ACTUAL, FORECAST, PREVIOUS) are
        NEVER compressed, regardless of how small the window gets.
        Minimum window width ensures EVENT always has at least _EVENT_MIN_WIDTH.
        """
        t = self.table
        # Re-apply fixed column widths (defensive — prevents any compression)
        for i, w in enumerate(COL_WIDTHS):
            if w > 0:
                if t.columnWidth(i) != w:
                    t.setColumnWidth(i, w)
        # EVENT column (index 3) fills the remaining space
        event_w = table_w - _FIXED_COLS_SUM
        # account for vertical scrollbar if visible (~5px when shown)
        vsb = t.verticalScrollBar()
        if vsb.isVisible() and vsb.width() > 0:
            event_w -= vsb.width()
        event_w = max(event_w, _EVENT_MIN_WIDTH)
        if t.columnWidth(3) != event_w:
            t.setColumnWidth(3, event_w)

    def _update_geometry(self) -> None:
        w, h = self.width(), self.height()
        m = _MARGIN

        # Title area
        self._title_label.setGeometry(m, m - 2, w // 2 - m, _TITLE_AREA_H)
        self._title_count.setGeometry(w // 2, m - 2, w // 2 - m, _TITLE_AREA_H)

        sep_y = m + _TITLE_AREA_H - 6
        self._sep.setGeometry(m, sep_y, w - 2 * m, 1)

        # Table fills middle
        table_top = sep_y + 3
        table_h = h - table_top - 28
        table_w = w - 2 * m
        self.table.setGeometry(m, table_top, table_w, table_h)

        # Enforce column widths — fixed columns stay exact, EVENT fills remaining
        self._layout_columns(table_w)

        # Status bar at bottom
        self._status.setGeometry(m, h - 22, w - 2 * m, 18)

        self._update_mask()

    def resizeEvent(self, e) -> None:
        super().resizeEvent(e)
        self._update_geometry()
        self._delegate.invalidate_heights()
        # Debounce row height recalculation until resize settles
        self._row_height_timer.start(50)
        # Hide scrollbars during resize (they only show during active scroll)
        if self._scrollbars_visible:
            self._apply_table_stylesheet(hide_scrollbars=True)

    # ── Painting ─────────────────────────────────────────────────────

    def paintEvent(self, e) -> None:
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        w, h = self.width(), self.height()
        r = _CORNER_RADIUS

        # Clear entire widget first
        p.setCompositionMode(QPainter.CompositionMode.CompositionMode_Source)
        p.fillRect(0, 0, w, h, Qt.GlobalColor.transparent)
        p.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceOver)

        # Card background
        path = QPainterPath()
        path.addRoundedRect(QRectF(0, 0, w, h), r, r)
        p.fillPath(path, _BG_CARD)

        # Card border
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.setPen(QPen(QColor(0, 0, 0, 25), 1))
        p.drawRoundedRect(QRectF(0.5, 0.5, w - 2, h - 2), r - 0.5, r - 0.5)

        # Subtle top highlight
        p.fillRect(QRectF(1, 1, w - 2, r), QColor(255, 255, 255, 25))

        p.end()

    # ── Mouse / Drag ─────────────────────────────────────────────────

    def _drag_area_top(self) -> int:
        m = _MARGIN
        return m + _TITLE_AREA_H - 6 + 3

    def mousePressEvent(self, e: QMouseEvent) -> None:
        if e.button() == Qt.MouseButton.LeftButton:
            if e.position().y() < self._drag_area_top():
                window = self.windowHandle()
                if window is not None:
                    window.startSystemMove()
                    e.accept()
                    QTimer.singleShot(100, self._delayed_save_geometry)
                    return
        super().mousePressEvent(e)

    def _delayed_save_geometry(self) -> None:
        QTimer.singleShot(500, self.persist_geometry)

    def moveEvent(self, e) -> None:
        super().moveEvent(e)
        self._save_timer.start(500)
        self._update_mask()

    # ── Mask ─────────────────────────────────────────────────────────

    def _update_mask(self) -> None:
        w, h = self.width(), self.height()
        path = QPainterPath()
        path.addRoundedRect(QRectF(0, 0, w, h), _CORNER_RADIUS, _CORNER_RADIUS)
        self.setMask(QRegion(path.toFillPolygon().toPolygon()))

    # ── Event Filter ─────────────────────────────────────────────────

    def eventFilter(self, obj, event):
        if obj is self.table.viewport():
            et = event.type()
            if et == QEvent.Type.MouseMove:
                pos = event.position().toPoint()
                idx = self.table.indexAt(pos)
                row = idx.row() if idx.isValid() else -1
                if row != self._hover_row:
                    self._hover_row = row
                    self._delegate.set_hover(row)
            elif et == QEvent.Type.Leave:
                if self._hover_row != -1:
                    self._hover_row = -1
                    self._delegate.set_hover(-1)
            elif et == QEvent.Type.MouseButtonPress:
                pos = event.position().toPoint()
                idx = self.table.indexAt(pos)
                if idx.isValid() and event.button() == Qt.MouseButton.LeftButton:
                    if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
                        self._copy(idx.row())
                        event.accept()
                        return True
            elif et == QEvent.Type.MouseButtonDblClick:
                pos = event.position().toPoint()
                idx = self.table.indexAt(pos)
                if idx.isValid():
                    self._open_browser(idx.row())
                    event.accept()
                    return True
        return super().eventFilter(obj, event)

    def contextMenuEvent(self, event) -> None:
        menu = QMenu(self)
        menu.setStyleSheet("""
            QMenu {
                background: rgba(248,248,250,252);
                border: 1px solid rgba(0,0,0,10);
                border-radius: 10px;
                padding: 6px;
            }
            QMenu::item { padding: 7px 22px; border-radius: 6px; color: #1d1d1f; }
            QMenu::item:selected { background: rgba(0,0,0,7); }
            QMenu::separator { height: 1px; background: rgba(0,0,0,7); margin: 4px 10px; }
        """)

        gp = event.pos()
        idx = self.table.indexAt(gp)
        over = idx.row() if idx.isValid() else -1

        if 0 <= over < len(self._events):
            ev = self._events[over]
            a = QAction(f"  {ev.name[:55]}", menu)
            a.setEnabled(False)
            menu.addAction(a)
            menu.addSeparator()
            a = QAction("  Copy event details", menu)
            a.triggered.connect(lambda: self._copy(over))
            menu.addAction(a)
            a = QAction("  Open in browser", menu)
            a.triggered.connect(lambda: self._open_browser(over))
            menu.addAction(a)
            menu.addSeparator()

        cm = menu.addMenu("  Filter by currency")
        for cur in sorted({e.currency for e in self._events}):
            a = QAction(f"  {cur}", cm)
            a.setCheckable(True)
            a.setChecked(cur in self._filters["currencies"])
            a.triggered.connect(lambda checked, c=cur: self._toggle_cur(c, checked))
            cm.addAction(a)
        if self._filters["currencies"]:
            a = QAction("  Clear filter", cm)
            a.triggered.connect(self._clear_cur)
            cm.addAction(a)

        im = menu.addMenu("  Min importance")
        for lvl in [ImportanceLevel.LOW, ImportanceLevel.MEDIUM, ImportanceLevel.HIGH]:
            a = QAction(f"  {lvl.name.capitalize()}", im)
            a.setCheckable(True)
            a.setChecked(self._filters["min_importance"] is lvl)
            a.triggered.connect(lambda checked, l=lvl: self._set_imp(l))
            im.addAction(a)

        menu.addSeparator()
        a = QAction("  Refresh now", menu)
        a.triggered.connect(self._manual_refresh)
        menu.addAction(a)
        a = QAction("  Always on Top: " + ("On" if self._always_on_top else "Off"), menu)
        a.triggered.connect(self._toggle_aot)
        menu.addAction(a)
        menu.addSeparator()

        # Auto-start toggle (only meaningful in packaged mode)
        import autostart
        autostart_enabled = autostart.is_autostart_enabled()
        a = QAction("  Launch at Login: " + ("On" if autostart_enabled else "Off"), menu)
        a.triggered.connect(self._toggle_autostart)
        menu.addAction(a)

        a = QAction("  Quit", menu)
        a.triggered.connect(QApplication.quit)
        menu.addAction(a)

        menu.exec(event.globalPos())

    # ── Row height calculation for EVENT word wrap ───────────────────

    def _recalc_row_heights(self) -> None:
        """Calculate row heights based on EVENT column text length.

        Uses QTextLayout to precisely measure how many lines the text will wrap
        into, then assigns the appropriate row height. This avoids both
        truncation and visual cramping.
        """
        t = self.table
        if t.rowCount() == 0:
            return
        fm = QFontMetrics(t.font())
        col_event = 3
        fixed_sum = sum(t.columnWidth(i) for i in range(len(COLUMNS)) if COL_WIDTHS[i] > 0 and i != col_event)
        event_w = t.viewport().width() - fixed_sum
        event_w = max(event_w, 50)

        for row in range(t.rowCount()):
            item = t.item(row, col_event)
            if item is None:
                t.setRowHeight(row, _ROW_HEIGHT_SINGLE)
                continue
            text = item.text()
            pad = 16  # 8px padding each side
            avail_w = event_w - pad
            if avail_w <= 0:
                t.setRowHeight(row, _ROW_HEIGHT_TRIPLE)
                continue
            # Use boundingRect to count actual wrapped lines
            flags = int(Qt.TextFlag.TextWordWrap)
            text_rect = fm.boundingRect(0, 0, avail_w, 1000, flags, text)
            line_count = max(1, text_rect.height() // fm.lineSpacing())
            if line_count <= 1:
                t.setRowHeight(row, _ROW_HEIGHT_SINGLE)
            elif line_count == 2:
                t.setRowHeight(row, _ROW_HEIGHT_DOUBLE)
            else:
                t.setRowHeight(row, _ROW_HEIGHT_TRIPLE)

        self._update_now()

    # ── Data ─────────────────────────────────────────────────────────

    def refresh(self) -> None:
        events = load_cached_events(self.cache_file)
        filtered = [e for e in events
                    if (not self._filters["currencies"] or e.currency in self._filters["currencies"])
                    and e.importance >= self._filters["min_importance"]]
        self._events = filtered
        self._hover_row = -1
        self._delegate.set_hover(-1)
        self._delegate.invalidate_heights()

        t = self.table
        t.setRowCount(0)
        t._high_rows = {}

        if not filtered:
            t.setRowCount(1)
            it = QTableWidgetItem("Waiting for data…")
            it.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            f = QFont(self.font_family, self.font_size)
            f.setItalic(True)
            it.setFont(f)
            it.setForeground(_TEXT_TERTIARY)
            t.setItem(0, 0, it)
            t.setSpan(0, 0, 1, len(COLUMNS))
            t.setRowHeight(0, _ROW_HEIGHT_SINGLE)
            t._high_rows[0] = False
            self._title_count.setText("No events")
            self._set_status("Waiting for data — fetching…")
            self._delegate.clear_now()
            t.viewport().update()
            return

        t.setRowCount(len(filtered))
        now = datetime.now(LOCAL_TZ)

        for row, ev in enumerate(filtered):
            t._high_rows[row] = ev.is_high_impact()
            cells = [
                ev.time.strftime("%H:%M"),
                _flag_and_code(ev.currency),
                "",
                ev.name,
                ev.actual or "—",
                ev.forecast or "—",
                ev.previous or "—",
            ]
            for col, txt in enumerate(cells):
                it = QTableWidgetItem(txt)
                if col == 0:
                    it.setForeground(_TEXT_SECONDARY)
                    it.setTextAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
                    it.setToolTip(ev.time.strftime("%Y-%m-%d %H:%M %Z"))
                elif col == 1:
                    # CUR column: flag + country code — delegate paints it
                    it.setForeground(_TEXT_PRIMARY)
                    it.setTextAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignCenter)
                    it.setToolTip(ev.currency)
                elif col == 2:
                    it.setIcon(QIcon(_make_stars_pixmap(ev.importance)))
                    it.setTextAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignCenter)
                    it.setSizeHint(QSize(48, _ROW_HEIGHT_SINGLE))
                elif col == 3:
                    it.setForeground(_TEXT_PRIMARY)
                    it.setTextAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
                    it.setToolTip(
                        f"{ev.name}\n"
                        f"{ev.time.strftime('%Y-%m-%d %H:%M %Z')} · {ev.importance.name}\n"
                        f"Actual: {ev.actual or '—'}  Forecast: {ev.forecast or '—'}  Previous: {ev.previous or '—'}"
                    )
                elif col in (4, 5, 6):
                    nf = QFont(self.font_family, self.font_size)
                    nf.setStyleHint(QFont.StyleHint.Monospace)
                    it.setFont(nf)
                    it.setForeground(_TEXT_TERTIARY)
                    it.setTextAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight)
                    if col == 4 and ev.actual and ev.actual != "—":
                        av = _try_float(ev.actual)
                        fv = _try_float(ev.forecast)
                        if av is not None:
                            it.setForeground(_GREEN if (fv is None or av >= fv) else _RED)
                t.setItem(row, col, it)

        for i, w in enumerate(COL_WIDTHS):
            if w > 0:
                t.setColumnWidth(i, w)

        # Size EVENT column to fill remaining space
        self._layout_columns(t.width())

        # Calculate dynamic row heights for EVENT word wrap (also updates NOW indicator)
        self._recalc_row_heights()

        t.viewport().update()
        self._title_count.setText(f"{len(filtered)} events")
        self._set_status(f"Updated {now.strftime('%H:%M')} · {len(filtered)} events")

    def _update_now(self) -> None:
        if not self._events:
            self._delegate.clear_now()
            return
        now = datetime.now(LOCAL_TZ)
        trow = -1
        y = 0.0
        for i, ev in enumerate(self._events):
            if ev.time >= now:
                trow = i
                if i > 0:
                    prev = self._events[i - 1].time
                    delta = (ev.time - prev).total_seconds()
                    if delta > 0:
                        rh = self.table.rowHeight(i) if i < self.table.rowCount() else _ROW_HEIGHT_SINGLE
                        y = min(rh, max(0, (now - prev).total_seconds() / delta * rh))
                    else:
                        y = 0
                else:
                    y = 0
                break
        else:
            trow = len(self._events) - 1
            rh = self.table.rowHeight(trow) if trow < self.table.rowCount() else _ROW_HEIGHT_SINGLE
            y = rh
        if trow >= 0:
            self._delegate.set_now(trow, y)

    # ── Actions ──────────────────────────────────────────────────────

    def _copy(self, row: int) -> None:
        if not (0 <= row < len(self._events)):
            return
        ev = self._events[row]
        flag = _flag_and_code(ev.currency)
        txt = (f"{ev.time.strftime('%H:%M')} | {flag} | {ev.name}\n"
               f"Actual: {ev.actual or '—'} | Forecast: {ev.forecast or '—'} | Previous: {ev.previous or '—'}")
        QApplication.clipboard().setText(txt)
        self._set_status(f"Copied: {ev.name[:45]}")

    def _open_browser(self, row: int = -1) -> None:
        url = "https://www.investing.com/economic-calendar/"
        if 0 <= row < len(self._events):
            ev = self._events[row]
            if ev.source_url:
                url = ev.source_url
        QDesktopServices.openUrl(QUrl(url))
        self._set_status("Opened in browser")

    def _set_status(self, text: str) -> None:
        self._status.setText(text)

    def set_status(self, text: str) -> None:
        self._set_status(text)

    def on_fetch_completed(self, count: int) -> None:
        self.refresh()

    def on_fetch_failed(self, err: str) -> None:
        logger.error("Fetch failed: %s", err)
        self._set_status(f"Fetch error: {err[:60]}")

    def _toggle_cur(self, cur: str, on: bool) -> None:
        (self._filters["currencies"].add if on else self._filters["currencies"].discard)(cur)
        self.refresh()

    def _clear_cur(self) -> None:
        self._filters["currencies"].clear()
        self.refresh()

    def _set_imp(self, lvl: ImportanceLevel) -> None:
        self._filters["min_importance"] = lvl
        self.refresh()

    def _manual_refresh(self) -> None:
        self._set_status("Refreshing…")
        (self._scheduler.trigger_fetch_now() if self._scheduler else self.refresh())

    def _toggle_aot(self) -> None:
        self._always_on_top = not self._always_on_top
        fl = Qt.WindowType.FramelessWindowHint
        if self._always_on_top:
            fl |= Qt.WindowType.WindowStaysOnTopHint
        self.setWindowFlags(fl)
        self.show()
        self._set_status(f"Always on Top: {'On' if self._always_on_top else 'Off'}")

    def _toggle_autostart(self) -> None:
        import autostart
        new_state = autostart.toggle_autostart()
        self._set_status(f"Launch at Login: {'On' if new_state else 'Off'}")

    def persist_geometry(self) -> None:
        try:
            import yaml
            g = self.geometry()
            self.config.setdefault("widget", {}).setdefault("geometry", {})
            self.config["widget"]["geometry"] = {
                "x": g.x(), "y": g.y(), "width": g.width(), "height": g.height()}
            with open("config.yaml", "w", encoding="utf-8") as fh:
                yaml.safe_dump(self.config, fh, sort_keys=False, allow_unicode=True)
        except Exception as exc:
            logger.warning("persist_geometry: %s", exc)
