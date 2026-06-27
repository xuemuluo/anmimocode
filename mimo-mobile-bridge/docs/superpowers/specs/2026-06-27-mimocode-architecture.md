# MiMoCode 界面功能与架构分析

## 1. 整体架构

MiMoCode 采用模块化架构，主要由以下核心包组成：

```
MiMo-Code/
├── packages/
│   ├── opencode/          # 核心业务逻辑
│   ├── sdk/               # SDK 客户端
│   ├── plugin/            # 插件系统
│   ├── ui/                # UI 组件
│   └── mimo/              # CLI 入口
```

---

## 2. 核心数据模型

### 2.1 Session（会话）

**位置**: `packages/opencode/src/session/session.ts`

```typescript
interface Session {
  id: SessionID           // 会话唯一标识
  slug: string            // URL 友好的标识
  projectID: ProjectID    // 所属项目 ID
  workspaceID?: WorkspaceID  // 工作区 ID
  directory: string       // 工作目录
  parentID?: SessionID    // 父会话 ID（用于子任务）
  contextFrom?: SessionID // 继承上下文的会话 ID
  contextWatermark?: MessageID  // 上下文水位标记
  title: string           // 会话标题
  version: string         // MiMoCode 版本
  summary?: {             // 代码变更摘要
    additions: number     // 新增行数
    deletions: number     // 删除行数
    files: number         // 修改文件数
    diffs?: FileDiff[]    // 差异详情
  }
  share?: {               // 分享信息
    url: string           // 分享链接
  }
  time: {
    created: number       // 创建时间
    updated: number       // 更新时间
    compacting?: number   // 上次压缩时间
    archived?: number     // 归档时间
  }
  permission?: PermissionRuleset  // 权限规则
  revert?: {              // 回滚信息
    messageID: MessageID
    partID?: PartID
    snapshot?: string
    diff?: string
  }
}
```

### 2.2 Session Status（会话状态）

**位置**: `packages/opencode/src/session/status.ts`

```typescript
type SessionStatus = 
  | { type: "idle" }                    // 空闲
  | { type: "retry", attempt: number, message: string, next: number }  // 重试中
  | { type: "busy", message?: string }  // 忙碌
```

### 2.3 Message（消息）

**位置**: `packages/opencode/src/session/message-v2.ts`

```typescript
// 用户消息
interface UserMessage {
  id: MessageID
  sessionID: SessionID
  agentID?: string
  role: "user"
  time: { created: number }
  format?: OutputFormat    // 输出格式（text/json_schema）
  summary?: {
    title?: string
    body?: string
    diffs: FileDiff[]
  }
  agent: string           // agent 类型
  model: {
    providerID: ProviderID
    modelID: ModelID
    variant?: string
  }
  system?: string         // 系统提示
  tools?: Record<string, boolean>  // 启用的工具
  provenance?: Provenance  // 来源信息
}

// AI 助手消息
interface AssistantMessage {
  id: MessageID
  sessionID: SessionID
  agentID?: string
  role: "assistant"
  time: {
    created: number
    completed?: number    // 完成时间
  }
  error?: MessageError    // 错误信息
  parentID: MessageID     // 关联的用户消息 ID
  modelID: ModelID
  providerID: ProviderID
  agent: string           // agent 类型
  path: {
    cwd: string           // 当前工作目录
    root: string          // 项目根目录
  }
  summary?: boolean       // 是否为摘要消息
  cost: number            // 费用（美元）
  tokens: {               // Token 使用情况
    total?: number
    input: number
    output: number
    reasoning: number
    cache: {
      read: number
      write: number
    }
  }
  structured?: any        // 结构化输出
  variant?: string
  finish?: string         // 完成原因
}
```

### 2.4 Part（消息部分）

消息由多个 Part 组成，每个 Part 代表一种内容类型：

```typescript
type Part = 
  | TextPart           // 文本
  | ReasoningPart      // 推理过程
  | FilePart           // 文件附件
  | ToolPart           // 工具调用
  | StepStartPart      // 步骤开始
  | StepFinishPart     // 步骤结束
  | SnapshotPart       // 快照
  | PatchPart          // 补丁
  | AgentPart          // Agent 信息
  | SubtaskPart        // 子任务
  | CompactionPart     // 压缩信息
  | CheckpointPart     // 检查点
  | RetryPart          // 重试信息
```

