# Economic Calendar 安装指南

## 一键打包安装

在终端中执行以下命令即可完成环境准备、打包、安装和启动：

```bash
cd /path/to/economic-calendar
bash build.sh
```

脚本会自动完成以下步骤：

| 步骤 | 说明 |
|------|------|
| 1. 虚拟环境 | 创建/检查 `.venv`，不污染系统全局 Python |
| 2. 依赖安装 | 安装 `requirements.txt` 及 PyInstaller |
| 3. Chromium | 确保 Playwright Chromium 浏览器已安装 |
| 4. 清理 | 删除旧的 `build/`、`dist/` 目录 |
| 5. 打包 | PyInstaller 构建 `EconomicCalendar.app` |
| 6. 嵌入浏览器 | 将 Chromium 复制到 .app 内部 |
| 7. 安装 | 写入 `/Applications`（失败则降级到 `~/Applications`） |
| 8. 去隔离 | `xattr -cr` 清除 quarantine 标记 |
| 9. 启动 | 自动启动应用 |
| 10. 完成 | 输出安装信息和使用提示 |

## 首次运行

打包完成后，应用会自动启动。如果 macOS 提示「无法打开」或「已损坏」，这是因为应用未经 Apple 公证，按以下任一方式解决：

**方式一：右键打开**
1. 在 Finder 中找到 EconomicCalendar.app
2. 右键点击 → 选择「打开」
3. 在弹窗中点击「打开」

**方式二：系统设置**
1. 打开 系统设置 → 隐私与安全性
2. 滚动到底部，找到关于 EconomicCalendar 的提示
3. 点击「仍要打开」

> 如果 `build.sh` 已执行过 `xattr -cr`，通常不会出现此提示。

## 开启开机自启动

应用运行后，在 widget 上右键打开菜单：

1. 找到 **Launch at Login: Off**
2. 点击切换为 **On**

下次开机/登录时应用会自动启动。

也可以在 **系统设置 → 通用 → 登录项** 中管理。

## 数据与日志位置

打包后运行的应用将数据存储在以下位置：

| 用途 | 路径 |
|------|------|
| 配置文件 | `~/Library/Application Support/EconomicCalendar/config.yaml` |
| 缓存数据 | `~/Library/Application Support/EconomicCalendar/cache.json` |
| 通知状态 | `~/Library/Application Support/EconomicCalendar/notified.json` |
| 运行日志 | `~/Library/Logs/EconomicCalendar/widget.log` |

修改配置（如货币筛选、刷新频率、通知设置）只需编辑 `config.yaml`，重启应用后生效。

## 开发模式运行（不打包）

如果只需在开发环境中直接运行：

```bash
cd /path/to/economic-calendar
bash setup.sh    # 首次运行：创建 venv、安装依赖
./run.sh         # 启动 widget
```

## 重新打包

修改代码后需要重新打包安装：

```bash
bash build.sh
```

脚本会自动清理旧产物、重新构建并替换已安装的版本。
