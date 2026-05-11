# Flutter UI 设计稿（占位）

> 当环境就绪后，根据此设计稿实现 `main.dart`、`screens/`、`widgets/`。

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
| AppBar | 标题 "Copilot Mirror"，右侧绿/灰圆点（反映 `connectionStatus`） |
| Body | `Column`：`ConnectionStatusBar` → `Expanded(ChatMessageList)` → `ChatComposer` |

### ChatMessageList

- `ListView.builder`，`padding EdgeInsets.only(top: 4, bottom: 8)`
- 空状态：
  - **未连接**：云断开图标 + "Not connected" + "Start the Node.js Bridge to connect." + FilledButton "Connect"
  - **连接中**：气泡图标 + "Connecting…"
- 非空：渲染 `MessageBubble` 列表
- 滚动跟随：用户接近底部自动跟随；上滑暂停；偏移 > 120px 时显示 "跳到底部" FAB
- 错误提示：`Positioned` 顶部，`errorContainer` 背景色，3s 自动消失或点击消除

---

## 3. widgets/connection_status_bar.dart

- `Container`，高度约 28px
- 根据 `ConnectionStatus` 显示不同背景色和文案：

| 状态 | 背景色 | 图标 | 文案 |
|------|--------|------|------|
| connected | 绿色 700 | cloud_done | Connected |
| connecting | 橙色 700 | cloud_upload | Connecting… |
| reconnecting | 橙色 700 | cloud_sync | Reconnecting… |
| disconnected | 灰色 700 | cloud_off | Disconnected |
| failed | 红色 700 | error_outline | Connection Failed |

---

## 4. widgets/message_bubble.dart

- 根据 `MessageRole` 决定对齐和颜色：

| role | 对齐 | 气泡色 |
|------|------|--------|
| user | 右对齐 | `primaryContainer` |
| assistant | 左对齐 | `surfaceContainerHigh` |
| system | 居中 | `surfaceContainerHighest`，小字 |
| tool | 左对齐 | 同 assistant |

- 圆角：`BorderRadius.only`，16px 三圆角 + 4px 一角（根据角色翻转）
- assistant 消息头部显示 "Copilot" 标签 + 机器人图标
- 最大宽度 `MediaQuery.of(context).size.width * 0.82`
- blocks 列表按顺序渲染对应的 Block 组件

---

## 5. Block 组件

### 5.1 widgets/text_block_view.dart

- 使用 `flutter_markdown` 的 `MarkdownBody`
- 内容优先取 `block.visibleContent`，回退到 `block.content`
- 空内容 + streaming 态 → `LinearProgressIndicator` 占位
- 支持 Markdown 内联代码、标题、列表、引用、代码块

### 5.2 widgets/thinking_block_view.dart

- 可折叠卡片
- 背景：蓝紫渐变 `LinearGradient(Colors: [0x156366F1, 0x1506B6D4])`
- 边框：primary 色 20% 透明度
- 头部：心理学图标 + "Thinking" + streaming 时显示小加载圈 + 展开/收起箭头
- 收起动画：`AnimationController` 200ms，`CustomClipper` 裁剪高度
- 展开后内容：灰色小字，行高 1.5

### 5.3 widgets/code_block_view.dart

- `surfaceContainerHighest` 背景，8px 圆角
- 头部栏：语言标签 + 文件名（可选）+ 复制按钮
- 复制按钮点击：`Clipboard.setData` + SnackBar "Copied to clipboard"
- 代码体：`SingleChildScrollView(horizontal)`，行号列 + 代码列
- 等宽字体 13px，行高 1.5

### 5.4 widgets/tool_call_block_view.dart

- 状态卡片，左上角色标 + 图标：

| 状态 | 颜色 | 图标 |
|------|------|------|
| queued | grey | hourglass_empty |
| running | blue | sync + 加载圈 |
| succeeded | green | check_circle_outline |
| failed | red | error_outline |
| cancelled | amber | cancel_outlined |

- 显示工具名称（`block.fileName`）

### 5.5 widgets/artifact_block_view.dart

- 卡片布局：类型图标 + 名称 + URI + 打开按钮
- 图标映射：file→description_outlined, image→image_outlined, html→web, markdown→article_outlined, diff→compare, terminal→terminal

---

## 6. widgets/chat_composer.dart

- `TextField`，多行（minLines=1, maxLines=5），圆角 20px
- hintText：连接态 "Ask Copilot…"，断线态 "Disconnected…"
- 发送按钮：`Icons.send_rounded`，`primary` 背景
- 发送中：`CircularProgressIndicator` 替换图标，按钮 disabled
- 断线时输入框 disabled
- `onSubmitted` 触发发送，发送后 `_controller.clear()`
- 底部适配 `MediaQuery.of(context).padding.bottom`

---

## 7. 注意事项（真机部署时）

- Android 模拟器：`ws://10.0.2.2:17321/copilot-mirror/ws`
- iOS 模拟器：`ws://localhost:17321/copilot-mirror/ws`
- 真机：使用电脑局域网 IP，如 `ws://192.168.1.10:17321/copilot-mirror/ws`
- 防火墙需放行 17321 端口
