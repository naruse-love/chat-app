import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/utils/sse_decoder.dart';
import 'package:chat/services/sse_parser.dart';

void main() {
  group('SseDecoder & SseParser Tests', () {
    test('Parse normal JSON stream chunk', () async {
      final List<List<int>> chunks = [
        'data: {"id": "1", "choices": [{"delta": {"content": "Hello"}}]}\n\ndata: [DONE]\n\n'
            .codeUnits,
      ];
      final stream = Stream.fromIterable(chunks).map(Uint8List.fromList);

      final result = await SseParser.parse(stream.transform(const SseDecoder())).toList();

      expect(result, hasLength(1));
      expect(result[0]['id'], '1');
      expect(result[0]['choices'][0]['delta']['content'], 'Hello');
    });

    test('Handle split chunks across packets', () async {
      // The line is split into three chunks:
      // Chunk 1: "data: {"id": "
      // Chunk 2: "1", "choices": [{"delta"
      // Chunk 3: ": {"content": "Hello"}}]}\n\ndata: [DONE]\n\n"
      final List<List<int>> chunks = [
        'data: {"id": "'.codeUnits,
        '1", "choices": [{"delta"'.codeUnits,
        ': {"content": "Hello"}}]}\n\ndata: [DONE]\n\n'.codeUnits,
      ];
      final stream = Stream.fromIterable(chunks).map(Uint8List.fromList);

      final result = await SseParser.parse(stream.transform(const SseDecoder())).toList();

      expect(result, hasLength(1));
      expect(result[0]['id'], '1');
      expect(result[0]['choices'][0]['delta']['content'], 'Hello');
    });

    test('Ignore comments and empty lines', () async {
      final List<List<int>> chunks = [
        '\n: ping\n\ndata: {"content": "text"}\n\n\n'.codeUnits,
        'data: [DONE]\n\n'.codeUnits,
      ];
      final stream = Stream.fromIterable(chunks).map(Uint8List.fromList);

      final result = await SseParser.parse(stream.transform(const SseDecoder())).toList();

      expect(result, hasLength(1));
      expect(result[0]['content'], 'text');
    });

    test('Throw FormatException on invalid JSON', () async {
      final List<List<int>> chunks = [
        'data: {invalid_json}\n\n'.codeUnits,
      ];
      final stream = Stream.fromIterable(chunks).map(Uint8List.fromList);

      expect(
        SseParser.parse(stream.transform(const SseDecoder())).toList(),
        throwsA(isA<FormatException>()),
      );
    });

    test('Gracefully terminate stream on [DONE] and ignore trailing data', () async {
      final List<List<int>> chunks = [
        'data: {"index": 0}\n\ndata: [DONE]\n\ndata: {"index": 1}\n\n'.codeUnits,
      ];
      final stream = Stream.fromIterable(chunks).map(Uint8List.fromList);

      final result = await SseParser.parse(stream.transform(const SseDecoder())).toList();

      expect(result, hasLength(1));
      expect(result[0]['index'], 0);
    });
  });
}
