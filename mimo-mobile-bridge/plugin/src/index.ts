import type { Hooks, PluginInput } from "@mimo-ai/plugin"
import { WebSocket, WebSocketServer } from "ws"
import { EventForwarder } from "./event-forwarder.js"
import { handleMessage } from "./handler.js"

/** 默认监听端口 */
const DEFAULT_PORT = 8765
/** 默认配对码（仅用于开发，生产环境应通过配置覆盖） */
const DEFAULT_PAIRING_CODE = "000000"

/** 桥接服务配置 */
export interface BridgeConfig {
  port: number
  host: string
  pairingCode: string
  autoAllowRead: boolean
  timeout: number
}

/**
 * 创建 MiMoCode 移动端桥接插件
 * 启动 WebSocket 服务器，让手机端 App 通过局域网连接到 MiMoCode
 */
export function createPlugin(input: PluginInput): Hooks {
  const config: BridgeConfig = {
    port: DEFAULT_PORT,
    host: "0.0.0.0",
    pairingCode: DEFAULT_PAIRING_CODE,
    autoAllowRead: true,
    timeout: 30000,
  }

  // 启动 WebSocket 服务器，监听所有网络接口以接受局域网连接
  const wss = new WebSocketServer({ port: config.port, host: config.host })
  // 已认证的客户端集合
  const clients = new Set<WebSocket>()
  const eventForwarder = new EventForwarder(clients)

  console.log(
    `[MiMo Mobile Bridge] WebSocket 服务器已启动，监听 ${config.host}:${config.port}`,
  )

  // 连接处理：每个新连接都需要先通过配对码验证
  wss.on("connection", (ws) => {
    let authenticated = false

    ws.on("message", async (data) => {
      const message = JSON.parse(data.toString())

      // 配对码验证（第一道安全防线）
      if (!authenticated) {
        if (
          message.type === "auth" &&
          message.pairingCode === config.pairingCode
        ) {
          authenticated = true
          ws.send(JSON.stringify({ type: "auth.success" }))
          clients.add(ws)
        } else {
          ws.send(JSON.stringify({ type: "auth.failed" }))
          ws.close()
        }
        return
      }

      // 已认证后，交由消息处理器分发到对应的 SDK 调用
      await handleMessage(ws, input.client, message)
    })

    ws.on("close", () => {
      clients.delete(ws)
    })

    ws.on("error", (error) => {
      console.error("[MiMo Mobile Bridge] WebSocket error:", error)
      clients.delete(ws)
    })
  })

  // 返回插件钩子，将 MiMoCode 事件转发给所有客户端
  return {
    event: async ({ event }) => {
      eventForwarder.forward(event)
    },
    "session.pre": async (i) => {
      eventForwarder.broadcast({
        type: "session.start",
        sessionId: i.sessionID,
        agentId: i.agentID,
      })
    },
    "session.post": async (i) => {
      eventForwarder.broadcast({
        type: "session.complete",
        sessionId: i.sessionID,
        outcome: i.outcome,
      })
    },
    "tool.execute.before": async (i) => {
      eventForwarder.broadcast({
        type: "tool.start",
        sessionId: i.sessionID,
        tool: i.tool,
        callId: i.callID,
      })
    },
    "tool.execute.after": async (i) => {
      eventForwarder.broadcast({
        type: "tool.finish",
        sessionId: i.sessionID,
        tool: i.tool,
        callId: i.callID,
      })
    },
    "permission.ask": async (i) => {
      eventForwarder.broadcast({
        type: "permission.request",
        id: i.id,
        pattern: i.pattern,
        action: i.action,
      })
    },
  }
}

export default createPlugin
