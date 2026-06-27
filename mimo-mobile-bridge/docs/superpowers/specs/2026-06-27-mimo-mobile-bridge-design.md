# MiMo Mobile Bridge 设计文档

## 1. 概述

### 1.1 项目目标

创建一个手机端应用程序，通过局域网连接到电脑上运行的 MiMoCode，实现：
- 实时对话（流式响应）
- 会话管理
- 项目管理
- 任务状态监控
- 终端执行查看
- AI/Token 使用情况
- 权限确认

### 1.2 技术选型

| 组件 | 技术 | 说明 |
|------|------|------|
| 电脑端插件 | Node.js/TypeScript | MiMoCode 插件，启动 WebSocket 服务器 |
| 手机端 App | Flutter | 跨平台移动应用 |
| 通信协议 | WebSocket | 实时双向通信 |
| 数据格式 | JSON | 轻量级数据交换 |

---

## 2. 系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        手机端 (Flutter)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 对话界面 │  │ 会话管理 │  │ 项目管理 │  │ 状态监控 │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘    │
│       │              │              │              │          │
│       └──────────────┴──────────────┴──────────────┘          │
│                          │                                    │
│                    WebSocket Client                           │
└──────────────────────────┬──────────────────────────────────┘
                           │ 局域网
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    电脑端 (MiMoCode 插件)                     │
│                    WebSocket Server                           │
│                          │                                    │
│       ┌──────────────────┴──────────────────┐                │
│       │         MiMoCode SDK Client         │                │
│       │  (OpencodeClient from @mimo-ai/sdk) │                │
│       └──────────────────┬──────────────────┘                │
│                          │                                    │
│       ┌──────────────────┴──────────────────┐                │
│       │           MiMoCode Core             │                │
│       │  - Session 管理                      │                │
│       │  - AI Provider 调用                  │                │
│       │  - 工具执行                          │                │
│       │  - 文件操作                          │                │
│       └─────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 通信流程

```
手机 App                    插件 (WebSocket Server)              MiMoCode
   │                              │                                │
   │── 连接请求 ──────────────────>│                                │
   │<── 连接确认 ──────────────────│                                │
   │                              │                                │
   │── 发送消息 {type:"chat", ...}>│                                │
   │                              │── session.prompt() ───────────>│
   │                              │<── 流式响应 ───────────────────│
   │<── 流式推送 {type:"chunk",..}│                                │
   │<── 完成 {type:"done", ...}───│                                │
   │                              │                                │
   │── 查询会话列表 ──────────────>│                                │
   │                              │── session.list() ─────────────>│
   │                              │<── 会话列表 ───────────────────│
   │<── 返回会话列表 ─────────────│                                │
```

---

## 3. 功能规格

### 3.1 实时对话

**描述**: 用户在手机端输入消息，MiMoCode 处理后流式返回响应

**多窗口会话区分机制**:

MiMoCode 支持多个窗口同时进行对话，每个会话有独立的 `sessionID`。为防止数据紊乱，采用以下策略：

```
┌─────────────────────────────────────────────────────────────────┐
│                      手机端会话管理架构                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │  会话 A     │    │  会话 B     │    │  会话 C     │        │
│   │  (活跃)     │    │  (后台)     │    │  (后台)     │        │
│   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │
│          │                  │                  │                │
│          └──────────────────┼──────────────────┘                │
│                             │                                   │
│                    ┌────────▼────────┐                          │
│                    │  会话路由器     │                          │
│                    │  (SessionRouter)│                          │
│                    └────────┬────────┘                          │
│                             │                                   │
│          ┌──────────────────┼──────────────────┐                │
│          │                  │                  │                │
│   ┌──────▼──────┐    ┌─────▼──────┐    ┌──────▼──────┐        │
│   │  消息队列 A │    │  消息队列 B│    │  消息队列 C │        │
│   │  (FIFO)     │    │  (FIFO)    │    │  (FIFO)     │        │
│   └─────────────┘    └────────────┘    └─────────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**核心设计原则**:

1. **SessionID 绑定**: 每个 WebSocket 消息都必须携带 `sessionId` 字段
2. **消息路由**: 手机端根据 `sessionId` 将消息路由到对应的会话界面
3. **状态隔离**: 每个会话维护独立的状态（消息列表、加载状态、错误信息）
4. **后台监听**: 非活跃会话在后台继续接收事件，更新状态指示器

**WebSocket 消息格式**:

```typescript
// 客户端 -> 服务器
interface ChatMessage {
  type: "chat"
  sessionId: string   // 必须指定目标会话
  content: string
  agent?: string      // 可选，指定 agent 类型
  requestId?: string  // 可选，用于匹配响应
}

// 服务器 -> 客户端 (流式文本片段)
interface ChatChunk {
  type: "chunk"
  sessionId: string   // 用于路由到正确的会话界面
  requestId?: string  // 匹配请求
  partId: string      // 消息部分 ID
  content: string     // 流式文本片段
  field: string       // 更新的字段 (如 "text")
}

// 服务器 -> 客户端 (工具执行更新)
interface ToolUpdate {
  type: "tool.update"
  sessionId: string
  partId: string
  tool: string        // 工具名称
  status: "pending" | "running" | "completed" | "error"
  title?: string      // 工具执行标题
  input?: Record<string, any>
  output?: string
  error?: string
  time?: {
    start: number
    end?: number
  }
}

// 服务器 -> 客户端 (步骤完成)
interface StepFinish {
  type: "step.finish"
  sessionId: string
  partId: string
  reason: string
  tokens: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
  cost: number
}

// 服务器 -> 客户端 (会话完成)
interface ChatDone {
  type: "done"
  sessionId: string
  messageId: string
  tokens?: {
    input: number
    output: number
    total: number
  }
  cost?: number
}

// 服务器 -> 客户端 (错误)
interface ChatError {
  type: "error"
  sessionId: string
  requestId?: string
  code: string
  message: string
}
```

**事件订阅机制**:

```typescript
// 客户端 -> 服务器 (订阅事件)
interface EventSubscribe {
  type: "event.subscribe"
  sessionIds?: string[]  // 可选，指定订阅的会话，不传则订阅所有
}

// 服务器 -> 客户端 (事件推送)
interface EventMessage {
  type: "event"
  event: ServerEvent
}

type ServerEvent = 
  | { type: "message.updated", properties: { sessionID: string, info: Message } }
  | { type: "message.part.updated", properties: { sessionID: string, part: Part } }
  | { type: "message.part.delta", properties: { sessionID: string, messageID: string, partID: string, field: string, delta: string } }
  | { type: "session.updated", properties: { sessionID: string, info: Session } }
  | { type: "session.status", properties: { sessionID: string, status: SessionStatus } }
  | { type: "session.idle", properties: { sessionID: string } }
  | { type: "session.diff", properties: { sessionID: string, diff: FileDiff[] } }
  | { type: "session.error", properties: { sessionID?: string, error: MessageError } }
  | { type: "permission.updated", properties: { id: string, permission: Permission } }
  | { type: "permission.replied", properties: { id: string, reply: "once" | "always" | "reject" } }
  | { type: "provider.statusChanged", properties: { providerID: string, status: ProviderStatus, error?: Error } }
```

### 3.2 会话管理

**功能列表**:
- 获取会话列表
- 创建新会话
- 获取会话详情
- 获取会话消息历史
- 中止会话
- 删除会话

**WebSocket 消息格式**:

```typescript
// 获取会话列表
interface SessionListRequest {
  type: "session.list"
  limit?: number
  search?: string
}

interface SessionListResponse {
  type: "session.list"
  sessions: Session[]
}

interface Session {
  id: string
  title: string
  createdAt: number
  updatedAt: number
  status: "idle" | "processing" | "error"
  messageCount: number
}

// 创建会话
interface SessionCreateRequest {
  type: "session.create"
  title?: string
  workingDirectory?: string
}

// 获取消息历史
interface SessionMessagesRequest {
  type: "session.messages"
  sessionId: string
  limit?: number
  before?: string  // 分页游标
}

// 中止会话
interface SessionAbortRequest {
  type: "session.abort"
  sessionId: string
}
```

### 3.3 项目管理

**功能列表**:
- 获取当前项目信息
- 列出已打开的项目
- 切换工作目录

**WebSocket 消息格式**:

```typescript
// 获取当前项目
interface ProjectCurrentRequest {
  type: "project.current"
}

interface ProjectCurrentResponse {
  type: "project.current"
  project: {
    id: string
    name: string
    directory: string
    branch?: string
  }
}

// 列出项目
interface ProjectListRequest {
  type: "project.list"
}

// 切换工作目录
interface ProjectChangeDirRequest {
  type: "project.changeDir"
  directory: string
}
```

### 3.4 任务状态监控

**精细任务状态定义**:

基于 MiMoCode 的 Session Status 和 Actor 系统，定义以下精细状态：

```typescript
// 会话状态（对应 MiMoCode SessionStatus）
type SessionStatus = 
  | { type: "idle" }                                          // 空闲
  | { type: "busy", message?: string }                       // 忙碌
  | { type: "retry", attempt: number, message: string, next: number }  // 重试中

