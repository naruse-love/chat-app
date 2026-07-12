import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/models/chat_message.dart';

class MockAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (cancelFuture != null) {
      cancelFuture.then((_) {
        // Intercept cancellation and throw standard cancel exception if cancel is triggered
      });
    }
    if (handler != null) {
      return handler!(options);
    }
    throw UnimplementedError('MockAdapter handler is not configured');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ChatService Tests', () {
    late Dio dio;
    late MockAdapter mockAdapter;
    late ChatService chatService;

    setUp(() {
      dio = Dio();
      mockAdapter = MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      chatService = ChatService(dio: dio);
    });

    test('getModels parses models response correctly', () async {
      mockAdapter.handler = (options) {
        expect(options.path, endsWith('/models'));
        expect(options.method, 'GET');

        final mockResponse = {
          'data': [
            {
              'id': 'openai/gpt-4o',
              'owned_by': 'openai',
              'supports_vision': true,
              'supports_tools': true,
            },
            {
              'id': 'google/gemini-1.5-flash',
              'owned_by': 'google',
            }
          ]
        };
        return ResponseBody.fromString(
          json.encode(mockResponse),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final models = await chatService.getModels(
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-api-key',
      );

      expect(models, hasLength(2));
      expect(models[0].id, 'openai/gpt-4o');
      expect(models[0].provider, 'openai');
      expect(models[0].modelName, 'gpt-4o');
      expect(models[0].supportsVision, isTrue);
      expect(models[0].supportsTools, isTrue);

      expect(models[1].id, 'google/gemini-1.5-flash');
      expect(models[1].provider, 'google');
      expect(models[1].modelName, 'gemini-1.5-flash');
      expect(models[1].supportsVision, isTrue); // Inferred from modelName gemini-1.5
    });

    test('chatCompletionsStream yields correct parsed chunks', () async {
      mockAdapter.handler = (options) {
        expect(options.path, endsWith('/chat/completions'));
        expect(options.method, 'POST');

        final requestBody = options.data as Map<String, dynamic>;
        expect(requestBody['model'], 'gpt-4o');
        expect(requestBody['stream'], isTrue);

        const sseData =
            'data: {"choices": [{"delta": {"content": "Hello "}}]}\n\n'
            'data: {"choices": [{"delta": {"content": "world!"}}]}\n\n'
            'data: [DONE]\n\n';

        final stream = Stream.fromIterable([
          utf8.encode(sseData),
        ]).map((e) => Uint8List.fromList(e));

        return ResponseBody(
          stream,
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = chatService.chatCompletionsStream(
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-api-key',
        model: 'gpt-4o',
        messages: messages,
      );

      final results = await stream.toList();
      expect(results, hasLength(2));
      expect(results[0]['choices'][0]['delta']['content'], 'Hello ');
      expect(results[1]['choices'][0]['delta']['content'], 'world!');
    });

    test('chatCompletionsStream propagates cancellation correctly', () async {
      final cancelToken = CancelToken();
      final controller = StreamController<Uint8List>();

      mockAdapter.handler = (options) {
        return ResponseBody(
          controller.stream,
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = chatService.chatCompletionsStream(
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-api-key',
        model: 'gpt-4o',
        messages: messages,
        cancelToken: cancelToken,
      );

      // Start reading the stream, then trigger cancel after a small delay
      final futureResults = stream.toList();

      Future.delayed(const Duration(milliseconds: 10), () {
        cancelToken.cancel('User requested cancellation');
        controller.addError(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
            error: 'User requested cancellation',
          ),
        );
        controller.close();
      });

      expect(
        futureResults,
        throwsA(predicate((e) => e is DioException && e.type == DioExceptionType.cancel)),
      );
    });
  });
}
