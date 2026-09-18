# Economic Calendar — 开发者文档

用户使用说明见根目录 [README](../README.md)；架构与设计决策见 [docs/DESIGN.md](../docs/DESIGN.md)。本文档覆盖构建系统、数据路径与全部可调配置。

- macOS 26（Tahoe）+ Xcode 26 构建，Swift 6 / SwiftUI，Liquid Glass（`glassEffect`）
- SwiftPM 包 + 脚本组装 .app（无 .xcodeproj）；`build.sh` 内部已用 `DEVELOPER_DIR` 指向 `/Applications/Xcode.app`，**不需要** `xcode-select` 切换
- 无 Dock 图标（`LSUIElement`），Nonactivating Panel（点击不抢焦点），仅右键菜单退出

## 构建 / 运行

```bash
swift/Scripts/build.sh                 # 构建 dist/EconomicCalendar.app（release）
swift/Scripts/build.sh --debug         # debug 构建
swift/Scripts/build.sh --open          # 构建后直接打开
swift/Scripts/build.sh --install       # 退出旧实例 → 装到 /Applications（无权限则 ~/Applications）→ xattr -cr → 启动

swift/Scripts/run.sh                   # 开发模式裸跑（不打包；通知/登录项自动停用；数据在 <repo>/data）
```

CLI 工具（等价于旧 `python -m fetcher` 系列）：

```bash
swift/Scripts/run.sh --print-cache   # 解码并打印 cache.json
swift/Scripts/run.sh --fetch-once    # 单次抓取 → 写缓存 → 打印表格
swift/Scripts/run.sh --parse-test    # 解析自检（日期头 / PM 时间 / 货币映射 / 事件 ID 兼容 / 端到端过滤）
```

改 `Resources/ExtractCalendar.js` 或解析逻辑时，先跑 `--fetch-once` 再跑 `--parse-test`。

## 数据与状态

| 文件 | 捆绑模式（.app） | 开发模式（裸跑） |
|---|---|---|
| `cache.json` | `~/Library/Application Support/EconomicCalendar/` | `<repo>/data/` |
| `notified.json` | 同上（事件 ID 与旧版逐字节一致，去重延续） | 同上 |
| `widget.log` | `~/Library/Logs/EconomicCalendar/` | `<repo>/data/` |
| `debug_page.html` | 同 App Support（抓取为空时自动落盘） | 同 `<repo>/data/` |

判断逻辑：`Bundle.main.bundleURL.pathExtension == "app"` 即捆绑模式。

首次启动会**只读迁移**旧 `config.yaml`（几何、Always on Top、过滤、抓取/通知参数）到 UserDefaults，不修改、不删除 YAML 文件，迁移后打标记不重复执行。

## 配置

界面行为（窗口几何、置顶、筛选选择）自动持久化到 UserDefaults，无需手动配置。抓取与通知参数有内置默认值，可按需覆盖（bundle id 为 `com.economiccalendar.widget`）：

| Key | 默认 | 说明 |
|---|---|---|
| `config.sourceURL` | `https://www.investing.com/economic-calendar/` | 数据源 |
| `config.refreshIntervalMinutes` | `10` | 抓取间隔（分钟，≥1） |
| `config.dateRangeDays` | `2` | 抓取窗口：昨天 00:00 起 +N 天 |
| `config.currencies` | `USD EUR GBP JPY CNY` | 抓取币种白名单（抓取层过滤） |
| `config.minImportance` | `low` | 抓取层最低重要性 |
| `config.notificationsEnabled` | `true` | 通知总开关 |
| `config.leadTimeMinutes` | `15` | 事件开始前多少分钟通知 |
| `config.notifyMinImportance` | `high` | 通知的最低重要性 |
| `config.sound` | `default` | 通知铃声 |

示例：

```bash
defaults write com.economiccalendar.widget config.refreshIntervalMinutes -int 5
defaults write com.economiccalendar.widget config.currencies -array USD EUR CNY
```

调试开关：`EC_GLASS_MODE=material|solid` 环境变量可强制玻璃降级档位（默认 `glass`；系统「降低透明度」开启时自动 `.solid`）。

## 代码结构速览

```
Sources/EconomicCalendar/
  App/          # AppDelegate 装配、AppPanel、AppModel（唯一数据源）、AppActions、CLI
  Core/         # 事件模型与解析（含事件 ID 契约）、actor 存储、配置/迁移、路径、日志
  Fetching/     # CalendarFetcher（WKWebView 管线）+ Resources/ExtractCalendar.js
  Services/     # RefreshScheduler、Notifier(UN)、LoginItemService(SMAppService+osascript)
  UI/           # RootView、列表/行/时间分割线、筛选栏、右键菜单、拖动与 ⌃点击捕获
Support/Info.plist
Scripts/        # build.sh / run.sh
Resources/      # AppIcon.icns、icon.iconset
```

细节与理由全部在 [docs/DESIGN.md](../docs/DESIGN.md)：抓取管线映射表、时间分割线零占位设计、自动滚动策略、事件 ID 兼容契约、并发模型。

## 从旧 Python 版的关系

旧实现（PyQt6 + Playwright）已删除（git 历史 `b2bb622` 及之前可查）。数据文件格式、事件 ID、窗口行为、功能集合全部保持兼容，升级无缝；`docs/DESIGN.md §3.6` 记录了 ID 兼容的实现契约与回归断言。