// 任务执行阶段
type TaskPhase = 
  | "initializing"    // 初始化中
  | "thinking"        // AI 思考中
  | "executing"       // 工具执行中
  | "waiting_input"   // 等待用户输入
  | "waiting_permission"  // 等待权限确认
  | "summarizing"     // 总结中
  | "completed"       // 完成
  | "error"           // 错误
  | "aborted"         // 已中止

// 工具执行状态
type ToolExecutionStatus = {
  tool: string            // 工具名称
  status: "pending" | "running" | "completed" | "error"
  title?: string          // 执行标题
  input?: Record<string, any>
  output?: string
  error?: string
  time?: {
    start: number
    end?: number
    elapsed?: number
  }
}

// 会话详细状态
interface SessionDetailedStatus {
  sessionId: string
  sessionTitle: string
  status: SessionStatus
  phase: TaskPhase
  currentTask?: string
  currentTool?: ToolExecutionStatus
  progress?: {
    current: number
    total: number
    percentage: number
    estimatedRemaining?: number  // 预估剩余时间 (ms)
  }
  metrics: {
    tokens: {
      input: number
      output: number
      reasoning: number
      cache: { read: number; write: number }
    }
    cost: number
    duration: number
    messageCount: number
    toolCallCount: number
  }
  history: Array<{
    timestamp: number
    event: string
    details?: Record<string, any>
  }>
  lastUpdate: number
}
```

**任务状态机**:

```
┌─────────────────────────────────────────────────────────────────┐
│                       任务状态机                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐              │
│   │  idle    │────>│initializing│───>│ thinking │              │
│   └──────────┘     └──────────┘     └──────────┘              │
│        ^                                   │                    │
│        │                                   v                    │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐              │
│   │completed │<────│summarizing│<────│executing │              │
│   └──────────┘     └──────────┘     └──────────┘              │
│        ^                                   │                    │
│        │                                   v                    │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐              │
│   │ aborted  │<────│  error   │<────│waiting_* │              │
│   └──────────┘     └──────────┘     └──────────┘              │
│                                                                 │
│   waiting_* = waiting_input | waiting_permission               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**WebSocket 消息格式**:

```typescript
// 状态订阅
interface StatusSubscribeRequest {
  type: "status.subscribe"
  sessionIds?: string[]  // 可选，指定订阅的会话
  includeMetrics?: boolean
  includeHistory?: boolean
}

// 状态更新推送
interface StatusUpdate {
  type: "status.update"
  sessions: {
    [sessionId: string]: SessionDetailedStatus
  }
  system: {
    cpuUsage?: number
    memoryUsage?: number
    uptime: number
    activeSessions: number
    totalSessions: number
  }
}

// 单个会话状态更新
interface SessionStatusUpdate {
  type: "session.status.update"
  sessionId: string
  status: SessionDetailedStatus
}

// 工具执行状态更新
interface ToolExecutionUpdate {
  type: "tool.execution.update"
  sessionId: string
  toolId: string
  execution: ToolExecutionStatus
}

// 进度更新
interface ProgressUpdate {
  type: "progress.update"
  sessionId: string
  progress: {
    current: number
    total: number
    percentage: number
    estimatedRemaining?: number
  }
}
```

**状态监控界面设计**:

```dart
// lib/screens/status_screen.dart
class StatusScreen extends StatefulWidget {
  @override
  _StatusScreenState createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  Map<String, SessionDetailedStatus> _sessions = {};
  SystemStatus? _systemStatus;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('状态监控')),
      body: ListView(
        children: [
          // 系统状态卡片
          if (_systemStatus != null)
            SystemStatusCard(status: _systemStatus!),
          
          // 活动会话列表
          ..._sessions.values
            .where((s) => s.status.type != 'idle')
            .map((s) => SessionStatusCard(
              status: s,
              onTap: () => _navigateToSession(s.sessionId),
              onAbort: () => _abortSession(s.sessionId),
            )),
          
          // 空闲会话列表
          if (_sessions.values.any((s) => s.status.type == 'idle'))
            ExpansionTile(
              title: Text('空闲会话'),
              children: _sessions.values
                .where((s) => s.status.type == 'idle')
                .map((s) => SessionStatusCard(
                  status: s,
                  compact: true,
                ))
                .toList(),
            ),
        ],
      ),
    );
  }
}

// lib/widgets/session_status_card.dart
class SessionStatusCard extends StatelessWidget {
  final SessionDetailedStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onAbort;
  final bool compact;
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  _buildStatusIcon(status.status),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.sessionTitle,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (onAbort != null)
                    IconButton(
                      icon: Icon(Icons.stop),
                      onPressed: onAbort,
                      color: Colors.red,
                    ),
                ],
              ),
              
              // 当前任务
              if (status.currentTask != null) ...[
                SizedBox(height: 8),
                Text(
                  status.currentTask!,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
              
              // 进度条
              if (status.progress != null) ...[
                SizedBox(height: 8),
                LinearProgressIndicator(
                  value: status.progress!.percentage / 100,
                ),
                SizedBox(height: 4),
                Text(
                  '${status.progress!.percentage.toStringAsFixed(1)}%'
                  '${status.progress!.estimatedRemaining != null 
                    ? ' · ${_formatDuration(status.progress!.estimatedRemaining!)}'
                    : ''}',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              
              // 工具执行状态
              if (status.currentTool != null) ...[
                SizedBox(height: 8),
                _buildToolStatus(status.currentTool!),
              ],
              
              // 指标
              if (!compact) ...[
                SizedBox(height: 8),
                _buildMetricsRow(status.metrics),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusIcon(SessionStatus status) {
    switch (status.type) {
      case 'idle':
        return Icon(Icons.check_circle, color: Colors.grey);
      case 'busy':
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'retry':
        return Icon(Icons.refresh, color: Colors.orange);
      default:
        return Icon(Icons.help, color: Colors.grey);
    }
  }
  
  Widget _buildToolStatus(ToolExecutionStatus tool) {
    return Row(
      children: [
        _buildToolStatusIcon(tool.status),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tool.title ?? tool.tool,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              if (tool.time?.elapsed != null)
                Text(
                  _formatDuration(tool.time!.elapsed!),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildMetricsRow(SessionMetrics metrics) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildMetric('Token', _formatNumber(metrics.tokens.input + metrics.tokens.output)),
        _buildMetric('费用', '\$${metrics.cost.toStringAsFixed(4)}'),
        _buildMetric('消息', metrics.messageCount.toString()),
        _buildMetric('工具', metrics.toolCallCount.toString()),
      ],
    );
  }
}
```

### 3.5 终端执行查看

**功能列表**:
- 列出活动的 PTY 会话
- 创建新的 PTY 会话
- 查看终端输出
- 向终端发送输入

**WebSocket 消息格式**:

```typescript
// 列出 PTY 会话
interface PtyListRequest {
  type: "pty.list"
}

interface PtyListResponse {
  type: "pty.list"
  sessions: PtySession[]
}

interface PtySession {
  id: string
  title: string
  command: string
  cwd: string
  status: "running" | "exited"
  pid?: number
}

// 创建 PTY 会话
interface PtyCreateRequest {
  type: "pty.create"
  command: string
  cwd?: string
  title?: string
}

// 终端输出流
interface PtyOutput {
  type: "pty.output"
  sessionId: string
  data: string  // 终端输出数据
}

// 终端输入
interface PtyInput {
  type: "pty.input"
  sessionId: string
  data: string  // 用户输入
}

// 终端退出
interface PtyExit {
  type: "pty.exit"
  sessionId: string
  exitCode: number
}
```

### 3.6 AI/Token 使用情况

**WebSocket 消息格式**:

```typescript
// 获取使用统计
interface UsageRequest {
  type: "usage.get"
  sessionId?: string  // 可选，不传则返回全局统计
}

interface UsageResponse {
  type: "usage.get"
  session?: {
    tokens: {
      input: number
      output: number
      reasoning: number
      cache: {
        read: number
        write: number
      }
    }
    cost: number
    messageCount: number
  }
  global?: {
    totalTokens: number
    totalCost: number
    sessionCount: number
  }
}
```

### 3.7 权限确认与弹窗设计

**权限分级策略**:

基于 MiMoCode 的 Permission 系统，采用三级权限策略：

| 级别 | 操作类型 | 处理方式 | 弹窗类型 |
|------|----------|----------|----------|
| **自动允许** | 读取文件、查看状态、列出目录、搜索代码 | 自动执行，无需弹窗 | 无 |
| **标准确认** | 写入文件、编辑文件、执行命令 | 手机端弹窗确认 | 标准确认弹窗 |
| **危险操作** | 删除文件、执行系统命令、修改配置 | 手机端弹窗确认 + 二次确认 | 危险操作弹窗 |

**权限分类规则**:

