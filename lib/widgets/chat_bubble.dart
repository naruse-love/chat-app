import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'markdown_renderer.dart';

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

  void _showMessageActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
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

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final isTool = widget.message.role == 'tool';
    final theme = Theme.of(context);
    
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : (isTool
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
                  if (widget.message.reasoningContent != null &&
                      widget.message.reasoningContent!.isNotEmpty) ...[
                    _buildReasoningPanel(theme),
                    const SizedBox(height: 8.0),
                  ],
                  
                  if (isUser)
                    Text(
                      widget.message.content,
                      style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                    )
                  else
                    MarkdownRenderer(
                      markdownData: widget.message.content,
                      isStreaming: widget.isStreaming,
                      textColor: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                    ),
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
          InkWell(
            onTap: () {
              setState(() {
                _isReasoningExpanded = !_isReasoningExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
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
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
              child: Text(
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
}
