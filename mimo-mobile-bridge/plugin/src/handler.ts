import type { WebSocket } from "ws"
import { ErrorCode } from "./types.js"

/**
 * SDK Client 类型
 * 通过 @mimo-ai/sdk 的 createOpencodeClient 创建，包含 session/permission/pty/project/provider 等子模块
 */
type Client = any

/**
 * 消息处理器入口
 * 根据消息 type 分发到对应的 SDK 调用
 * 所有响应通过 ws.send() 返回，携带 message.id 用于匹配请求
 */
export async function handleMessage(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  try {
    switch (message.type) {
      // 会话相关
      case "session.list":
        return await handleSessionList(ws, client, message)
      case "session.create":
        return await handleSessionCreate(ws, client, message)
      case "session.get":
        return await handleSessionGet(ws, client, message)
      case "session.delete":
        return await handleSessionDelete(ws, client, message)
      case "session.abort":
        return await handleSessionAbort(ws, client, message)
      case "session.status":
        return await handleSessionStatus(ws, client, message)
      case "session.messages":
        return await handleSessionMessages(ws, client, message)
      case "session.prompt":
        return await handleSessionPrompt(ws, client, message)
      case "session.summarize":
        return await handleSessionSummarize(ws, client, message)
      case "session.share":
        return await handleSessionShare(ws, client, message)
      case "session.fork":
        return await handleSessionFork(ws, client, message)
      case "session.task":
        return await handleSessionTask(ws, client, message)

      // 权限相关
      case "permission.reply":
        return await handlePermissionReply(ws, client, message)

      // PTY 相关
      case "pty.list":
        return await handlePtyList(ws, client, message)
      case "pty.create":
        return await handlePtyCreate(ws, client, message)

      // 项目相关
      case "project.current":
        return await handleProjectCurrent(ws, client, message)
      case "project.list":
        return await handleProjectList(ws, client, message)

      // Provider 相关
      case "provider.list":
        return await handleProviderList(ws, client, message)

      default:
        sendError(ws, message.id, ErrorCode.INVALID_REQUEST, `未知的消息类型: ${message.type}`)
    }
  } catch (error) {
    // 顶层兜底：确保任何异常都返回错误消息，避免连接挂起
    sendError(
      ws,
      message.id,
      ErrorCode.INTERNAL_ERROR,
      error instanceof Error ? error.message : String(error),
    )
  }
}

// ============================================================
// 工具函数
// ============================================================

/** 发送错误响应 */
function sendError(
  ws: WebSocket,
  id: string | undefined,
  code: string,
  message: string,
): void {
  ws.send(JSON.stringify({ type: "error", id, code, message }))
}

/** 发送 JSON 响应 */
function send(ws: WebSocket, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify(payload))
}

// ============================================================
// 会话相关处理器
// ============================================================

/** 获取会话列表 */
async function handleSessionList(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.list({
    limit: message.limit,
    search: message.search,
    archived: message.archived,
  })
  send(ws, { type: "session.list", id: message.id, sessions: response.data })
}

/** 创建会话 */
async function handleSessionCreate(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.create({
    title: message.title,
    directory: message.directory,
  })
  send(ws, { type: "session.created", id: message.id, session: response.data })
}

/** 获取会话详情 */
async function handleSessionGet(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.get({ id: message.sessionId })
  send(ws, { type: "session.get", id: message.id, session: response.data })
}

/** 删除会话 */
async function handleSessionDelete(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  await client.session.remove({ id: message.sessionId })
  send(ws, {
    type: "session.deleted",
    id: message.id,
    sessionId: message.sessionId,
  })
}

/** 中止会话 */
async function handleSessionAbort(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  await client.session.abort({ id: message.sessionId })
  send(ws, {
    type: "session.aborted",
    id: message.id,
    sessionId: message.sessionId,
  })
}

/** 获取会话状态 */
async function handleSessionStatus(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.status({ id: message.sessionId })
  send(ws, {
    type: "session.status",
    id: message.id,
    sessionId: message.sessionId,
    status: response.data,
  })
}