**TextPart - 文本**:
```typescript
interface TextPart {
  id: PartID
  sessionID: SessionID
  messageID: MessageID
  type: "text"
  text: string
  synthetic?: boolean    // 是否为合成内容
  ignored?: boolean      // 是否被忽略
  time?: {
    start: number
    end?: number
  }
  metadata?: Record<string, any>
}
```

**ToolPart - 工具调用**:
```typescript
interface ToolPart {
  id: PartID
  sessionID: SessionID
  messageID: MessageID
  type: "tool"
  callID: string         // 调用 ID
  tool: string           // 工具名称
  state: ToolState       // 工具状态
  metadata?: Record<string, any>
}

type ToolState = 
  | { status: "pending", input: Record<string, any>, raw: string }
  | { status: "running", input: Record<string, any>, title?: string, metadata?: Record<string, any>, time: { start: number } }
  | { status: "completed", input: Record<string, any>, output: string, title: string, metadata: Record<string, any>, time: { start: number, end: number, compacted?: number }, attachments?: FilePart[] }
  | { status: "error", input: Record<string, any>, error: string, metadata?: Record<string, any>, time: { start: number, end: number } }
```

**StepFinishPart - 步骤完成**:
```typescript
interface StepFinishPart {
  id: PartID
  sessionID: SessionID
  messageID: MessageID
  type: "step-finish"
  reason: string         // 完成原因
  snapshot?: string      // 快照
  cost: number           // 费用
  tokens: {
    total?: number
    input: number
    output: number
    reasoning: number
    cache: {
      read: number
      write: number
    }
  }
}
```

---

## 3. SDK Client API

**位置**: `packages/sdk/js/src/v2/gen/sdk.gen.ts`

### 3.1 Session API

```typescript
interface SessionAPI {
  // 获取会话列表
  list(input?: { limit?: number; search?: string }): Promise<SessionList>
  
  // 创建新会话
  create(input?: SessionCreateInput): Promise<Session>
  
  // 获取会话详情
  get(path: { id: string }): Promise<Session>
  
  // 删除会话
  remove(path: { id: string }): Promise<void>
  
  // 获取会话状态
  status(path: { id: string }): Promise<SessionStatus>
  
  // 获取会话消息
  messages(path: { id: string }, input?: { limit?: number; cursor?: string }): Promise<MessagePage>
  
  // 发送消息（流式响应）
  prompt(path: { id: string }, input: PromptInput): AsyncIterable<PromptEvent>
  
  // 异步发送消息
  promptAsync(path: { id: string }, input: PromptInput): Promise<PromptAsync>
  
  // 中止会话
  abort(path: { id: string }): Promise<void>
  
  // 获取任务列表
  task(path: { id: string }): Promise<SessionTaskList>
  
  // 获取 Actor 列表
  actors(path: { id: string }): Promise<SessionActorList>
  
  // 压缩会话
  summarize(path: { id: string }): Promise<void>
  
  // 分享会话
  share(path: { id: string }): Promise<SessionShare>
  
  // 删除分享
  unshare(path: { id: string }): Promise<void>
  
  // 回滚消息
  revert(path: { id: string }, input: SessionRevertInput): Promise<void>
  
  // 清除回滚
  revertClear(path: { id: string }): Promise<void>
  
  // Fork 会话
  fork(path: { id: string }, input?: SessionForkInput): Promise<Session>
}
```

### 3.2 Message API

```typescript
interface MessageAPI {
  // 获取消息详情
  get(path: { id: string; messageID: string }): Promise<Message>
  
  // 删除消息
  remove(path: { id: string; messageID: string }): Promise<void>
  
  // 删除消息部分
  removePart(path: { id: string; messageID: string; partID: string }): Promise<void>
  
  // 重试消息
  retry(path: { id: string; messageID: string }): Promise<void>
}
```

### 3.3 File API

```typescript
interface FileAPI {
  // 列出文件
  list(input?: { path?: string }): Promise<FileList>
  
  // 读取文件
  read(path: { path: string }, input?: FileReadInput): Promise<FileContent>
  
  // 获取文件状态
  status(): Promise<FileStatus>
}
```

### 3.4 Project API

```typescript
interface ProjectAPI {
  // 列出项目
  list(): Promise<ProjectList>
  
  // 获取当前项目
  current(): Promise<ProjectCurrent>
  
  // 切换工作目录
  changeDir(input: ProjectChangeDirInput): Promise<ProjectChangeDir>
}
```

### 3.5 Provider API

