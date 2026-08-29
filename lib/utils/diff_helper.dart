import 'dart:math' as math;

/// Type of line in a diff comparison.
enum DiffLineType {
  /// Line was added in the new version (+).
  added,

  /// Line was deleted from the old version (-).
  deleted,

  /// Line is unchanged between versions ( ).
  unchanged,

  /// Informational header line (e.g. @@ -1,4 +1,6 @@).
  header,
}

/// Represents a single line in a diff representation.
class DiffLine {
  /// The classification of this diff line.
  final DiffLineType type;

  /// The raw text of this line (without diff marker prefix).
  final String text;

  /// 1-based line number in the original text (null if added or header).
  final int? oldLineNumber;

  /// 1-based line number in the modified text (null if deleted or header).
  final int? newLineNumber;

  const DiffLine({
    required this.type,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  /// Single-character visual prefix.
  String get prefix {
    switch (type) {
      case DiffLineType.added:
        return '+';
      case DiffLineType.deleted:
        return '-';
      case DiffLineType.unchanged:
        return ' ';
      case DiffLineType.header:
        return '@@';
    }
  }

  /// Full line formatted with its prefix.
  String get formattedLine => '$prefix $text';

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'text': text,
      if (oldLineNumber != null) 'oldLineNumber': oldLineNumber,
      if (newLineNumber != null) 'newLineNumber': newLineNumber,
    };
  }

  factory DiffLine.fromJson(Map<String, dynamic> json) {
    return DiffLine(
      type: DiffLineType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DiffLineType.unchanged,
      ),
      text: json['text'] as String? ?? '',
      oldLineNumber: json['oldLineNumber'] as int?,
      newLineNumber: json['newLineNumber'] as int?,
    );
  }

  @override
  String toString() => 'DiffLine($prefix, old: $oldLineNumber, new: $newLineNumber, "$text")';
}

/// Statistical summary of a diff comparison.
class DiffSummary {
  final int additions;
  final int deletions;
  final int unchanged;

  const DiffSummary({
    required this.additions,
    required this.deletions,
    required this.unchanged,
  });

  int get totalLines => additions + deletions + unchanged;
  bool get hasChanges => additions > 0 || deletions > 0;

  /// Human-readable summary string (e.g. '+12 行 / -3 行').
  String get formattedSummary => '+$additions 行 / -$deletions 行';

  Map<String, dynamic> toJson() {
    return {
      'additions': additions,
      'deletions': deletions,
      'unchanged': unchanged,
      'hasChanges': hasChanges,
      'formattedSummary': formattedSummary,
    };
  }

