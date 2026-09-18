# Economic Calendar 设计文档

本文档沉淀项目的架构设计、关键决策及其理由。使用说明见根目录 [README](../README.md)，构建细节见 [swift/README](../swift/README.md)。

## 1. 背景与目标

Economic Calendar 是一个 **macOS 桌面经济日历小组件**：以浮层卡片形式常驻桌面，自动抓取 investing.com 的经济日历，按重要性 / 国家筛选，在事件开始前推送通知。

项目前身是 Python/PyQt6 + Playwright 无头 Chromium 实现（已删除，见 git 历史）。2026-09 重写为原生 Swift，动机：

| 痛点（旧版） | 重写目标 |
|---|---|
| UI 不随系统浅色/深色切换 | 全部系统动态色 + 材质，自动适配 |
| "NOW" 时间线浮在行内容之上 | 分界线插在行分界处，永不遮挡 |
| 时间线不能反映精确时间 | 胶囊显示当前 `HH:mm`，每分钟更新 |
| 不会跳转到当前时间 | 自动滚动定位 + 5 分钟无操作回位 |
| 筛选藏在右键菜单里 | 玻璃筛选按钮常驻 + 菜单保留 |
| 依赖 Python 运行时 + Playwright Chromium（~400MB） | 零依赖原生应用（约 2MB） |
| 外部 terminal-notifier 通知 | 系统 UNUserNotificationCenter |

**明确不做的事**：不做 WidgetKit 桌面小组件 —— WidgetKit 至今不支持自由滚动（只支持按钮/开关型交互），与"滚动浏览完整日历"的核心诉求冲突。这是选择原生 App 的决定性原因。

## 2. 总体架构

```
┌─────────────────────────────────────────────────────────┐
│ AppPanel (NSPanel)                                      │
│  borderless + nonactivatingPanel + resizable            │
│  level = .normal / .floating(Always on Top)             │
│  LSUIElement → 无 Dock 图标                              │
│                                                         │
│  ┌───────────────────────────────────────────┐          │
│  │ NSHostingView < RootView >                │          │
│  │                                           │          │
│  │  TitleBar ─┬ DragRegion(拖动窗口)          │          │
│  │  FilterBar │ ★All ★★+ ★★★ 🌐(玻璃chips)  │          │
│  │  ColumnHeader (TIME…PREVIOUS)             │          │
│  │  EventList                                │          │
│  │   ├ EventRow × N                          │          │
│  │   └ NowDivider (零高度,插在行间)            │          │
│  │  StatusView                               │          │
│  └───────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────┘
        │ @Observable                    ▲
        ▼                                │ 应用
┌───────────────┐   ┌────────────────┐  ┌──────────────────┐
│ AppModel      │◄──│ Refresh        │  │ Notifier         │
│ (MainActor)   │   │ Scheduler      │  │ (UN center)      │
│ events/rows/  │   │ 3s初抓+10m循环  │  │ 60s 检查循环      │
│ filters/status│   └───────┬────────┘  └────────┬─────────┘
└───────▲───────┘           │                    │
        │ load/apply        ▼                    ▼
┌───────┴───────┐  ┌────────────────┐  ┌──────────────────┐
│ CacheStore    │  │ CalendarFetcher│  │ NotifiedStore    │
│ (actor)       │  │ WKWebView 管线 │  │ (actor) 去重     │
│ cache.json    │  │ + 提取 JS      │  │ notified.json    │
└───────────────┘  └────────────────┘  └──────────────────┘
```

### 模块地图