```typescript
// 权限分类器
function classifyPermission(action: string, resource: string): PermissionLevel {
  // 自动允许的操作
  const autoAllowActions = [
    'file.read',
    'file.list',
    'file.status',
    'session.list',
    'session.get',
    'session.messages',
    'session.status',
    'project.list',
    'project.current',
    'provider.list',
    'provider.get',
    'permission.list',
    'pty.list',
    'glob',
    'grep',
    'codesearch',
    'websearch',
  ]
  
  if (autoAllowActions.includes(action)) return 'auto'
  
  // 危险操作
  const dangerousActions = [
    'file.delete',
    'bash.system',  // 系统命令
    'config.modify',
    'permission.modify',
  ]
  
  if (dangerousActions.includes(action)) return 'dangerous'
  
  // 默认需要标准确认
  return 'standard'
}
```

**弹窗类型定义**:

```typescript
// 弹窗类型
type DialogType = 
  | 'standard_confirm'    // 标准确认弹窗
  | 'dangerous_confirm'   // 危险操作弹窗
  | 'tool_progress'       // 工具执行进度弹窗
  | 'task_status'         // 任务状态弹窗
  | 'error_alert'         // 错误警告弹窗
  | 'session_switch'      // 会话切换弹窗

// 弹窗基础接口
interface BaseDialog {
  id: string
  type: DialogType
  sessionId: string       // 关联的会话
  timestamp: number
  dismissible: boolean    // 是否可关闭
  autoClose?: number      // 自动关闭时间 (ms)
}

// 标准确认弹窗
interface StandardConfirmDialog extends BaseDialog {
  type: 'standard_confirm'
  title: string
  message: string
  icon?: string           // 图标类型
  details?: {
    action: string        // 操作类型
    resource: string      // 资源路径
    description: string   // 详细描述
    preview?: string      // 操作预览
  }
  actions: {
    primary: {
      label: string
      reply: 'once' | 'always'
    }
    secondary?: {
      label: string
      reply: 'reject'
    }
  }
}

// 危险操作弹窗
interface DangerousConfirmDialog extends BaseDialog {
  type: 'dangerous_confirm'
  title: string
  message: string
  icon: 'warning' | 'error'
  details: {
    action: string
    resource: string
    description: string
    risks: string[]       // 风险说明
    consequences: string[] // 可能的后果
  }
  actions: {
    primary: {
      label: string
      reply: 'once'
      confirmText?: string  // 二次确认输入文本
    }
    secondary: {
      label: string
      reply: 'reject'
    }
  }
}

// 工具执行进度弹窗
interface ToolProgressDialog extends BaseDialog {
  type: 'tool_progress'
  tool: string            // 工具名称
  title: string
  status: 'pending' | 'running' | 'completed' | 'error'
  progress?: number       // 0-100
  details?: {
    input?: Record<string, any>
    output?: string
    error?: string
    time?: {
      start: number
      end?: number
      elapsed?: number
    }
  }
  actions?: {
    abort?: boolean       // 是否显示中止按钮
    dismiss?: boolean     // 是否显示关闭按钮
  }
}

// 任务状态弹窗
interface TaskStatusDialog extends BaseDialog {
  type: 'task_status'
  sessionId: string
  sessionTitle: string
  status: 'idle' | 'working' | 'waiting' | 'completed' | 'error'
  currentTask?: string
  progress?: {
    current: number
    total: number
    percentage: number
  }
  metrics?: {
    tokens: {
      input: number
      output: number
      reasoning: number
      cache: { read: number; write: number }
    }
    cost: number
    duration: number
  }
  actions?: {
    viewDetails?: boolean
    switchSession?: boolean
    abort?: boolean
  }
}

// 错误警告弹窗
interface ErrorAlertDialog extends BaseDialog {
  type: 'error_alert'
  severity: 'warning' | 'error' | 'critical'
  title: string
  message: string
  code?: string
  details?: {
    error: string
    stack?: string
    context?: Record<string, any>
  }
  actions: {
    retry?: boolean
    dismiss?: boolean
    report?: boolean
  }
}

// 会话切换弹窗
interface SessionSwitchDialog extends BaseDialog {
  type: 'session_switch'
  sessions: Array<{
    id: string
    title: string
    status: 'idle' | 'working' | 'waiting' | 'error'
    lastActive: number
    unreadCount: number
  }>
  currentSessionId?: string
  actions: {
    switch: (sessionId: string) => void
    dismiss: () => void
  }
}
```

**WebSocket 消息格式**:

```typescript
// 权限请求推送
interface PermissionRequest {
  type: "permission.request"
  requestId: string
  sessionId: string
  permission: {
    id: string
    action: string
    resource: string
    description: string
    level: "auto" | "standard" | "dangerous"
    metadata?: {
      message?: string
      [key: string]: any
    }
  }
  // 弹窗配置
  dialog: {
    type: DialogType
    title: string
    message: string
    details?: Record<string, any>
    actions?: {
      primary?: { label: string; reply: string }
      secondary?: { label: string; reply: string }
    }
  }
}

// 权限响应
interface PermissionResponse {
  type: "permission.reply"
  requestId: string
  permissionId: string
  reply: "once" | "always" | "reject"
}

// 工具执行进度推送
interface ToolProgressUpdate {
  type: "tool.progress"
  sessionId: string
  toolId: string
  tool: string
  status: "pending" | "running" | "completed" | "error"
  title?: string
  input?: Record<string, any>
  output?: string
  error?: string
  time?: {
    start: number
    end?: number
  }
  // 进度弹窗配置
  dialog?: {
    show: boolean
    dismissible: boolean
    autoClose?: number
  }
}

// 任务状态更新推送
interface TaskStatusUpdate {
  type: "task.status"
  sessionId: string
  sessionTitle: string
  status: "idle" | "working" | "waiting" | "completed" | "error"
  currentTask?: string
  progress?: {
    current: number
    total: number
    percentage: number
  }
  metrics?: {
    tokens: {
      input: number
      output: number
      reasoning: number
      cache: { read: number; write: number }
    }
    cost: number
    duration: number
  }
  // 状态弹窗配置
  dialog?: {
    show: boolean
    type: 'notification' | 'banner' | 'modal'
    dismissible: boolean
  }
}
```

**弹窗管理器设计**:

```dart
// lib/services/dialog_manager.dart
class DialogManager {
  final Map<String, BaseDialog> _activeDialogs = {};
  final StreamController<BaseDialog> _dialogStream = StreamController.broadcast();
  
  Stream<BaseDialog> get dialogStream => _dialogStream.stream;
  
  // 显示权限确认弹窗
  Future<PermissionResponse> showPermissionDialog(PermissionRequest request) async {
    final dialog = _createDialogFromRequest(request);
    _activeDialogs[dialog.id] = dialog;
    _dialogStream.add(dialog);
    
    // 等待用户响应
    final response = await _waitForResponse(dialog.id);
    _activeDialogs.remove(dialog.id);
    return response;
  }
  
  // 显示工具进度弹窗
  void showToolProgress(ToolProgressUpdate update) {
    final dialog = ToolProgressDialog(
      id: '${update.sessionId}-${update.toolId}',
      sessionId: update.sessionId,
      tool: update.tool,
      title: update.title ?? update.tool,
      status: update.status,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: update.dialog?.dismissible ?? false,
      autoClose: update.dialog?.autoClose,
    );
    
    _activeDialogs[dialog.id] = dialog;
    _dialogStream.add(dialog);
  }
  
  // 显示任务状态弹窗
  void showTaskStatus(TaskStatusUpdate update) {
    final dialog = TaskStatusDialog(
      id: 'task-${update.sessionId}',
      sessionId: update.sessionId,
      sessionTitle: update.sessionTitle,
      status: update.status,
      currentTask: update.currentTask,
      progress: update.progress,
      metrics: update.metrics,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: update.dialog?.dismissible ?? true,
    );
    
    _activeDialogs[dialog.id] = dialog;
    _dialogStream.add(dialog);
  }
  
  // 关闭弹窗
  void dismissDialog(String dialogId) {
    _activeDialogs.remove(dialogId);
  }
  
  // 关闭会话相关弹窗
  void dismissSessionDialogs(String sessionId) {
    _activeDialogs.removeWhere((id, dialog) => 
      dialog.sessionId == sessionId
    );
  }
  
  // 获取活跃弹窗
  List<BaseDialog> getActiveDialogs() {
    return _activeDialogs.values.toList();
  }
  
  // 获取会话相关弹窗
  List<BaseDialog> getSessionDialogs(String sessionId) {
    return _activeDialogs.values
      .where((dialog) => dialog.sessionId == sessionId)
      .toList();
  }
}
```

**弹窗 UI 组件**:

```dart
// lib/widgets/permission_dialog.dart
class PermissionDialogWidget extends StatelessWidget {
  final StandardConfirmDialog dialog;
  final Function(String reply) onReply;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(_getIcon(dialog.icon)),
      title: Text(dialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dialog.message),
          if (dialog.details != null) ...[
            SizedBox(height: 16),
            _buildDetailsSection(dialog.details!),
          ],
        ],
      ),
      actions: [
        if (dialog.actions.secondary != null)
          TextButton(
            onPressed: () => onReply(dialog.actions.secondary!.reply),
            child: Text(dialog.actions.secondary!.label),
          ),
        ElevatedButton(
          onPressed: () => onReply(dialog.actions.primary.reply),
          child: Text(dialog.actions.primary.label),
        ),
      ],
    );
  }
}

// lib/widgets/dangerous_dialog.dart
class DangerousDialogWidget extends StatefulWidget {
  final DangerousConfirmDialog dialog;
  final Function(String reply) onReply;
  
  @override
  _DangerousDialogWidgetState createState() => _DangerousDialogWidgetState();
}

class _DangerousDialogWidgetState extends State<DangerousDialogWidget> {
  String _confirmText = '';
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.warning, color: Colors.red),
      title: Text(widget.dialog.title, style: TextStyle(color: Colors.red)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.dialog.message),
          SizedBox(height: 16),
          _buildRisksSection(widget.dialog.details.risks),
          SizedBox(height: 16),
          if (widget.dialog.actions.primary.confirmText != null) ...[
            Text('请输入 "${widget.dialog.actions.primary.confirmText}" 确认:'),
            TextField(
              onChanged: (value) => setState(() => _confirmText = value),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => widget.onReply('reject'),
          child: Text(widget.dialog.actions.secondary.label),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _canConfirm() 
            ? () => widget.onReply(widget.dialog.actions.primary.reply)
            : null,
          child: Text(widget.dialog.actions.primary.label),
        ),
      ],
    );
  }
  
  bool _canConfirm() {
    if (widget.dialog.actions.primary.confirmText == null) return true;
    return _confirmText == widget.dialog.actions.primary.confirmText;
  }
}
```

### 3.8 Provider 信息

**WebSocket 消息格式**:

```typescript
// 获取 Provider 列表
interface ProviderListRequest {
  type: "provider.list"
}

interface ProviderListResponse {
  type: "provider.list"
  providers: Provider[]
}

interface Provider {
  id: string
  name: string
  status: "connected" | "disconnected" | "error"
  models: string[]
  defaultModel?: string
}
```

---

## 4. 数据模型

### 4.1 消息协议

所有 WebSocket 消息都遵循以下格式：

```typescript
interface WebSocketMessage {
  type: string           // 消息类型
  id?: string           // 请求 ID，用于匹配响应
  timestamp?: number    // 时间戳
  payload?: unknown     // 消息负载
}
```

### 4.2 错误处理

```typescript
interface ErrorMessage {
  type: "error"
  id?: string           // 对应的请求 ID
  code: string          // 错误代码
  message: string       // 错误描述
  details?: unknown     // 错误详情
}
```

**错误代码**:
- `INVALID_REQUEST` - 无效请求
- `SESSION_NOT_FOUND` - 会话不存在
- `PERMISSION_DENIED` - 权限不足
- `TIMEOUT` - 请求超时
- `INTERNAL_ERROR` - 内部错误

---

## 5. 安全设计

### 5.1 连接安全

- 仅支持局域网连接（拒绝公网连接）
- 连接时需要配对码验证
- 支持连接超时自动断开

### 5.2 权限控制

- 分级权限策略（自动/确认）
- 可配置的权限规则
- 操作日志记录

### 5.3 数据安全

- 敏感信息不持久化存储
- WebSocket 连接支持加密（wss://）
- 会话数据本地存储

---

## 6. 用户界面设计

### 6.1 胶囊通知设计

**概述**: 胶囊通知是一种轻量级的悬浮通知，类似 iOS Dynamic Island，显示在屏幕顶部，以胶囊形状展示关键信息。

**胶囊通知类型**:

```typescript
// 胶囊通知类型
type CapsuleType = 
  | 'session_status'      // 会话状态
  | 'tool_execution'      // 工具执行
  | 'permission_request'  // 权限请求
  | 'task_complete'       // 任务完成
  | 'error_alert'         // 错误警告
  | 'progress'            // 进度更新

// 胶囊通知数据结构
interface CapsuleNotification {
  id: string
  type: CapsuleType
  sessionId: string
  priority: 'low' | 'normal' | 'high' | 'urgent'
  
  // 显示内容
  title: string
  subtitle?: string
  icon?: string           // 图标类型或 URL
  badge?: number          // 角标数字
  
  // 状态指示
  status?: 'idle' | 'working' | 'waiting' | 'completed' | 'error'
  progress?: number       // 0-100
  
  // 动作
  actions?: CapsuleAction[]
  quickActions?: QuickAction[]  // 快捷动作按钮
  onTap?: () => void      // 点击展开
  onLongPress?: () => void // 长按操作
  
  // 生命周期
  duration?: number       // 自动消失时间 (ms)，0 表示常驻
  timestamp: number
  dismissible: boolean
}

// 胶囊动作
interface CapsuleAction {
  id: string
  label: string
  icon?: string
  type: 'primary' | 'secondary' | 'destructive'
  handler: () => void
}

// 快捷动作按钮
interface QuickAction {
  id: string
  label: string
  icon?: string
  type: 'confirm' | 'deny' | 'once' | 'always' | 'reject' | 'view' | 'abort'
  reply?: 'once' | 'always' | 'reject'  // 权限回复类型
  handler: () => void
  primary?: boolean  // 是否为主要按钮（高亮显示）
}
```

**胶囊通知视觉设计**:

```
┌─────────────────────────────────────────────────────────────────┐
│                      胶囊通知视觉设计                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                                                         │  │
│   │   状态栏区域                                             │  │
│   │                                                         │  │
│   ├─────────────────────────────────────────────────────────┤  │
│   │                                                         │  │
│   │   ┌─────────────────────────────────────────────────┐   │  │
│   │   │  🔵 执行中...                    ●●●○○ 60%    │   │  │
│   │   │  正在编译项目                                    │   │  │
│   │   └─────────────────────────────────────────────────┘   │  │
│   │                        胶囊通知                          │  │
│   │                                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**胶囊状态变化**:

```
┌─────────────────────────────────────────────────────────────────┐
│                      胶囊状态变化流程                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 收起状态 (默认) - 带快捷动作按钮                           │
│   ┌─────────────────────────────────────────┐                  │
│   │ 🔵 执行中...                            │                  │
│   │ 正在编译项目                             │                  │
│   │ ┌──────┐ ┌──────────┐ ┌──────┐         │                  │
│   │ │仅此一次│ │始终允许 │ │ 拒绝 │         │                  │
│   │ └──────┘ └──────────┘ └──────┘         │                  │
│   └─────────────────────────────────────────┘                  │
│                                                                 │
│   2. 权限请求胶囊 - 快捷确认                                    │
│   ┌─────────────────────────────────────────┐                  │
│   │ ⚠️ 请求写入文件                         │                  │
│   │ src/config.ts                           │                  │
│   │ ┌──────┐ ┌──────────┐ ┌──────┐         │                  │
│   │ │✓ 确定│ │ 仅此一次 │ │ 拒绝 │         │                  │
│   │ └──────┘ └──────────┘ └──────┘         │                  │
│   └─────────────────────────────────────────┘                  │
│                                                                 │
│   3. 任务完成胶囊 - 快捷操作                                    │
│   ┌─────────────────────────────────────────┐                  │
│   │ ✅ 编译完成                              │                  │
│   │ 耗时: 2分30秒                            │                  │
│   │ ┌──────────┐ ┌──────┐                   │                  │
│   │ │查看详情  │ │知道了│                   │                  │
│   │ └──────────┘ └──────┘                   │                  │
│   └─────────────────────────────────────────┘                  │
│                                                                 │
│   4. 错误警告胶囊 - 快捷处理                                    │
│   ┌─────────────────────────────────────────┐                  │
│   │ ❌ 编译失败                              │                  │
│   │ Error: Module not found                 │                  │
│   │ ┌──────┐ ┌──────────┐ ┌──────┐         │                  │
│   │ │ 重试 │ │查看错误  │ │ 忽略 │         │                  │
│   │ └──────┘ └──────────┘ └──────┘         │                  │
│   └─────────────────────────────────────────┘                  │
│                                                                 │
│   5. 展开状态 (点击)                                            │
│   ┌────────────────────────────────────────┐                   │
│   │ 🔵 正在执行: 编译项目                  │                   │
│   │ 进度: 60% (3/5 步骤)                   │                   │
│   │ ┌──────┐ ┌──────┐ ┌──────┐            │                   │
│   │ │ 查看 │ │ 中止 │ │ 切换 │            │                   │
│   │ └──────┘ └──────┘ └──────┘            │                   │
│   └────────────────────────────────────────┘                   │
│                                                                 │
│   6. 长按状态 (长按)                                            │
│   ┌────────────────────────────────────────┐                   │
│   │ 快速操作                               │                   │
│   │ ┌────────────────────────────────────┐ │                   │
│   │ │ 切换到此会话                       │ │                   │
│   │ ├────────────────────────────────────┤ │                   │
│   │ │ 静音此会话                         │ │                   │
│   │ ├────────────────────────────────────┤ │                   │
│   │ │ 清除此通知                         │ │                   │
│   │ └────────────────────────────────────┘ │                   │
│   └────────────────────────────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**胶囊通知配置**:

