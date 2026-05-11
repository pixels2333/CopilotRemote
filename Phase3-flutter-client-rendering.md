# 第三阶段：Flutter 客户端高性能渲染层方案

## 1. 阶段目标

第三阶段负责将 Node.js Bridge 推送的 WebSocket 流式 JSON 事件，转换为手机端高性能、低延迟、视觉体验优秀的聊天界面。

本方案只保留实现设计和落地方案，不包含具体 Flutter 代码。

核心目标：

- 使用 Riverpod 或 Bloc 构建稳定的消息状态机。
- 处理 `session.snapshot`、`message.start`、`block.start`、`block.delta`、`block.update`、`block.end`、`message.end` 等协议事件。
- 将流式 chunk 实时拼接到当前消息气泡。
- 为 thinking 区域提供渐变背景、折叠和动画。
- 为代码块提供语法高亮、行号、复制和横向滚动。
- 实现流畅打字机效果和智能滚动跟随。
- 提供类原生 AI App 的多行输入框，并通过 WebSocket 发送指令。

## 2. 推荐技术栈

| 能力 | 推荐库 |
| --- | --- |
| 状态管理 | Riverpod 或 Bloc |
| WebSocket | `web_socket_channel` |
| Markdown | `flutter_markdown` |
| 代码高亮 | `flutter_highlight` / `highlight` |
| ID 生成 | `uuid` |
| 集合辅助 | `collection` |

优先推荐 Riverpod，因为它适合将 WebSocket 连接、状态机和 UI 订阅拆分为独立 provider，结构清晰，测试也更方便。

## 3. 客户端分层架构

```text
WebSocket Channel
  → Protocol Decoder
  → Chat State Controller
  → Immutable Chat State
  → Chat UI Renderer
  → User Command Sender
```

建议文件职责：

| 模块 | 职责 |
| --- | --- |
| 模型层 | 定义 Envelope、Session、Message、Block、状态枚举。 |
| WebSocket 客户端 | 建立连接、发送 hello、监听消息、断线重连。 |
| 协议解码器 | 将 JSON 转换为协议事件，并做版本校验。 |
| Chat Controller | 状态机 reducer，处理所有协议事件。 |
| UI 层 | 渲染消息列表、气泡、block、输入框。 |
| 组件层 | Thinking、Markdown、CodeBlock、ToolCall、Artifact 等独立组件。 |

## 4. 核心数据模型设计

### 4.1 Envelope

Envelope 是 Flutter 收到的最外层协议对象。

关键字段：

| 字段 | 说明 |
| --- | --- |
| `v` | 协议版本。 |
| `seq` | 服务端事件序号，用于排序和去重。 |
| `type` | 事件类型。 |
| `sessionId` | 当前会话 ID。 |
| `requestId` | 请求关联 ID。 |
| `timestamp` | 事件时间。 |
| `payload` | 事件载荷。 |

### 4.2 Message

Message 表示一条聊天消息。

字段建议：

| 字段 | 说明 |
| --- | --- |
| `id` | 消息 ID。 |
| `role` | user、assistant、system、tool。 |
| `status` | pending、streaming、completed、failed、cancelled。 |
| `createdAt` | 创建时间。 |
| `updatedAt` | 更新时间。 |
| `blocks` | 内容块列表。 |
| `metadata` | 扩展信息。 |

### 4.3 Block

Block 是 UI 渲染和流式拼接的最小单位。

字段建议：

| 字段 | 说明 |
| --- | --- |
| `id` | block ID。 |
| `type` | text、thinking、code_block、tool_call、artifact。 |
| `status` | 当前输出状态。 |
| `content` | reducer 已拼接完成的完整内容。 |
| `visibleContent` | 打字机当前已经展示的内容。 |
| `language` | 代码语言。 |
| `fileName` | 代码块关联文件名。 |
| `toolState` | 工具调用状态。 |
| `artifactId` | artifact ID。 |
| `metadata` | 扩展信息。 |

