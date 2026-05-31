# muxy fork — CCH 式会话管理改造

基于 [muxy](https://github.com/muxy-app/muxy)(Ghostty 内核终端)二次开发,补上 Claude Code Hub 的核心能力:**项目 → 多命名会话、稳定 sessionId 持久化、自动接回对话**,并移除遥测、保留懒加载。

## 新增能力

### 1. CCH 式持久会话
- 新增 `Muxy/Models/ClaudeSession.swift` — 会话模型(稳定 `claudeSessionId`)
- 新增 `Muxy/Services/ClaudeSessionStore.swift` — 持久库,存于 `~/Library/Application Support/Muxy/claude-sessions.json`(= CCH 的 `data.json`)
- 每个项目 → 多个命名会话(用 tab 承载),关项目重开 / 关 App 重启都从库读回

### 2. 自动接回对话
- 自愈式启动命令:`claude --resume <id> || claude --session-id <id>`
- 有会话就 resume,没有就用同一个稳定 id 创建 —— 绝不新开随机会话

### 3. 重启 App 也接回(关键)
- `Muxy/Models/AppState.swift` `restoreSelection()`:App 重启后不复用工作区快照(会绕过库),改为从 `ClaudeSessionStore` 重建 TabArea → `--resume` 接回

### 4. 懒加载
- 利用 muxy 原生 onAppear 懒渲染:打开项目时只有激活的 tab 启动 claude,其他 tab/分屏切换到时才加载

### 5. 多终端一致
- `Muxy/Models/TabArea.swift`:新 tab(⌘T)、分屏(split)出来的窗格 —— 都是独立持久 claude 会话

### 6. 去遥测
- `Muxy/Services/SentryService.swift` `resolveBundledDSN()` 恒返回 nil → Sentry 永不初始化

## 改动文件
| 文件 | 改动 |
|---|---|
| `Muxy/Models/ClaudeSession.swift` | 🆕 会话模型 + 自愈启动命令 |
| `Muxy/Services/ClaudeSessionStore.swift` | 🆕 会话持久库(损坏保留 .corrupt、空路径 guard) |
| `Muxy/Models/TabArea.swift` | init/createTab/split 接入 store |
| `Muxy/Models/AppState.swift` | restoreSelection 重启走 store 重建 |
| `Muxy/Services/SentryService.swift` | 禁用 Sentry |

## 构建
```bash
# 1. 下预编译 GhosttyKit(不需要 zig)
curl -fsSL -o GhosttyKit.xcframework.tar.gz \
  https://github.com/muxy-app/ghostty/releases/download/build-2026-04-29/GhosttyKit.xcframework.tar.gz
curl -fsSL -o GhosttyKit-resources.tar.gz \
  https://github.com/muxy-app/ghostty/releases/download/build-2026-04-29/GhosttyKit-resources.tar.gz
tar xzf GhosttyKit.xcframework.tar.gz
tar xzf GhosttyKit-resources.tar.gz
cp GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h GhosttyKit/ghostty.h
cp -R terminfo Muxy/Resources/terminfo   # 或从已装 Muxy.app 拷
bash scripts/setup.sh                      # 下 ripgrep

# 2. 编译 + 打包
swift build
bash scripts/build-release.sh --arch arm64 --version 0.28.0

# 3. ad-hoc 签名 + 安装
codesign --force --deep --sign - --entitlements Muxy/Muxy.entitlements build/Muxy.app
cp -R build/Muxy.app /Applications/Muxy.app
```

## 样式
muxy 读 `~/Library/Application Support/Muxy/ghostty.conf`(标准 Ghostty 配置语法),支持字体/主题/透明度/模糊等全部 Ghostty 样式项。