```dart
// lib/widgets/capsule_notification.dart
class CapsuleNotification extends StatefulWidget {
  final CapsuleNotificationData data;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final Function(CapsuleAction)? onAction;
  
  @override
  _CapsuleNotificationState createState() => _CapsuleNotificationState();
}

class _CapsuleNotificationState extends State<CapsuleNotification> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    
    // 自动收起
    if (widget.data.duration != null && widget.data.duration! > 0) {
      Future.delayed(Duration(milliseconds: widget.data.duration!), () {
        if (mounted) {
          _controller.reverse();
          widget.onDismiss?.call();
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _getBackgroundColor(),
            borderRadius: BorderRadius.circular(_isExpanded ? 16 : 28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_isExpanded ? 16 : 28),
            child: GestureDetector(
              onTap: _handleTap,
              onLongPress: _handleLongPress,
              onVerticalDragUpdate: _handleDrag,
              child: _isExpanded ? _buildExpanded() : _buildCollapsed(),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCollapsed() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主要内容行
          Row(
            children: [
              // 状态图标
              _buildStatusIcon(),
              SizedBox(width: 12),
              
              // 标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.data.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.data.subtitle != null)
                      Text(
                        widget.data.subtitle!,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              
              // 进度指示器
              if (widget.data.progress != null) ...[
                SizedBox(width: 12),
                _buildProgressIndicator(),
              ],
              
              // 角标
              if (widget.data.badge != null && widget.data.badge! > 0) ...[
                SizedBox(width: 8),
                _buildBadge(),
              ],
            ],
          ),
          
          // 快捷动作按钮（收起状态也显示）
          if (widget.data.quickActions != null && widget.data.quickActions!.isNotEmpty) ...[
            SizedBox(height: 8),
            _buildQuickActions(widget.data.quickActions!),
          ],
        ],
      ),
    );
  }
  
  Widget _buildExpanded() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              _buildStatusIcon(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.data.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (widget.data.subtitle != null)
                      Text(
                        widget.data.subtitle!,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // 关闭按钮
              if (widget.data.dismissible)
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: widget.onDismiss,
                ),
            ],
          ),
          
          // 进度条
          if (widget.data.progress != null) ...[
            SizedBox(height: 12),
            LinearProgressIndicator(
              value: widget.data.progress! / 100,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 4),
            Text(
              '${widget.data.progress!.toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          
          // 快捷动作按钮（收起状态也显示）
          if (widget.data.quickActions != null && widget.data.quickActions!.isNotEmpty) ...[
            SizedBox(height: 12),
            _buildQuickActions(widget.data.quickActions!),
          ],
          
          // 标准动作按钮
          if (widget.data.actions != null && widget.data.actions!.isNotEmpty) ...[
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: widget.data.actions!.map((action) {
                return Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: _buildActionButton(action),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
  
  // 构建快捷动作按钮
  Widget _buildQuickActions(List<QuickAction> actions) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: actions.map((action) {
        return _buildQuickActionButton(action);
      }).toList(),
    );
  }
  
  // 构建单个快捷动作按钮
  Widget _buildQuickActionButton(QuickAction action) {
    final isPrimary = action.primary ?? false;
    
    return ElevatedButton.icon(
      onPressed: () => action.handler(),
      icon: _getQuickActionIcon(action),
      label: Text(action.label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _getQuickActionColor(action.type, isPrimary),
        foregroundColor: isPrimary ? Colors.white : Colors.white70,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isPrimary 
            ? BorderSide.none 
            : BorderSide(color: Colors.white30, width: 1),
        ),
        elevation: isPrimary ? 2 : 0,
      ),
    );
  }
  
  // 获取快捷动作图标
  Widget _getQuickActionIcon(QuickAction action) {
    IconData iconData;
    
    switch (action.type) {
      case 'confirm':
        iconData = Icons.check;
        break;
      case 'deny':
      case 'reject':
        iconData = Icons.close;
        break;
      case 'once':
        iconData = Icons.looks_one;
        break;
      case 'always':
        iconData = Icons.check_circle;
        break;
      case 'view':
        iconData = Icons.visibility;
        break;
      case 'abort':
        iconData = Icons.stop;
        break;
      default:
        iconData = Icons.touch_app;
    }
    
    return Icon(iconData, size: 16);
  }
  
  // 获取快捷动作颜色
  Color _getQuickActionColor(String type, bool isPrimary) {
    if (isPrimary) {
      switch (type) {
        case 'confirm':
        case 'once':
        case 'always':
          return Colors.green.shade600;
        case 'deny':
        case 'reject':
        case 'abort':
          return Colors.red.shade600;
        case 'view':
          return Colors.blue.shade600;
        default:
          return Colors.grey.shade600;
      }
    }
    
    return Colors.white.withOpacity(0.1);
  }
  
  Widget _buildStatusIcon() {
    IconData iconData;
    Color color;
    
    switch (widget.data.status) {
      case 'working':
        iconData = Icons.sync;
        color = Colors.blue;
        break;
      case 'waiting':
        iconData = Icons.hourglass_empty;
        color = Colors.orange;
        break;
      case 'completed':
        iconData = Icons.check_circle;
        color = Colors.green;
        break;
      case 'error':
        iconData = Icons.error;
        color = Colors.red;
        break;
      default:
        iconData = Icons.info;
        color = Colors.grey;
    }
    
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: Icon(iconData, color: color, size: 24, key: ValueKey(widget.data.status)),
    );
  }
  
  Widget _buildProgressIndicator() {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: widget.data.progress! / 100,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
          Text(
            '${widget.data.progress!.toStringAsFixed(0)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        widget.data.badge! > 99 ? '99+' : widget.data.badge.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  Widget _buildActionButton(CapsuleAction action) {
    return ElevatedButton(
      onPressed: () => action.handler(),
      style: ElevatedButton.styleFrom(
        backgroundColor: _getActionButtonColor(action.type),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.icon != null) ...[
            Icon(_getActionIcon(action.icon), size: 16),
            SizedBox(width: 4),
          ],
          Text(action.label),
        ],
      ),
    );
  }
  
  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onTap?.call();
  }
  
  void _handleLongPress() {
    _showContextMenu();
  }
  
  void _handleDrag(DragUpdateDetails details) {
    if (details.primaryDelta! < -10) {
      // 向左滑动关闭
      widget.onDismiss?.call();
    }
  }
  
  void _showContextMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.open_in_new),
              title: Text('切换到此会话'),
              onTap: () {
                Navigator.pop(context);
                // 切换会话逻辑
              },
            ),
            ListTile(
              leading: Icon(Icons.notifications_off),
              title: Text('静音此会话'),
              onTap: () {
                Navigator.pop(context);
                // 静音逻辑
              },
            ),
            ListTile(
              leading: Icon(Icons.clear),
              title: Text('清除此通知'),
              onTap: () {
                Navigator.pop(context);
                widget.onDismiss?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

**胶囊通知管理器**:

```dart
// lib/services/capsule_manager.dart
class CapsuleManager {
  final Map<String, CapsuleNotificationData> _notifications = {};
  final StreamController<List<CapsuleNotificationData>> _streamController = 
      StreamController.broadcast();
  
  Stream<List<CapsuleNotificationData>> get notificationsStream => 
      _streamController.stream;
  
  List<CapsuleNotificationData> get activeNotifications => 
      _notifications.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  
  // 显示胶囊通知
  void show(CapsuleNotificationData notification) {
    _notifications[notification.id] = notification;
    _notifyListeners();
    
    // 自动消失
    if (notification.duration != null && notification.duration! > 0) {
      Future.delayed(Duration(milliseconds: notification.duration!), () {
        dismiss(notification.id);
      });
    }
  }
  
  // 更新胶囊通知
  void update(String id, CapsuleNotificationData Function(CapsuleNotificationData) updater) {
    if (_notifications.containsKey(id)) {
      _notifications[id] = updater(_notifications[id]!);
      _notifyListeners();
    }
  }
  
  // 关闭胶囊通知
  void dismiss(String id) {
    _notifications.remove(id);
    _notifyListeners();
  }
  
  // 关闭会话相关通知
  void dismissSession(String sessionId) {
    _notifications.removeWhere((id, notification) => 
      notification.sessionId == sessionId
    );
    _notifyListeners();
  }
  
  // 清除所有通知
  void clearAll() {
    _notifications.clear();
    _notifyListeners();
  }
  
  void _notifyListeners() {
    _streamController.add(activeNotifications);
  }
  
  void dispose() {
    _streamController.close();
  }
}

// 胶囊通知快捷方法
extension CapsuleManagerExtensions on CapsuleManager {
  // 显示会话状态胶囊
  void showSessionStatus({
    required String sessionId,
    required String title,
    String? subtitle,
    required String status,
    int? progress,
  }) {
    show(CapsuleNotificationData(
      id: 'session-$sessionId',
      type: 'session_status',
      sessionId: sessionId,
      priority: 'normal',
      title: title,
      subtitle: subtitle,
      status: status,
      progress: progress,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: true,
      duration: status == 'completed' ? 3000 : null,
    ));
  }
  
