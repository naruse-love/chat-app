import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:highlight/highlight.dart' show highlight, Node;

class MarkdownRenderer extends StatefulWidget {
  final String markdownData;
  final bool isStreaming;
  final TextStyle? textColor;

  const MarkdownRenderer({
    super.key,
    required this.markdownData,
    this.isStreaming = false,
    this.textColor,
  });

  @override
  State<MarkdownRenderer> createState() => _MarkdownRendererState();
}

class _MarkdownRendererState extends State<MarkdownRenderer> {
  late String _displayData;
  String? _pendingData;
  Timer? _throttleTimer;
  bool _isThrottleActive = false;

  @override
  void initState() {
    super.initState();
    _displayData = widget.markdownData;
  }

  @override
  void didUpdateWidget(covariant MarkdownRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStreaming) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _isThrottleActive = false;
      _pendingData = null;
      setState(() {
        _displayData = widget.markdownData;
      });
    } else {
      _pendingData = widget.markdownData;
      if (!_isThrottleActive) {
        _applyThrottle();
      }
    }
  }

  void _applyThrottle() {
    if (!mounted) return;
    _isThrottleActive = true;
    setState(() {
      if (_pendingData != null) {
        _displayData = _pendingData!;
        _pendingData = null;
      }
    });

    _throttleTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _isThrottleActive = false;
      if (widget.isStreaming && _pendingData != null) {
        _applyThrottle();
      }
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = widget.textColor ?? theme.textTheme.bodyLarge;

    return MarkdownBody(
      data: _displayData,
      selectable: false,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: textStyle,
        code: textStyle?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.transparent,
        ),
      ),
      builders: {
        'code': CodeElementBuilder(
          context: context,
          isStreaming: widget.isStreaming,
        ),
      },
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isStreaming;

  CodeElementBuilder({
    required this.context,
    required this.isStreaming,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final classAttr = element.attributes['class'] ?? '';
    final hasLanguage = classAttr.startsWith('language-');
    final isBlock = element.textContent.contains('\n') || hasLanguage;

    final codeContent = element.textContent.trimRight();

    if (!isBlock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.brightness == Brightness.light
              ? Colors.grey[200]
              : Colors.grey[800],
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Text(
          codeContent,
          style: preferredStyle?.copyWith(
            fontFamily: 'monospace',
            fontSize: (preferredStyle.fontSize ?? 14.0) * 0.9,
          ),
        ),
      );
    }

    final language = hasLanguage ? classAttr.substring(9) : 'code';
    return CodeBlockWidget(
      code: codeContent,
      language: language,
      isStreaming: isStreaming,
    );
  }
}

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;
  final bool isStreaming;

  const CodeBlockWidget({
    super.key,
    required this.code,
    required this.language,
    required this.isStreaming,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _isCopied = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() {
      _isCopied = true;
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    List<TextSpan> highlightedSpans = [];
    final defaultStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.0,
      color: isDark ? Colors.grey[300] : Colors.grey[800],
    );

    if (widget.isStreaming) {
      highlightedSpans = [TextSpan(text: widget.code, style: defaultStyle)];
    } else {
      try {
        final parsed = highlight.parse(
          widget.code,
          language: widget.language.isEmpty ? null : widget.language,
        );
        final highlightTheme = isDark ? _darkHighlightTheme : _lightHighlightTheme;
        highlightedSpans = HighlightSpans.buildSpans(
          parsed.nodes ?? [],
          highlightTheme,
          defaultStyle,
        );
      } catch (e) {
        highlightedSpans = [TextSpan(text: widget.code, style: defaultStyle)];
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[200],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7.0),
                topRight: Radius.circular(7.0),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.language.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.outline,
                  ),
                ),
                GestureDetector(
                  onTap: _copyToClipboard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCopied ? Icons.check : Icons.copy,
                        size: 14.0,
                        color: _isCopied ? Colors.green : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        _isCopied ? 'Copied!' : 'Copy',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _isCopied ? Colors.green : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12.0),
            child: RichText(
              text: TextSpan(
                children: highlightedSpans,
                style: defaultStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HighlightSpans {
  static List<TextSpan> buildSpans(
    List<Node> nodes,
    Map<String, TextStyle> theme,
    TextStyle defaultStyle,
  ) {
    final List<TextSpan> spans = [];

    void traverse(Node node, TextStyle parentStyle) {
      final nodeStyle = node.className != null
          ? parentStyle.merge(theme[node.className])
          : parentStyle;

      if (node.value != null) {
        spans.add(TextSpan(text: node.value, style: nodeStyle));
      }

      if (node.children != null) {
        for (final child in node.children!) {
          traverse(child, nodeStyle);
        }
      }
    }

    for (final node in nodes) {
      traverse(node, defaultStyle);
    }

    return spans;
  }
}

const Map<String, TextStyle> _darkHighlightTheme = {
  'keyword': TextStyle(color: Color(0xFFC678DD), fontWeight: FontWeight.bold),
  'string': TextStyle(color: Color(0xFF98C379)),
  'number': TextStyle(color: Color(0xFFD19A66)),
  'comment': TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
  'class': TextStyle(color: Color(0xFFE5C07B)),
  'function': TextStyle(color: Color(0xFF61AFEF)),
  'variable': TextStyle(color: Color(0xFFE06C75)),
  'built_in': TextStyle(color: Color(0xFF56B6C2)),
  'title': TextStyle(color: Color(0xFF61AFEF)),
  'params': TextStyle(color: Color(0xFFABB2BF)),
};

const Map<String, TextStyle> _lightHighlightTheme = {
  'keyword': TextStyle(color: Color(0xFF0000FF), fontWeight: FontWeight.bold),
  'string': TextStyle(color: Color(0xFFA31515)),
  'number': TextStyle(color: Color(0xFF098658)),
  'comment': TextStyle(color: Color(0xFF008000), fontStyle: FontStyle.italic),
  'class': TextStyle(color: Color(0xFF267F99)),
  'function': TextStyle(color: Color(0xFF795E26)),
  'variable': TextStyle(color: Color(0xFF001080)),
  'built_in': TextStyle(color: Color(0xFF008080)),
  'title': TextStyle(color: Color(0xFF795E26)),
  'params': TextStyle(color: Color(0xFF000000)),
};
