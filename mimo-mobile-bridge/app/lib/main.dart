import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/websocket_service.dart';
import 'services/session_service.dart';
import 'services/project_service.dart';
import 'services/notification_service.dart';
// TODO: 安装 flutter_local_notifications 后取消注释
// import 'services/system_notification_service.dart';
import 'screens/connection_screen.dart';
import 'screens/project_list_screen.dart';

/// 应用主入口
///
/// MiMo Mobile - 手机端 AI 编码助手
/// 通过局域网 WebSocket 连接到电脑端运行的 MiMoCode 插件
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: 安装 flutter_local_notifications 后取消注释
  // _initSystemNotifications();
  runApp(const MiMoMobileApp());
}

// TODO: 安装 flutter_local_notifications 后取消注释
// /// 初始化系统通知服务
// void _initSystemNotifications() async {
//   final systemNotification = SystemNotificationService();
//   await systemNotification.initialize();
//   systemNotification.onPermissionAction = (permissionId, reply) {
//     debugPrint('[SystemNotification] 权限操作: $permissionId -> $reply');
//   };
//   systemNotification.onNotificationTap = (sessionId) {
//     debugPrint('[SystemNotification] 点击通知: sessionId=$sessionId');
//   };
// }

/// 应用根 Widget
class MiMoMobileApp extends StatelessWidget {
  const MiMoMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // WebSocket 服务 - 核心通信层，最先注册（非 ChangeNotifier，使用 Provider）
        Provider<WebSocketService>(create: (_) => WebSocketService()),
        // 通知服务 - 依赖 WebSocket，注册胶囊通知管理
        // 在创建时注入 WebSocketService 引用，使通知服务能监听消息并自动生成通知
        ChangeNotifierProvider<NotificationService>(
          create: (ctx) {
            final ws = ctx.read<WebSocketService>();
            final service = NotificationService();
            service.webSocketService = ws;
            return service;
          },
        ),
        // 项目服务
        ChangeNotifierProvider<ProjectService>(
          create: (ctx) => ProjectService(ctx.read<WebSocketService>()),
        ),
        // 会话服务
        ChangeNotifierProvider<SessionService>(
          create: (ctx) => SessionService(ctx.read<WebSocketService>()),
        ),
      ],
      child: MaterialApp(
        title: 'MiMo Mobile',
        debugShowCheckedModeBanner: false,
        theme: _buildDarkTheme(),
        home: const _AppEntrance(),
      ),
    );
  }

  /// 构建暗色主题
  ///
  /// 设计规范：
  /// - 背景 #0a0a0f
  /// - 卡片 #1a1a25
  /// - 主色调：蓝色 #4f8cff 和紫色 #a855f7 渐变
  ThemeData _buildDarkTheme() {
    const backgroundColor = Color(0xFF0A0A0F);
    const cardColor = Color(0xFF1A1A25);
    const primaryColor = Color(0xFF4F8CFF);
    const accentColor = Color(0xFFA855F7);

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: cardColor,
        background: backgroundColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primaryColor, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryColor),
      ),
      dividerTheme:
          const DividerThemeData(color: Color(0x14FFFFFF), thickness: 1),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Color(0xFFE0E0E8)),
        bodySmall: TextStyle(color: Color(0xFF8B8B9E)),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: Color(0xFF8B8B9E)),
      ),
    );
  }
}

/// 应用入口判断
///
/// 根据本地是否保存连接信息决定显示连接设置界面还是项目列表
class _AppEntrance extends StatefulWidget {
  const _AppEntrance();

  @override
  State<_AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<_AppEntrance> {
  bool _initialized = false;
  bool _hasConnection = false;

  @override
  void initState() {
    super.initState();
    _checkSavedConnection();
  }

  /// 检查本地保存的连接信息
  Future<void> _checkSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('host');
      final port = prefs.getInt('port');
      final pairingCode = prefs.getString('pairingCode');

      final hasConnection = host != null &&
          host.isNotEmpty &&
          port != null &&
          pairingCode != null &&
          pairingCode.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _hasConnection = hasConnection;
        _initialized = true;
      });

      // 如果有保存的连接信息，自动尝试连接
      if (hasConnection) {
        _tryAutoConnect(host!, port, pairingCode!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _hasConnection = false;
      });
    }
  }

  /// 尝试自动连接已保存的服务器
  Future<void> _tryAutoConnect(String host, int port, String pairingCode) async {
    if (!mounted) return;
    final ws = context.read<WebSocketService>();
    try {
      await ws.connect(host: host, port: port, pairingCode: pairingCode);
    } catch (_) {
      // 自动连接失败时，留在项目列表界面让用户手动重连
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _hasConnection ? const ProjectListScreen() : const ConnectionScreen();
  }
}