### 4.4 双缓冲内容模型

为了兼顾 WebSocket 高频输入和 UI 动画流畅度，每个文本类 block 建议维护两份内容：

| 字段 | 作用 |
| --- | --- |
| `content` | 协议层完整内容，收到 chunk 后立即更新。 |
| `visibleContent` | UI 当前可见内容，由打字机 ticker 平滑推进。 |

这样可以让网络事件和 UI 帧率解耦，避免每个 chunk 都导致复杂 Markdown 重排。

## 5. 状态管理方案

### 5.1 ChatState

ChatState 建议包含：

| 字段 | 说明 |
| --- | --- |
| `messages` | 当前消息列表。 |
| `connectionStatus` | disconnected、connecting、connected、reconnecting、failed。 |
| `sessionId` | 当前会话 ID。 |
| `lastSeq` | 最近处理的服务端序号。 |
| `isSending` | 当前是否正在发送用户消息。 |
| `errorMessage` | 最近错误提示。 |

### 5.2 ChatController

ChatController 是核心 reducer，职责包括：

- 建立 WebSocket 连接。
- 发送 `client.hello`。
- 根据 `seq` 去重。
- 按事件类型更新 ChatState。
- 管理打字机 ticker。
- 发送用户指令。
- 处理错误和断线。

### 5.3 事件处理规则

| 事件 | 状态变化 |
| --- | --- |
| `server.hello` | 更新连接状态和 sessionId。 |
| `session.snapshot` | 替换完整消息列表。 |
| `message.start` | 追加新消息。 |
| `block.start` | 在指定消息下追加 block。 |
| `block.delta` | 根据 op、offset、chunk 更新 block.content。 |
| `block.update` | 合并工具调用或 artifact 的结构化字段。 |
| `block.end` | 标记 block 完成，并让 visibleContent 追平 content。 |
| `message.end` | 标记消息完成。 |
| `server.ack` | 清除发送中状态。 |
| `server.error` | 展示错误并清除发送中状态。 |
| `server.status` | 更新连接或 CDP 状态提示。 |

## 6. WebSocket 处理方案

### 6.1 连接流程

1. Flutter 启动后创建 WebSocket 连接。
2. 连接成功后发送 `client.hello`。
3. 如果本地保存了 `lastSeq`，在 hello 中携带 resume 信息。
4. 等待 `server.hello` 和 `session.snapshot`。
5. 后续持续接收增量事件。

### 6.2 发送消息

用户点击发送后，Flutter 构造 `client.command.sendMessage`，包含：

- 输入文本。
- 当前 sessionId。
- requestId。
- `submit: true`。
- `focus: true`。

Node.js Bridge 确认后返回 `server.ack`。如果失败返回 `server.error`。

### 6.3 断线重连

建议策略：

- WebSocket 断开后立即进入 reconnecting 状态。
- 使用指数退避重连。
- 重连时携带最近 `lastSeq`。
- 如果服务端无法续传，会发送完整快照。
- UI 保留当前消息列表，不因短暂断线清空页面。

## 7. 主聊天界面方案

### 7.1 页面结构

```text
ChatScreen
  ├── AppBar / connection status
  ├── MessageList
  │     └── MessageBubble
  │           ├── TextBlockView
  │           ├── ThinkingBlockView
  │           ├── CodeBlockView
  │           ├── ToolCallBlockView
  │           └── ArtifactBlockView
  └── ChatComposer
```

### 7.2 MessageList

建议使用 `ListView.builder`。消息多时不应一次性构建全部 widget。

滚动跟随策略：

- 用户接近底部时自动滚动到底部。
- 用户主动上滑查看历史时，停止强制跟随。
- 新消息到达时可以显示“跳到底部”悬浮按钮。
- 流式输出时滚动动画应短而平滑，避免卡顿。

