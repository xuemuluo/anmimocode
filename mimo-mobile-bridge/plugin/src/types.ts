/**
 * WebSocket 消息类型定义
 * 包含手机端 -> 服务器（请求）和 服务器 -> 手机端（响应/事件）的所有消息类型
 */

// ============================================================
// 基础类型
// ============================================================

/** 基础请求消息：所有客户端请求都携带可选 id 用于匹配响应 */
export interface BaseRequest {
  type: string
  id?: string
}

/** 基础响应消息：所有响应都携带对应请求的 id */
export interface BaseResponse {
  type: string
  id?: string
}

/** 错误响应 */
export interface ErrorMessage extends BaseResponse {
  type: "error"
  id?: string
  code: string
  message: string
  details?: unknown
}

// ============================================================
// 认证消息
// ============================================================

export interface AuthRequest extends BaseRequest {
  type: "auth"
  pairingCode: string
}

export interface AuthSuccess extends BaseResponse {
  type: "auth.success"
}

export interface AuthFailed extends BaseResponse {
  type: "auth.failed"
}

// ============================================================
// 会话相关请求
// ============================================================

export interface SessionListRequest extends BaseRequest {
  type: "session.list"
  limit?: number
  search?: string
  archived?: boolean
}

export interface SessionCreateRequest extends BaseRequest {
  type: "session.create"
  title?: string
  directory?: string
}

export interface SessionGetRequest extends BaseRequest {
  type: "session.get"
  sessionId: string
}

export interface SessionDeleteRequest extends BaseRequest {
  type: "session.delete"
  sessionId: string
}

export interface SessionAbortRequest extends BaseRequest {
  type: "session.abort"
  sessionId: string
}

export interface SessionStatusRequest extends BaseRequest {
  type: "session.status"
  sessionId: string
}

export interface SessionMessagesRequest extends BaseRequest {
  type: "session.messages"
  sessionId: string
  limit?: number
  cursor?: string
}

export interface SessionPromptRequest extends BaseRequest {
  type: "session.prompt"
  sessionId: string
  /** 消息内容，二选一：parts 优先 */
  content?: string
  parts?: Array<{ type: string; text?: string; [key: string]: unknown }>
  agent?: string
  model?: string
}

export interface SessionSummarizeRequest extends BaseRequest {
  type: "session.summarize"
  sessionId: string
}

export interface SessionShareRequest extends BaseRequest {
  type: "session.share"
  sessionId: string
}

export interface SessionForkRequest extends BaseRequest {
  type: "session.fork"
  sessionId: string
  messageId?: string
  partId?: string
}

export interface SessionTaskRequest extends BaseRequest {
  type: "session.task"
  sessionId: string
}

// ============================================================
// 会话相关响应
// ============================================================

export interface SessionListResponse extends BaseResponse {
  type: "session.list"
  sessions: unknown
}

export interface SessionCreatedResponse extends BaseResponse {
  type: "session.created"
  session: unknown
}

export interface SessionGetResponse extends BaseResponse {
  type: "session.get"
  session: unknown
}

export interface SessionDeletedResponse extends BaseResponse {
  type: "session.deleted"
  sessionId: string
}

export interface SessionAbortedResponse extends BaseResponse {
  type: "session.aborted"
  sessionId: string
}

export interface SessionStatusResponse extends BaseResponse {
  type: "session.status"
  sessionId: string
  status: unknown
}

export interface SessionMessagesResponse extends BaseResponse {
  type: "session.messages"
  sessionId: string
  messages: unknown
}

/** 流式响应中的单个事件 */
export interface PromptEventMessage extends BaseResponse {
  type: "prompt.event"
  sessionId: string
  event: unknown
}

/** 流式响应完成 */
export interface PromptDoneMessage extends BaseResponse {
  type: "prompt.done"
  sessionId: string
}

export interface SessionSummarizedResponse extends BaseResponse {
  type: "session.summarized"
  sessionId: string
}

export interface SessionSharedResponse extends BaseResponse {
  type: "session.shared"
  sessionId: string
  share: unknown
}

export interface SessionForkedResponse extends BaseResponse {
  type: "session.forked"
  session: unknown
}

export interface SessionTaskResponse extends BaseResponse {
  type: "session.task"
  sessionId: string
  tasks: unknown
}

// ============================================================
// 权限相关
// ============================================================

