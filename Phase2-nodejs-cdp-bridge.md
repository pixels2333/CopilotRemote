# 第二阶段：Node.js CDP Bridge 核心抓取层方案

## 1. 阶段目标

本阶段实现 Copilot Mirror 的核心抓取层。Node.js CDP Bridge 负责连接 VS Code 暴露的 Chrome DevTools Protocol 端口，定位 GitHub Copilot Chat 页面，注入 DOM 观察逻辑，将页面变化转换为第一阶段定义的 WebSocket 协议事件，并支持手机端反向控制 VS Code Copilot。

本方案只描述实现思路、模块职责、关键流程和鲁棒性策略，不包含具体代码实现。

## 2. 核心能力

- 连接 `localhost:9229` 并遍历所有 CDP targets。
- 自动定位 GitHub Copilot Chat Webview 或承载 Copilot Chat 的 VS Code workbench target。
- 向目标页面注入高效 MutationObserver。
- 实时识别普通文本、thinking、代码块、工具调用和 artifact。
- 通过 CDP Binding 优先回传结构化事件，必要时降级到 console 日志回传。
- 将内部 DOM 事件转换成 WebSocket 协议事件。
- 支持 Flutter 客户端发送 prompt、停止生成、聚焦输入框等反向指令。
- 能处理 Copilot 页面刷新、会话重启、target 变化和 CDP 断开重连。

## 3. 模块设计

| 模块 | 职责 |
| --- | --- |
| Bridge Runtime | Bridge 进程入口，负责生命周期、配置、日志和优雅退出。 |
| CDP Connection Manager | 连接 CDP endpoint，维护当前 CDP client。 |
| Target Resolver | 遍历 targets，定位最可能的 Copilot Chat 页面。 |
| Page Injector | 向目标页面注入观察脚本，并在刷新后重新注入。 |
| DOM Observer Script | 在页面内观察 DOM 变化，抽取结构化消息。 |
| Event Normalizer | 将页面内事件归一化为 message、block、delta。 |
| Delta Engine | 比较上次内容和当前内容，生成 append 或 replace。 |
| Session Store | 保存当前 session 快照、事件序号、事件缓冲区。 |
| WebSocket Gateway | 接收 Flutter 连接，处理握手、续传和广播。 |
| Command Bridge | 将 Flutter 指令转为 CDP 页面操作。 |

## 4. Target 定位策略

Bridge 启动后访问 CDP target 列表，对每个 target 打分。优先选择分数最高的 `page` 或 `webview` target。

建议评分因素：

| 条件 | 权重建议 |
| --- | --- |
| URL 同时包含 `github` 和 `copilot` | 最高 |
| URL 包含 `copilot` | 高 |
| title 包含 `Copilot` | 高 |
| title 包含 `Chat` | 中 |
| URL 包含 `webview` 或 `vscode-webview` | 中 |
| title 包含 `Visual Studio Code` | 低，作为兜底 |

定位流程：

1. 获取 CDP target 列表。
2. 过滤 `page`、`webview` 等可调试 target。
3. 根据 URL 和 title 进行初步打分。
4. 对候选 target 进行轻量页面探测，例如检查是否存在 chat、copilot、message、textbox 等 DOM 特征。
5. 选择最高分 target 建立 CDP 会话。
6. 如果 target 消失或页面刷新，重新执行定位流程。

## 5. 脚本注入方案

### 5.1 注入目标

注入脚本应完成以下任务：

- 找到 Copilot Chat 的会话根节点。
- 抽取当前完整历史快照。
- 安装 MutationObserver 监听后续变化。
- 对 DOM 变化做节流和合并，避免过高频率回传。
- 将页面状态转换为结构化事件。
- 通过 Binding 或 console 通道回传给 Node.js。

### 5.2 观察范围

MutationObserver 建议监听：

| 变化类型 | 用途 |
| --- | --- |
| `childList` | 捕获新消息、新 block、新 artifact。 |
| `subtree` | 捕获深层内容变化。 |
| `characterData` | 捕获流式文本变化。 |
| `attributes` | 捕获状态、折叠、aria、class 变化。 |

需要重点关注的 DOM 区域：

- conversation root。
- message item。
- assistant response。
- user request。
- code block 容器。
- thinking / reasoning 区域。
- tool call 控件。
- artifact / preview 区域。
- Copilot 输入框。

### 5.3 性能策略

- DOM 变化不应立即逐条回传，应合并到下一帧或短时间窗口内处理。
- 每次处理只生成相对上次状态的差异。
- 文本块保存上次已发送长度，优先生成 append chunk。
- 如果发现当前文本不是上次文本的前缀，则生成 replace。
- 大代码块可以降低回传频率，避免高亮和布局压力传递到 Flutter。

## 6. DOM 到协议事件的归一化

### 6.1 消息识别

Bridge 需要为每个消息生成稳定 ID。可综合以下因素：

- DOM 顺序。
- role。
- 消息开头文本摘要。
- 节点特征属性。
- 当前会话 ID。

消息 role 的识别来源：

- class / data-testid / aria-label 中的 user、request、assistant、response、copilot 等关键词。
- 文本前缀兜底。
- DOM 所在区域兜底。

### 6.2 Block 识别

每条消息内部按内容类型拆分 block。

