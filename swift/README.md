# Economic Calendar — 原生 macOS 版（Swift + Liquid Glass）

`investing.com` 经济日历桌面小组件的 **Swift 原生重写版**，替代同目录上层的
Python/PyQt6 实现（旧实现暂时保留在仓库根目录，功能对齐后再清理）。

- macOS 26（Tahoe）+ Xcode 26 构建，UI 使用 **Liquid Glass**（`glassEffect`）
- 自动适配 **浅色 / 深色外观**；开启「降低透明度」时自动退化为不透明卡片
- **Nonactivating Panel**：点击日历不会从你正在打字的窗口抢走键盘焦点
- 窗口层级与旧版一致：默认普通层级，右键菜单可切换 **Always on Top**（浮动）
- 窗口可拖边缘调节大小（524×300 ~ 1200×1600），松手后自动记住
- 无 Dock 图标（`LSUIElement`），仅通过右键菜单退出

## 构建 / 运行

```bash
# 开发运行（裸可执行；通知与登录项功能停用；数据在 <repo>/data）
swift/Scripts/run.sh

# 构建 dist/EconomicCalendar.app（release，ad-hoc 签名）
swift/Scripts/build.sh

# 构建 debug 包 / 构建后直接打开 / 安装到 /Applications 并启动
swift/Scripts/build.sh --debug
swift/Scripts/build.sh --open
swift/Scripts/build.sh --install
```

> 依赖完整 Xcode 26（`build.sh` 内部已用 `DEVELOPER_DIR` 指向
> `/Applications/Xcode.app`，不需要 `xcode-select` 切换）。

CLI 工具（替代旧 `python -m fetcher --dry-run`）：

```bash
swift/Scripts/run.sh --print-cache   # 打印 data/cache.json 内容
swift/Scripts/run.sh --fetch-once    # 跑一次抓取、写缓存并打印
swift/Scripts/run.sh --parse-test    # 解析逻辑自检（含事件 ID 一致性断言）
```

## 数据与状态（与 Python 版完全互通）

| 文件 | 捆绑模式位置 | 开发模式位置 |
|---|---|---|
| `cache.json` | `~/Library/Application Support/EconomicCalendar/` | `<repo>/data/` |
| `notified.json` | 同上（事件 ID 逐字节兼容，升级不会重发通知） | 同上 |
| `widget.log` | `~/Library/Logs/EconomicCalendar/` | `<repo>/data/` |

首次启动会**只读迁移**旧 `config.yaml`（窗口位置、Always on Top、抓取过滤、
通知参数）到 `UserDefaults`，不会修改或删除 YAML，旧 Python 版可继续使用。

覆盖配置示例（可选）：

```bash
defaults write com.economiccalendar.widget config.refreshIntervalMinutes -int 5
defaults write com.economiccalendar.widget config.currencies -array USD EUR CNY
```

## 与旧版的功能映射

| 功能 | 状态 |
|---|---|
| 双击行 → 打开该事件 investing.com 详情页 | ✓ |
| Ctrl+点击 → 复制事件详情 | ✓ |
| 右键菜单（复制/打开/货币过滤/最低重要性/立即刷新/置顶/登录启动/退出） | ✓ |
| 重要性筛选 + 国家（货币）筛选 | 由右键菜单升级为**玻璃按钮筛选栏**，选择持久化 |
| 当前时间分界线 | 由悬浮 "NOW" 覆盖线改为**插在两行之间的分界元素**，显示当前 `HH:mm`；早于/晚于全部事件时完整显示在列表顶部/底部；加载、刷新、改筛选时自动滚动定位 |
| 事件前 15 分钟高重要性通知 | terminal-notifier → 原生 `UNUserNotificationCenter`（首次启动请求授权，点通知打开事件页） |
| 登录启动 | osascript → `SMAppService`（失败自动回退 osascript） |
| 抓取 | Playwright Chromium → 离屏 `WKWebView` + 同款页面内提取 JS |
| 每 10s 重读缓存 | 改为抓取完成直接更新（同进程，无需轮询） |