  // 显示工具执行胶囊
  void showToolExecution({
    required String sessionId,
    required String toolName,
    required String status,
    String? title,
    int? progress,
  }) {
    show(CapsuleNotificationData(
      id: 'tool-$sessionId-$toolName',
      type: 'tool_execution',
      sessionId: sessionId,
      priority: 'normal',
      title: title ?? '执行 $toolName',
      status: status,
      progress: progress,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: status == 'completed' || status == 'error',
      duration: status == 'completed' ? 2000 : null,
    ));
  }
  
  // 显示权限请求胶囊（带快捷动作）
  void showPermissionRequest({
    required String sessionId,
    required String permissionId,
    required String title,
    required String description,
    String? action,
    String? resource,
  }) {
    show(CapsuleNotificationData(
      id: 'permission-$permissionId',
      type: 'permission_request',
      sessionId: sessionId,
      priority: 'high',
      title: title,
      subtitle: description,
      status: 'waiting',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: false,
      // 快捷动作按钮
      quickActions: [
        QuickAction(
          id: 'once',
          label: '仅此一次',
          icon: 'looks_one',
          type: 'once',
          reply: 'once',
          primary: true,  // 主要按钮，高亮显示
          handler: () {
            // 回复权限：仅此一次
            _replyPermission(permissionId, 'once');
            dismiss('permission-$permissionId');
          },
        ),
        QuickAction(
          id: 'always',
          label: '始终允许',
          icon: 'check_circle',
          type: 'always',
          reply: 'always',
          handler: () {
            // 回复权限：始终允许
            _replyPermission(permissionId, 'always');
            dismiss('permission-$permissionId');
          },
        ),
        QuickAction(
          id: 'reject',
          label: '拒绝',
          icon: 'close',
          type: 'reject',
          reply: 'reject',
          handler: () {
            // 回复权限：拒绝
            _replyPermission(permissionId, 'reject');
            dismiss('permission-$permissionId');
          },
        ),
      ],
      // 标准动作按钮（展开后显示）
      actions: [
        CapsuleAction(
          id: 'details',
          label: '查看详情',
          type: 'secondary',
          handler: () {
            // 显示权限详情
          },
        ),
      ],
    ));
  }
  
  // 显示任务完成胶囊（带快捷动作）
  void showTaskComplete({
    required String sessionId,
    required String title,
    String? subtitle,
    int? duration,
    Map<String, dynamic>? metrics,
  }) {
    show(CapsuleNotificationData(
      id: 'complete-$sessionId',
      type: 'task_complete',
      sessionId: sessionId,
      priority: 'normal',
      title: title,
      subtitle: subtitle,
      status: 'completed',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: true,
      duration: 8000,
      // 快捷动作按钮
      quickActions: [
        QuickAction(
          id: 'view',
          label: '查看详情',
          icon: 'visibility',
          type: 'view',
          primary: true,
          handler: () {
            // 切换到会话查看详情
          },
        ),
        QuickAction(
          id: 'dismiss',
          label: '知道了',
          icon: 'check',
          type: 'confirm',
          handler: () {
            dismiss('complete-$sessionId');
          },
        ),
      ],
    ));
  }
  
  // 显示错误警告胶囊（带快捷动作）
  void showErrorAlert({
    required String sessionId,
    required String title,
    required String error,
    String? code,
    StackTrace? stackTrace,
  }) {
    show(CapsuleNotificationData(
      id: 'error-$sessionId-${DateTime.now().millisecondsSinceEpoch}',
      type: 'error_alert',
      sessionId: sessionId,
      priority: 'urgent',
      title: title,
      subtitle: error,
      status: 'error',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      dismissible: true,
      duration: 15000,
      // 快捷动作按钮
      quickActions: [
        QuickAction(
          id: 'retry',
          label: '重试',
          icon: 'refresh',
          type: 'confirm',
          primary: true,
          handler: () {
            // 重试操作
            dismiss('error-$sessionId-${DateTime.now().millisecondsSinceEpoch}');
          },
        ),
        QuickAction(
          id: 'view_error',
          label: '查看错误',
          icon: 'bug_report',
          type: 'view',
          handler: () {
            // 显示错误详情
          },
        ),
        QuickAction(
          id: 'dismiss',
          label: '忽略',
          icon: 'close',
          type: 'deny',
          handler: () {
            dismiss('error-$sessionId-${DateTime.now().millisecondsSinceEpoch}');
          },
        ),
      ],
    ));
  }
  
  // 辅助方法：回复权限请求
  void _replyPermission(String permissionId, String reply) {
    // 通过 WebSocket 发送权限回复
    _webSocketService?.sendMessage({
      'type': 'permission.reply',
      'permissionId': permissionId,
      'reply': reply,
    });
  }
  
  // 辅助方法：中止会话
  void _abortSession(String sessionId) {
    // 通过 WebSocket 发送中止请求
    _webSocketService?.sendMessage({
      'type': 'session.abort',
      'sessionId': sessionId,
    });
  }
}
```

**胶囊通知配置**:

```dart
// lib/config/capsule_config.dart
class CapsuleConfig {
  // 显示位置
  static const Alignment alignment = Alignment.topCenter;
  
  // 边距
  static const EdgeInsets margin = EdgeInsets.only(top: 8, left: 16, right: 16);
  
  // 动画时长
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // 最大显示数量
  static const int maxVisible = 3;
  
  // 自动消失时间
  static const Map<String, int> autoDismis = {
    'session_status': 0,      // 常驻
    'tool_execution': 0,      // 常驻
    'permission_request': 0,  // 常驻
    'task_complete': 5000,    // 5秒
    'error_alert': 10000,     // 10秒
    'progress': 0,            // 常驻
  };
  
  // 优先级排序
  static const Map<String, int> priorityOrder = {
    'urgent': 0,
    'high': 1,
    'normal': 2,
    'low': 3,
  };
}
```

**胶囊通知集成示例**:

```dart
// lib/app.dart
class MiMoApp extends StatefulWidget {
  @override
  _MiMoAppState createState() => _MiMoAppState();
}