```typescript
interface ProviderAPI {
  // 列出 Provider
  list(): Promise<ProviderList>
  
  // 获取 Provider 详情
  get(path: { id: string }): Promise<Provider>
  
  // 获取 Provider 状态
  status(path: { id: string }): Promise<ProviderStatus>
  
  // 获取默认模型
  modelsDefault(): Promise<ProviderModelsDefault>
  
  // 设置默认模型
  modelsDefaultSet(input: ProviderModelsDefaultSetInput): Promise<void>
}
```

### 3.6 Permission API

```typescript
interface PermissionAPI {
  // 列出待处理权限
  list(): Promise<PermissionList>
  
  // 回复权限请求
  reply(path: { id: string }, input: PermissionReplyInput): Promise<void>
}
```

### 3.7 PTY (Terminal) API

```typescript
interface PtyAPI {
  // 列出 PTY 会话
  list(): Promise<PtyList>
  
  // 创建 PTY 会话
  create(input?: PtyCreateInput): Promise<PtyCreate>
  
  // 读取 PTY 输出
  read(path: { id: string }): Promise<ReadableStream>
  
  // 连接到 PTY (WebSocket)
  connect(path: { id: string }): WebSocket
  
  // 写入 PTY 输入
  write(path: { id: string }, input: PtyWriteInput): Promise<void>
  
  // 关闭 PTY
  close(path: { id: string }): Promise<void>
  
  // 调整 PTY 大小
  resize(path: { id: string }, input: PtyResizeInput): Promise<void>
}
```

### 3.8 Event API

```typescript
interface EventAPI {
  // 订阅事件 (SSE)
  subscribe(): AsyncIterable<ServerEvent>
}

// 事件类型
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

---

## 4. UI 组件

### 4.1 消息显示组件

**位置**: `packages/ui/src/components/`

- `markdown-stream.ts` - 流式 Markdown 渲染
- `session-diff.ts` - 代码差异显示
- `message-file.ts` - 文件附件显示

### 4.2 主题系统

**位置**: `packages/ui/src/theme/`

支持 30+ 预设主题：
- Catppuccin (Frappe/Macchiato/Mocha)
- Dracula
- GitHub Dark/Light
- Gruvbox
- Nord
- One Dark/One Dark Pro
- Solarized
- Tokyo Night
- Vesper
- ... 等

### 4.3 国际化

**位置**: `packages/ui/src/i18n/`

支持 15+ 语言：
- Arabic, Bosnian, Brazilian, Chinese, Danish, German, English, Spanish, French, Japanese, Korean, Norwegian, Polish, Russian, Thai, Turkish, Traditional Chinese

---

## 5. 核心功能模块

### 5.1 会话管理

- 创建/删除/归档会话
- 会话标题自动/手动设置
- 会话 Fork（分支）
- 会话分享
- 会话压缩（上下文管理）
- 子会话管理

### 5.2 消息处理

- 流式响应处理
- 消息历史记录
- 消息重试
- 消息回滚
- 检查点管理

### 5.3 工具执行

支持的工具类型：
- `bash` / `bash_interactive` - 命令执行
- `read` / `write` / `edit` / `multiedit` - 文件操作
- `glob` / `grep` - 文件搜索
- `codesearch` - 代码搜索
- `webfetch` / `websearch` - 网络操作
- `task` - 子任务
- `skill` - 技能调用
- `question` - 用户提问
- `plan` - 计划生成
- `memory` - 记忆管理
- `apply_patch` - 应用补丁
- `lsp` - LSP 操作
- `notebook` - Notebook 操作

### 5.4 权限管理

```typescript
interface Permission {
  id: string
  sessionID: string
  messageID: string
  pattern: string        // 匹配模式
  action: string         // 操作类型
  metadata: {
    message: string      // 权限描述
    [key: string]: any
  }
  reply?: "once" | "always" | "reject"
}
```

### 5.5 Provider 管理

支持的 AI Provider：
- Anthropic (Claude)
- OpenAI (GPT-4)
- Google (Gemini)
- xAI (Grok)
- OpenRouter
- ... 等

### 5.6 代码差异管理

- Git diff 解析
- 文件差异可视化
- 变更统计
- 快照管理

---

## 6. 插件系统

**位置**: `packages/plugin/src/index.ts`

### 6.1 插件钩子

```typescript
interface Hooks {
  // 系统事件
  event?: (input: EventInput, next: () => Promise<void>) => Promise<void>
  
  // 配置修改
  config?: (input: { config: GlobalConfig }) => Promise<{ config: GlobalConfig }>
  
