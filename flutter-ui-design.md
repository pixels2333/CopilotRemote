# Flutter UI 设计稿

> 基于 `flutter-preview.html` 的最终视觉效果同步更新。根据此设计稿实现 `main.dart`、`screens/`、`widgets/`。

---

## 0. 主题 & 颜色规范

| 变量 | 值 | 用途 |
|------|-----|------|
| seed color | `#6366F1` | Primary / FilledButton / agent chip active 边框 |
| body bg | `#131315` | 聊天区域背景 |
| surface | `#1C1C1F` | AppBar / Composer / Drawer 背景 |
| surface2 | `#1E1E24` | 消息气泡（assistant）/ 输入框背景 |
| surface3 | `#18181B` | 代码块背景 |
| border | `#2A2A2E` | 分割线 / 气泡边框 |
| border2 | `#3F3F46` | 按钮边框 / chip 默认边框 |
| text primary | `#E4E4E7` | 正文 |
| text secondary | `#A1A1AA` | 副标题 / role 标签 |
| text muted | `#71717A` | placeholder / 描述 |
| user bubble | `#6366F1` | 用户气泡背景 |
| success green | `#4ADE80` | 连接成功 / tool succeeded |
| error red | `#7F1D1D` | error toast 背景 |
| accent purple | `#A78BFA` | Thinking 区块 / agent chip icon |

暗色模式：`ThemeData.dark()`，`colorSchemeSeed = Color(0xFF6366F1)`。

---

## 1. main.dart

**位置**: `lib/main.dart`

- `ProviderScope` 包裹整个应用
- `MaterialApp`，暗色主题，seed color = `#6366F1`
- 启动时自动调用 `chatProvider.notifier.connect('ws://127.0.0.1:17321/copilot-mirror/ws')`
- home 指向 `ChatScreen`

---

## 2. screens/chat_screen.dart

**布局**: `Scaffold`

| 区域 | 组件 |
|------|------|
| AppBar | Logo + 标题 "Copilot Mirror" + 副标题（当前会话名）；右侧依次：`AgentChip`、`SessionSwitchButton`、连接状态圆点 |
| Body | `Stack`：`Column(ConnectionStatusBar → Expanded(ChatMessageList) → ChatComposer)` + `SessionLoadingOverlay` + `SwitchingToast` |
| 底部 | `ChatComposer`（含 `/` 按钮 + 输入框 + 发送按钮） |

### AppBar 详细结构

```
Row(
  logo(22×22, gradient #6366F1→#8B5CF6, radius 6),
  Column(title "Copilot Mirror" 17sp bold, subtitle 10sp #71717A),
  Spacer,
  AgentChip,
  SessionSwitchButton(32×32),
  StatusDot,
)
```

### ChatMessageList

- `ListView.builder`，`padding EdgeInsets.only(top: 4, bottom: 8)`
- 空状态：
  - **未连接**：云断开图标 + "Not connected" + "启动 Node.js Bridge 后点击连接" + FilledButton "Connect"
  - **已连接无消息**：气泡图标 + "No messages yet" + 描述文字
- 非空：渲染 `MessageBubble` 列表
- 滚动跟随：用户接近底部自动跟随；上滑暂停；偏移 > 120px 时显示 "↓" FAB（`bottom: 72px, right: 18px`）
- 错误 Toast：`Positioned` 顶部，`#7F1D1D` 背景，`#FCA5A5` 文字，3s 自动消失或点击 `×` 关闭

---

## 3. widgets/connection_status_bar.dart

- `Container`，高度约 28px，`padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)`
- 根据 `ConnectionStatus` 显示不同背景色和文案：

| 状态 | 背景色 | 图标 | 文案 |
|------|--------|------|------|
| connected | `#166534` | `cloud_done` ✓ | Connected |
| connecting | `#9A3412` | `cloud_upload` | Connecting… |
| reconnecting | `#9A3412` | `cloud_sync` | Reconnecting… |
| disconnected | `#374151` | `cloud_off` ⚠ | Disconnected |
| failed | `#991B1B` | `error_outline` | Connection Failed |

---

## 4. widgets/message_bubble.dart

- 根据 `MessageRole` 决定对齐和颜色：

| role | 对齐 | 气泡色 | 边框 |
|------|------|--------|------|
| user | 右对齐 | `#6366F1` | 无 |
| assistant | 左对齐 | `#1E1E24` | `1px #2A2A2E` |
| system | 居中 | `#27272A` | 无，字号 12sp，圆角 20px |
| tool | 左对齐 | 同 assistant | 同 assistant |

- 圆角：`BorderRadius.only`，16px 三圆角 + 4px 一角（user: 右下 4px；assistant: 左下 4px）
- assistant 消息头部：`Row(🤖 icon 12sp #A78BFA, "Copilot" 11sp #A78BFA)`，`margin bottom 4px`
- 最大宽度 `MediaQuery.of(context).size.width * 0.82`
- blocks 列表按顺序渲染对应的 Block 组件

