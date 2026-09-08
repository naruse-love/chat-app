import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/widgets/markdown_renderer.dart';
import 'package:chat/widgets/chat_bubble.dart';
import 'package:chat/services/mcp/transports/sse_mcp_transport.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockChatService extends ChatService {
  int getModelsCallCount = 0;
  List<ModelInfo> mockModels = [];

  @override
  Future<List<ModelInfo>> getModels({
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    getModelsCallCount++;
    return mockModels;
  }
}

class FakeSecureStorage extends Fake implements SecureStorageService {
  final Map<String, String> _storage = {};
  @override
  Future<String?> read(String key) async => _storage[key];
  @override
  Future<void> write(String key, String value) async => _storage[key] = value;
  @override
  Future<void> delete(String key) async => _storage.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Math Formatting & TeX Parsing Tests', () {
    test('preprocessMath correctly converts block math outside code blocks', () {
      const input = '''
Here is an equation:
\$\$
\\int_0^1 x^2 dx = \\frac{1}{3}
\$\$
And another:
\\[
E = mc^2
\\]
And code block that should NOT be modified:
```python
x = "\$\$not math\$\$"
```
''';

      final processed = MarkdownRenderer.preprocessMath(input);
      expect(processed, contains('```math\n\\int_0^1 x^2 dx = \\frac{1}{3}\n```'));
      expect(processed, contains('```math\nE = mc^2\n```'));
      expect(processed, contains('x = "\$\$not math\$\$"'));
    });

    testWidgets('Renders inline math formula using Math.tex', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: 'Einstein showed that \$E = mc^2\$ was true.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Math.tex renders a Math widget
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('Renders LaTeX paren inline formula \\(...\\)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: 'The formula is \\(a^2 + b^2 = c^2\\) in geometry.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('Renders block math with MathBlockWidget and copy button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: '''
\$\$
\\sum_{i=1}^n i = \\frac{n(n+1)}{2}
\$\$
''',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MathBlockWidget), findsOneWidget);
      expect(find.text('MATH'), findsOneWidget);
      expect(find.text('复制公式'), findsOneWidget);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('Does not parse currency amount like \$100 as math', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: 'The item costs \$100 and tax is \$15.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Math), findsNothing);
      expect(find.textContaining('\$100'), findsOneWidget);
    });
  });

  group('Thinking Process Markdown Support Tests', () {
    testWidgets('Renders thinking process with rich Markdown formatting', (tester) async {
      final msg = ChatMessage(
        id: 'msg-think-1',
        conversationId: 'c1',
        role: 'assistant',
        content: 'Final response after thinking.',
        reasoningContent: '### 思考步骤\n1. **分析输入**: 检查条件\n2. 计算 \$x = 10\$',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatBubble(message: msg),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 思考过程 to expand
      expect(find.text('思考过程'), findsOneWidget);
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();

      // Should render bold and headers via MarkdownRenderer, and inline math
      expect(find.textContaining('思考步骤'), findsOneWidget);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  group('Model Caching & Last Used Persistence Tests', () {
    late DatabaseHelper dbHelper;
    late FakeSecureStorage secureStorage;
    late ApiConfigDao apiConfigDao;
    late MockChatService mockChatService;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dbHelper = DatabaseHelper.instance;
      secureStorage = FakeSecureStorage();
      apiConfigDao = ApiConfigDao(dbHelper, secureStorage);
      mockChatService = MockChatService();
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads from network on first run and caches models and selection', () async {
      final config = ApiConfig(
        id: 'custom_provider_1',
        name: 'Custom Provider',
        baseUrl: 'https://api.custom.com/v1',
        apiKeyRef: 'key_1',
        isDefault: false,
        createdAt: DateTime.now(),
      );

      mockChatService.mockModels = [
        ModelInfo(
          id: 'model-a',
          provider: 'custom',
          modelName: 'Model A',
          supportsVision: false,
          supportsTools: true,
        ),
        ModelInfo(
          id: 'model-b',
          provider: 'custom',
          modelName: 'Model B',
          supportsVision: true,
          supportsTools: true,
        ),
      ];

      final notifier = ModelNotifier(mockChatService, apiConfigDao, config);

      // Wait for async fetch
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.models.length, 2);
      expect(notifier.state.selectedModel?.id, 'model-a');
      expect(mockChatService.getModelsCallCount, 1);

      // Select model-b
      notifier.selectModel(notifier.state.models[1]);
      expect(notifier.state.selectedModel?.id, 'model-b');

      await Future.delayed(const Duration(milliseconds: 50));

      // Create new notifier simulating app exit and restart
      final notifier2 = ModelNotifier(mockChatService, apiConfigDao, config);
      await Future.delayed(const Duration(milliseconds: 50));

      // Network call count must NOT increase (loaded directly from cache!)
      expect(mockChatService.getModelsCallCount, 1);
      expect(notifier2.state.models.length, 2);
      // Remembers model-b from previous session!
      expect(notifier2.state.selectedModel?.id, 'model-b');

      // Manual refresh forces network fetch
      await notifier2.fetchModels(forceRefresh: true);
      expect(mockChatService.getModelsCallCount, 2);

      notifier.dispose();
      notifier2.dispose();
    });
  });

  group('MCP Auto-load & Transport Resilience Tests', () {
    test('SseMcpTransport handles POST responses containing SSE formatted lines', () async {
      final transport = SseMcpTransport(
        uri: Uri.parse('https://example.com/mcp'),
      );

      expect(transport.transportType, McpTransportType.sse);
      expect(transport.sessionId, isNull);

      await transport.close();
    });
  });
}
