# Economic Calendar

investing.com 经济日历 macOS 桌面小组件 — 原生 Swift（SwiftUI + Liquid Glass）实现。

无 Dock 图标的浮层卡片：每 10 分钟抓取一次经济日历，按重要性 / 货币筛选，
当前时间分割线自动定位，高重要性事件提前通知。点击不抢当前应用焦点。

构建、安装与配置说明见 **[swift/README.md](swift/README.md)**。

```bash
swift/Scripts/build.sh --install   # 构建并安装到 /Applications 后启动
```

要求：macOS 26+，Xcode 26+。