| 文件（`swift/Sources/EconomicCalendar/`） | 职责 | 对应旧实现 |
|---|---|---|
| `main.swift` | 入口；强制本 app en-US；CLI 分发（`--fetch-once` 等） | `main.py` |
| `App/AppDelegate.swift` | 装配：面板/视图/调度/迁移；窗口代理（几何持久化、影子刷新） | `main.py` |
| `App/AppPanel.swift` | NSPanel 子类：层级切换、几何恢复/保存 | `widget.py` 窗口部分 |
| `App/AppModel.swift` | 唯一数据源：事件、筛选、行列表、状态、滚动信号、30s now-tick | `widget.py` 状态 |
| `App/AppActions.swift` | 用户动作（复制/打开/刷新/置顶/登录/退出） | `widget.py` 动作 |
| `App/PrintCacheTool.swift` | CLI 输出 + 解析自检（`--print-cache` / `--parse-test`） | `fetcher._print_table` |
| `Core/EconomicEvent.swift` | 事件模型 + 磁盘 DTO（字段名与旧 cache.json 一致） | `models.py` |
| `Core/EventParsing.swift` | 日期头/时间解析、货币映射、**事件 ID（MD5 前 12 位）**、抓取过滤 | `fetcher.py` 解析部分 |
| `Core/DisplayRow.swift` | 行列表构建：事件行 + **时间分界线插入** | 新设计 |
| `Core/CacheStore.swift` / `NotifiedStore.swift` | actor 化 JSON 存储（原子写） | `fetcher/state.py` |
| `Core/AppConfig.swift` + `AppSettings.swift` | 配置常量 + UserDefaults；`LegacyMigrator` 只读迁移旧 config.yaml | `config.yaml` + `paths.py` |
| `Core/CountryMaps.swift` | 国家→货币、货币→旗帜两张表 | `fetcher/widget.py` |
| `Core/AppPaths.swift` / `AppLog.swift` | 路径解析（dev/bundled）、os.Logger + 文件日志 | `paths.py` |
| `Fetching/CalendarFetcher.swift` | WKWebView 抓取管线（下详） | `fetcher.py` 抓取部分 |
| `Resources/ExtractCalendar.js` | 页面内提取函数（EXTRACT_JS 原样移植） | `fetcher.EXTRACT_JS` |
| `Services/RefreshScheduler.swift` | 3s 首抓 + 10 分钟循环 + 60s 通知检查 + 防重入 | `scheduler.py` |
| `Services/Notifier.swift` | UN 通知 + 授权请求 + 点击打开事件页 | `notifier.py` |
| `Services/LoginItemService.swift` | SMAppService 主路径 + osascript 回退 | `autostart.py` |
| `UI/*` | SwiftUI 视图（Root/TitleBar/FilterBar/List/Row/Divider/Chrome/菜单/交互） | `widget.py` UI 部分 |

## 3. 关键设计决策

### 3.1 窗口：NSPanel(borderless + nonactivatingPanel)

- **不抢焦点**是用户明确选择的使用体验：点击日历不打断正在打字的窗口。代价是面板通常不是 key window —— 本应用没有文本输入，无副作用；菜单/弹窗（NSMenu/popover 自带 key window）均正常。
- 层级沿用旧行为：默认 `.normal`，右键切 `.floating`。比 Qt 简单：改 `level` 属性即可，无需重建窗口flags。
- **可调大小**：styleMask 加 `.resizable`，无边框窗口自动获得边缘拖拽热区；范围钳制 524×300（固定列宽总和 + 事件列最小宽，继承旧版最小值推导）~ 1200×1600。
- 边框窗口的已知坑：`canBecomeKey` 必须重写为 true；阴影在移动/缩放后需要 `invalidateShadow()`（AppKit 按不透明像素计算阴影，透明圆角窗口会拿到过期结果）。
- 拖动区域仅标题栏（`DragRegionView.mouseDown → performDrag`），右键事件放行给 SwiftUI 的 contextMenu。

### 3.2 Liquid Glass 使用策略

遵循 HIG「节制使用」：玻璃只给**功能层**——卡片底、筛选 chips、时间胶囊；列表行永不上玻璃（55 行玻璃 = 渲染灾难 + 注意力灾难）。

**交互态透明**：唯一驱动信号是**本窗口是否聚焦**（`didBecomeKey/didResignKey`；面板 `becomesKeyOnlyIfNeeded = false`，点击即变 key 但不激活 app）——聚焦 = 可读 `.regular`，失焦 = 透明 widget 态 `.clear`。不做桌面聚焦/前台应用启发式（试过，Finder 在 CGWindowList 里的桌面杂音窗口会让判定极不可靠）。

**材质实现的关键坑（两次踩坑）**：① SwiftUI `.glassEffect` 在透明无边框窗口里对窗外内容是**快照式采样** —— 可读态用它背景"冻住"不跟随壁纸；② 即便闲置态用 `Glass.clear`，只要用 `if/else` 分支切换玻璃视图，**销毁重建后的 glassEffect 不再初始化背景采样**，透明凝光态一次交互后就回不来了。最终方案：卡片两态共用**一块** AppKit `NSGlassEffectView`（系统 widget 同源、活体采样），只切 `style`（可读 `.regular` ↔ 透明 `.clear`，经 `onInteractingChange` 回调驱动），SwiftUI 层不画任何卡片玻璃。注意：**`style` 的 setter 会重置 `cornerRadius`**，每次切换后必须重设圆角（配合 `wantsLayer`+`masksToBounds`），否则方形玻璃直角会从圆角内容后露出。

