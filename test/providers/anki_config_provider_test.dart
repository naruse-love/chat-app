import 'package:flutter_test/flutter_test.dart';
import 'package:chat/providers/anki_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnkiConfigProvider Tests', () {
    test('loads default configuration when SharedPreferences is empty', () async {
      final notifier = AnkiConfigNotifier();
      // 等待异步 _loadConfig 完成
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.deckName, '日语生词本');
      expect(notifier.state.modelName, '日语生词本-AI');
      expect(notifier.state.isLoaded, isTrue);
    });

    test('loads saved configuration from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'anki_deck_name': '自定义牌组',
        'anki_model_name': '自定义模型',
      });

      final notifier = AnkiConfigNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.deckName, '自定义牌组');
      expect(notifier.state.modelName, '自定义模型');
      expect(notifier.state.isLoaded, isTrue);
    });

    test('updateDeckName updates state and persists to SharedPreferences', () async {
      final notifier = AnkiConfigNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.updateDeckName('JLPT N1生词');
      expect(notifier.state.deckName, 'JLPT N1生词');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('anki_deck_name'), 'JLPT N1生词');

      // 空白名称被忽略
      await notifier.updateDeckName('   ');
      expect(notifier.state.deckName, 'JLPT N1生词');
    });

    test('updateModelName updates state and persists to SharedPreferences', () async {
      final notifier = AnkiConfigNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.updateModelName('JLPT卡片模板');
      expect(notifier.state.modelName, 'JLPT卡片模板');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('anki_model_name'), 'JLPT卡片模板');

      // 空白名称被忽略
      await notifier.updateModelName('   ');
      expect(notifier.state.modelName, 'JLPT卡片模板');
    });
  });
}
