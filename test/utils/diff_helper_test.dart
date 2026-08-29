import 'package:flutter_test/flutter_test.dart';
import 'package:chat/utils/diff_helper.dart';

void main() {
  group('DiffHelper Unit Tests', () {
    test('returns empty diff for empty inputs', () {
      final diff = DiffHelper.computeDiff('', '');
      expect(diff, isEmpty);
      final summary = DiffHelper.summarize(diff);
      expect(summary.hasChanges, isFalse);
    });

    test('handles completely new file (all additions)', () {
      const newText = 'Line 1\nLine 2\nLine 3';
      final diff = DiffHelper.computeDiff('', newText);
      expect(diff.length, equals(3));
      for (final line in diff) {
        expect(line.type, equals(DiffLineType.added));
        expect(line.prefix, equals('+'));
      }
      final summary = DiffHelper.summarize(diff);
      expect(summary.additions, equals(3));
      expect(summary.deletions, equals(0));
      expect(summary.formattedSummary, equals('+3 行 / -0 行'));
    });

    test('handles completely deleted file (all deletions)', () {
      const oldText = 'Line A\nLine B';
      final diff = DiffHelper.computeDiff(oldText, '');
      expect(diff.length, equals(2));
      for (final line in diff) {
        expect(line.type, equals(DiffLineType.deleted));
        expect(line.prefix, equals('-'));
      }
      final summary = DiffHelper.summarize(diff);
      expect(summary.additions, equals(0));
      expect(summary.deletions, equals(2));
      expect(summary.formattedSummary, equals('+0 行 / -2 行'));
    });

    test('handles identical files (all unchanged)', () {
      const text = 'Line 1\nLine 2\nLine 3';
      final diff = DiffHelper.computeDiff(text, text);
      expect(diff.length, equals(3));
      for (final line in diff) {
        expect(line.type, equals(DiffLineType.unchanged));
        expect(line.prefix, equals(' '));
      }
      final summary = DiffHelper.summarize(diff);
      expect(summary.hasChanges, isFalse);
      expect(summary.unchanged, equals(3));
    });

    test('computes line-by-line differences with LCS dynamic programming', () {
      const oldText = 'apple\nbanana\ncherry\ndate';
      const newText = 'apple\nblueberry\ncherry\ndragonfruit';

      final diff = DiffHelper.computeDiff(oldText, newText);
      final summary = DiffHelper.summarize(diff);

      expect(summary.additions, equals(2));
      expect(summary.deletions, equals(2));
      expect(summary.unchanged, equals(2));
      expect(summary.hasChanges, isTrue);

      // Check line types
      final types = diff.map((e) => e.type).toList();
      expect(types.first, equals(DiffLineType.unchanged)); // apple
    });

    test('generates unified diff with header hunks', () {
      const oldText = '# Title\nFirst paragraph.\nOld note.';
      const newText = '# Title\nFirst paragraph.\nNew note.\nFooter.';

      final unified = DiffHelper.formatUnifiedDiff(
        oldText,
        newText,
        oldFileName: 'notes.md',
        newFileName: 'notes.md',
      );

      expect(unified, contains('--- notes.md'));
      expect(unified, contains('+++ notes.md'));
      expect(unified, contains('@@ -'));
      expect(unified, contains('- Old note.'));
      expect(unified, contains('+ New note.'));
      expect(unified, contains('+ Footer.'));
    });
  });
}