透明态完整复刻 widget 视觉：全部文字/图标切换为白灰色系（环境键 `widgetIdle` 驱动，各视图前景色随动），卡片边缘叠加"外暗内亮"双环**凝光描边**（任何壁纸上可见）。切换用 `withAnimation` 0.35s 过渡，两种外观自动适配。

三级降级链（`GlassMode`）：

1. `.glass` — SwiftUI `.glassEffect(.regular)`（默认，macOS 26）
2. `material` — AppKit `NSVisualEffectView(.popover)`（`EC_GLASS_MODE=material` 强制）
3. `.solid` — 不透明 `windowBackgroundColor`（系统「降低透明度」开启时自动切换，KVO 监听 `accessibilityDisplayShouldReduceTransparency`）

浅色/深色零成本：玻璃材质与全部语义色（`.primary/.secondary`、`systemRed` 等）自动跟随系统外观，代码里没有任何硬编码颜色。

筛选 chips 的交互实现踩过坑：`Button` + `Glass.interactive()` 在非激活面板里点击延迟明显甚至吞点击（interactive 玻璃的按压动画接管了事件）。最终形态是**玻璃背景 + `onTapGesture`**，点击即时生效。

### 3.3 时间分割线：零高度列表元素

旧版把 "NOW" 线**画在行内容之上**（列绘制时覆盖 + 行内插值定位），必然遮挡内容且边界状态残缺。新设计：

- 分界线是**真实的列表元素**（`DisplayRow.nowDivider`），插在事件序列中 `firstIndex { $0.time >= now }` 的位置 —— 天然只出现在两行分界处；
- 元素本身 `frame(height: 0)`，**不占布局空间**：强调色线（1.5pt）压在行分界 hairline 上，玻璃时间胶囊（当前 `HH:mm`）居中叠压相邻两行 —— investing.com 同款视觉效果；
- 边界情况：`now` 早于全部事件 → 元素在索引 0，胶囊整体偏移到线下方；晚于全部事件 → 在末尾，胶囊偏移到线上方。线还有 ±1pt 内推，保证贴边时也不被滚动视口裁掉；
- 胶囊文字用 `TimelineView(.periodic(60s))` 局部刷新（只有胶囊重绘）；分界线位置由 AppModel 的 30s tick 重算（对齐旧版 `_now_timer`）。

卡片圆角 26pt（`Theme.cornerRadius`），对齐系统桌面小组件的圆角规格；窗口透明底 + SwiftUI clipShape 裁圆角，边框窗口阴影靠 `invalidateShadow()` 维持。时间格的活体状态（倒计时/实时时钟/All Day）见 §3.3b —— 显示与站点逐字对齐正是本轮"数据对不上"反馈的修复。

### 3.3b 时间格的活体状态（数据正确性关键）

investing.com 表格的时间格**不是静态文本**，实测有四种状态：

| 状态 | 格内文本 | 处理 |
|---|---|---|
| 固定时间 | `07:30` / `01:00 PM` | 正常解析为事件时刻 |
| 临近倒计时 | `30m`、`24m`（下一事件） | 保留原文为 `timeLabel`，排序置当日顶部 |
| 实时时钟 | 等于抓取时刻（进行中事件） | 解析结果 ≈ 抓取分钟 → 判定为活体时钟，保留原文为 `timeLabel` |
| 未定档 | `All Day` / `Tentative` | 同上，置当日顶部 |

旧版（Python 与首版 Swift 均如此）对一切非 `HH:MM` 文本**静默吞成当日 00:00**，制造出假午夜事件 —— BoJ 决议曾被记到 00:00。修复后契约：

1. 解析只接受全串锚定的 `H:MM(AM/PM)?`（拒绝 `30m`、`All Day`、`10:15:42` 时钟带秒）；
2. 非固定时间的行显示**站点原文**（`EconomicEvent.timeLabel`），绝不编造时间；
3. `timeLabel` 事件按当日 00:00 排序（对齐 investing.com 的日顶部摆放）、**跳过通知**（无可靠时刻）；
4. 事件 ID 仍用页面原始时间文本哈希 —— 与既有行为兼容；
5. **跨轮稳定**：倒计时/时钟标签每轮都在变，直接落盘会让时间与 ID 每轮漂移（"列表一拉就乱"的根源）。`stabilizeUnscheduledTimes` 会把本轮 label 事件与上一轮缓存中同 `source_url` 的**固定时间**版本匹配（回退 URL 除外——无链接行共享日历首页 URL，会张冠李戴），命中则沿用旧的固定时间与 ID、只更新数值；命中不了（事件首次出现/真 All Day）才保留标签。每轮匹配失败会持续到站点稳定出固定时间为止，与站点逐字对齐；
6. **排序不变量三重收口**：`parseRawRows` 排序 + `stabilizeUnscheduledTimes` 输出排序 + `CacheStore.write`/`applyFetched` 落盘上屏前再排序 —— 无论上游发生什么，存储与展示必为时间升序。

