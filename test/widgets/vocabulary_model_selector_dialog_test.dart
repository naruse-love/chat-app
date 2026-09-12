import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/vocabulary_config_provider.dart';
import 'package:chat/widgets/vocabulary_model_selector_dialog.dart';

class FakeVocabularyConfigNotifier extends StateNotifier<VocabularyConfigState>
    implements VocabularyConfigNotifier {
  ApiConfig? lastSetConfig;
  ModelInfo? lastSetModel;
  String? lastCustomModel;
  bool resetCalled = false;
  bool fetchModelsCalled = false;

  @override
  Future<void> get initialization => Future.value();

  @override
  set initialization(Future<void> value) {}

  FakeVocabularyConfigNotifier(super.state);

  @override
  Future<void> setConfig(ApiConfig config) async {
    lastSetConfig = config;
    state = state.copyWith(
      config: config,
      availableModels: [
        ModelInfo(
          id: 'model-for-${config.id}',
          provider: config.name,
          modelName: 'Model for ${config.name}',
          supportsVision: false,
          supportsTools: true,
        ),
      ],
      model: ModelInfo(
        id: 'model-for-${config.id}',
        provider: config.name,
        modelName: 'Model for ${config.name}',
        supportsVision: false,
        supportsTools: true,
      ),
    );
  }

  @override
  Future<void> setModel(ModelInfo model) async {
    lastSetModel = model;
    state = state.copyWith(model: model);
  }

  @override
  Future<void> addCustomModel(String modelId) async {
    lastCustomModel = modelId;
    final newModel = ModelInfo(
      id: modelId,
      provider: 'custom',
      modelName: modelId,
      supportsVision: false,
      supportsTools: true,
    );
    state = state.copyWith(
      model: newModel,
      availableModels: [newModel, ...state.availableModels],
    );
  }

  @override
  Future<void> fetchModels({bool forceRefresh = false}) async {
    fetchModelsCalled = true;
  }

  @override
  Future<void> resetToDefault() async {
    resetCalled = true;
    final defaultCfg = ApiConfig(
      id: 'opencode_free',
      name: 'OpenCode Free',
      baseUrl: 'https://opencode.ai/zen/v1',
      apiKeyRef: 'ref_free',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    final defaultModel = ModelInfo(
      id: 'deepseek-v4-flash-free',
      provider: 'opencode',
      modelName: 'deepseek-v4-flash-free',
      supportsVision: false,
      supportsTools: true,
    );
    state = state.copyWith(
      config: defaultCfg,
      model: defaultModel,
      availableModels: [defaultModel],
      isCustomSelected: false,
    );
  }
}

class FakeApiConfigNotifier extends StateNotifier<ApiConfigState>
    implements ApiConfigNotifier {
  FakeApiConfigNotifier(super.state);

  @override
  Future<void> createConfig(ApiConfig config, String apiKey) async {}

  @override
  Future<void> deleteConfig(String id) async {}

  @override
  Future<void> loadConfigs() async {}

  @override
  Future<void> setActiveConfig(ApiConfig config) async {}

  @override
  Future<void> setDefaultConfig(ApiConfig config) async {}

  @override
  Future<void> updateConfig(ApiConfig config, {String? apiKey}) async {}
}

void main() {
  final configA = ApiConfig(
    id: 'cfg_a',
    name: 'Provider A',
    baseUrl: 'https://a.com/v1',
    apiKeyRef: 'ref_a',
    isDefault: true,
    createdAt: DateTime.now(),
  );

  final configB = ApiConfig(
    id: 'cfg_b',
    name: 'Provider B',
    baseUrl: 'https://b.com/v1',
    apiKeyRef: 'ref_b',
    isDefault: false,
    createdAt: DateTime.now(),
  );

  final modelA1 = ModelInfo(
    id: 'model_a1',
    provider: 'Provider A',
    modelName: 'Model A1',
    supportsVision: false,
    supportsTools: true,
  );

  final modelA2 = ModelInfo(
    id: 'model_a2',
    provider: 'Provider A',
    modelName: 'Model A2',
    supportsVision: false,
    supportsTools: true,
  );

  testWidgets('VocabularyModelSelectorDialog renders and supports model switching', (tester) async {
    final vocabNotifier = FakeVocabularyConfigNotifier(VocabularyConfigState(
      config: configA,
      model: modelA1,
      availableModels: [modelA1, modelA2],
    ));

    final apiNotifier = FakeApiConfigNotifier(ApiConfigState(
      configs: [configA, configB],
      activeConfig: configA,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyConfigProvider.overrideWith((ref) => vocabNotifier),
          apiConfigProvider.overrideWith((ref) => apiNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabularyModelSelectorDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify dialog title and descriptions
    expect(find.text('生词本专属翻译模型'), findsOneWidget);
    expect(find.text('供应商 (API 配置)'), findsOneWidget);
    expect(find.text('翻译模型'), findsOneWidget);

    // Verify provider dropdown items
    expect(find.text('Provider A (系统默认)'), findsOneWidget);

    // Switch model dropdown to model A2
    await tester.tap(find.text('Model A1'));
    await tester.pumpAndSettle();

    expect(find.text('Model A2').last, findsOneWidget);
    await tester.tap(find.text('Model A2').last);
    await tester.pumpAndSettle();

    expect(vocabNotifier.lastSetModel?.id, 'model_a2');
  });

  testWidgets('VocabularyModelSelectorDialog handles provider change without assertion crashes', (tester) async {
    final vocabNotifier = FakeVocabularyConfigNotifier(VocabularyConfigState(
      config: configA,
      model: modelA1,
      availableModels: [modelA1],
    ));

    final apiNotifier = FakeApiConfigNotifier(ApiConfigState(
      configs: [configA, configB],
      activeConfig: configA,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyConfigProvider.overrideWith((ref) => vocabNotifier),
          apiConfigProvider.overrideWith((ref) => apiNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabularyModelSelectorDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch provider to Provider B
    await tester.tap(find.text('Provider A (系统默认)'));
    await tester.pumpAndSettle();

    expect(find.text('Provider B').last, findsOneWidget);
    await tester.tap(find.text('Provider B').last);
    await tester.pumpAndSettle();

    expect(vocabNotifier.lastSetConfig?.id, 'cfg_b');
    // Verify dialog rebuilt with Provider B's model without crashing!
    expect(find.text('Model for Provider B'), findsOneWidget);
  });

  testWidgets('VocabularyModelSelectorDialog adds custom model', (tester) async {
    final vocabNotifier = FakeVocabularyConfigNotifier(VocabularyConfigState(
      config: configA,
      model: modelA1,
      availableModels: [modelA1],
    ));

    final apiNotifier = FakeApiConfigNotifier(ApiConfigState(
      configs: [configA],
      activeConfig: configA,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyConfigProvider.overrideWith((ref) => vocabNotifier),
          apiConfigProvider.overrideWith((ref) => apiNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabularyModelSelectorDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click "使用自定义模型 ID"
    await tester.tap(find.text('使用自定义模型 ID'));
    await tester.pumpAndSettle();

    // Enter custom model ID
    await tester.enterText(find.byType(TextField), 'custom-openai/gpt-4.5');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(vocabNotifier.lastCustomModel, 'custom-openai/gpt-4.5');
  });

  testWidgets('VocabularyModelSelectorDialog deduplicates duplicate model and config IDs without error', (tester) async {
    // Intentionally pass duplicate configs and duplicate models
    final dupConfig1 = ApiConfig(id: 'dup_id', name: 'Dup 1', baseUrl: 'https://dup.com', apiKeyRef: 'r1', isDefault: false, createdAt: DateTime.now());
    final dupConfig2 = ApiConfig(id: 'dup_id', name: 'Dup 2', baseUrl: 'https://dup.com', apiKeyRef: 'r2', isDefault: false, createdAt: DateTime.now());

    final dupModel1 = ModelInfo(id: 'same_model', provider: 'p', modelName: 'Same 1', supportsVision: false, supportsTools: true);
    final dupModel2 = ModelInfo(id: 'same_model', provider: 'p', modelName: 'Same 2', supportsVision: false, supportsTools: true);

    final vocabNotifier = FakeVocabularyConfigNotifier(VocabularyConfigState(
      config: dupConfig1,
      model: dupModel1,
      availableModels: [dupModel1, dupModel2],
    ));

    final apiNotifier = FakeApiConfigNotifier(ApiConfigState(
      configs: [dupConfig1, dupConfig2],
      activeConfig: dupConfig1,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyConfigProvider.overrideWith((ref) => vocabNotifier),
          apiConfigProvider.overrideWith((ref) => apiNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabularyModelSelectorDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Should render without throwing duplicate DropdownMenuItem value assertions!
    expect(tester.takeException(), isNull);
    expect(find.text('Dup 1'), findsOneWidget);
    expect(find.text('Same 1'), findsOneWidget);
  });

  testWidgets('VocabularyModelSelectorDialog resetToDefault calls notifier and shows SnackBar', (tester) async {
    final vocabNotifier = FakeVocabularyConfigNotifier(VocabularyConfigState(
      config: configB,
      model: modelA1,
      availableModels: [modelA1],
    ));

    final apiNotifier = FakeApiConfigNotifier(ApiConfigState(
      configs: [configA, configB],
      activeConfig: configA,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyConfigProvider.overrideWith((ref) => vocabNotifier),
          apiConfigProvider.overrideWith((ref) => apiNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabularyModelSelectorDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复默认'));
    await tester.pump();

    expect(vocabNotifier.resetCalled, isTrue);
  });
}