export interface PermissionReplyRequest extends BaseRequest {
  type: "permission.reply"
  requestId: string
  reply: "once" | "always" | "reject"
  message?: string
}

export interface PermissionRepliedResponse extends BaseResponse {
  type: "permission.replied"
  requestId: string
  reply: "once" | "always" | "reject"
}

// ============================================================
// PTY 相关
// ============================================================

export interface PtyListRequest extends BaseRequest {
  type: "pty.list"
}

export interface PtyCreateRequest extends BaseRequest {
  type: "pty.create"
  command: string
  args?: string[]
  cwd?: string
  title?: string
  env?: Record<string, string>
}

export interface PtyListResponse extends BaseResponse {
  type: "pty.list"
  sessions: unknown
}

export interface PtyCreatedResponse extends BaseResponse {
  type: "pty.created"
  session: unknown
}

// ============================================================
// 项目相关
// ============================================================

export interface ProjectCurrentRequest extends BaseRequest {
  type: "project.current"
}

export interface ProjectListRequest extends BaseRequest {
  type: "project.list"
}

export interface ProjectCurrentResponse extends BaseResponse {
  type: "project.current"
  project: unknown
}

export interface ProjectListResponse extends BaseResponse {
  type: "project.list"
  projects: unknown
}

// ============================================================
// Provider 相关
// ============================================================

export interface ProviderListRequest extends BaseRequest {
  type: "provider.list"
}

export interface ProviderListResponse extends BaseResponse {
  type: "provider.list"
  providers: unknown
}

// ============================================================
// 服务器主动推送消息（广播）
// ============================================================

/** MiMoCode 系统事件转发 */
export interface EventMessage {
  type: "mimo.event"
  event: unknown
}

export interface SessionStartMessage {
  type: "session.start"
  sessionId: string
  agentId?: string
}

export interface SessionCompleteMessage {
  type: "session.complete"
  sessionId: string
  outcome?: unknown
}

export interface ToolStartMessage {
  type: "tool.start"
  sessionId: string
  tool: string
  callId: string
}

export interface ToolFinishMessage {
  type: "tool.finish"
  sessionId: string
  tool: string
  callId: string
  title?: string
}

export interface PermissionRequestMessage {
  type: "permission.request"
  id: string
  pattern: string
  action: string
}

// ============================================================
// 联合类型
// ============================================================

/** 所有客户端请求消息 */
export type ClientRequest =
  | AuthRequest
  | SessionListRequest
  | SessionCreateRequest
  | SessionGetRequest
  | SessionDeleteRequest
  | SessionAbortRequest
  | SessionStatusRequest
  | SessionMessagesRequest
  | SessionPromptRequest
  | SessionSummarizeRequest
  | SessionShareRequest
  | SessionForkRequest
  | SessionTaskRequest
  | PermissionReplyRequest
  | PtyListRequest
  | PtyCreateRequest
  | ProjectCurrentRequest
  | ProjectListRequest
  | ProviderListRequest

/** 所有服务器响应消息 */
export type ServerResponse =
  | AuthSuccess
  | AuthFailed
  | ErrorMessage
  | SessionListResponse
  | SessionCreatedResponse
  | SessionGetResponse
  | SessionDeletedResponse
  | SessionAbortedResponse
  | SessionStatusResponse
  | SessionMessagesResponse
  | PromptEventMessage
  | PromptDoneMessage
  | SessionSummarizedResponse
  | SessionSharedResponse
  | SessionForkedResponse
  | SessionTaskResponse
  | PermissionRepliedResponse
  | PtyListResponse
  | PtyCreatedResponse
  | ProjectCurrentResponse
  | ProjectListResponse
  | ProviderListResponse

/** 所有服务器广播消息 */
export type ServerBroadcast =
  | EventMessage
  | SessionStartMessage
  | SessionCompleteMessage
  | ToolStartMessage
  | ToolFinishMessage
  | PermissionRequestMessage

/** 错误代码常量 */
export const ErrorCode = {
  INVALID_REQUEST: "INVALID_REQUEST",
  SESSION_NOT_FOUND: "SESSION_NOT_FOUND",
  PERMISSION_DENIED: "PERMISSION_DENIED",
  TIMEOUT: "TIMEOUT",
  INTERNAL_ERROR: "INTERNAL_ERROR",
  PROMPT_ERROR: "PROMPT_ERROR",
} as const