回归断言在 `--parse-test`（14 项，含 All Day/倒计时/时钟/跨轮稳定化）。

### 3.4 自动滚动策略

| 触发 | 行为 |
|---|---|
| 启动 / 数据加载 | 滚动到分界线（中间居中、顶端贴顶、底端贴底） |
| 筛选变化 | 同上（用户主动操作，期望看到"现在"） |
| 后台抓取刷新 | **仅当用户没有在手动浏览时**才滚动 |
| 手动滚动后 5 分钟无操作 | 自动回位到分界线 |

实现要点：列表用**普通 `VStack` 而非 `LazyVStack`** —— 50~100 行的量级下全量布局成本可忽略，换来的是所有行高即时可算，`ScrollViewReader.scrollTo` 精确落点（Lazy 容器的估算高度会让 scrollTo 飘）。用户滚动通过 `onScrollPhaseChange` 的 `.tracking/.interacting/.decelerating` 相位识别（程序化动画滚动是 `.animating`，不会误判）。

### 3.5 抓取管线：WKWebView 替代 Playwright

旧版用 Playwright 驱动独立 Chromium（打包要带 ~400MB 浏览器）。原生方案是**离屏 WKWebView + 页面内同一份提取 JS**：

| Playwright 机制 | WKWebView 对应 | 说明 |
|---|---|---|
| `locale=en-US, timezone=Asia/Shanghai` | `UserDefaults.register(["AppleLanguages": ["en-US"]])` | investing.com 按访客语言渲染日期头（"Thursday, September 17, 2026"），中文环境会让英文正则全部失配 → **必须**强制本 app 英文（只影响本 app）；时区直接用系统（用户本就是 +08:00） |
| `user_agent=Chrome/128` | **保持 Safari 默认 UA** | WebKit 引擎 + Chrome UA 是矛盾指纹，属经典 bot 信号 |
| `route.abort(image/media)` | `WKContentRuleList` 全局拦截 | 同效，零进程开销 |
| 每次 `new_context()` | `websiteDataStore = .default()` | 反向选择：**持久化** cookie，Cloudflare 放行凭据跨抓取复用，减少挑战 |
| `wait_until="domcontentloaded"` + `wait_for_selector` | 轮询 `table[class*='datatable-v2']`（60s 预算） | **WKWebView 的 `didFinish` 在广告密集页几乎不触发**（信标永不加载完），不能等它 |
| `networkidle`（15s 回退 5s） | 固定 5s settle | WKWebView 无 networkidle 等价物 |
| 提取后解析 | 同一提取 JS（`Resources/ExtractCalendar.js` 原样移植）+ Swift 侧解析 | 返回 `JSON.stringify` 字符串，规避 `AnyObject` 桥接坑 |
| 隐藏页渲染节流 | 重试阶梯：`visibilityState` spoof → 挂到离屏真实窗口（12000,0） | 独立 webview 的 `visibilityState=hidden` 会节流 rAF/hydration |
| daemon 线程 | `beginActivity(.userInitiated)` | 防 App Nap 节流后台抓取 |

**等待原语**：所有"等页面"都走 `OnceResultBox`（线程安全一次性结果槽）+ 主 actor 上的 120ms 协作轮询，而不是 `CheckedContinuation` —— 导航回调可能在超时之后才到，continuation 会泄漏或二次 resume，结果槽模式天然免疫。

失败语义（沿用旧版）：提取 0 行 ≠ 错误 → 保留旧缓存继续显示；只有管线抛异常（导航失败/超时）才报 `Fetch error:`。提取为空时自动落 `debug_page.html`，investing.com 改版时用它对照修 JS。

### 3.6 事件 ID 与通知去重的兼容性契约

`notified.json` 跨版本延续的前提是**事件 ID 逐字节一致**。ID = `md5("{currency}|{name}|{date}|{time}")` 前 12 位十六进制，输入是页面原始字符串（日期头原文、未补零的 `H:MM`）。Swift 侧用 `CryptoKit Insecure.MD5` 移植，任何字段拼接顺序/内容的偏差都会让旧去重记录全部失配、升级后通知风暴。

