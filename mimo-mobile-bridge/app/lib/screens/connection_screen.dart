import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/websocket_service.dart';
import 'project_list_screen.dart';

/// 连接设置界面
///
/// 用于配置 WebSocket 服务器地址、端口和配对码
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8765');
  final _pairingCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isConnecting = false;
  bool _obscureCode = true;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  /// 加载已保存的配置
  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hostController.text = prefs.getString('host') ?? '';
      _portController.text =
          (prefs.getInt('port') ?? 8765).toString();
      _pairingCodeController.text = prefs.getString('pairingCode') ?? '';
    });
  }

  /// 保存配置到本地
  Future<void> _saveConfig(String host, int port, String pairingCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', host);
    await prefs.setInt('port', port);
    await prefs.setString('pairingCode', pairingCode);
  }

  /// 清除已保存的配置
  Future<void> _clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('host');
    await prefs.remove('port');
    await prefs.remove('pairingCode');
  }

  /// 处理连接
  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8765;
    final pairingCode = _pairingCodeController.text.trim();

    setState(() {
      _isConnecting = true;
    });

    try {
      final ws = context.read<WebSocketService>();

      // 订阅状态变化（NotificationService 已在 main.dart 中注入 WebSocket 引用）
      bool? authSuccess;
      final stateSub = ws.stateStream.listen((state) {
        if (state == WebSocketConnectionState.ready) {
          authSuccess = true;
        }
      });

      await ws.connect(
        host: host,
        port: port,
        pairingCode: pairingCode,
      );

      // 等待认证结果（最多 8 秒）
      int waited = 0;
      while (authSuccess != true && waited < 8000) {
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }
      stateSub.cancel();

      if (authSuccess == true) {
        await _saveConfig(host, port, pairingCode);

        if (!mounted) return;
        // 连接成功，替换为项目列表界面
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProjectListScreen()),
        );
      } else {
        // 认证失败
        if (!mounted) return;
        _showError('连接超时或认证失败，请检查配对码是否正确');
        ws.disconnect();
      }
    } catch (e) {
      if (!mounted) return;
      _showError('连接失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  /// 显示错误提示
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF4757),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 40),
                _buildForm(),
                const SizedBox(height: 32),
                _buildConnectButton(),
                const SizedBox(height: 16),
                _buildClearButton(),
                const SizedBox(height: 32),
                _buildHelpSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建头部
  Widget _buildHeader() {
    return Column(
      children: [
        // Logo
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F8CFF).withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'M',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'MiMo Mobile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '手机端 AI 编码助手',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '连接到电脑端 MiMoCode 插件',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 构建表单
  Widget _buildForm() {
    return Column(
      children: [
        // IP 地址
        TextFormField(
          controller: _hostController,
          decoration: const InputDecoration(
            hintText: '例如: 192.168.1.100',
            labelText: '服务器 IP 地址',
            prefixIcon: Icon(Icons.dns_outlined),
          ),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入服务器 IP 地址';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // 端口
        TextFormField(
          controller: _portController,
          decoration: const InputDecoration(
            hintText: '8765',
            labelText: '端口',
            prefixIcon: Icon(Icons.router_outlined),
          ),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入端口号';
            }
            final port = int.tryParse(value.trim());
            if (port == null || port < 1 || port > 65535) {
              return '请输入有效端口号 (1-65535)';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // 配对码
        TextFormField(
          controller: _pairingCodeController,
          decoration: InputDecoration(
            hintText: '请输入配对码',
            labelText: '配对码',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureCode
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () {
                setState(() {
                  _obscureCode = !_obscureCode;
                });
              },
            ),
          ),
          obscureText: _obscureCode,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入配对码';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// 构建连接按钮
  Widget _buildConnectButton() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F8CFF).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isConnecting ? null : _handleConnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: _isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '连接',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  /// 构建清除按钮
  Widget _buildClearButton() {
    return TextButton(
      onPressed: () async {
        await _clearConfig();
        _hostController.clear();
        _portController.text = '8765';
        _pairingCodeController.clear();
      },
      child: Text(
        '清除已保存的配置',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
    );
  }

  /// 构建帮助说明
  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4F8CFF).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFF4F8CFF), size: 16),
              const SizedBox(width: 8),
              const Text(
                '使用说明',
                style: TextStyle(
                  color: Color(0xFF4F8CFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHelpStep('1', '在电脑端启动 MiMoCode 并安装 mimo-mobile-bridge 插件'),
          const SizedBox(height: 8),
          _buildHelpStep('2', '在电脑端查看插件显示的 IP 地址和配对码'),
          const SizedBox(height: 8),
          _buildHelpStep('3', '确保手机和电脑在同一局域网'),
          const SizedBox(height: 8),
          _buildHelpStep('4', '输入信息并点击连接'),
        ],
      ),
    );
  }

  /// 构建帮助步骤
  Widget _buildHelpStep(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4F8CFF).withValues(alpha: 0.2),
          ),
          child: Center(
            child: Text(
              num,
              style: const TextStyle(
                color: Color(0xFF4F8CFF),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
