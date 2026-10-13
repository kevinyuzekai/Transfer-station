# 文件中转站 · File Transfer Station

> 一个常驻 macOS 桌面的轻量小工具：把文件随手「扔」进悬浮球暂存，需要时再拖出来；同时记录复制过的文本、图片和文件，供随时取回。

把内容「暂时放下」，之后再随手取用——全程不超过两次拖拽。

---

## 特性

### 文件中转站
- **悬浮球常驻**：启动后显示在主屏右下角，始终悬浮于其他窗口之上，角标实时显示待取用文件数；球体可拖动到任意位置，位置自动记忆。
- **拖入即存**：把文件（支持多选、文件夹）拖到悬浮球上松手即完成暂存，无需确认框。
- **只记引用**：中转站只记录原文件的路径引用，不复制实体、不占额外磁盘。
- **拖出取用**：把条目拖到资源管理器 / 聊天 / 邮件等目标即可投递，默认「复制」；右键可「复制到…」「移动到…」。
- **失效识别**：打开面板、拖出前、应用获得焦点时校验原文件是否仍在；失效条目变灰、禁止拖出，并提供「重新定位」与「移除」。
- **置顶与清理**：条目可置顶固定；支持单条移除与一键清空（清空不会删除任何原文件）。

### 剪贴板历史
- **自动记录**：后台监听系统剪贴板，自动记录复制过的**文本 / 图片 / 文件**。
- **去重**：与最新一条相同的内容不重复记录，仅刷新时间。
- **检索**：按类型（全部 / 文本 / 图片 / 文件）筛选，并按关键词实时搜索文本内容与文件名。
- **取回**：点击条目即可把内容写回系统剪贴板，随后在原应用直接粘贴。
- **容量收敛**：默认保留最近 500 条，超出后自动淘汰最旧的非置顶条目；置顶条目不参与淘汰。

### 设置
| 设置项 | 默认值 | 说明 |
| --- | --- | --- |
| 剪贴板历史上限 | 500 条 | 步进调整，改动即时生效 |
| 开机自动启动 | 开 | 写入 LaunchAgent，登录后常驻 |
| 监听剪贴板 | 开 | 关闭后不再产生新历史条目 |
| 全局快捷键 | `Ctrl+Shift+V` | 展开 / 收起入口菜单 |
| 拖出默认行为 | 复制 | 复制 / 移动 |
| 悬浮球位置 | 右下角 | 可重置到默认位置 |

### 明确不做
局域网 / 跨设备传输、云同步与账号、对暂存文件做内容编辑、团队共享与权限体系。全部数据仅保存在本机，不联网上传。

---

## 下载安装

前往 [Releases](https://github.com/kevinyuzekai/Transfer-station/releases) 下载最新的 `FileTransferStation-<版本>.dmg`：

1. 双击打开 DMG。
2. 把「文件中转站」拖入 `Applications`。
3. 首次打开若被 Gatekeeper 拦截，请在 **系统设置 → 隐私与安全性** 中点击「仍要打开」（应用为 ad-hoc 签名）。
4. 打开后应用以「无 Dock 图标」的方式常驻，右下角出现悬浮球。

> 支持 macOS 13 及以上（Apple Silicon 与 Intel，通用二进制）。

---

## 使用

- **暂存文件**：从访达（Finder）把文件拖到悬浮球上松手。
- **取用文件**：点击悬浮球 → 文件中转站 → 把条目拖到目标窗口；或右键选择复制 / 移动到指定文件夹。
- **找回复制过的内容**：点击悬浮球（或按 `Ctrl+Shift+V`）→ 剪贴板历史 → 点击条目就会写回剪贴板。
- **收起**：再次点击悬浮球、按快捷键、或点击面板外的任意位置。

---

## 从源码构建

需要 macOS 13+ 与 Xcode 命令行工具（Swift 5.9+）。

```bash
git clone https://github.com/kevinyuzekai/Transfer-station.git
cd Transfer-station

# 生成 .app（通用二进制）
./scripts/build-app.sh

# 打包成 DMG
VERSION=1.0.0 ./scripts/package-dmg.sh
```

产物位于 `dist/`：
- `dist/FileTransferStation.app`
- `dist/FileTransferStation-<版本>.dmg`

### 发布流程（GitHub Actions）

推一个 `v*` 标签即可在 GitHub 的 macOS runner 上自动构建并发布 DMG：

```bash
git tag v1.0.0
git push origin v1.0.0
```

工作流会：编译通用二进制 → 组装 `.app` → 打包 DMG → 创建 Release 并上传 DMG。
也可在 Actions 页面手动触发 `workflow_dispatch` 仅生成产物（不发布）。

---

## 项目结构

```
Sources/FileTransferStation/
  main.swift          # 入口（NSApplication agent 模式）
  AppDelegate.swift   # 悬浮球 / 面板窗口、剪贴板监听、快捷键、外部点击收起
  AppModel.swift      # 状态与业务逻辑：中转站、剪贴板历史、设置、持久化
  Models.swift        # 条目 Item、设置、持久化数据结构
  Views.swift         # SwiftUI 界面：悬浮球、入口菜单、两块面板、设置
  DragSupport.swift   # 悬浮球拖入接收（NSDraggingDestination）、面板窗口
  HotKey.swift        # Carbon 全局快捷键
  LaunchAtLogin.swift # 开机自启（LaunchAgent）
scripts/
  build-app.sh        # 编译 + 组装 .app
  package-dmg.sh      # 打 DMG
.github/workflows/
  release.yml         # 构建并发布
```

数据保存在 `~/Library/Application Support/FileTransferStation/`（`data.json` 与 `images/`）。

---

## 说明

- 应用为 ad-hoc 签名，未做公证（notarization），首次打开需在「隐私与安全性」中放行。
- 中转站「只记引用」意味着原文件被移动或删除后条目会失效——这是设计取舍，界面会显式标注并提供「重新定位」。
- 剪贴板中的图片没有文件路径，会落盘到应用数据目录；删除条目或清空历史时会同步清除。
