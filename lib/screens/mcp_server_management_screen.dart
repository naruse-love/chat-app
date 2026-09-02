import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/mcp/mcp_server_config.dart';
import '../models/mcp/mcp_server_state.dart';
import '../models/mcp/mcp_tool_info.dart';
import '../models/mcp/mcp_transport_type.dart';
import '../models/tool/tool_security_level.dart';
import '../providers/mcp_provider.dart';

/// MCP 服务器管理屏幕
/// 支持查看所有已配置的 MCP Server、实时连接状态、工具探测、启停控制、连接测试与增删改查。
class McpServerManagementScreen extends ConsumerWidget {
  const McpServerManagementScreen({super.key});

  void _showEditDialog(BuildContext context, WidgetRef ref, {McpServerState? serverState}) {
    showDialog(
      context: context,
      builder: (dialogContext) => McpServerEditDialog(
        serverState: serverState,
        onSave: (config, headers) async {
          if (serverState == null) {
            await ref.read(mcpProvider.notifier).addServer(config, headers: headers);
          } else {
            await ref.read(mcpProvider.notifier).updateServer(config, headers: headers);
          }
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref, McpServerConfig config) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除 MCP 服务器'),
        content: Text('确定要删除服务器 "${config.name}" 吗？此操作将断开连接并注销其注入的所有动态工具。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(mcpProvider.notifier).deleteServer(config.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showToolsBottomSheet(BuildContext context, McpServerState serverState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => McpToolsBottomSheet(serverState: serverState),
    );
  }

  Future<void> _handleTestConnection(BuildContext context, WidgetRef ref, McpServerConfig config) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在测试连接...'),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await ref.read(mcpProvider.notifier).testConnection(config);
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    if (result.isConnected) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '连接测试成功！发现 ${result.toolCount} 个工具'
            '${result.resourceCount > 0 ? "，${result.resourceCount} 个资源" : ""}'
            '${result.promptCount > 0 ? "，${result.promptCount} 个提示词模板" : ""}',
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? '测试连接失败'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mcpState = ref.watch(mcpProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加服务器',
            onPressed: () => _showEditDialog(context, ref),
          ),
        ],
      ),
      body: mcpState.isLoading && mcpState.servers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : mcpState.servers.isEmpty
              ? _buildEmptyState(context, ref, theme)
              : _buildServerList(context, ref, mcpState, theme),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加服务器',
        onPressed: () => _showEditDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无 MCP 服务器配置',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮添加 MCP 服务，支持 SSE、WebSocket 与 Stdio 传输通道',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showEditDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('添加服务'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerList(
    BuildContext context,
    WidgetRef ref,
    McpState mcpState,
    ThemeData theme,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: mcpState.servers.length,
      itemBuilder: (context, index) {
        final serverState = mcpState.servers[index];
        final config = serverState.config;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: serverState.isConnected
                  ? Colors.green.withValues(alpha: 0.5)
                  : (serverState.hasError
                      ? Colors.red.withValues(alpha: 0.4)
                      : theme.colorScheme.outlineVariant),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showToolsBottomSheet(context, serverState),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildTransportIcon(config.transportType, serverState.status, theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                config.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildTransportBadge(config.transportType),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getEndpointDescription(config),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildStatusChip(serverState, theme),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: config.isEnabled,
                    onChanged: (value) {
                      ref.read(mcpProvider.notifier).toggleServerEnabled(config.id, value);
                    },
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (value) async {
                      if (value == 'connect') {
                        ref.read(mcpProvider.notifier).connectServer(config.id);
                      } else if (value == 'disconnect') {
                        ref.read(mcpProvider.notifier).disconnectServer(config.id);
                      } else if (value == 'test') {
                        await _handleTestConnection(context, ref, config);
                      } else if (value == 'tools') {
                        _showToolsBottomSheet(context, serverState);
                      } else if (value == 'edit') {
                        _showEditDialog(context, ref, serverState: serverState);
                      } else if (value == 'delete') {
                        _showDeleteConfirmation(context, ref, config);
                      }
                    },
                    itemBuilder: (context) => [
                      if (serverState.status != McpConnectionStatus.connected)
                        const PopupMenuItem(
                          value: 'connect',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow, size: 18, color: Colors.green),
                              SizedBox(width: 8),
                              Text('连接'),
                            ],
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'disconnect',
                          child: Row(
                            children: [
                              Icon(Icons.stop, size: 18, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('断开'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'test',
                        child: Row(
                          children: [
                            Icon(Icons.network_check, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('测试连接'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'tools',
                        child: Row(
                          children: [
                            Icon(Icons.build_circle_outlined, size: 18, color: Colors.deepPurple),
                            SizedBox(width: 8),
                            Text('查看工具'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransportIcon(
    McpTransportType transport,
    McpConnectionStatus status,
    ThemeData theme,
  ) {
    IconData iconData;
    Color iconColor;

    switch (transport) {
      case McpTransportType.stdio:
        iconData = Icons.terminal;
        iconColor = Colors.teal;
        break;
      case McpTransportType.sse:
        iconData = Icons.rss_feed;
        iconColor = Colors.deepOrange;
        break;
      case McpTransportType.websocket:
        iconData = Icons.sync_alt;
        iconColor = Colors.blue;
        break;
      case McpTransportType.http:
        iconData = Icons.http;
        iconColor = Colors.purple;
        break;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }

  Widget _buildTransportBadge(McpTransportType transport) {
    String label;
    Color color;

    switch (transport) {
      case McpTransportType.stdio:
        label = 'Stdio';
        color = Colors.teal;
        break;
      case McpTransportType.sse:
        label = 'SSE';
        color = Colors.deepOrange;
        break;
      case McpTransportType.websocket:
        label = 'WebSocket';
        color = Colors.blue;
        break;
      case McpTransportType.http:
        label = 'HTTP';
        color = Colors.purple;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _getEndpointDescription(McpServerConfig config) {
    switch (config.transportType) {
      case McpTransportType.stdio:
        final cmd = config.command ?? '';
        final args = config.arguments?.join(' ') ?? '';
        return '$cmd $args'.trim();
      case McpTransportType.sse:
      case McpTransportType.websocket:
      case McpTransportType.http:
        return config.url ?? '';
    }
  }

  Widget _buildStatusChip(McpServerState serverState, ThemeData theme) {
    switch (serverState.status) {
      case McpConnectionStatus.connected:
        final countText = serverState.toolCount > 0
            ? ' · ${serverState.toolCount} 个工具'
            : '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 13, color: Colors.green),
              const SizedBox(width: 4),
              Text(
                '已连接$countText',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        );
      case McpConnectionStatus.connecting:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
              ),
              SizedBox(width: 4),
              Text(
                '连接中...',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        );
      case McpConnectionStatus.error:
        final tooltip = serverState.errorMessage ?? '未知错误';
        return Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '连接失败: $tooltip',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      case McpConnectionStatus.disconnected:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause_circle_outline, size: 13, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text(
                '未连接',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// MCP Server 添加 / 编辑对话框
class McpServerEditDialog extends ConsumerStatefulWidget {
  final McpServerState? serverState;
  final Future<void> Function(McpServerConfig config, Map<String, String>? headers) onSave;

  const McpServerEditDialog({
    super.key,
    this.serverState,
    required this.onSave,
  });

  @override
  ConsumerState<McpServerEditDialog> createState() => _McpServerEditDialogState();
}

class _McpServerEditDialogState extends ConsumerState<McpServerEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _headersController;
  late final TextEditingController _commandController;
  late final TextEditingController _argumentsController;
  late final TextEditingController _workingDirController;
  late final TextEditingController _envController;

  late McpTransportType _transportType;
  late ToolSecurityLevel _defaultSecurityLevel;
  late bool _autoConnect;
  late bool _isEnabled;

  bool _isTesting = false;
  String? _testResultNotice;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final config = widget.serverState?.config;

    _nameController = TextEditingController(text: config?.name ?? '');
    _urlController = TextEditingController(text: config?.url ?? '');
    _headersController = TextEditingController(
      text: config?.headers != null && config!.headers!.isNotEmpty
          ? jsonEncode(config.headers)
          : '',
    );
    _commandController = TextEditingController(text: config?.command ?? '');
    _argumentsController = TextEditingController(
      text: config?.arguments != null ? config!.arguments!.join(' ') : '',
    );
    _workingDirController = TextEditingController(text: config?.workingDirectory ?? '');
    _envController = TextEditingController(
      text: config?.environment != null && config!.environment!.isNotEmpty
          ? jsonEncode(config.environment)
          : '',
    );

    _transportType = config?.transportType ?? McpTransportType.sse;
    _defaultSecurityLevel = config?.defaultSecurityLevel ?? ToolSecurityLevel.readOnly;
    _autoConnect = config?.autoConnect ?? true;
    _isEnabled = config?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _commandController.dispose();
    _argumentsController.dispose();
    _workingDirController.dispose();
    _envController.dispose();
    super.dispose();
  }

  Map<String, String>? _parseHeaders() {
    final text = _headersController.text.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        final k = line.substring(0, idx).trim();
        final v = line.substring(idx + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map.isNotEmpty ? map : null;
  }

  Map<String, String>? _parseEnv() {
    final text = _envController.text.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        final k = line.substring(0, idx).trim();
        final v = line.substring(idx + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map.isNotEmpty ? map : null;
  }

  List<String>? _parseArguments() {
    final text = _argumentsController.text.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    final args = <String>[];
    final regex = RegExp(r'''[^\s"']+|"([^"]*)"|'([^']*)'|`([^`]*)`''');
    for (final m in regex.allMatches(text)) {
      final match = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(0);
      if (match != null && match.isNotEmpty) {
        args.add(match);
      }
    }
    return args.isNotEmpty ? args : null;
  }

  McpServerConfig _buildConfig() {
    final id = widget.serverState?.config.id ?? const Uuid().v4();
    final now = DateTime.now();

    return McpServerConfig(
      id: id,
      name: _nameController.text.trim(),
      transportType: _transportType,
      command: _transportType == McpTransportType.stdio ? _commandController.text.trim() : null,
      arguments: _transportType == McpTransportType.stdio ? _parseArguments() : null,
      workingDirectory: _transportType == McpTransportType.stdio && _workingDirController.text.trim().isNotEmpty
          ? _workingDirController.text.trim()
          : null,
      environment: _transportType == McpTransportType.stdio ? _parseEnv() : null,
      url: _transportType != McpTransportType.stdio ? _urlController.text.trim() : null,
      headers: _transportType != McpTransportType.stdio ? _parseHeaders() : null,
      isEnabled: _isEnabled,
      autoConnect: _autoConnect,
      defaultSecurityLevel: _defaultSecurityLevel,
      createdAt: widget.serverState?.config.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResultNotice = null;
    });

    final tempConfig = _buildConfig();
    final headers = _parseHeaders();

    final result = await ref.read(mcpProvider.notifier).testConnection(tempConfig, headers: headers);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _testSuccess = result.isConnected;
      if (result.isConnected) {
        _testResultNotice = '连接成功！已探测到 ${result.toolCount} 个工具'
            '${result.resourceCount > 0 ? "，${result.resourceCount} 个资源" : ""}'
            '${result.promptCount > 0 ? "，${result.promptCount} 个提示词" : ""}';
      } else {
        _testResultNotice = result.errorMessage ?? '连接失败';
      }
    });
  }

  void _showImportJsonDialog(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.code, size: 20),
            SizedBox(width: 8),
            Text('导入 JSON 配置'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持粘贴 Claude / Cursor / OpenCode 或标准 MCP 配置 JSON：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: '{\n  "servers": {\n    "websearch": {\n      "type": "http",\n      "url": "http://10.0.0.103:8338/mcp"\n    }\n  }\n}',
                border: OutlineInputBorder(),
              ),
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isNotEmpty) {
                _parseAndApplyJson(raw);
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('解析导入'),
          ),
        ],
      ),
    );
  }

  void _parseAndApplyJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return;

      Map<String, dynamic> target = Map<String, dynamic>.from(decoded);

      // 支持 {"servers": {"name": {...}}} 或 {"mcpServers": {"name": {...}}}
      String? parsedName;
      if (target.containsKey('servers') && target['servers'] is Map) {
        final sMap = target['servers'] as Map;
        if (sMap.isNotEmpty) {
          parsedName = sMap.keys.first.toString();
          target = Map<String, dynamic>.from(sMap[parsedName] as Map);
        }
      } else if (target.containsKey('mcpServers') && target['mcpServers'] is Map) {
        final sMap = target['mcpServers'] as Map;
        if (sMap.isNotEmpty) {
          parsedName = sMap.keys.first.toString();
          target = Map<String, dynamic>.from(sMap[parsedName] as Map);
        }
      }

      final name = parsedName ?? target['name']?.toString();
      if (name != null && name.isNotEmpty) {
        _nameController.text = name;
      }

      final rawType = target['type']?.toString().toLowerCase();
      if (rawType != null) {
        if (rawType == 'http' || rawType == 'streamable-http' || rawType == 'streamable_http') {
          _transportType = McpTransportType.http;
        } else if (rawType == 'sse') {
          _transportType = McpTransportType.sse;
        } else if (rawType == 'ws' || rawType == 'websocket') {
          _transportType = McpTransportType.websocket;
        } else if (rawType == 'stdio') {
          _transportType = McpTransportType.stdio;
        }
      } else {
        if (target.containsKey('url')) {
          final url = target['url'].toString();
          if (url.startsWith('ws://') || url.startsWith('wss://')) {
            _transportType = McpTransportType.websocket;
          } else if (url.endsWith('/mcp')) {
            _transportType = McpTransportType.http;
          } else {
            _transportType = McpTransportType.sse;
          }
        } else if (target.containsKey('command')) {
          _transportType = McpTransportType.stdio;
        }
      }

      if (target.containsKey('url')) {
        _urlController.text = target['url'].toString();
      }
      if (target.containsKey('command')) {
        _commandController.text = target['command'].toString();
      }
      if (target.containsKey('args')) {
        final args = target['args'];
        if (args is List) {
          _argumentsController.text = args.map((e) => e.toString()).join(' ');
        } else {
          _argumentsController.text = args.toString();
        }
      } else if (target.containsKey('arguments')) {
        final args = target['arguments'];
        if (args is List) {
          _argumentsController.text = args.map((e) => e.toString()).join(' ');
        } else {
          _argumentsController.text = args.toString();
        }
      }
      if (target.containsKey('headers') && target['headers'] is Map) {
        _headersController.text = jsonEncode(target['headers']);
      }
      if (target.containsKey('env') && target['env'] is Map) {
        _envController.text = jsonEncode(target['env']);
      }

      setState(() {
        _testResultNotice = null;
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final config = _buildConfig();
    final headers = _parseHeaders();

    Navigator.pop(context);
    await widget.onSave(config, headers);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.serverState != null;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_note : Icons.add_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEditing ? '编辑 MCP 服务器' : '添加 MCP 服务器',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: '导入 JSON 配置',
                    onPressed: () => _showImportJsonDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '服务器名称 *',
                          hintText: '例如: Filesystem / Brave Search',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入服务器名称';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<McpTransportType>(
                        initialValue: _transportType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '传输通道类型 *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: McpTransportType.http,
                            child: Text('HTTP / Streamable HTTP (/mcp)'),
                          ),
                          DropdownMenuItem(
                            value: McpTransportType.sse,
                            child: Text('Server-Sent Events (SSE)'),
                          ),
                          DropdownMenuItem(
                            value: McpTransportType.websocket,
                            child: Text('WebSocket'),
                          ),
                          DropdownMenuItem(
                            value: McpTransportType.stdio,
                            child: Text('标准进程 (Stdio)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _transportType = value;
                              _testResultNotice = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // HTTP / SSE / WebSocket fields
                      if (_transportType == McpTransportType.http ||
                          _transportType == McpTransportType.sse ||
                          _transportType == McpTransportType.websocket) ...[
                        TextFormField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: _transportType == McpTransportType.http
                                ? 'HTTP 服务端点 URL *'
                                : (_transportType == McpTransportType.sse
                                    ? 'SSE 服务端点 URL *'
                                    : 'WebSocket 服务端点 URL *'),
                            hintText: _transportType == McpTransportType.http
                                ? '例如: http://10.0.0.103:8338/mcp'
                                : (_transportType == McpTransportType.sse
                                    ? '例如: http://127.0.0.1:8000/sse'
                                    : '例如: ws://127.0.0.1:8080/mcp'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入连接 URL';
                            }
                            final uri = Uri.tryParse(value.trim());
                            if (uri == null || !uri.hasScheme) {
                              return '请输入有效的 URL (包含 http/https/ws/wss 协议头)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _headersController,
                          decoration: const InputDecoration(
                            labelText: '自定义请求头 (Headers，可选)',
                            hintText: 'JSON格式: {"Authorization": "Bearer ..."} 或 Key: Value',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                      ],

                      // Stdio fields
                      if (_transportType == McpTransportType.stdio) ...[
                        TextFormField(
                          controller: _commandController,
                          decoration: const InputDecoration(
                            labelText: '可执行命令 (Command) *',
                            hintText: '例如: npx / node / python / uvx',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入命令路径';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _argumentsController,
                          decoration: const InputDecoration(
                            labelText: '命令行参数 (Arguments，可选)',
                            hintText: '例如: -y @modelcontextprotocol/server-filesystem /tmp',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _workingDirController,
                          decoration: const InputDecoration(
                            labelText: '工作目录 (Working Directory，可选)',
                            hintText: '例如: D:/work/project',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _envController,
                          decoration: const InputDecoration(
                            labelText: '环境变量 (Environment Variables，可选)',
                            hintText: 'JSON格式: {"API_KEY": "xxx"} 或 KEY=VALUE',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                      ],

                      const SizedBox(height: 16),
                      DropdownButtonFormField<ToolSecurityLevel>(
                        initialValue: _defaultSecurityLevel,
                        decoration: const InputDecoration(
                          labelText: '默认工具安全等级',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ToolSecurityLevel.safe,
                            child: Text('安全 Level 0 (免确认)'),
                          ),
                          DropdownMenuItem(
                            value: ToolSecurityLevel.readOnly,
                            child: Text('只读 Level 1 (只读安全)'),
                          ),
                          DropdownMenuItem(
                            value: ToolSecurityLevel.sensitiveConfirm,
                            child: Text('需确认 Level 2 (敏感操作)'),
                          ),
                          DropdownMenuItem(
                            value: ToolSecurityLevel.privilegedNative,
                            child: Text('特权 Level 3 (设备原生)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _defaultSecurityLevel = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('启动时自动连接'),
                        subtitle: const Text('应用启动或加载时自动建立连接并注册工具'),
                        value: _autoConnect,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setState(() {
                            _autoConnect = value;
                          });
                        },
                      ),

                      if (_testResultNotice != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _testSuccess
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _testSuccess
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.red.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _testSuccess ? Icons.check_circle : Icons.error_outline,
                                color: _testSuccess ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testResultNotice!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _testSuccess ? Colors.green[800] : Colors.red[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 16),
                    label: const Text('测试连接'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MCP 已发现工具、资源与 Prompt 查看底部抽屉
class McpToolsBottomSheet extends StatelessWidget {
  final McpServerState serverState;

  const McpToolsBottomSheet({super.key, required this.serverState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = serverState.tools;
    final resources = serverState.resources;
    final prompts = serverState.prompts;

    final hasTabs = resources.isNotEmpty || prompts.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.hub_outlined, color: Colors.deepPurple, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serverState.config.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '状态: ${serverState.status.displayName} · 发现 ${tools.length} 个工具',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              if (tools.isEmpty && resources.isEmpty && prompts.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          serverState.isConnected
                              ? '该 MCP 服务器未暴露任何工具或资源'
                              : '服务器未连接，连接后将自动探测已暴露的工具与资源',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else if (!hasTabs)
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: tools.length,
                    itemBuilder: (context, index) => _buildToolItem(context, tools[index], theme),
                  ),
                )
              else
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: [
                            Tab(text: '工具 (${tools.length})'),
                            Tab(text: '资源 (${resources.length})'),
                            Tab(text: '提示词 (${prompts.length})'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              ListView.builder(
                                controller: scrollController,
                                itemCount: tools.length,
                                itemBuilder: (context, index) =>
                                    _buildToolItem(context, tools[index], theme),
                              ),
                              ListView.builder(
                                itemCount: resources.length,
                                itemBuilder: (context, index) =>
                                    _buildResourceItem(context, resources[index], theme),
                              ),
                              ListView.builder(
                                itemCount: prompts.length,
                                itemBuilder: (context, index) =>
                                    _buildPromptItem(context, prompts[index], theme),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolItem(BuildContext context, McpToolInfo tool, ThemeData theme) {
    final properties = tool.inputSchema['properties'] as Map<String, dynamic>? ?? {};
    final requiredProps = (tool.inputSchema['required'] as List?)?.map((e) => e.toString()).toSet() ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, size: 16, color: Colors.deepPurple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tool.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    serverState.config.defaultSecurityLevel.label,
                    style: const TextStyle(fontSize: 10, color: Colors.deepPurple, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (tool.description != null && tool.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                tool.description!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (properties.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '参数列表 (${properties.length}):',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              ...properties.entries.map((e) {
                final isReq = requiredProps.contains(e.key);
                final propDef = e.value is Map ? e.value as Map : {};
                final type = propDef['type']?.toString() ?? 'any';
                final desc = propDef['description']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ${e.key}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($type)',
                        style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                      ),
                      if (isReq) ...[
                        const SizedBox(width: 4),
                        const Text('*', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                      if (desc.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            desc,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResourceItem(BuildContext context, McpResourceInfo resource, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: Colors.indigo),
        title: Text(resource.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resource.uri, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            if (resource.description != null) Text(resource.description!),
          ],
        ),
        trailing: resource.mimeType != null
            ? Chip(
                label: Text(resource.mimeType!, style: const TextStyle(fontSize: 10)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }

  Widget _buildPromptItem(BuildContext context, McpPromptInfo prompt, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline, color: Colors.teal),
        title: Text(prompt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: prompt.description != null ? Text(prompt.description!) : null,
        trailing: Text('${prompt.arguments.length} 个参数', style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