class _MiMoAppState extends State<MiMoApp> {
  final CapsuleManager _capsuleManager = CapsuleManager();
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Stack(
        children: [
          // 主界面
          MainScreen(),
          
          // 胶囊通知层
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: StreamBuilder<List<CapsuleNotificationData>>(
              stream: _capsuleManager.notificationsStream,
              builder: (context, snapshot) {
                final notifications = snapshot.data ?? [];
                return Column(
                  children: notifications.take(CapsuleConfig.maxVisible).map((notification) {
                    return CapsuleNotification(
                      data: notification,
                      onTap: () => _handleCapsuleTap(notification),
                      onDismiss: () => _capsuleManager.dismiss(notification.id),
                      onAction: (action) => _handleCapsuleAction(notification, action),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleCapsuleTap(CapsuleNotificationData notification) {
    // 切换到对应会话
    if (notification.sessionId != null) {
      // 导航到会话详情
    }
  }
  
  void _handleCapsuleAction(CapsuleNotificationData notification, CapsuleAction action) {
    // 处理胶囊动作
    switch (action.id) {
      case 'allow':
        // 允许权限
        break;
      case 'deny':
        // 拒绝权限
        break;
      case 'view':
        // 查看详情
        break;
    }
  }
}
```

### 6.2 手机 App 主要界面

```
┌─────────────────────────────────┐
│           MiMo Mobile           │
├─────────────────────────────────┤
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌────┐│
│  │ 对话 │ │ 会话 │ │ 项目 │ │更多││
│  └─────┘ └─────┘ └─────┘ └────┘│
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────┐    │
│  │                         │    │
│  │      对话内容区域        │    │
│  │                         │    │
│  │                         │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ 输入消息...        [发送]│    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

### 6.2 会话列表界面

```
┌─────────────────────────────────┐
│           会话列表               │
├─────────────────────────────────┤
│  [+] 新建会话                   │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │ 📝 修复登录页面 bug      │    │
│  │    3 分钟前 · 12 条消息   │    │
│  │    状态: 空闲             │    │
│  └─────────────────────────┘    │
│  ┌─────────────────────────┐    │
│  │ 📝 添加用户管理功能      │    │
│  │    1 小时前 · 45 条消息   │    │
│  │    状态: 执行中...        │    │
│  └─────────────────────────┘    │
│  ┌─────────────────────────┐    │
│  │ 📝 重构数据库层          │    │
│  │    昨天 · 89 条消息       │    │
│  │    状态: 已完成           │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

### 6.3 状态监控界面

```
┌─────────────────────────────────┐
│           状态监控               │
├─────────────────────────────────┤
│  系统状态                       │
│  ┌─────────────────────────┐    │
│  │ CPU: 45%  内存: 2.1GB   │    │
│  │ 运行时间: 2h 30m         │    │
│  └─────────────────────────┘    │
│                                 │
│  活动会话                       │
│  ┌─────────────────────────┐    │
│  │ 🟢 会话 #1 - 执行中     │    │
│  │    当前任务: 编译项目     │    │
│  │    已用 Token: 1,234     │    │
│  │    费用: $0.05           │    │
│  └─────────────────────────┘    │
│                                 │
│  待处理权限                     │
│  ┌─────────────────────────┐    │
│  │ ⚠️ 请求写入文件          │    │
│  │    src/config.ts         │    │
│  │    [允许] [拒绝]         │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

---

## 7. 插件接口设计

### 7.1 插件入口

**实际 MiMoCode 插件接口**:

```typescript
// mimo-mobile-bridge/src/index.ts
import type { Plugin, PluginInput, Hooks } from "@mimo-ai/plugin"

export default function createPlugin(input: PluginInput): Promise<Hooks> {
  // 实际 PluginInput 包含：
  // - client: ReturnType<typeof createOpencodeClient>  // SDK 客户端
  // - project: Project                                  // 项目信息
  // - directory: string                                 // 工作目录
  // - worktree: string                                  // Git 工作树
  // - serverUrl: URL                                    // MiMoCode 服务器 URL
  // - $: BunShell                                       // Shell 执行器
  // - experimental_workspace: { register(...) }         // 工作区注册
  
  const { client, project, directory, serverUrl } = input
  
  // 启动 WebSocket 服务器
  const server = new WebSocketServer({
    port: 8765,
    host: '0.0.0.0'  // 监听所有网络接口
  })
  
  // 订阅 MiMoCode 事件流（SSE）
  subscribeToEvents(client, server)
  
  // 处理 WebSocket 连接
  server.on('connection', (ws) => {
    handleConnection(ws, client)
  })
  
  // 返回插件钩子
  return {
    // 系统事件监听
    event: async ({ event }) => {
      // 转发事件给所有连接的客户端
      broadcastToClients(server, { type: 'event', data: event })
    },
    
    // 会话开始前
    "session.pre": async (input, output) => {
      broadcastToClients(server, {
        type: 'session.start',
        sessionId: input.sessionID,
        agentId: input.agentID,
        taskId: input.task_id,
      })
    },
    
    // 会话结束后
    "session.post": async (input, output) => {
      broadcastToClients(server, {
        type: 'session.complete',
        sessionId: input.sessionID,
        agentId: input.agentID,
        outcome: input.outcome,
        error: input.error,
        finalText: input.finalText,
      })
    },
    
    // 每个 LLM 步骤前
    "session.userQuery.pre": async (input, output) => {
      broadcastToClients(server, {
        type: 'step.start',
        sessionId: input.sessionID,
        agentId: input.agentID,
        step: input.step,
        messageId: input.messageID,
        query: input.query,
      })
    },
    
    // 每个 LLM 步骤后
    "session.userQuery.post": async (input, output) => {
      broadcastToClients(server, {
        type: 'step.finish',
        sessionId: input.sessionID,
        agentId: input.agentID,
        step: input.step,
        messageId: input.messageID,
        assistantMessageId: input.assistantMessageID,
        finish: input.finish,
        error: input.error,
        finalText: input.finalText,
      })
    },
    
    // 权限请求拦截
    "permission.ask": async (input, output) => {
      // 将权限请求转发给手机端
      const requestId = input.id
      const response = await waitForPermissionResponse(server, requestId, input)
      
      // 根据手机端响应设置状态
      if (response === 'reject') {
        output.status = 'deny'
      } else if (response === 'always') {
        output.status = 'allow'
      } else {
        output.status = 'ask'  // 默认询问用户
      }
    },
    
    // 工具执行前拦截
    "tool.execute.before": async (input, output) => {
      broadcastToClients(server, {
        type: 'tool.start',
        sessionId: input.sessionID,
        tool: input.tool,
        callId: input.callID,
      })
    },
    
    // 工具执行后拦截
    "tool.execute.after": async (input, output) => {
      broadcastToClients(server, {
        type: 'tool.finish',
        sessionId: input.sessionID,
        tool: input.tool,
        callId: input.callID,
        title: output.title,
        output: output.output,
        metadata: output.metadata,
      })
    },
    
    // Actor 停止前
    "actor.preStop": async (input, output) => {
      broadcastToClients(server, {
        type: 'actor.preStop',
        sessionId: input.sessionID,
        actorId: input.actorID,
        agentType: input.agentType,
        mode: input.mode,
        task: input.task,
      })
    },
    
    // Actor 停止后
    "actor.postStop": async (input, output) => {
      broadcastToClients(server, {
        type: 'actor.postStop',
        sessionId: input.sessionID,
        actorId: input.actorID,
        agentType: input.agentType,
        outcome: input.outcome,
        error: input.error,
        finalText: input.finalText,
      })
    },
  }
}

// 订阅 MiMoCode 事件流
async function subscribeToEvents(client: ReturnType<typeof createOpencodeClient>, server: WebSocketServer) {
  try {
    const events = await client.event.subscribe()
    
    for await (const event of events) {
      // 转发所有事件给客户端
      broadcastToClients(server, {
        type: 'mimo.event',
        event: event,
      })
    }
  } catch (error) {
    console.error('Failed to subscribe to events:', error)
  }
}
```

### 7.2 WebSocket 消息处理器

**实际 MiMoCode SDK 调用方式**:

```typescript
// mimo-mobile-bridge/src/handler.ts
import type { createOpencodeClient } from "@mimo-ai/sdk"

type Client = ReturnType<typeof createOpencodeClient>

export function handleConnection(ws: WebSocket, client: Client) {
  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString())
      
      switch (message.type) {
        // 会话相关
        case 'session.list':
          await handleSessionList(ws, client, message)
          break
        case 'session.create':
          await handleSessionCreate(ws, client, message)
          break
        case 'session.get':
          await handleSessionGet(ws, client, message)
          break
        case 'session.delete':
          await handleSessionDelete(ws, client, message)
          break
        case 'session.abort':
          await handleSessionAbort(ws, client, message)
          break
        case 'session.status':
          await handleSessionStatus(ws, client, message)
          break
        case 'session.messages':
          await handleSessionMessages(ws, client, message)
          break
        case 'session.prompt':
          await handleSessionPrompt(ws, client, message)
          break
        case 'session.promptAsync':
          await handleSessionPromptAsync(ws, client, message)
          break
        case 'session.summarize':
          await handleSessionSummarize(ws, client, message)
          break
        case 'session.share':
          await handleSessionShare(ws, client, message)
          break
        case 'session.fork':
          await handleSessionFork(ws, client, message)
          break
        case 'session.task':
          await handleSessionTask(ws, client, message)
          break
        case 'session.actors':
          await handleSessionActors(ws, client, message)
          break
        case 'session.diff':
          await handleSessionDiff(ws, client, message)
          break
        
        // 权限相关
        case 'permission.reply':
          await handlePermissionReply(ws, client, message)
          break
        
        // PTY 相关
        case 'pty.list':
          await handlePtyList(ws, client, message)
          break
        case 'pty.create':
          await handlePtyCreate(ws, client, message)
          break
        case 'pty.connect':
          await handlePtyConnect(ws, client, message)
          break
        
        // 项目相关
        case 'project.current':
          await handleProjectCurrent(ws, client, message)
          break
        case 'project.list':
          await handleProjectList(ws, client, message)
          break
        
        // Provider 相关
        case 'provider.list':
          await handleProviderList(ws, client, message)
          break
        
        // 事件订阅
        case 'event.subscribe':
          await handleEventSubscribe(ws, client, message)
          break
        
        default:
          ws.send(JSON.stringify({
            type: 'error',
            code: 'INVALID_REQUEST',
            message: `Unknown message type: ${message.type}`,
          }))
      }
    } catch (error) {
      ws.send(JSON.stringify({
        type: 'error',
        code: 'INTERNAL_ERROR',
        message: error.message,
      }))
    }
  })
}

// 会话列表
async function handleSessionList(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.list({
    limit: message.limit,
    search: message.search,
    archived: message.archived,
  })
  
  ws.send(JSON.stringify({
    type: 'session.list',
    id: message.id,
    sessions: response.data,
  }))
}

// 创建会话
async function handleSessionCreate(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.create({
    title: message.title,
    directory: message.directory,
  })
  
  ws.send(JSON.stringify({
    type: 'session.created',
    id: message.id,
    session: response.data,
  }))
}

// 获取会话详情
async function handleSessionGet(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.get({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.get',
    id: message.id,
    session: response.data,
  }))
}

// 删除会话
async function handleSessionDelete(ws: WebSocket, client: Client, message: any) {
  await client.session.delete({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.deleted',
    id: message.id,
    sessionId: message.sessionId,
  }))
}

// 中止会话
async function handleSessionAbort(ws: WebSocket, client: Client, message: any) {
  await client.session.abort({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.aborted',
    id: message.id,
    sessionId: message.sessionId,
  }))
}

// 获取会话状态
async function handleSessionStatus(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.status({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.status',
    id: message.id,
    sessionId: message.sessionId,
    status: response.data,
  }))
}

// 获取会话消息
async function handleSessionMessages(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.messages({
    id: message.sessionId,
    limit: message.limit,
    cursor: message.cursor,
  })
  
  ws.send(JSON.stringify({
    type: 'session.messages',
    id: message.id,
    sessionId: message.sessionId,
    messages: response.data,
  }))
}

// 发送消息（流式响应）
async function handleSessionPrompt(ws: WebSocket, client: Client, message: any) {
  const { sessionId, parts, agent, model } = message
  
  // 构建请求参数
  const params: any = {
    id: sessionId,
    parts: parts || [{ type: 'text', text: message.content }],
  }
  
  if (agent) params.agent = agent
  if (model) params.model = model
  
  try {
    // 调用 SDK 的 prompt 方法（流式响应）
    const response = await client.session.prompt(params)
    
    // 流式推送响应
    for await (const event of response) {
      ws.send(JSON.stringify({
        type: 'prompt.event',
        id: message.id,
        sessionId,
        event: event,
      }))
    }
    
    // 发送完成消息
    ws.send(JSON.stringify({
      type: 'prompt.done',
      id: message.id,
      sessionId,
    }))
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      id: message.id,
      sessionId,
      code: 'PROMPT_ERROR',
      message: error.message,
    }))
  }
}

// 异步发送消息
async function handleSessionPromptAsync(ws: WebSocket, client: Client, message: any) {
  const { sessionId, parts, agent, model } = message
  
  const params: any = {
    id: sessionId,
    parts: parts || [{ type: 'text', text: message.content }],
  }
  
  if (agent) params.agent = agent
  if (model) params.model = model
  
  const response = await client.session.promptAsync(params)
  
  ws.send(JSON.stringify({
    type: 'prompt.async',
    id: message.id,
    sessionId,
    data: response.data,
  }))
}

// 压缩会话
async function handleSessionSummarize(ws: WebSocket, client: Client, message: any) {
  await client.session.summarize({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.summarized',
    id: message.id,
    sessionId: message.sessionId,
  }))
}

// 分享会话
async function handleSessionShare(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.share({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.shared',
    id: message.id,
    sessionId: message.sessionId,
    share: response.data,
  }))
}

// Fork 会话
async function handleSessionFork(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.fork({
    id: message.sessionId,
    messageID: message.messageId,
    partID: message.partId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.forked',
    id: message.id,
    session: response.data,
  }))
}

// 获取任务列表
async function handleSessionTask(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.task({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.task',
    id: message.id,
    sessionId: message.sessionId,
    tasks: response.data,
  }))
}

// 获取 Actor 列表
async function handleSessionActors(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.actors({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.actors',
    id: message.id,
    sessionId: message.sessionId,
    actors: response.data,
  }))
}

// 获取会话差异
async function handleSessionDiff(ws: WebSocket, client: Client, message: any) {
  const response = await client.session.diff({
    id: message.sessionId,
  })
  
  ws.send(JSON.stringify({
    type: 'session.diff',
    id: message.id,
    sessionId: message.sessionId,
    diff: response.data,
  }))
}

// 回复权限请求
async function handlePermissionReply(ws: WebSocket, client: Client, message: any) {
  const { requestId, reply, message: replyMessage } = message
  
  await client.permission.reply({
    requestID: requestId,
    reply: reply,  // 'once' | 'always' | 'reject'
    message: replyMessage,
  })
  
  ws.send(JSON.stringify({
    type: 'permission.replied',
    id: message.id,
    requestId,
    reply,
  }))
}

// 列出 PTY 会话
async function handlePtyList(ws: WebSocket, client: Client, message: any) {
  const response = await client.pty.list()
  
  ws.send(JSON.stringify({
    type: 'pty.list',
    id: message.id,
    sessions: response.data,
  }))
}

// 创建 PTY 会话
async function handlePtyCreate(ws: WebSocket, client: Client, message: any) {
  const response = await client.pty.create({
    command: message.command,
    args: message.args,
    cwd: message.cwd,
    title: message.title,
    env: message.env,
  })
  
  ws.send(JSON.stringify({
    type: 'pty.created',
    id: message.id,
    session: response.data,
  }))
}

// 连接 PTY（WebSocket 代理）
async function handlePtyConnect(ws: WebSocket, client: Client, message: any) {
  // PTY 连接需要特殊处理，因为它是 WebSocket 流
  // 这里返回连接信息，客户端需要单独建立 PTY 连接
  const response = await client.pty.connectToken({
    id: message.ptyId,
  })
  
  ws.send(JSON.stringify({
    type: 'pty.connect',
    id: message.id,
    ptyId: message.ptyId,
    token: response.data,
    url: `/pty/${message.ptyId}/connect`,
  }))
}

// 获取当前项目
async function handleProjectCurrent(ws: WebSocket, client: Client, message: any) {
  const response = await client.project.current()
  
  ws.send(JSON.stringify({
    type: 'project.current',
    id: message.id,
    project: response.data,
  }))
}

// 列出项目
async function handleProjectList(ws: WebSocket, client: Client, message: any) {
  const response = await client.project.list()
  
  ws.send(JSON.stringify({
    type: 'project.list',
    id: message.id,
    projects: response.data,
  }))
}

// 列出 Provider
async function handleProviderList(ws: WebSocket, client: Client, message: any) {
  const response = await client.provider.list()
  
  ws.send(JSON.stringify({
    type: 'provider.list',
    id: message.id,
    providers: response.data,
  }))
}

// 订阅事件
async function handleEventSubscribe(ws: WebSocket, client: Client, message: any) {
  // 事件订阅已经在插件初始化时建立
  // 这里只是确认订阅状态
  ws.send(JSON.stringify({
    type: 'event.subscribed',
    id: message.id,
    status: 'connected',
  }))
}
```

---

## 8. Flutter App 架构

### 8.1 目录结构

```
mimo_mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── models/
│   │   ├── session.dart
│   │   ├── message.dart
│   │   └── status.dart
│   ├── services/
│   │   ├── websocket_service.dart
│   │   ├── session_service.dart
│   │   └── project_service.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── chat_screen.dart
│   │   ├── session_list_screen.dart
│   │   └── status_screen.dart
│   ├── widgets/
│   │   ├── message_bubble.dart
│   │   ├── session_card.dart
│   │   └── status_indicator.dart
│   └── utils/
│       ├── constants.dart
│       └── helpers.dart
├── pubspec.yaml
└── test/
```

### 8.2 核心服务

```dart
// lib/services/websocket_service.dart
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final String host;
  final int port;
  
  WebSocketService({required this.host, required this.port});
  
  Future<void> connect() async {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://$host:$port'),
    );
    
    _channel!.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) => _handleError(error),
      onDone: () => _handleDisconnect(),
    );
  }
  
  void sendMessage(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }
  
  Stream<Map<String, dynamic>> get messageStream =>
    _channel!.stream.map((data) => jsonDecode(data));
  
  void disconnect() {
    _channel?.sink.close();
  }
}
```

---

## 9. 配置文件

### 9.1 MiMoCode 插件配置

```json
// .mimocode/mimocode.json
{
  "plugin": [
    "mimo-mobile-bridge"
  ],
  "mobile-bridge": {
    "port": 8765,
    "host": "0.0.0.0",
    "pairingCode": "123456",
    "autoAllowRead": true,
    "timeout": 30000
  }
}
```

### 9.2 Flutter App 配置

```dart
// lib/utils/constants.dart
class AppConfig {
  static const defaultPort = 8765;
  static const connectionTimeout = Duration(seconds: 30);
  static const reconnectInterval = Duration(seconds: 5);
  static const maxReconnectAttempts = 5;
}
```

---

## 10. 测试策略

### 10.1 单元测试

- WebSocket 消息解析
- 权限分级逻辑
- 状态管理

### 10.2 集成测试

- 插件与 MiMoCode SDK 集成
- Flutter App 与 WebSocket 服务通信
- 端到端对话流程

### 10.3 E2E 测试

- 完整用户流程测试
- 多设备并发测试
- 网络异常恢复测试

---

## 11. 部署和分发

### 11.1 插件发布

```bash
# 构建插件
npm run build

# 发布到 npm
npm publish
```

### 11.2 Flutter App 分发

- Android: Google Play / APK 直装
- iOS: TestFlight / App Store
- 可考虑使用 Codemagic 或 GitHub Actions 自动化构建

---

## 12. 未来扩展

### 12.1 可能的功能扩展

- 语音输入支持
- 图片/文件发送
- 多设备同步
- 推送通知
- 离线缓存
- 深色模式
- 国际化支持

### 12.2 性能优化

- 消息压缩
- 连接池管理
- 响应缓存
- 带宽优化

---

## 附录

### A. 参考资料

- [MiMoCode GitHub](https://github.com/XiaomiMiMo/MiMo-Code)
- [MiMoCode Plugin API](packages/plugin/src/index.ts)
- [MiMoCode SDK](packages/sdk/js/src/v2/)
- [Flutter WebSocket](https://pub.dev/packages/web_socket_channel)

### B. 术语表

| 术语 | 说明 |
|------|------|
| MiMoCode | 电脑端 AI 编码助手 |
| 插件 (Plugin) | MiMoCode 的扩展模块 |
| SDK Client | MiMoCode 提供的 API 客户端 |
| PTY | 伪终端 (Pseudo Terminal) |
| WebSocket | 全双工通信协议 |
| 流式响应 | 边生成边返回的响应方式 |
