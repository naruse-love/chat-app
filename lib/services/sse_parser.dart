import 'dart:convert';

/// A helper class to parse the SSE (Server-Sent Events) line stream.
/// It extracts the JSON payload from lines starting with "data: "
/// and closes the stream gracefully when "data: [DONE]" is received.
class SseParser {
  /// Parses a stream of individual lines (as emitted by [SseDecoder])
  /// into a stream of JSON [Map<String, dynamic>] objects.
  static Stream<Map<String, dynamic>> parse(Stream<String> lineStream) async* {
    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith(':')) continue; // Skip SSE comments/pings

      if (trimmed.startsWith('data:')) {
        final dataContent = trimmed.substring(5).trim();
        if (dataContent == '[DONE]') {
          break; // Gracefully terminate the stream
        }

        try {
          final decoded = json.decode(dataContent);
          if (decoded is Map<String, dynamic>) {
            yield decoded;
          }
        } catch (e) {
          // Propagate parsing exceptions to the stream listener
          throw FormatException('Failed to parse SSE JSON: $e, data: "$dataContent"');
        }
      }
    }
  }
}