---

## 5. Block 组件

### 5.1 widgets/text_block_view.dart

- 使用 `flutter_markdown` 的 `MarkdownBody`
- 内容优先取 `block.visibleContent`，回退到 `block.content`
- 空内容 + streaming 态 → `LinearProgressIndicator` 占位
- 支持 Markdown 内联代码（`background rgba(255,255,255,0.08)` 圆角 4px 13sp 等宽体）、标题、列表、引用、代码块

### 5.2 widgets/thinking_block_view.dart

- 可折叠卡片，`margin: 4px 0`，`border-radius: 10px`
- 背景：`LinearGradient(colors: [Color(0x156366F1), Color(0x1506B6D4)])`
- 边框：`1px rgba(99,102,241,0.2)`
- 头部：`🧠 icon + "Thinking" + streaming 时 CircularProgressIndicator(12×12) + 展开/收起箭头`，全行点击切换
- 收起动画：`AnimationController` 200ms，`SizeTransition` 或 `ClipRect`
- 展开内容：`#A1A1AA` 12sp，行高 1.6，`padding: 0 10px 8px`

### 5.3 widgets/code_block_view.dart

- 背景 `#18181B`，圆角 10px，边框 `1px #27272A`
- 头部栏（`#1F1F23`）：语言标签（如 `📘 typescript`）+ `📋 复制` 按钮
- 复制按钮点击：`Clipboard.setData` + SnackBar "Copied to clipboard"
- 代码体：`SingleChildScrollView(scrollDirection: Axis.horizontal)`，等宽字体 `Cascadia Code / Fira Code / Consolas` 12sp，行高 1.6，`padding: 8px 10px`

### 5.4 widgets/tool_call_block_view.dart

- `margin: 4px 0`，`padding: 8px 10px`，圆角 10px
- 背景 `rgba(74,222,128,0.06)`，边框 `1px rgba(74,222,128,0.25)`
- 布局：`Row(icon, Column(toolName bold #4ADE80, status 11sp #71717A, summary 12sp #A1A1AA))`

| 状态 | 图标颜色 | 图标 |
|------|----------|------|
| queued | grey | `hourglass_empty` |
| running | blue | `sync` + 旋转动画 |
| succeeded | `#4ADE80` | `check_circle_outline` ✓ |
| failed | red | `error_outline` |
| cancelled | amber | `cancel_outlined` |

### 5.5 widgets/artifact_block_view.dart

- `margin: 4px 0`，`padding: 10px`，圆角 10px
- 背景 `rgba(251,191,36,0.06)`，边框 `1px rgba(251,191,36,0.25)`
- 布局：`Row(typeIcon 20sp, Column(name 13sp #E4E4E7, uri 11sp #71717A), openButton)`
- 图标映射：file→`description_outlined 📄`, image→`image_outlined 🖼`, html→`web 🌐`, markdown→`article_outlined 📝`, diff→`compare`, terminal→`terminal`

---

## 6. widgets/agent_chip.dart

AppBar 右侧的 agent 选择 chip，点击打开底部 Picker。

```
GestureDetector(
  onTap: () => showAgentPicker(context),
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: activeAgent != null ? Color(0xFF6366F1) : Color(0xFF3F3F46)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.smart_toy_outlined, size: 14, color: Color(0xFF6366F1)),
        SizedBox(width: 4),
        Text(activeAgentName, style: TextStyle(fontSize: 12, color: Color(0xFFE4E4E7))),
        SizedBox(width: 2),
        Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF71717A)),
      ],
    ),
  ),
)
```

**Agent Picker（底部 Sheet）**

- 与 Session Drawer 同样结构：`DraggableScrollableSheet` 或 `showModalBottomSheet`
- 最大高度 55% 屏幕
- 顶部手柄条（`36×4px #52525B`）
- 标题行：`🤖 Switch Agent`
- 分割线
- agent 列表（`ListView`）：每项 `Row(🤖 icon 20sp, Column(name 14sp bold if active, description 12sp #71717A), active ? ✓ : SizedBox)`
- 点击项：更新 `ChatState.activeAgentId`，调用 `switchAgent()`，关闭 sheet

**数据（运行时从 Bridge 拉取）**

当前调试场景下的 agent 列表（`client.command.listAgents` 返回）：

| id | name |
|----|------|
| agent | agent（默认激活） |
| plan | plan |
| windows_developer | Agent Windows Developer |
| data | Data |
| demonstrate | DemonStrate |

---

## 7. widgets/chat_composer.dart

Composer 区域：`padding: 8px 12px 12px`，背景 `#1C1C1F`，顶部边框 `1px #2A2A2E`。

```
Row(
  SlashButton,          // 36×36，圆角 8px，边框 #3F3F46
  Expanded(TextField),  // 圆角 20px，背景 #1E1E24
  SendButton,           // 40×40 圆形，背景 #6366F1
)
```

