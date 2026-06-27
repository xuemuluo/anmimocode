# MiMo Mobile Bridge

手机端通过局域网连接电脑 MiMoCode，实现实时对话、会话管理、任务监控。

## 功能特性

- 📱 **项目列表** - 显示电脑端已打开的项目，点击进入会话
- 💬 **实时对话** - 流式响应，支持工具执行显示
- 🔔 **胶囊通知** - 可展开/收起，快捷动作按钮
- 🔐 **权限确认** - 三级权限：仅此一次/始终允许/拒绝
- 📊 **系统通知** - 后台/锁屏/全屏应用时的通知

## 项目结构

```
├── mimo-mobile-bridge/
│   ├── plugin/                # 电脑端插件 (TypeScript)
│   │   └── src/
│   │       ├── index.ts       # WebSocket 服务器入口
│   │       ├── handler.ts     # 17 个消息处理器
│   │       └── event-forwarder.ts
│   ├── app/                   # 手机端 App (Flutter)
│   │   └── lib/
│   │       ├── models/        # 数据模型
│   │       ├── services/      # WebSocket/通知服务
│   │       ├── screens/       # 界面
│   │       └── widgets/       # 组件
│   ├── prototype/             # HTML 界面原型
│   └── docs/                  # 设计文档
├── bqb/                       # 表情包资源
└── MiMo-Code/                 # MiMoCode 电脑端源码
```

## 快速开始

### 电脑端插件

```bash
cd mimo-mobile-bridge/plugin
npm install
npm run build
```

### 手机端 App

```bash
cd mimo-mobile-bridge/app
flutter pub get
flutter build apk --release
```

### 连接流程

1. 启动 MiMoCode，加载 `mimo-mobile-bridge` 插件
2. 手机和电脑连接同一 WiFi
3. 手机 App 输入电脑 IP 和配对码（默认 123456）
4. 开始使用

## 技术栈

| 组件 | 技术 |
|------|------|
| 电脑端插件 | TypeScript / Node.js |
| 手机端 App | Flutter / Dart |
| 通信协议 | WebSocket (端口 8765) |
| 数据格式 | JSON |

## 设计文档

- [MiMoCode 架构分析](mimo-mobile-bridge/docs/superpowers/specs/2026-06-27-mimocode-architecture.md)
- [Mobile Bridge 设计文档](mimo-mobile-bridge/docs/superpowers/specs/2026-06-27-mimo-mobile-bridge-design.md)
- [使用方法](mimo-mobile-bridge/USAGE.md)
