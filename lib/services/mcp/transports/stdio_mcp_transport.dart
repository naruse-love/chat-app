import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

/// 基于本地子进程标准输入输出（Stdio）的 MCP 传输通道实现
class StdioMcpTransport implements McpTransport {
  final String command;
  final List<String> arguments;
  final Map<String, String>? environment;
  final String? workingDirectory;
  final ProcessStarter _processStarter;

  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _isClosed = false;

  StdioMcpTransport({
    required this.command,
    this.arguments = const [],
    this.environment,
    this.workingDirectory,
    ProcessStarter? processStarter,
  }) : _processStarter = processStarter ?? Process.start;

  @override
  McpTransportType get transportType => McpTransportType.stdio;

  @override
  McpConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == McpConnectionStatus.connected;

  @override
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void _setStatus(McpConnectionStatus newStatus) {
    if (_status != newStatus && !_isClosed) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw StateError('Cannot connect a closed StdioMcpTransport');
    }
    if (_status == McpConnectionStatus.connected ||
        _status == McpConnectionStatus.connecting) {
      return;
    }

    // 平台沙箱约束检测：移动端（iOS / Android）不支持 Process.start
    if (Platform.isAndroid || Platform.isIOS) {
      _setStatus(McpConnectionStatus.error);
      throw UnsupportedError(
        'Stdio 传输仅支持桌面操作系统（Windows, macOS, Linux），移动端沙箱不支持子进程启动，请使用 SSE 或 WebSocket 传输',
      );
    }

    _setStatus(McpConnectionStatus.connecting);

    try {
      _process = await _processStarter(
        command,
        arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        runInShell: Platform.isWindows,
      );

      _setStatus(McpConnectionStatus.connected);

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is Map<String, dynamic>) {
                _messageController.add(decoded);
              }
            } catch (_) {
              // 忽略非 JSON 行（例如子进程自定义输出的日志）
            }
          }
        },
        onError: (error) {
          _setStatus(McpConnectionStatus.error);
        },
        onDone: () {
          if (!_isClosed) {
            _setStatus(McpConnectionStatus.disconnected);
          }
        },
        cancelOnError: true,
      );

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((errLine) {
        // 可记录 stderr 日志
      });

      _process!.exitCode.then((code) {
        if (!_isClosed) {
          if (code != 0) {
            _setStatus(McpConnectionStatus.error);
          } else {
            _setStatus(McpConnectionStatus.disconnected);
          }
        }
      });
    } catch (e) {
      _setStatus(McpConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_isClosed) {
      throw StateError('StdioMcpTransport is closed');
    }
    if (_status != McpConnectionStatus.connected || _process == null) {
      throw StateError('StdioMcpTransport is not connected');
    }

    final jsonString = jsonEncode(message);
    _process!.stdin.writeln(jsonString);
    await _process!.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _setStatus(McpConnectionStatus.disconnected);
    _isClosed = true;

    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;

    try {
      _process?.kill();
    } catch (_) {}
    _process = null;

    await _statusController.close();
    await _messageController.close();
  }
}