这道契约用 `--parse-test` 里的已知样例断言锁死（`1b1e565cbc47`），回归即失败。

### 3.7 通知与登录项

- **通知**：`UNUserNotificationCenter`。两个坑：① 裸 SPM 可执行（无 bundle id）调用会直接崩 → 仅在 `.app` 内启用，`swift run` 自动降级为日志；② LSUIElement 附属应用在前台时默认不弹横幅 → delegate `willPresent` 必须返回 `[.banner, .sound]`。首次启动请求授权一次，拒绝则静默降级。点通知打开对应事件页（旧版做不到）。
- **登录项**：主路径 `SMAppService.mainApp`；失败（签名/路径问题）回退旧版验证过的 osascript System Events 流程。两者都落在系统设置的登录项列表里。

### 3.8 并发模型（Swift 6 严格并发）

- `@MainActor`：全部 UI、AppModel、CalendarFetcher（WKWebView 必须主线程）、Scheduler、Notifier；
- `actor`：CacheStore / NotifiedStore（磁盘 IO 出主线程）；
- 模型全是 `Sendable` 值类型，跨 actor 传递无隔离开销；
- 唯一的 `nonisolated(unsafe)`：EventParsing 里 4 个 ISO8601/DateFormatter 常量（NSDateFormatter 自 macOS 10.9 起线程安全，固定 format 只读使用）。

### 3.9 持久化与配置

| 文件 | bundle 模式 | dev 模式 | 兼容性 |
|---|---|---|---|
| `cache.json` | `~/Library/Application Support/EconomicCalendar/` | `<repo>/data/` | 格式不变，与旧版互换 |
| `notified.json` | 同上 | 同上 | ID 兼容 → 去重延续 |
| `widget.log` | `~/Library/Logs/EconomicCalendar/` | `<repo>/data/` | — |

- 旧 `config.yaml` **只读迁移**（一次）：几何（Qt 顶左 y 向下 → macOS 底左 y 向上换算）、Always on Top、过滤、抓取/通知参数 → UserDefaults；之后 UserDefaults 即用户配置（`defaults write com.economiccalendar.widget …` 覆盖），bundle 内置常量兜底。
- 刻意保留的旧行为：显示时区固定 Asia/Shanghai（与旧版一致）；列表被筛选清空时状态栏显示 "Waiting for data — fetching…"（旧行为）。有意的小改进：状态栏 "Updated HH:MM" 现在显示真实抓取时刻（旧版每 10s 轮询会刷成当前时间）。

## 4. 关键时序

**启动**：`main.swift` 注册 en-US → `AppDelegate` 迁移 config.yaml → 建 panel/hosting → 从 cache.json 加载并渲染（含分界线 + 自动滚动）→ 3s 后首抓。

**抓取**：Scheduler（防重入）→ WKWebView 加载 → 轮询表格 → 关 cookie 弹窗 → 5s settle → 提取 JS → Swift 解析/过滤/排序 → 写 cache.json → `applyFetched`（UI 刷新 + 条件滚动）→ 通知检查。

**通知**（每 60s）：遍历事件 → importance ≥ high 且 `0 ≤ 距开始 ≤ 15min` 且未通知过 → UN 投递 → 写 notified.json（启动时清理 30 天前记录）。

## 5. 验证与调试工具

| 工具 | 用途 |
|---|---|
| `--parse-test` | 解析逻辑自检（日期头/PM 时间/货币映射/**事件 ID 兼容**/端到端过滤），改解析必跑 |
| `--fetch-once` | 单次真实抓取 + 写缓存 + 打印表格，调提取 JS 的最快回路 |
| `--print-cache` | 解码 cache.json 打印（对齐旧 `python -m fetcher --dry-run`） |
| `debug_page.html` | 抓取为空时自动落盘的页面快照，investing.com 改版第一现场 |
| `EC_GLASS_MODE=material/solid` | 强制玻璃降级档位，排查渲染问题 |

## 6. 已知限制与可能的方向

- investing.com 改版会让提取 JS 失效（历史上有过一次列结构变化）—— `debug_page.html` + `--fetch-once` 是修复回路；Date 头语言若新增非英文 locale 需扩正则。
- 显示时区硬编码 Asia/Shanghai，出国需改代码（旧版相同）。
- 无沙盒、ad-hoc 签名：分发给别人需对方执行 `xattr -cr`（`--install` 已内置）；若要正式分发考虑 Developer ID 签名 + 公证。
- 滚动条按需求永久隐藏；窗口最大 1200×1600。
- 可能的方向：菜单栏紧凑模式、事件详情浮层、多数据源抽象。