### 7.3 MessageBubble

MessageBubble 根据 role 决定左右对齐和颜色：

| role | UI 表现 |
| --- | --- |
| user | 右侧气泡，强调色背景。 |
| assistant | 左侧气泡，暗色或卡片背景。 |
| system | 居中弱提示。 |
| tool | 可并入 assistant 消息或作为工具状态卡片。 |

每条消息内部按 blocks 顺序渲染，不建议将所有内容拼成一个 Markdown 字符串，因为 code、thinking、tool、artifact 需要不同视觉形态。

## 8. 精细化渲染方案

### 8.1 Text Block

普通文本使用 Markdown 渲染。

优化建议：

- 高频流式输入时不要每个字符都重建 Markdown。
- 可每 50-100ms 提交一次可见文本给 Markdown 渲染。
- Inline code、列表、引用等交给 Markdown 组件处理。
- 大段文本输出时保持行高稳定，减少布局抖动。

### 8.2 Thinking Block

Thinking 区域建议设计为特殊卡片：

- 渐变背景，与普通回答区分。
- 默认折叠，避免打断主回答阅读。
- 支持点击展开 / 收起。
- 展开使用高度动画或交叉淡入动画。
- 标题区显示 Thinking、图标和当前状态。
- 流式输出时可以显示轻微闪烁或呼吸动画。

视觉建议：

| 元素 | 建议 |
| --- | --- |
| 背景 | 蓝紫或蓝绿色低透明渐变。 |
| 边框 | 半透明高亮边框。 |
| 标题 | 图标 + Thinking 文案。 |
| 内容 | 灰色弱化文本，行高略大。 |
| 动画 | 200ms 左右展开收起。 |

### 8.3 Code Block

代码块建议独立渲染，不交给 Markdown 的普通代码块能力。

功能要求：

- 使用 `flutter_highlight` 做语法高亮。
- 顶部显示语言或文件名。
- 左侧显示行号。
- 支持一键复制完整代码。
- 支持横向滚动，避免强制换行导致布局开销。
- 流式代码输出时降低高亮刷新频率。

性能建议：

- 对 streaming 中的代码块做节流渲染。
- 对 completed 的代码块缓存高亮结果。
- 超大代码块可以默认折叠或按需展开。

### 8.4 Tool Call Block

工具调用卡片应展示：

- 工具名称。
- 当前状态：queued、running、succeeded、failed、cancelled。
- 参数摘要。
- 结果预览。
- 运行中加载动画。

建议状态颜色：

| 状态 | 颜色语义 |
| --- | --- |
| queued | 灰色 |
| running | 蓝色 / 加载动画 |
| succeeded | 绿色 |
| failed | 红色 |
| cancelled | 黄色或灰色 |

### 8.5 Artifact Block

Artifact 卡片应展示：

- 文件名或标题。
- artifact 类型。
- URI 或来源。
- 打开按钮。
- 保存或复制按钮。

打开行为可根据类型决定：

| artifact 类型 | 手机端行为 |
| --- | --- |
| file | 展示文件预览或请求 VS Code 打开。 |
| image | 图片预览。 |
| html | WebView 预览。 |
| diff | Diff 视图。 |
| terminal | 终端输出卡片。 |

## 9. 流式打字机方案

### 9.1 基本流程

1. WebSocket 收到 `block.delta`。
2. Reducer 立即拼接到 `block.content`。
3. 打字机 ticker 定期从 `content` 推进 `visibleContent`。
4. UI 渲染 `visibleContent`。
5. block 完成时让 `visibleContent` 追平 `content`。

### 9.2 推进速度

建议根据剩余字符数动态调整：

| 剩余字符 | 每帧推进 |
| --- | --- |
| 少量文本 | 1-4 字符 |
| 中等文本 | 4-8 字符 |
| 大段文本 | 8-20 字符 |

这样既有打字机感，又不会在长回答时拖得过慢。

