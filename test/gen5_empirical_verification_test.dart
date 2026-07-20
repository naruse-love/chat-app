import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:chat/data/database_helper.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/services/url_fetch_service.dart';
import 'package:chat/services/search_service.dart';

import 'e2e_integration_test.dart';

class Gen5MockAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handler != null) {
      return handler!(options);
    }
    throw UnimplementedError('Gen5MockAdapter handler is not configured');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockChatService mockChatService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gen5_verification_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);
    mockSecureStorage = MockFlutterSecureStorage();
    mockChatService = MockChatService();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    try {
      final db = await dbHelper.database;
      await db.close();
    } catch (_) {}
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Gen5 Requirement 1: OpenCode Free Auto-population & Fallback Metadata', () {
    test('Verify OpenCode Free auto-population on completely fresh database state', () async {
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      // Trigger initial load
      container.read(apiConfigProvider);
      await Future.delayed(const Duration(milliseconds: 200));

      final state = container.read(apiConfigProvider);
      expect(state.configs, hasLength(1), reason: 'Fresh DB must contain exactly 1 pre-populated config');
      final config = state.configs.first;
      expect(config.id, equals('opencode_free'));
      expect(config.name, equals('OpenCode Free'));
      expect(config.baseUrl, equals('https://opencode.ai/zen/v1'));
      expect(config.isDefault, isTrue);
      expect(config.apiKeyRef, equals('opencode_free_api_key_ref'));
      expect(state.activeConfig?.id, equals('opencode_free'));

      final storedKey = await mockSecureStorage.read(key: 'opencode_free_api_key_ref');
      expect(storedKey, equals(''));
    });

    test('Verify OpenCode Free fallback models metadata and tool calling flag defaults', () async {
      final fallbackModels = ModelInfo.defaultOpenCodeFallbackModels;
      expect(fallbackModels, hasLength(5));

      final ids = fallbackModels.map((m) => m.id).toList();
      expect(ids, equals([
        'deepseek-v4-flash-free',
        'mimo-v2.5-free',
        'hy3-free',
        'nemotron-3-ultra-free',
        'north-mini-code-free',
      ]));

      for (final model in fallbackModels) {
        expect(model.provider, equals('opencode'));
        expect(model.supportsTools, isTrue, reason: 'All OpenCode Free models must support tools by default');
        expect(model.supportsVision, isFalse);
      }
    });

    test('Verify fallback models are activated on API fetch failure', () async {
      mockChatService.listModelsHandler = (baseUrl, apiKey) async {
        throw DioException(
          requestOptions: RequestOptions(path: baseUrl),
          type: DioExceptionType.connectionError,
          error: 'Connection refused',
        );
      };

      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);
      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      await Future.delayed(const Duration(milliseconds: 100));

      final modelNotifier = container.read(modelProvider.notifier);
      await modelNotifier.fetchModels();

      final modelState = container.read(modelProvider);
      expect(modelState.models, hasLength(5));
      expect(modelState.selectedModel?.id, equals('deepseek-v4-flash-free'));
    });
  });

  group('Gen5 Requirement 2: UrlFetchService HTML Parsing, Tag Stripping, Truncation & Error Recovery', () {
    late Dio dio;
    late Gen5MockAdapter mockAdapter;
    late UrlFetchService urlFetchService;

    setUp(() {
      dio = Dio();
      mockAdapter = Gen5MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      urlFetchService = UrlFetchService(dio: dio);
    });

    test('Strips script, style, noscript tags and cleans up whitespace', () async {
      mockAdapter.handler = (options) {
        const html = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { background-color: #fff; font-size: 16px; }
    .hidden { display: none; }
  </style>
  <script type="text/javascript">
    var secretKey = "API_KEY_SECRET";
    console.log("Execute script");
  </script>
</head>
<body>
  <noscript>
    <div class="no-script-warning">JavaScript is disabled in your browser.</div>
  </noscript>
  <header><h1>Header Title</h1></header>
  <article>
    <p>Paragraph 1 line 1.\nParagraph 1 line 2.</p>
    <p>Paragraph 2 content.</p>
  </article>
</body>
</html>
''';
        return ResponseBody.fromString(html, 200);
      };

      final text = await urlFetchService.fetchUrlContent('https://test.local/article');
      expect(text, contains('Header Title'));
      expect(text, contains('Paragraph 1 line 1.'));
      expect(text, contains('Paragraph 2 content.'));
      expect(text, isNot(contains('secretKey')));
      expect(text, isNot(contains('background-color')));
      expect(text, isNot(contains('JavaScript is disabled')));
    });

    test('Enforces strictly 8000 character upper limit', () async {
      mockAdapter.handler = (options) {
        final hugeBody = 'Lorem ipsum dolor sit amet. ' * 500; // > 13000 chars
        final html = '<html><body><div>$hugeBody</div></body></html>';
        return ResponseBody.fromString(html, 200);
      };

      final text = await urlFetchService.fetchUrlContent('https://test.local/huge');
      expect(text.length, equals(8000));
    });

    test('Handles timeout and network errors with proper Chinese recovery messages', () async {
      // Timeout case
      mockAdapter.handler = (options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      };
      final timeoutText = await urlFetchService.fetchUrlContent('https://test.local/slow');
      expect(timeoutText, contains('读取网页超时'));

      // HTTP 500 case
      mockAdapter.handler = (options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 500),
        );
      };
      final errorText = await urlFetchService.fetchUrlContent('https://test.local/500');
      expect(errorText, contains('读取网页失败'));
    });

    test('Handles empty body or whitespace-only response gracefully', () async {
      mockAdapter.handler = (options) => ResponseBody.fromString('   \n  \t ', 200);
      final emptyText = await urlFetchService.fetchUrlContent('https://test.local/empty');
      expect(emptyText, equals('网页内容为空'));
    });
  });

  group('Gen5 Requirement 3: SearXNG Dual-Page Concurrency & URL Deduplication', () {
    late Dio dio;
    late Gen5MockAdapter mockAdapter;
    late SearchService searchService;

    setUp(() {
      dio = Dio();
      mockAdapter = Gen5MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      searchService = SearchService(dio: dio);
    });

    test('SearXNG fires concurrent requests for pageno=1 and pageno=2 and deduplicates identical URLs', () async {
      final requestedPages = <int>[];

      mockAdapter.handler = (options) {
        final pageno = options.queryParameters['pageno'] as int;
        requestedPages.add(pageno);

        if (pageno == 1) {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Article A', 'url': 'https://example.com/a', 'content': 'Content A'},
                {'title': 'Article B', 'url': 'https://example.com/b', 'content': 'Content B'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Article B Duplicate', 'url': 'https://example.com/b', 'content': 'Duplicate Content B'},
                {'title': 'Article C', 'url': 'https://example.com/c', 'content': 'Content C'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
      };

      final results = await searchService.search(
        query: 'searxng test',
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      // Verify concurrent request parameters
      expect(requestedPages, containsAll([1, 2]));
      expect(requestedPages.length, equals(2));

      // Verify deduplication: Article B duplicate from page 2 should be omitted
      expect(results, hasLength(3));
      expect(results[0].url, equals('https://example.com/a'));
      expect(results[1].url, equals('https://example.com/b'));
      expect(results[1].title, equals('Article B'));
      expect(results[2].url, equals('https://example.com/c'));
    });

    test('SearXNG recovers when one page fails and returns partial results from the successful page', () async {
      mockAdapter.handler = (options) {
        final pageno = options.queryParameters['pageno'] as int;
        if (pageno == 1) {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Article P1', 'url': 'https://example.com/p1', 'content': 'P1 Content'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
      };

      final results = await searchService.search(
        query: 'searxng fail p2',
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      expect(results, hasLength(1));
      expect(results[0].url, equals('https://example.com/p1'));
    });
  });
}
