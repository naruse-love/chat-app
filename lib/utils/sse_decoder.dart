import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// A StreamTransformer that decodes incoming binary chunks ([Uint8List])
/// into individual lines ([String]) using UTF-8 decoding.
/// It buffers incomplete lines across network chunks to ensure no character or line
/// is split.
class SseDecoder extends StreamTransformerBase<Uint8List, String> {
  const SseDecoder();

  @override
  Stream<String> bind(Stream<Uint8List> stream) {
    late StreamController<String> controller;
    late StreamSubscription<Uint8List> subscription;
    final List<int> buffer = [];

    controller = StreamController<String>(
      onListen: () {
        subscription = stream.listen(
          (data) {
            buffer.addAll(data);
            _processBuffer(controller, buffer, false);
          },
          onError: (error, stackTrace) {
            controller.addError(error, stackTrace);
          },
          onDone: () {
            _processBuffer(controller, buffer, true);
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () => subscription.cancel(),
    );

    return controller.stream;
  }

  void _processBuffer(StreamController<String> controller, List<int> buffer, bool isDone) {
    int start = 0;
    while (start < buffer.length) {
      int lineEnd = -1;
      int nextStart = -1;

      // Scan for newline boundaries (\n, \r\n, \r)
      for (int i = start; i < buffer.length; i++) {
        if (buffer[i] == 10) { // '\n'
          lineEnd = i;
          nextStart = i + 1;
          break;
        } else if (buffer[i] == 13) { // '\r'
          if (i + 1 < buffer.length && buffer[i + 1] == 10) { // '\r\n'
            lineEnd = i;
            nextStart = i + 2;
          } else {
            lineEnd = i;
            nextStart = i + 1;
          }
          break;
        }
      }

      if (lineEnd != -1) {
        final lineBytes = buffer.sublist(start, lineEnd);
        try {
          final line = utf8.decode(lineBytes);
          controller.add(line);
        } catch (e, stackTrace) {
          controller.addError(e, stackTrace);
        }
        start = nextStart;
      } else {
        // No line terminator found in the remainder of this chunk.
        // If we are not done, keep it in the buffer for the next chunk.
        break;
      }
    }

    if (isDone) {
      if (start < buffer.length) {
        final lineBytes = buffer.sublist(start);
        try {
          final line = utf8.decode(lineBytes);
          controller.add(line);
        } catch (e, stackTrace) {
          controller.addError(e, stackTrace);
        }
      }
      buffer.clear();
    } else if (start > 0) {
      buffer.removeRange(0, start);
    }
  }
}
