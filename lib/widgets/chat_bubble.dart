import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import 'markdown_renderer.dart';

class _ToolMeta {
  final String displayName;
  final String category;
  final IconData icon;
  final String securityLevelBadge;
  final Color categoryColor;

  const _ToolMeta({
    required this.displayName,
    required this.category,
    required this.icon,
    required this.securityLevelBadge,
    required this.categoryColor,
  });
}

_ToolMeta _getToolMetadata(String toolName) {
  switch (toolName) {
    case 'math_eval':
      return const _ToolMeta(
        displayName: '数学计算',
        category: '基础计算',
        icon: Icons.calculate,
        securityLevelBadge: '安全 Level 0',
        categoryColor: Colors.teal,
      );
    case 'time_calculator':
      return const _ToolMeta(
        displayName: '时间/时区计算',
        category: '时间工具',
        icon: Icons.schedule,
        securityLevelBadge: '安全 Level 0',
        categoryColor: Colors.indigo,
      );
    case 'weather_query':
      return const _ToolMeta(
        displayName: '天气查询',
        category: '生活服务',
        icon: Icons.cloud,
        securityLevelBadge: '安全 Level 0',
        categoryColor: Colors.amber,
      );
    case 'wiki_lookup':
      return const _ToolMeta(
        displayName: '维基百科检索',
        category: '知识检索',
        icon: Icons.menu_book,
        securityLevelBadge: '安全 Level 0',
        categoryColor: Colors.purple,
      );
    case 'web_search':
      return const _ToolMeta(
        displayName: '网络搜索',
        category: '搜索引擎',
        icon: Icons.travel_explore,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.blue,
      );
    case 'google_search':
      return const _ToolMeta(
        displayName: 'Google 搜索',
        category: '搜索引擎',
        icon: Icons.travel_explore,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.redAccent,
      );
    case 'bing_search':
      return const _ToolMeta(
        displayName: 'Bing 搜索',
        category: '搜索引擎',
        icon: Icons.travel_explore,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.cyan,
      );
    case 'url_fetch':
      return const _ToolMeta(
        displayName: '网页抓取',
        category: '网页内容',
        icon: Icons.language,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.green,
      );
    case 'file_read':
      return const _ToolMeta(
        displayName: '沙箱文件读取',
        category: '文件系统',
        icon: Icons.file_open,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.blueGrey,
      );
    case 'file_write':
      return const _ToolMeta(
        displayName: '沙箱文件写入',
        category: '文件系统',
        icon: Icons.edit_document,
        securityLevelBadge: '需确认 Level 2',
        categoryColor: Colors.deepOrange,
      );
    case 'file_list':
      return const _ToolMeta(
        displayName: '沙箱目录列表',
        category: '文件系统',
        icon: Icons.folder,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.brown,
      );
    case 'file_delete':
      return const _ToolMeta(
        displayName: '沙箱文件删除',
        category: '文件系统',
        icon: Icons.delete_forever,
        securityLevelBadge: '需确认 Level 2',
        categoryColor: Colors.red,
      );
    case 'code_eval':
      return const _ToolMeta(
        displayName: '代码沙箱执行',
        category: '代码执行',
        icon: Icons.terminal,
        securityLevelBadge: '需确认 Level 2',
        categoryColor: Colors.deepPurple,
      );
    case 'clipboard_read':
      return const _ToolMeta(
        displayName: '读取剪贴板',
        category: '系统交互',
        icon: Icons.content_paste,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Colors.lightBlue,
      );
    case 'clipboard_write':
      return const _ToolMeta(
        displayName: '写入剪贴板',
        category: '系统交互',
        icon: Icons.content_copy,
        securityLevelBadge: '需确认 Level 2',
        categoryColor: Colors.orange,
      );
    // === Milestone 25: Native Privileged Tools ===
    case 'calendar_query_events':
      return const _ToolMeta(
        displayName: '查询日程',
        category: '设备日历',
        icon: Icons.calendar_month,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'calendar_create_event':
      return const _ToolMeta(
        displayName: '创建日程',
        category: '设备日历',
        icon: Icons.event_available,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'notification_schedule':
      return const _ToolMeta(
        displayName: '设置通知',
        category: '系统通知',
        icon: Icons.notification_add,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'notification_cancel':
      return const _ToolMeta(
        displayName: '取消通知',
        category: '系统通知',
        icon: Icons.notifications_off,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'contacts_search':
      return const _ToolMeta(
        displayName: '搜索通讯录',
        category: '设备通讯录',
        icon: Icons.contacts,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'geolocation_get':
      return const _ToolMeta(
        displayName: '获取当前定位',
        category: '设备定位',
        icon: Icons.my_location,
        securityLevelBadge: '特权 Level 3',
        categoryColor: Color(0xFFC62828),
      );
    case 'reverse_geocode':
      return const _ToolMeta(
        displayName: '地理逆编码',
        category: '地理服务',
        icon: Icons.pin_drop,
        securityLevelBadge: '只读 Level 1',
        categoryColor: Color(0xFF1976D2),
      );
    default:
      if (toolName.startsWith('mcp_')) {
        final cleanName = toolName.replaceFirst('mcp_', '');
        return _ToolMeta(
          displayName: 'MCP: $cleanName',
          category: 'MCP 扩展工具',
          icon: Icons.hub_outlined,
          securityLevelBadge: 'MCP',
          categoryColor: Colors.deepPurple,
        );
      }
      return _ToolMeta(
        displayName: toolName,
        category: '自定义工具',
        icon: Icons.extension,
        securityLevelBadge: '工具',
        categoryColor: Colors.grey,
      );
  }
}

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onImageTap;
  final bool isStreaming;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRollbackToHere;

  const ChatBubble({
    super.key,
    required this.message,
    this.onImageTap,
    this.isStreaming = false,
    this.onEdit,
    this.onRegenerate,
    this.onRollbackToHere,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isReasoningExpanded = false;
  bool _isToolOutputExpanded = false;

  String _stripMarkdown(String markdown) {
    // 1. Remove code blocks
    var txt = markdown.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // 2. Remove inline code backticks
    txt = txt.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    // 3. Remove bold/italic markers
    txt = txt.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    txt = txt.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    txt = txt.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
    txt = txt.replaceAll(RegExp(r'_([^_]+)_'), r'$1');
    // 4. Remove headers (e.g., # Header)
    txt = txt.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');
    // 5. Remove markdown links, keep only text. E.g. [text](url) -> text
    txt = txt.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    // 6. Remove blockquotes, horizontal rules, lists
    txt = txt.replaceAll(RegExp(r'^>\s+', multiLine: true), '');
    txt = txt.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    txt = txt.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    // 7. Collapse multiple newlines
    txt = txt.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return txt.trim();
  }

  void _showMessageActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('自由选择文本'),
              onTap: () {
                Navigator.pop(context);
                _showTextSelectionDialog(context, widget.message.content);
              },
            ),
            if (widget.message.role == 'user')
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制文本'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: widget.message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制文本'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            if (widget.message.role == 'assistant') ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制纯文本'),
                onTap: () {
                  Navigator.pop(context);
                  final plainText = _stripMarkdown(widget.message.content);
                  Clipboard.setData(ClipboardData(text: plainText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制纯文本'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('复制 Markdown'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: widget.message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制 Markdown'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
            if (widget.message.role == 'user' && widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑消息'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onEdit!();
                },
              ),
            if (widget.onRegenerate != null &&
                (widget.message.role == 'assistant' || widget.message.role == 'user'))
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新生成回答'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onRegenerate!();
                },
              ),
            if (widget.message.role == 'assistant' && widget.onRollbackToHere != null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('从此处回退（删除后续消息）'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onRollbackToHere!();
                },
              ),
            if (widget.message.role == 'user' && widget.onRollbackToHere != null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('从此处回退（删除后续消息）'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onRollbackToHere!();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showTextSelectionDialog(BuildContext context, String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自由选择与复制文本'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '(无文本内容)' : text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final isTool = widget.message.role == 'tool';
    final isIntermediateAssistant = widget.message.role == 'assistant' &&
        widget.message.toolCalls != null &&
        widget.message.toolCalls!.isNotEmpty;
    final theme = Theme.of(context);
    
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : ((isTool || isIntermediateAssistant)
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest);
    final textColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return GestureDetector(
      onLongPress: _showMessageActions,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
        alignment: alignment,
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isTool)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Text(
                  '工具输出: ${widget.message.toolCallId ?? ""}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            
            if (widget.message.imagePath != null &&
                widget.message.imagePath!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: _buildImageThumbnail(context),
              ),

            Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      widget.message.content,
                      style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                    )
                  else if (isTool)
                    _buildToolOutputPanel(theme, theme.textTheme.bodyLarge?.copyWith(color: textColor))
                  else if (isIntermediateAssistant)
                    _buildIntermediateAssistantPanel(theme, theme.textTheme.bodyLarge?.copyWith(color: textColor))
                  else ...[
                    if (widget.message.reasoningContent != null &&
                        widget.message.reasoningContent!.isNotEmpty) ...[
                      _buildReasoningPanel(theme),
                      const SizedBox(height: 8.0),
                    ],
                    MarkdownRenderer(
                      markdownData: widget.message.content,
                      isStreaming: widget.isStreaming,
                      textColor: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                    ),
                  ],
                ],
              ),
            ),
            
            // Token usage display
            if (widget.message.role == 'assistant' &&
                (widget.message.promptTokens != null || widget.message.completionTokens != null))
              Padding(
                padding: const EdgeInsets.only(top: 2.0, left: 8.0, right: 8.0),
                child: Text(
                  '🪙 ${widget.message.promptTokens ?? "?"}↑ / ${widget.message.completionTokens ?? "?"}↓',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.only(top: 2.0, left: 8.0, right: 8.0),
              child: Text(
                _formatTimestamp(widget.message.timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context) {
    final imagePath = widget.message.imagePath!;
    final isLocal = !imagePath.startsWith('http') && !imagePath.startsWith('data:');
    
    Widget imageWidget;
    if (isLocal) {
      imageWidget = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 150,
          height: 150,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else if (imagePath.startsWith('data:image/')) {
      try {
        final uri = Uri.parse(imagePath);
        final bytes = uri.data?.contentAsBytes();
        if (bytes != null) {
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 150,
              height: 150,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          );
        } else {
          throw Exception("Could not parse base64 bytes");
        }
      } catch (e) {
        imageWidget = Container(
          width: 150,
          height: 150,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      }
    } else {
      imageWidget = Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 150,
          height: 150,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onImageTap,
      child: Hero(
        tag: 'hero-${widget.message.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 200,
              maxHeight: 200,
            ),
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.brightness == Brightness.light
            ? Colors.grey[100]
            : Colors.grey[900],
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            width: 3.0,
          ),
        ),
      ),
      margin: const EdgeInsets.only(bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isReasoningExpanded = !_isReasoningExpanded;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.psychology,
                        size: 16.0,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        '思考过程',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        _isReasoningExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16.0,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.copy,
                      size: 16.0,
                      color: theme.colorScheme.outline,
                    ),
                    tooltip: '复制思考内容',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.message.reasoningContent!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制思考内容'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
              child: SelectableText(
                widget.message.reasoningContent!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            crossFadeState: _isReasoningExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildIntermediateAssistantPanel(ThemeData theme, TextStyle? textColor) {
    final toolLabels = widget.message.toolCalls
            ?.map((tc) => _getToolMetadata(tc.functionName).displayName)
            .toSet()
            .join(', ') ??
        '';
    final summaryTitle = toolLabels.isNotEmpty
        ? toolLabels
        : (widget.message.toolCalls?.map((tc) => tc.functionName).join(', ') ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isReasoningExpanded = !_isReasoningExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16.0,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6.0),
                Flexible(
                  child: Text(
                    '思考与工具调用 [$summaryTitle]',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4.0),
                Icon(
                  _isReasoningExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16.0,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message.toolCalls != null &&
                    widget.message.toolCalls!.isNotEmpty) ...[
                  Text(
                    '工具调用指令:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final tc in widget.message.toolCalls!) ...[
                    _buildToolCallCard(theme, tc),
                  ],
                  const SizedBox(height: 8),
                ],
                if (widget.message.reasoningContent != null &&
                    widget.message.reasoningContent!.isNotEmpty) ...[
                  Text(
                    '思考过程:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    width: double.infinity,
                    child: Text(
                      widget.message.reasoningContent!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.message.content.isNotEmpty) ...[
                  Text(
                    '过程输出:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MarkdownRenderer(
                    markdownData: widget.message.content,
                    isStreaming: widget.isStreaming,
                    textColor: theme.textTheme.bodyMedium?.copyWith(color: textColor?.color),
                  ),
                ],
              ],
            ),
          ),
          crossFadeState: _isReasoningExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildToolCallCard(ThemeData theme, dynamic tc) {
    final funcName = tc.functionName as String;
    final args = tc.arguments as String;
    final meta = _getToolMetadata(funcName);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(
          color: meta.categoryColor.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                meta.icon,
                size: 15.0,
                color: meta.categoryColor,
              ),
              const SizedBox(width: 6.0),
              Text(
                meta.displayName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
                decoration: BoxDecoration(
                  color: meta.categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  meta.category,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: meta.categoryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  meta.securityLevelBadge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: SelectableText(
              '$funcName($args)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolOutputPanel(ThemeData theme, TextStyle? textColor) {
    return Container(
      margin: const EdgeInsets.only(top: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isToolOutputExpanded = !_isToolOutputExpanded;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.build_circle_outlined,
                        size: 16.0,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        '工具执行结果',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        _isToolOutputExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16.0,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.copy,
                      size: 16.0,
                      color: theme.colorScheme.outline,
                    ),
                    tooltip: '复制结果',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制工具执行结果'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
              child: MarkdownRenderer(
                markdownData: widget.message.content,
                isStreaming: widget.isStreaming,
                textColor: textColor,
              ),
            ),
            crossFadeState: _isToolOutputExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

