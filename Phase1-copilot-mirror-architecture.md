# Copilot Mirror 技术架构与 WebSocket 通信协议方案

## 1. 项目目标

Copilot Mirror 的目标是通过 VS Code 的 `--remote-debugging-port=9229` 暴露 Chrome DevTools Protocol，由 Node.js Bridge 抓取 GitHub Copilot 侧边栏内容，再通过 WebSocket 实时同步到 Flutter 手机端。

整体链路：

```text
VS Code Copilot Sidebar
  → Chrome DevTools Protocol
  → Node.js Bridge
  → WebSocket JSON Protocol
  → Flutter Chat UI
```

核心目标：

- 手机端连接后立即同步当前 Copilot 会话历史。
- AI 输出时采用增量 chunk 推送，避免重复发送全文。
- 协议能区分普通文本、思考过程、代码块、工具调用和 artifact。
- 手机端可发送指令，经 Node.js Bridge 反向驱动 VS Code Copilot。
- Node.js 层负责 CDP 适配、DOM 归一化、增量计算、连接管理和协议转换。

## 2. 总体架构

### 2.1 VS Code 层

VS Code 作为数据源，运行时开启远程调试端口。Copilot Chat 的 UI 可能存在于 Webview target，也可能嵌在 workbench target 中。Bridge 不依赖 Copilot 内部 API，而是通过 CDP 对页面 DOM 进行观察和交互。

职责：

- 展示 Copilot Chat 历史消息。
- 展示正在流式生成的 assistant 回复。
- 展示 thinking、代码块、工具调用和预览文件。
- 接收由 Node.js Bridge 注入的输入和提交操作。

### 2.2 Node.js Bridge 层

Node.js Bridge 是核心中间层，负责把不稳定的 DOM 状态转换成稳定协议事件。

建议模块：

| 模块 | 职责 |
| --- | --- |
| CDP 连接管理 | 连接 `localhost:9229`，发现和维护 Copilot target。 |
| Target 定位器 | 根据 URL、title、target 类型和页面特征定位 Copilot Webview。 |
| DOM 探针 | 注入 MutationObserver，采集页面变化。 |
| 会话归一化 | 将 DOM 节点转换为 session、message、block 模型。 |
| 增量引擎 | 对比上次状态与当前状态，生成 append / replace 类型增量。 |
| 会话缓存 | 保存当前快照、事件序号、断线续传缓冲区。 |
| WebSocket 网关 | 处理 Flutter 握手、广播事件、接收指令。 |
| 指令桥 | 将手机端指令转成 VS Code 页面操作。 |

### 2.3 Flutter 层

Flutter 客户端负责高性能渲染和用户交互。

职责：

- 建立 WebSocket 连接并完成握手。
- 接收历史快照和后续增量事件。
- 使用状态机拼接消息和内容块。
- 实现打字机效果、滚动跟随、代码高亮、thinking 折叠区。
- 通过协议向 Node.js Bridge 发送 prompt、停止生成、打开 artifact 等指令。

## 3. 领域模型

### 3.1 Session

Session 表示一个 Copilot Chat 会话或当前侧边栏上下文。

关键字段：

| 字段 | 说明 |
| --- | --- |
| `sessionId` | 会话唯一 ID。 |
| `title` | 会话标题。 |
| `workspace` | 当前工作区路径，可为空。 |
| `createdAt` | 首次观察到会话的时间。 |
| `updatedAt` | 最近更新时间。 |
| `messages` | 当前历史消息列表。 |

### 3.2 Message

Message 表示用户或 assistant 的一次对话消息。

关键字段：

| 字段 | 说明 |
| --- | --- |
| `id` | 消息唯一 ID。 |
| `role` | `user`、`assistant`、`system` 或 `tool`。 |
| `status` | `pending`、`streaming`、`completed`、`failed` 或 `cancelled`。 |
| `createdAt` | 创建时间。 |
| `updatedAt` | 更新时间。 |
| `blocks` | 消息内部的结构化内容块。 |

### 3.3 Block

Block 是渲染和增量同步的最小结构单位。

支持类型：

| 类型 | 用途 | 是否流式 |
| --- | --- | --- |
| `text` | 普通 Markdown 或纯文本 | 是 |
| `thinking` | 思考过程或推理摘要 | 是 |
| `code_block` | 代码块，包含语言和文件名元信息 | 是 |
| `tool_call` | 工具调用状态、参数和结果摘要 | 主要结构化更新 |
| `artifact` | 文件、预览、diff、图片等生成物 | 通常结构化更新 |

## 4. WebSocket 协议设计

### 4.1 通用 Envelope

所有消息都使用统一信封，便于版本控制、排序、断线续传和请求关联。

