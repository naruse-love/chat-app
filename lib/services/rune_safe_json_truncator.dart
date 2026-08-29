import 'dart:convert';

/// A utility service for Unicode rune-safe string truncation and resilient JSON repair.
///
/// Prevents splitting UTF-16 surrogate pairs (such as emojis and rare CJK glyphs)
/// and safely repairs truncated JSON by balancing quotes, braces, and brackets.
class RuneSafeJsonTruncator {
  /// Safely truncates [input] to at most [maxRunes] Unicode code points (runes).
  ///
  /// Unlike `String.substring`, this guarantees that multi-byte UTF-16 surrogate pairs
  /// (emojis, complex scripts, ZWJ sequences) will never be split into lone surrogates.
  static String truncateString(
    String input,
    int maxRunes, {
    String suffix = '...[已截断]',
  }) {
    if (input.isEmpty || maxRunes <= 0) return '';
    final runes = input.runes.toList();
    if (runes.length <= maxRunes) return input;

    final truncatedRunes = runes.sublist(0, maxRunes);
    return String.fromCharCodes(truncatedRunes) + suffix;
  }

  /// Safely truncates a JSON string to at most [maxRunes] runes while ensuring
  /// the resulting output remains structurally valid and parseable JSON.
  static String truncateJsonString(
    String jsonString,
    int maxRunes, {
    String marker = '...[内容过长已安全截断]',
  }) {
    if (jsonString.isEmpty || maxRunes <= 0) return '{}';
    if (jsonString.runes.length <= maxRunes) return jsonString;

    // 1. Try structured semantic truncation first if valid JSON
    try {
      final dynamic decoded = json.decode(jsonString);
      final dynamic truncatedObj = truncateObject(decoded, maxRunes);
      return json.encode(truncatedObj);
    } catch (_) {
      // 2. Fallback to token/state-machine repair for incomplete or streaming JSON
      return _truncateAndRepairJsonTokens(jsonString, maxRunes, marker);
    }
  }

  /// Recursively truncates structured objects (Maps, Lists, Strings) to fit within [maxRunes].
  static dynamic truncateObject(dynamic obj, int maxRunes) {
    if (obj == null) return null;
    if (obj is num || obj is bool) return obj;

    if (obj is String) {
      final runes = obj.runes.toList();
      if (runes.length <= maxRunes) return obj;
      return truncateString(obj, maxRunes);
    }

    if (obj is Map) {
      final result = <String, dynamic>{};
      final entryBudget = obj.isNotEmpty ? (maxRunes ~/ obj.length).clamp(20, maxRunes) : maxRunes;
      for (final entry in obj.entries) {
        final keyStr = entry.key.toString();
        result[keyStr] = truncateObject(entry.value, entryBudget);
      }
      return result;
    }

    if (obj is List) {
      const maxItems = 20;
      if (obj.length > maxItems) {
        final listBudget = (maxRunes ~/ maxItems).clamp(20, maxRunes);
        final truncatedList = obj.take(maxItems).map((e) => truncateObject(e, listBudget)).toList();
        truncatedList.add({'__truncated__': '剩余 ${obj.length - maxItems} 项已省略'});
        return truncatedList;
      }
      final listBudget = obj.isNotEmpty ? (maxRunes ~/ obj.length).clamp(20, maxRunes) : maxRunes;
      return obj.map((e) => truncateObject(e, listBudget)).toList();
    }

    return obj.toString();
  }

  /// Token-based state machine that truncates raw JSON text and gracefully closes unclosed structures.
  static String _truncateAndRepairJsonTokens(String input, int maxRunes, String marker) {
    final runes = input.runes.toList();
    final clampedRunes = runes.sublist(0, maxRunes.clamp(0, runes.length));
    final rawSlice = String.fromCharCodes(clampedRunes);

    final stack = <String>[]; // Tracks open '{' and '['
    bool inString = false;
    bool escapeNext = false;
    final buffer = StringBuffer();

    for (int i = 0; i < rawSlice.length; i++) {
      final ch = rawSlice[i];

      if (escapeNext) {
        buffer.write(ch);
        escapeNext = false;
        continue;
      }

      if (ch == '\\' && inString) {
        buffer.write(ch);
        escapeNext = true;
        continue;
      }

      if (ch == '"') {
        inString = !inString;
        buffer.write(ch);
        continue;
      }

      if (!inString) {
        if (ch == '{') {
          stack.add('}');
          buffer.write(ch);
        } else if (ch == '[') {
          stack.add(']');
          buffer.write(ch);
        } else if (ch == '}' || ch == ']') {
          if (stack.isNotEmpty && stack.last == ch) {
            stack.removeLast();
          }
          buffer.write(ch);
        } else {
          buffer.write(ch);
        }
      } else {
        buffer.write(ch);
      }
    }

    // If truncated inside a string, add truncation marker and close quote
    if (inString) {
      buffer.write(marker);
      buffer.write('"');
    }

    // Clean up trailing dangling commas, colons, or incomplete tokens
    String currentText = buffer.toString().trimRight();
    while (currentText.endsWith(',') || currentText.endsWith(':')) {
      currentText = currentText.substring(0, currentText.length - 1).trimRight();
    }

    // Close remaining open brackets and braces in reverse order
    final repairBuffer = StringBuffer(currentText);
    for (int i = stack.length - 1; i >= 0; i--) {
      final closing = stack[i];
      // Avoid inserting empty colon or dangling key before closing brace
      final temp = repairBuffer.toString().trimRight();
      if (temp.endsWith(':') || temp.endsWith(',')) {
        repairBuffer.clear();
        repairBuffer.write(temp.substring(0, temp.length - 1));
      }
      repairBuffer.write(closing);
    }

    final candidate = repairBuffer.toString();

    // Verify if repair is valid JSON; if so, return it
    try {
      json.decode(candidate);
      return candidate;
    } catch (_) {
      // If still invalid due to partial primitive token, fallback to safe wrapper object
      return json.encode({
        'content': truncateString(input, maxRunes, suffix: marker),
        '__truncated__': true,
      });
    }
  }
}