### 9.3 滚动跟随

- 当前接近底部时自动跟随。
- 用户上滑后暂停跟随。
- 继续生成时可显示“新内容”按钮。
- message.end 后可执行一次最终滚动对齐。

## 10. 输入框交互方案

输入框目标是接近原生 AI App：

- 支持多行输入。
- 高度随内容增长，但设置最大高度。
- 发送按钮固定在右侧或右下角。
- 发送中禁用按钮或显示 loading。
- 支持键盘安全区。
- 发送后清空输入并保持焦点。

发送流程：

1. 用户输入文本。
2. 点击发送按钮。
3. Flutter 校验非空。
4. 设置 `isSending = true`。
5. 发送 `client.command.sendMessage`。
6. 收到 `server.ack` 后清除 sending。
7. 收到 `server.error` 时展示错误并恢复按钮。

## 11. 性能优化策略

### 11.1 状态更新

- Reducer 使用不可变状态，但避免无意义重建全部消息。
- 尽量只替换发生变化的 message 和 block。
- 对历史 completed 消息使用稳定 widget，减少重建。

### 11.2 Markdown 渲染

- 对 Markdown 渲染做 50-100ms 节流。
- 代码块单独渲染，不混入 Markdown。
- 对已完成的 Markdown 可缓存解析结果。

### 11.3 代码高亮

- Streaming 期间降低高亮频率。
- Completed 后进行最终高亮。
- 超大代码块可懒加载或折叠。

### 11.4 列表性能

- 使用懒加载列表。
- 消息气泡拆成细粒度 widget。
- 对大块内容使用横向滚动而不是强制换行。
- 避免每帧全局 setState。

## 12. 连接状态与错误体验

界面应明确展示当前状态：

| 状态 | UI 表现 |
| --- | --- |
| connecting | 顶部显示连接中。 |
| connected | 显示绿色状态点。 |
| reconnecting | 显示重连中，不清空历史。 |
| failed | 显示错误和重试按钮。 |
| disconnected | 显示离线状态。 |

错误处理建议：

- `server.error` 显示为 toast 或系统消息。
- 发送失败时保留用户输入，便于重试。
- Bridge 离线时输入框可禁用或提示离线。

## 13. 推荐落地顺序

1. 定义协议模型和状态枚举。
2. 实现 WebSocket 客户端和 `client.hello`。
3. 实现 ChatState 和 reducer。
4. 支持 `session.snapshot` 渲染历史消息。
5. 支持 `block.delta` 拼接文本。
6. 实现基础 MessageBubble 和 Markdown 文本。
7. 实现输入框并打通 `sendMessage`。
8. 加入打字机双缓冲。
9. 加入 thinking 折叠卡片。
10. 加入 code block 高亮、行号和复制。
11. 加入 tool_call 和 artifact 卡片。
12. 加入断线重连和 `lastSeq` 续传。
13. 做滚动、Markdown 和高亮性能优化。

## 14. 真机连接注意事项

- 真机上的 `127.0.0.1` 指手机自身，不是电脑。
- 真机需要使用电脑局域网 IP，例如 `ws://192.168.1.10:17321/copilot-mirror/ws`。
- Android 模拟器访问宿主机通常使用 `10.0.2.2`。
- iOS 模拟器访问宿主机可使用 Mac 本机地址；Windows 场景建议直接使用局域网 IP。
- 局域网调试时注意防火墙放行 Node.js WebSocket 端口。

## 15. MVP 验收标准

- App 能连接 Node.js Bridge。
- App 能收到并渲染 `session.snapshot`。
- App 能根据 `block.delta` 实时追加文本。
- 流式输出时滚动自然跟随。
- 用户能从手机端发送 prompt 到 VS Code Copilot。
- Thinking、代码块、工具调用和 artifact 至少有可区分的 UI 展示。
- 断线重连后不会重复拼接已收到的内容。