  factory DiffSummary.fromJson(Map<String, dynamic> json) {
    return DiffSummary(
      additions: json['additions'] as int? ?? 0,
      deletions: json['deletions'] as int? ?? 0,
      unchanged: json['unchanged'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'DiffSummary($formattedSummary, total: $totalLines)';
}

/// Pure Dart line-by-line diff calculator using Longest Common Subsequence (LCS).
///
/// Has zero external dependencies and provides clean formatting for UI rendering
/// and Unified Diff generation.
class DiffHelper {
  /// Computes line-by-line diff between [oldText] and [newText].
  static List<DiffLine> computeDiff(String oldText, String newText) {
    if (oldText.isEmpty && newText.isEmpty) return const [];

    final normOld = oldText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final normNew = newText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    if (normOld.isEmpty) {
      final newLines = normNew.split('\n');
      return List.generate(
        newLines.length,
        (i) => DiffLine(
          type: DiffLineType.added,
          text: newLines[i],
          oldLineNumber: null,
          newLineNumber: i + 1,
        ),
      );
    }

    if (normNew.isEmpty) {
      final oldLines = normOld.split('\n');
      return List.generate(
        oldLines.length,
        (i) => DiffLine(
          type: DiffLineType.deleted,
          text: oldLines[i],
          oldLineNumber: i + 1,
          newLineNumber: null,
        ),
      );
    }

    final oldLines = normOld.split('\n');
    final newLines = normNew.split('\n');

    final n = oldLines.length;
    final m = newLines.length;

    // Fast-path for identical content
    if (normOld == normNew) {
      return List.generate(
        n,
        (i) => DiffLine(
          type: DiffLineType.unchanged,
          text: oldLines[i],
          oldLineNumber: i + 1,
          newLineNumber: i + 1,
        ),
      );
    }

    // 1. Trim common prefix lines
    int prefixCount = 0;
    while (prefixCount < n && prefixCount < m && oldLines[prefixCount] == newLines[prefixCount]) {
      prefixCount++;
    }

    // 2. Trim common suffix lines
    int suffixCount = 0;
    while (suffixCount < (n - prefixCount) &&
        suffixCount < (m - prefixCount) &&
        oldLines[n - 1 - suffixCount] == newLines[m - 1 - suffixCount]) {
      suffixCount++;
    }

    final result = <DiffLine>[];

    // Add common prefix
    for (int i = 0; i < prefixCount; i++) {
      result.add(DiffLine(
        type: DiffLineType.unchanged,
        text: oldLines[i],
        oldLineNumber: i + 1,
        newLineNumber: i + 1,
      ));
    }

    // Solve LCS on the middle diff chunk
    final midOld = oldLines.sublist(prefixCount, n - suffixCount);
    final midNew = newLines.sublist(prefixCount, m - suffixCount);

    final midDiff = _computeLcsDiff(
      midOld,
      midNew,
      startOldLine: prefixCount + 1,
      startNewLine: prefixCount + 1,
    );
    result.addAll(midDiff);

    // Add common suffix
    for (int i = 0; i < suffixCount; i++) {
      final oldIdx = n - suffixCount + i;
      final newIdx = m - suffixCount + i;
      result.add(DiffLine(
        type: DiffLineType.unchanged,
        text: oldLines[oldIdx],
        oldLineNumber: oldIdx + 1,
        newLineNumber: newIdx + 1,
      ));
    }

    return result;
  }

  /// Internal LCS dynamic programming table calculation on list slices.
  static List<DiffLine> _computeLcsDiff(
    List<String> oldList,
    List<String> newList, {
    required int startOldLine,
    required int startNewLine,
  }) {
    final n = oldList.length;
    final m = newList.length;

    if (n == 0) {
      return List.generate(
        m,
        (j) => DiffLine(
          type: DiffLineType.added,
          text: newList[j],
          oldLineNumber: null,
          newLineNumber: startNewLine + j,
        ),
      );
    }
    if (m == 0) {
      return List.generate(
        n,
        (i) => DiffLine(
          type: DiffLineType.deleted,
          text: oldList[i],
          oldLineNumber: startOldLine + i,
          newLineNumber: null,
        ),
      );
    }

    // Build DP LCS length matrix
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < m; j++) {
        if (oldList[i] == newList[j]) {
          dp[i + 1][j + 1] = dp[i][j] + 1;
        } else {
          dp[i + 1][j + 1] = math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }

    // Backtrack to build diff lines
    final reversedLines = <DiffLine>[];
    int i = n;
    int j = m;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldList[i - 1] == newList[j - 1]) {
        reversedLines.add(DiffLine(
          type: DiffLineType.unchanged,
          text: oldList[i - 1],
          oldLineNumber: startOldLine + i - 1,
          newLineNumber: startNewLine + j - 1,
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        reversedLines.add(DiffLine(
          type: DiffLineType.added,
          text: newList[j - 1],
          oldLineNumber: null,
          newLineNumber: startNewLine + j - 1,
        ));
        j--;
      } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
        reversedLines.add(DiffLine(
          type: DiffLineType.deleted,
          text: oldList[i - 1],
          oldLineNumber: startOldLine + i - 1,
          newLineNumber: null,
        ));
        i--;
      }
    }

    return reversedLines.reversed.toList();
  }

  /// Computes summary metrics for the given [diffLines].
  static DiffSummary summarize(List<DiffLine> diffLines) {
    int additions = 0;
    int deletions = 0;
    int unchanged = 0;

    for (final line in diffLines) {
      switch (line.type) {
        case DiffLineType.added:
          additions++;
          break;
        case DiffLineType.deleted:
          deletions++;
          break;
        case DiffLineType.unchanged:
          unchanged++;
          break;
        case DiffLineType.header:
          break;
      }
    }

    return DiffSummary(
      additions: additions,
      deletions: deletions,
      unchanged: unchanged,
    );
  }

  /// Formats the diff into standard Unified Diff format with hunk headers.
  static String formatUnifiedDiff(
    String oldText,
    String newText, {
    String oldFileName = 'original',
    String newFileName = 'modified',
    int contextLines = 3,
  }) {
    final diffLines = computeDiff(oldText, newText);
    if (diffLines.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('--- $oldFileName');
    buffer.writeln('+++ $newFileName');

    // Group diff into hunks
    final hunks = _createHunks(diffLines, contextLines);
    for (final hunk in hunks) {
      buffer.writeln(hunk.header);
      for (final line in hunk.lines) {
        buffer.writeln(line.formattedLine);
      }
    }

    return buffer.toString().trimRight();
  }

  static List<_DiffHunk> _createHunks(List<DiffLine> diffLines, int contextLines) {
    final hunks = <_DiffHunk>[];
    if (diffLines.isEmpty) return hunks;

    // Identify indices of all changed lines
    final changeIndices = <int>[];
    for (int i = 0; i < diffLines.length; i++) {
      if (diffLines[i].type == DiffLineType.added || diffLines[i].type == DiffLineType.deleted) {
        changeIndices.add(i);
      }
    }

    if (changeIndices.isEmpty) return hunks;

    // Group changes into clusters separated by > 2 * contextLines unchanged lines
    int groupStart = math.max(0, changeIndices.first - contextLines);
    int groupEnd = math.min(diffLines.length, changeIndices.first + contextLines + 1);

    for (int k = 1; k < changeIndices.length; k++) {
      final changeIdx = changeIndices[k];
      final start = math.max(0, changeIdx - contextLines);
      final end = math.min(diffLines.length, changeIdx + contextLines + 1);

      if (start <= groupEnd) {
        groupEnd = math.max(groupEnd, end);
      } else {
        hunks.add(_buildHunk(diffLines.sublist(groupStart, groupEnd)));
        groupStart = start;
        groupEnd = end;
      }
    }

    hunks.add(_buildHunk(diffLines.sublist(groupStart, groupEnd)));
    return hunks;
  }

  static _DiffHunk _buildHunk(List<DiffLine> slice) {
    int oldStart = 0;
    int oldCount = 0;
    int newStart = 0;
    int newCount = 0;

    for (final line in slice) {
      if (line.type == DiffLineType.deleted || line.type == DiffLineType.unchanged) {
        if (oldStart == 0 && line.oldLineNumber != null) {
          oldStart = line.oldLineNumber!;
        }
        oldCount++;
      }
      if (line.type == DiffLineType.added || line.type == DiffLineType.unchanged) {
        if (newStart == 0 && line.newLineNumber != null) {
          newStart = line.newLineNumber!;
        }
        newCount++;
      }
    }

    final header = '@@ -$oldStart,$oldCount +$newStart,$newCount @@';
    return _DiffHunk(header: header, lines: slice);
  }
}

class _DiffHunk {
  final String header;
  final List<DiffLine> lines;

  _DiffHunk({required this.header, required this.lines});
}