/** 获取会话消息历史 */
async function handleSessionMessages(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.messages(
    { id: message.sessionId },
    { limit: message.limit, cursor: message.cursor },
  )
  send(ws, {
    type: "session.messages",
    id: message.id,
    sessionId: message.sessionId,
    messages: response.data,
  })
}

/**
 * 发送消息（流式响应）
 * SDK 的 prompt 方法返回 AsyncIterable，逐个事件推送后发送完成消息
 */
async function handleSessionPrompt(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const { sessionId, parts, agent, model } = message

  // 构建请求参数：parts 优先，否则用 content 构造文本 part
  const params: any = {
    id: sessionId,
    parts: parts || [{ type: "text", text: message.content }],
  }
  if (agent) params.agent = agent
  if (model) params.model = model

  try {
    // 调用 SDK 的 prompt 方法，返回流式事件迭代器
    const response = await client.session.prompt(params)

    // 逐个推送流式事件
    for await (const event of response) {
      ws.send(
        JSON.stringify({
          type: "prompt.event",
          id: message.id,
          sessionId,
          event,
        }),
      )
    }

    // 流式响应完成
    send(ws, { type: "prompt.done", id: message.id, sessionId })
  } catch (error) {
    // 流式过程中出错：单独捕获，使用 PROMPT_ERROR 错误码
    sendError(
      ws,
      message.id,
      ErrorCode.PROMPT_ERROR,
      error instanceof Error ? error.message : String(error),
    )
  }
}

/** 压缩会话 */
async function handleSessionSummarize(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  await client.session.summarize({ id: message.sessionId })
  send(ws, {
    type: "session.summarized",
    id: message.id,
    sessionId: message.sessionId,
  })
}

/** 分享会话 */
async function handleSessionShare(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.share({ id: message.sessionId })
  send(ws, {
    type: "session.shared",
    id: message.id,
    sessionId: message.sessionId,
    share: response.data,
  })
}

/** Fork 会话 */
async function handleSessionFork(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.fork(
    { id: message.sessionId },
    { messageID: message.messageId, partID: message.partId },
  )
  send(ws, { type: "session.forked", id: message.id, session: response.data })
}

/** 获取任务列表 */
async function handleSessionTask(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.session.task({ id: message.sessionId })
  send(ws, {
    type: "session.task",
    id: message.id,
    sessionId: message.sessionId,
    tasks: response.data,
  })
}

// ============================================================
// 权限相关处理器
// ============================================================

/** 回复权限请求 */
async function handlePermissionReply(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const { requestId, reply, message: replyMessage } = message
  await client.permission.reply(
    { id: requestId },
    { reply, message: replyMessage },
  )
  send(ws, {
    type: "permission.replied",
    id: message.id,
    requestId,
    reply,
  })
}

// ============================================================
// PTY 相关处理器
// ============================================================

/** 列出 PTY 会话 */
async function handlePtyList(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.pty.list()
  send(ws, { type: "pty.list", id: message.id, sessions: response.data })
}

/** 创建 PTY 会话 */
async function handlePtyCreate(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.pty.create({
    command: message.command,
    args: message.args,
    cwd: message.cwd,
    title: message.title,
    env: message.env,
  })
  send(ws, { type: "pty.created", id: message.id, session: response.data })
}

// ============================================================
// 项目相关处理器
// ============================================================

/** 获取当前项目 */
async function handleProjectCurrent(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.project.current()
  send(ws, { type: "project.current", id: message.id, project: response.data })
}

/** 列出项目 */
async function handleProjectList(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.project.list()
  send(ws, { type: "project.list", id: message.id, projects: response.data })
}

// ============================================================
// Provider 相关处理器
// ============================================================

/** 列出 Provider */
async function handleProviderList(
  ws: WebSocket,
  client: Client,
  message: any,
): Promise<void> {
  const response = await client.provider.list()
  send(ws, {
    type: "provider.list",
    id: message.id,
    providers: response.data,
  })
}