```json
{
  "v": 1,
  "seq": 1024,
  "type": "block.delta",
  "sessionId": "vscode-window-1/copilot-chat/default",
  "requestId": "req_001",
  "timestamp": "2026-05-11T10:05:05.120Z",
  "payload": {}
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `v` | 协议版本。 |
| `seq` | 服务端递增序号，用于排序、去重、续传。 |
| `type` | 事件类型。 |
| `sessionId` | 当前 Copilot 会话 ID。 |
| `requestId` | 客户端指令和服务端响应的关联 ID。 |
| `timestamp` | 事件产生时间。 |
| `payload` | 具体事件内容。 |

### 4.2 事件分类

| 方向 | 类型 | 用途 |
| --- | --- | --- |
| Flutter → Node.js | `client.hello` | 客户端握手与能力声明。 |
| Node.js → Flutter | `server.hello` | 服务端握手响应。 |
| Node.js → Flutter | `session.snapshot` | 完整历史快照。 |
| Node.js → Flutter | `session.resume` | 断线续传确认。 |
| Node.js → Flutter | `message.start` | 新消息开始。 |
| Node.js → Flutter | `block.start` | 新内容块开始。 |
| Node.js → Flutter | `block.delta` | 内容块增量片段。 |
| Node.js → Flutter | `block.update` | 工具调用或 artifact 的结构化更新。 |
| Node.js → Flutter | `block.end` | 内容块结束。 |
| Node.js → Flutter | `message.end` | 消息结束。 |
| Flutter → Node.js | `client.command.*` | 手机端反向控制指令。 |
| Node.js → Flutter | `server.ack` | 指令确认。 |
| Node.js → Flutter | `server.error` | 错误响应。 |
| 双向 | `ping` / `pong` | 心跳。 |

## 5. 会话握手与历史同步

### 5.1 客户端握手

Flutter 连接后发送 `client.hello`，声明客户端能力、认证信息和断线续传游标。

```json
{
  "v": 1,
  "type": "client.hello",
  "requestId": "req_hello_001",
  "timestamp": "2026-05-11T10:06:00.000Z",
  "payload": {
    "clientId": "flutter-phone",
    "protocolVersion": 1,
    "capabilities": {
      "acceptDelta": true,
      "acceptThinking": true,
      "acceptArtifacts": true
    },
    "resume": {
      "sessionId": "vscode-window-1/copilot-chat/default",
      "lastSeq": 1018
    }
  }
}
```

### 5.2 服务端握手响应

Node.js 返回 CDP 连接状态、当前 target 信息、当前 session 和可用命令能力。

### 5.3 历史快照

握手成功后，服务端应立即发送 `session.snapshot`。快照包含完整 message 列表和每条消息下的 blocks。Flutter 收到后直接替换本地会话状态。

### 5.4 断线续传

客户端重连时携带 `lastSeq`。服务端优先从事件缓冲区补发缺失事件；如果缓冲区已过期，则重新发送完整 `session.snapshot`。

## 6. 流式增量更新

### 6.1 事件生命周期

一次 assistant 回复建议按以下顺序推送：

```text
message.start
  → block.start
  → block.delta
  → block.delta
  → block.end