### SlashButton（`/` 按钮）

- 尺寸 `36×36`，圆角 8px，边框 `1px #3F3F46`
- 默认色 `#A1A1AA`；hover/active：边框 `#6366F1`，颜色 `#6366F1`，背景 `rgba(99,102,241,0.08)`
- 断线时 `opacity 0.3`，禁用
- 点击：切换 `SlashMenu` 浮层

### SlashMenu（浮层）

- 定位：`Stack` + `Positioned(bottom: 60, left: 12)`，宽 280px，最大高度 300px
- 背景 `#1E1E24`，边框 `1px #3F3F46`，圆角 12px
- 顶部标题行：`"Slash Commands · N available"` 11sp `#71717A`，下边框
- 列表项：`Row(icon >_ 14sp #6366F1 w20, Column(label 13sp #E4E4E7, desc 11sp #71717A))`
- 点击项：关闭浮层，触发 `applySlashCommand(index, label)`
- 点击浮层外区域（半透明遮罩 `rgba(0,0,0,0.3)`）关闭

**当前调试场景的 slash 命令列表**（`client.command.listSlashCommands` 返回）：

| label | description |
|-------|-------------|
| /explain | Explain the selected code |
| /fix | Propose a fix for problems |
| /tests | Generate unit tests |
| /doc | Add documentation |
| /optimize | Suggest performance improvements |
| /help | Show available commands |

### TextField

- `minLines: 1`，`maxLines: 5`，圆角 20px
- hintText：连接态 "Ask Copilot…"，断线态 "Disconnected…"，颜色 `#52525B`
- 断线时 `enabled: false`，`opacity 0.4`

### SendButton

- 尺寸 `40×40`，圆形，背景 `#6366F1`，图标 `➤`
- 发送中：`CircularProgressIndicator` 替换图标，按钮 disabled（背景 `#3F3F46`）
- hover 背景 `#4F46E5`
- `onSubmitted` / 按钮 tap 触发发送，发送后 `_controller.clear()`
- 底部适配 `MediaQuery.of(context).padding.bottom`

---

## 8. widgets/session_drawer.dart

点击 AppBar 右侧 `⇄` 按钮打开，与 `AgentPicker` 结构相同。

- 标题：`⇄ Switch Session`；右上角 `+ New` 按钮
- 列表项：`Row(session icon 32×32, Column(title 14sp, preview 12sp #71717A), active ? ✓ : SizedBox)`
- 活跃项：背景 `rgba(99,102,241,0.15)`，图标背景 `rgba(99,102,241,0.2)` 紫色
- 切换流程：
  1. 关闭抽屉
  2. 全屏 `SessionLoadingOverlay`（spinner + "Switching session…"）
  3. 调用 `switchSession(sessionId)` → Bridge 发送 `switchSession` 命令
  4. 收到 `session.switched` 事件后：隐藏 loading，显示 `SwitchingToast`（1.2s 后自动消失），更新 `AppBar` 副标题，清空消息列表

**新建会话流程**：点击 `+ New` → 同切换流程，收到 `session.created` 事件后更新。

---

## 9. 场景列表（5 个调试场景）

| 场景 tab | 描述 |
|----------|------|
| 💬 聊天场景 | 完整对话界面：所有 Block 组件 + agent chip + slash 按钮 + session 切换 |
| 📭 空状态 | 已连接但无消息，显示 "No messages yet" |
| 🔌 断线状态 | ConnectionStatus=disconnected，输入框禁用，显示 "Connect" 按钮 |
| 📋 会话切换 | 打开 Session Drawer，展示 5 条历史会话，切换 loading + toast |
| ⚡ Slash & Agent | slash 菜单浮层 + agent picker 演示场景 |

---

## 10. providers 更新说明

`ChatState` 新增字段：

```dart
final List<MirrorSlashCommandItem> slashCommands;
final List<MirrorAgentItem> agents;
final String? activeAgentId;
```

`ChatNotifier` 新增方法：

| 方法 | 触发 Bridge 命令 | 监听事件 |
|------|-----------------|---------|
| `listSlashCommands()` | `client.command.listSlashCommands` | `slash.list` |
| `applySlashCommand(index, label)` | `applySlashCommand` | — |
| `listAgents()` | `client.command.listAgents` | `agent.list` |
| `switchAgent(id, name, index)` | `switchAgent` | `agent.switched` |

---

## 11. 注意事项（真机部署时）

- Android 模拟器：`ws://10.0.2.2:17321/copilot-mirror/ws`
- iOS 模拟器：`ws://localhost:17321/copilot-mirror/ws`
- 真机：使用电脑局域网 IP，如 `ws://192.168.1.10:17321/copilot-mirror/ws`
- 防火墙需放行 17321 端口
- Escape 键 / 点击遮罩：关闭所有浮层（Agent Picker、Slash Menu、Session Drawer）
