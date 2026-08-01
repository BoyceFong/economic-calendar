# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for EconomicCalendar.app.

Build with: .venv/bin/pyinstaller EconomicCalendar.spec
Playwright Chromium browser is copied separately by build.sh after PyInstaller.
"""

import os
from pathlib import Path

block_cipher = None

# Project root
project_root = Path(SPECPATH).resolve()

# Data files to include (no Chromium browser — copied by build.sh)
datas = [
    ("config.yaml", "."),
    ("data/icon.icns", "data"),
]

# Include Playwright's internal driver (node binary, package.json, etc.)
playwright_pkg = project_root / ".venv" / "lib" / "python3.9" / "site-packages" / "playwright"
if playwright_pkg.exists():
    driver_dir = playwright_pkg / "driver"
    if driver_dir.exists():
        datas.append((str(driver_dir), os.path.join("playwright", "driver")))

a = Analysis(
    [
        "main.py",
        "widget.py",
        "fetcher.py",
        "models.py",
        "notifier.py",
        "scheduler.py",
        "state.py",
        "paths.py",
        "autostart.py",
    ],
    pathex=[str(project_root)],
    binaries=[],
    datas=datas,
    hiddenimports=[
        "PyQt6",
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtWidgets",
        "PyQt6.sip",
        "yaml",
        "playwright",
        "playwright.sync_api",
        "playwright._impl",
        "playwright.driver",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "numpy", "scipy", "pandas", "APScheduler"],
    noarchive=False,
    cipher=block_cipher,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="EconomicCalendar",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    icon="data/icon.icns",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="EconomicCalendar",
)

app = BUNDLE(
    coll,
    name="EconomicCalendar.app",
    icon="data/icon.icns",
    bundle_identifier="com.economiccalendar.widget",
    info_plist={
        "CFBundleName": "EconomicCalendar",
        "CFBundleDisplayName": "Economic Calendar",
        "CFBundleIdentifier": "com.economiccalendar.widget",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": "EconomicCalendar",
        "NSHighResolutionCapable": True,
        "LSMinimumSystemVersion": "10.15",
        "LSUIElement": True,  # Hide dock icon (background widget)
        "NSAppleEventsUsageDescription": "This app needs to manage login items for auto-start functionality.",
    },
)
