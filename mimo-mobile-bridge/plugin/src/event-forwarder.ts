import { WebSocket } from "ws"

/**
 * 事件转发器
 * 负责将 MiMoCode 事件转发给所有已连接的 WebSocket 客户端
 */
export class EventForwarder {
  constructor(private clients: Set<WebSocket>) {}

  /**
   * 向所有已连接客户端广播消息
   * 仅向处于 OPEN 状态的连接发送，避免向已关闭/正在关闭的连接写入
   */
  broadcast(message: any): void {
    const data = JSON.stringify(message)
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data)
      }
    }
  }

  /**
   * 转发 MiMoCode 系统事件，统一包装为 mimo.event 类型
   */
  forward(event: any): void {
    this.broadcast({ type: "mimo.event", event })
  }
}