  // 认证处理
  auth?: (input: AuthInput, next: () => Promise<unknown>) => Promise<unknown>
  
  // 工具注册
  tool?: Tool[]
  
  // Provider 注册
  provider?: Provider[]
  
  // 聊天消息拦截
  "chat.message"?: ChatMessageHook
  
  // 聊天参数修改
  "chat.params"?: ChatParamsHook
  
  // 聊天头部修改
  "chat.headers"?: ChatHeadersHook
  
  // 工具执行前拦截
  "tool.execute.before"?: ToolExecuteBeforeHook
  
  // 工具执行后拦截
  "tool.execute.after"?: ToolExecuteAfterHook
  
  // 会话开始前
  "session.pre"?: SessionPreHook
  
  // 会话结束后
  "session.post"?: SessionPostHook
  
  // Actor 停止前
  "actor.preStop"?: ActorPreStopHook
  
  // Actor 停止后
  "actor.postStop"?: ActorPostStopHook
  
  // 权限请求
  "permission.ask"?: PermissionAskHook
}
```

### 6.2 插件输入

```typescript
interface PluginInput {
  client: OpencodeClient    // SDK 客户端
  project: Project          // 项目信息
  directory: string         // 工作目录
  worktree: string          // Git 工作树
  home: string              // 用户主目录
  mimoDir: string           // MiMoCode 配置目录
  globalDir: string         // 全局配置目录
  cacheDir: string          // 缓存目录
  machineID: string         // 机器 ID
  version: string           // 版本号
  sessionID?: string        // 当前会话 ID
  userID?: string           // 用户 ID
  conversationID?: string   // 对话 ID
  environment?: Record<string, string>  // 环境变量
}
```

---

## 7. 数据流

### 7.1 用户发送消息流程

```
用户输入
    ↓
Session.prompt(sessionID, input)
    ↓
创建 UserMessage
    ↓
调用 AI Provider
    ↓
流式返回 AssistantMessage
    ↓
处理 Part（文本、工具调用等）
    ↓
更新 Session 状态
    ↓
发送事件通知
```

### 7.2 工具执行流程

```
AI 返回工具调用
    ↓
创建 ToolPart (status: "pending")
    ↓
检查权限
    ↓
执行工具 (status: "running")
    ↓
获取结果 (status: "completed" | "error")
    ↓
更新 ToolPart
    ↓
继续 AI 对话
```

### 7.3 事件通知流程

```
状态变化
    ↓
触发 SyncEvent / BusEvent
    ↓
Event.subscribe() 推送
    ↓
客户端接收并更新 UI
```

---

## 8. 文件结构

### 8.1 核心目录

```
packages/opencode/src/
├── session/              # 会话管理
│   ├── session.ts        # 会话核心逻辑
│   ├── message-v2.ts     # 消息模型
│   ├── status.ts         # 状态管理
│   ├── prompt.ts         # 提示处理
│   ├── processor.ts      # 消息处理
│   └── ...
├── tool/                 # 工具实现
│   ├── bash.ts           # 命令执行
│   ├── read.ts           # 文件读取
│   ├── write.ts          # 文件写入
│   ├── edit.ts           # 文件编辑
│   ├── grep.ts           # 文件搜索
│   └── ...
├── provider/             # AI Provider
├── permission/           # 权限管理
├── project/              # 项目管理
├── storage/              # 数据存储
├── sync/                 # 同步事件
├── bus/                  # 事件总线
└── ...
```

### 8.2 SDK 目录

```
packages/sdk/js/src/v2/
├── client.ts             # 客户端创建
├── gen/
│   ├── sdk.gen.ts        # SDK 方法定义
│   └── types.gen.ts      # 类型定义
└── index.ts              # 入口
```

---

## 9. 总结

MiMoCode 是一个功能强大的 AI 编码助手，具有：

1. **完善的会话管理** - 支持创建、Fork、分享、压缩等
2. **丰富的消息类型** - 文本、工具调用、推理、文件附件等
3. **强大的工具系统** - 文件操作、命令执行、代码搜索等
4. **灵活的插件系统** - 支持钩子、自定义工具、Provider
5. **完善的 SDK** - 提供完整的 API 访问
6. **实时事件系统** - SSE 事件订阅
7. **多 Provider 支持** - Claude、GPT、Gemini 等

这些功能为手机端 App 提供了强大的基础，可以通过插件系统深度集成所有功能。