message.end
```

如果消息中包含多个结构块，例如文本 + 代码块 + 工具调用，则每个 block 都独立拥有自己的生命周期。

### 6.2 Delta 设计

`block.delta` 只推送新增片段，不重复发送完整内容。

```json
{
  "v": 1,
  "seq": 1027,
  "type": "block.delta",
  "sessionId": "vscode-window-1/copilot-chat/default",
  "timestamp": "2026-05-11T10:06:10.120Z",
  "payload": {
    "messageId": "msg_assistant_001",
    "blockId": "blk_text_001",
    "blockType": "text",
    "op": "append",
    "offset": 0,
    "chunk": "可以，整体架构建议分为四层：",
    "format": "markdown",
    "done": false
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `messageId` | 目标消息。 |
| `blockId` | 目标内容块。 |
| `blockType` | 内容块类型。 |
| `op` | `append`、`replace` 或预留的 `patch`。 |
| `offset` | 本次 chunk 开始位置。 |
| `chunk` | 增量文本。 |
| `format` | `markdown`、`plain`、`json` 或 `diff`。 |
| `done` | 是否为最后一段。 |

### 6.3 增量规则

- 正常流式输出使用 `append`。
- 如果 DOM 内容发生重写，使用 `replace`。
- Flutter 必须用 `seq` 去重，并用 `offset` 校验拼接位置。
- 如果 offset 不匹配，Flutter 可请求重新同步或等待服务端发送新快照。

## 7. 结构化内容类型

### 7.1 Text

普通文本块，通常按 Markdown 渲染。适合说明、列表、引用和一般回复。

### 7.2 Thinking

思考块用于展示模型推理过程、规划过程或思考摘要。Flutter 端建议默认折叠，避免占用主要对话空间。

### 7.3 Code Block

代码块需要包含语言、文件名、内容和可选的 URI 信息。Flutter 端单独渲染，支持语法高亮、复制、横向滚动和行号。

### 7.4 Tool Call

工具调用块用于展示工具名称、运行状态、参数摘要和结果预览。状态应可从 `queued` 变化到 `running`、`succeeded`、`failed` 或 `cancelled`。

### 7.5 Artifact

Artifact 表示生成物或预览对象，例如文件、diff、HTML 预览、图片或终端输出。它通常不以文本 chunk 流式更新，而是通过 `block.update` 更新元信息。

## 8. 双向指令协议

手机端通过 `client.command.*` 发送指令，Node.js Bridge 转换为 CDP 操作。

### 8.1 发送消息

```json
{
  "v": 1,
  "type": "client.command.sendMessage",
  "sessionId": "vscode-window-1/copilot-chat/default",
  "requestId": "req_send_001",
  "timestamp": "2026-05-11T10:07:00.000Z",
  "payload": {
    "text": "请把这个方案整理成接口定义。",
    "options": {
      "submit": true,
      "focus": true
    }
  }
}
```

Node.js 处理流程：

1. 定位 Copilot 输入框。
2. 聚焦输入框。
3. 写入文本。
4. 触发输入事件。
5. 根据 `submit` 决定是否模拟发送。
6. 返回 `server.ack` 或 `server.error`。

### 8.2 其他指令

| 指令 | 用途 |
| --- | --- |
| `client.command.stopGeneration` | 停止当前生成。 |
| `client.command.focusInput` | 聚焦 VS Code Copilot 输入框。 |
| `client.command.switchSession` | 切换会话。 |
| `client.command.openArtifact` | 在 VS Code 或手机端打开 artifact。 |
| `client.command.resync` | 请求重新发送快照。 |

## 9. CDP 到 Flutter 的完整流转

### 9.1 启动阶段

1. VS Code 以 `--remote-debugging-port=9229` 启动。
2. Node.js Bridge 连接 CDP endpoint。
3. Bridge 遍历 targets，定位 Copilot 页面。
4. Bridge 注入 DOM 观察脚本。
5. WebSocket 服务等待 Flutter 连接。

### 9.2 历史同步阶段

1. Flutter 发起 `client.hello`。
2. Node.js 返回 `server.hello`。
3. Node.js 从当前 DOM 状态生成完整会话快照。
4. Flutter 用 `session.snapshot` 初始化本地状态。

### 9.3 实时输出阶段

1. Copilot DOM 发生变化。
2. MutationObserver 捕获变化。
3. 注入脚本提取 message 和 block 状态。
4. Node.js Delta Engine 生成协议事件。
5. WebSocket 广播给 Flutter。
6. Flutter reducer 拼接内容并驱动 UI 更新。

### 9.4 手机端反向控制阶段

1. 用户在 Flutter 输入 prompt。
2. Flutter 发送 `client.command.sendMessage`。
3. Node.js Bridge 通过 CDP 操作 Copilot 输入框。
4. VS Code Copilot 开始生成。
5. 后续输出继续按增量协议回传 Flutter。

## 10. 安全与可靠性

### 10.1 安全策略

- CDP 端口只监听本机，不暴露公网。
- WebSocket 使用 pairing token 或短期 token。
- 手机端指令必须白名单校验。
- 禁止手机端传入任意 JavaScript 给 CDP 执行。
- 附件和 artifact URI 只允许工作区或授权目录。

### 10.2 可靠性策略

- 服务端维护最近 N 条事件缓冲区。
- 所有服务端事件都必须带递增 `seq`。
- Flutter 用 `seq` 去重，用 `offset` 校验 chunk。
- CDP 断开后自动重连并重新注入脚本。
- target 刷新后重新生成快照，必要时通知 Flutter 重置状态。

## 11. 推荐落地顺序

1. 实现 WebSocket Gateway 和基础握手。
2. 实现 CDP target discovery。
3. 实现一次性 DOM snapshot。
4. 实现 Flutter 历史会话渲染。
5. 引入 MutationObserver。
6. 先使用 replace 保证正确性。
7. 增加 append chunk 增量优化。
8. 补齐 thinking、code_block、tool_call、artifact 识别。
9. 实现手机端反向控制。
10. 加入鉴权、续传、重连和性能优化。
