import 'package:flutter/material.dart';
import '../utils/diff_helper.dart';

/// A widget that renders a visual unified diff comparison with line numbers,
/// color-coded additions/deletions, and statistical chips.
class DiffViewerWidget extends StatefulWidget {
  final List<DiffLine> diffLines;
  final DiffSummary? summary;
  final String? filePath;
  final double? maxHeight;
  final bool initiallyExpanded;

  const DiffViewerWidget({
    super.key,
    required this.diffLines,
    this.summary,
    this.filePath,
    this.maxHeight = 320,
    this.initiallyExpanded = true,
  });

  @override
  State<DiffViewerWidget> createState() => _DiffViewerWidgetState();
}

class _DiffViewerWidgetState extends State<DiffViewerWidget> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = widget.summary ?? DiffHelper.summarize(widget.diffLines);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, summary, isDark),
          if (_isExpanded) _buildDiffContent(context, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DiffSummary summary, bool isDark) {
    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isDark ? const Color(0xFF252526) : const Color(0xFFEDEDED),
        child: Row(
          children: [
            Icon(
              _isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            const SizedBox(width: 6),
            if (widget.filePath != null && widget.filePath!.isNotEmpty) ...[
              const Icon(Icons.description_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.filePath!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              const Text(
                '差异预览 (Diff)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
            ],
            const SizedBox(width: 8),
            // Additions Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B4D2E) : const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${summary.additions}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF137333),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Deletions Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF5C1D1D) : const Color(0xFFFCE8E6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '-${summary.deletions}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFE57373) : const Color(0xFFC5221F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffContent(BuildContext context, bool isDark) {
    if (widget.diffLines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: Text(
          '无差异内容',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      );
    }

    final contentWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.diffLines.map((line) => _buildDiffRow(line, isDark)).toList(),
        ),
      ),
    );

    if (widget.maxHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: contentWidget,
        ),
      );
    }

    return contentWidget;
  }

  Widget _buildDiffRow(DiffLine line, bool isDark) {
    Color bgColor;
    Color textColor;
    Color prefixColor;

    switch (line.type) {
      case DiffLineType.added:
        bgColor = isDark ? const Color(0x2E2E7D32) : const Color(0x264CAF50);
        textColor = isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20);
        prefixColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
        break;
      case DiffLineType.deleted:
        bgColor = isDark ? const Color(0x2EC62828) : const Color(0x26F44336);
        textColor = isDark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C);
        prefixColor = isDark ? const Color(0xFFE57373) : const Color(0xFFC62828);
        break;
      case DiffLineType.header:
        bgColor = isDark ? const Color(0x2E1565C0) : const Color(0x1E2196F3);
        textColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF0D47A1);
        prefixColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
        break;
      case DiffLineType.unchanged:
        bgColor = Colors.transparent;
        textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF24292E);
        prefixColor = isDark ? Colors.white30 : Colors.black26;
        break;
    }

    final oldNumStr = line.oldLineNumber != null ? line.oldLineNumber.toString() : '';
    final newNumStr = line.newLineNumber != null ? line.newLineNumber.toString() : '';

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old line number column
          SizedBox(
            width: 32,
            child: Text(
              oldNumStr,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // New line number column
          SizedBox(
            width: 32,
            child: Text(
              newNumStr,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Prefix marker (+, -, @@, or space)
          SizedBox(
            width: 14,
            child: Text(
              line.prefix,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: prefixColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Code text
          Text(
            line.text,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