| DOM 特征 | 目标 block 类型 |
| --- | --- |
| 普通文本区域 | `text` |
| thinking / reasoning 相关节点 | `thinking` |
| `pre`、`code`、Monaco editor、codeblock 类名 | `code_block` |
| tool、tool-call、running tool 等特征 | `tool_call` |
| artifact、preview、attachment 等特征 | `artifact` |

### 6.3 事件映射

| 页面内事件 | WebSocket 事件 |
| --- | --- |
| 首次扫描完整对话 | `session.snapshot` |
| 发现新消息 | `message.start` |
| 发现新 block | `block.start` |
| 文本内容增长 | `block.delta` |
| 工具状态变化 | `block.update` |
| artifact 信息变化 | `block.update` |
| block 输出完成 | `block.end` |
| 消息输出完成 | `message.end` |

## 7. 数据回传通道

### 7.1 Runtime Binding

优先使用 CDP Runtime Binding。优点：

- 通道语义清晰。
- 便于区分业务事件和普通控制台日志。
- 更适合高频结构化数据回传。

建议页面脚本通过固定 binding 名称发送 JSON 字符串，Node.js 侧监听 binding 调用并解析。

### 7.2 Console Log 降级

如果 Binding 不可用，可以降级为 console 日志。建议使用固定前缀，例如 `[CopilotMirror]`，Node.js 只解析带此前缀的日志。

注意事项：

- console 通道可能混入页面自身日志。
- 高频 console 可能影响性能。
- 只作为兼容兜底，不作为首选通道。

## 8. WebSocket 转发设计

Node.js 收到页面事件后，需要统一经过以下处理：

1. JSON 解析和基本校验。
2. 转换为内部事件类型。
3. 更新 Session Store。
4. 生成带 `seq` 的协议 Envelope。
5. 写入事件缓冲区。
6. 广播给所有已连接 Flutter 客户端。

Flutter 新连接时：

1. 收到 `client.hello`。
2. 校验协议版本和认证信息。
3. 返回 `server.hello`。
4. 根据 `lastSeq` 决定补发事件或发送完整快照。

## 9. 反向控制方案

### 9.1 发送 Prompt

手机端发送 `client.command.sendMessage` 后，Bridge 应执行：

1. 确认 CDP client 已连接。
2. 在目标页面中定位 Copilot 输入框。
3. 聚焦输入框。
4. 设置文本内容。
5. 触发必要的 input / change 事件。
6. 根据 `submit` 参数模拟 Enter 或点击发送按钮。
7. 返回 `server.ack`。

输入框定位策略：

- 优先查找 textarea。
- 其次查找 `[contenteditable="true"]`。
- 再查找 `[role="textbox"]`。
- 结合 aria-label、placeholder 中的 copilot、chat、ask 等关键词。

### 9.2 停止生成

Bridge 根据按钮文本、aria-label 或 title 查找 Stop / Cancel 按钮，并触发点击。

### 9.3 聚焦输入框

只执行输入框定位和 focus，不发送内容。

### 9.4 打开 Artifact

根据 artifact ID 查询 Session Store 中的元信息，再决定：

- 在 VS Code 中打开文件。
- 通知 Flutter 展示预览。
- 返回错误说明 artifact 不可打开。

## 10. 鲁棒性设计

### 10.1 页面刷新

页面刷新后，原注入脚本会丢失。Bridge 应监听页面加载事件或 target 生命周期变化，并重新注入脚本。重新注入后应发送新快照，确保 Flutter 状态一致。

### 10.2 Target 变化

Copilot Webview 可能因重启、切换侧边栏、扩展刷新而生成新 target。Bridge 需要定期扫描 target，并在当前 target 失效时自动切换。

### 10.3 CDP 断开

CDP 断开后：

- 清理当前 client 状态。
- 广播 `server.status` 给 Flutter。
- 进入重连循环。
- 重连成功后重新定位 target 和注入脚本。

### 10.4 事件去重

Bridge 和 Flutter 都需要去重：

- Bridge 使用 messageId / blockId / content offset 避免重复生成 delta。
- Flutter 使用 seq 避免重连补发造成重复拼接。

### 10.5 降级策略

如果精细 DOM 识别失败，Bridge 可以降级为：

1. 发送完整文本块 replace。
2. 暂时不区分 thinking 和普通文本。
3. 等 selector 调整后再恢复精细结构化。

## 11. 安全边界

- 不允许手机端传入任意 JavaScript。
- 所有反向控制必须是白名单命令。
- Prompt 文本只能作为数据写入输入框，不能拼接成可执行脚本。
- WebSocket 建议使用 pairing token。
- CDP 端口只允许本机访问。

## 12. 推荐落地顺序

1. 建立 WebSocket 服务和基础握手。
2. 连接 CDP 并打印 target 列表。
3. 实现 target 自动定位。
4. 注入一次性快照脚本。
5. 将快照转换为 `session.snapshot`。
6. 引入 MutationObserver。
7. 实现 append / replace delta。
8. 增加 thinking、code_block、tool_call、artifact 识别。
9. 实现 sendMessage 反向控制。
10. 增加页面刷新、target 变化和 CDP 重连恢复。
11. 增加事件缓冲和断线续传。

## 13. 调试建议

- 先实现 target dump，确认 Copilot 所在 target 的 URL 和 title。
- 在注入脚本中先返回完整快照，不急于做增量。
- 使用桌面 WebSocket 调试工具观察协议事件。
- 对不稳定 selector 做可配置化，便于后续适配 Copilot UI 变化。
- 保留 Bridge 内部日志，但避免把用户消息明文长期落盘。
