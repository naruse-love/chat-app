import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/model_info.dart';

void main() {
  group('ModelInfo Parsing', () {
    test('should parse provider and modelName correctly', () {
      final model1 = ModelInfo.fromApiResponse({
        'id': 'openai/gpt-4o',
        'owned_by': 'system',
      });
      expect(model1.provider, 'openai');
      expect(model1.modelName, 'gpt-4o');
      expect(model1.ownedBy, 'system');

      final model2 = ModelInfo.fromApiResponse({
        'id': 'openai/azure/gpt-4o',
      });
      expect(model2.provider, 'openai');
      expect(model2.modelName, 'azure/gpt-4o');

      final model3 = ModelInfo.fromApiResponse({
        'id': 'gpt-4o',
      });
      expect(model3.provider, 'unknown');
      expect(model3.modelName, 'gpt-4o');
    });

    test('should infer vision support based on model family and name clues', () {
      final visionModels = [
        'openai/gpt-4o',
        'openai/gpt-4o-mini',
        'openai/gpt-4-vision-preview',
        'openai/gpt-5-preview',
        'anthropic/claude-3-5-sonnet',
        'anthropic/claude-4-opus',
        'google/gemini-1.5-flash',
        'google/gemini-2.0-pro',
        'meta/llama-3.2-11b',
        'custom/some-vl-model',
        'custom/qwen2.5-vl',
        'custom/pixtral-12b',
        'custom/paligemma-3b',
        'custom/glm-4v',
        'custom/gemma-3-27b',
      ];

      for (final id in visionModels) {
        final model = ModelInfo.fromApiResponse({'id': id});
        expect(model.supportsVision, isTrue, reason: '$id should support vision');
      }

      final nonVisionModels = [
        'openai/gpt-3.5-turbo',
        'deepseek/deepseek-chat',
        'meta/llama-3-8b',
        'google/gemini-embedding-001',
      ];

      for (final id in nonVisionModels) {
        final model = ModelInfo.fromApiResponse({'id': id});
        expect(model.supportsVision, isFalse, reason: '$id should NOT support vision');
      }
    });

    test('should infer tools support based on provider and name clues', () {
      final toolModels = [
        'openai/gpt-4o',
        'openai/gpt-3.5-turbo',
        'anthropic/claude-3-haiku',
        'google/gemini-1.5-pro',
        'deepseek/deepseek-chat',
        'meta/llama-3-8b-instruct',
        'qwen/qwen-72b-chat',
      ];

      for (final id in toolModels) {
        final model = ModelInfo.fromApiResponse({'id': id});
        expect(model.supportsTools, isTrue, reason: '$id should support tools');
      }

      final nonToolModels = [
        'openai/text-embedding-ada-002',
        'openai/gpt-3.5-turbo-0301',
        'custom/whisper-1',
      ];

      for (final id in nonToolModels) {
        final model = ModelInfo.fromApiResponse({'id': id});
        expect(model.supportsTools, isFalse, reason: '$id should NOT support tools');
      }
    });

    test('should honor explicit capability overrides in JSON response', () {
      // snake_case keys
      final model1 = ModelInfo.fromApiResponse({
        'id': 'openai/gpt-3.5-turbo',
        'supports_vision': true,
        'supports_tools': false,
      });
      expect(model1.supportsVision, isTrue);
      expect(model1.supportsTools, isFalse);

      // camelCase keys
      final model2 = ModelInfo.fromApiResponse({
        'id': 'custom/some-vl-model',
        'supportsVision': false,
        'supportsTools': true,
      });
      expect(model2.supportsVision, isFalse);
      expect(model2.supportsTools, isTrue);

      // Architecture modalities
      final model3 = ModelInfo.fromApiResponse({
        'id': 'custom/arch-model',
        'architecture': {
          'input_modalities': ['text', 'image'],
        },
      });
      expect(model3.supportsVision, isTrue);

      final model4 = ModelInfo.fromApiResponse({
        'id': 'custom/arch-model-2',
        'architecture': {
          'modality': 'text+image->text',
        },
      });
      expect(model4.supportsVision, isTrue);

      // Top level modalities
      final model5 = ModelInfo.fromApiResponse({
        'id': 'custom/top-modal',
        'modalities': ['text', 'image'],
      });
      expect(model5.supportsVision, isTrue);
    });

    test('should serialize to and from JSON correctly', () {
      final model = ModelInfo(
        id: 'openai/gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
        ownedBy: 'system',
      );

      final json = model.toJson();
      expect(json['id'], 'openai/gpt-4o');
      expect(json['provider'], 'openai');
      expect(json['modelName'], 'gpt-4o');
      expect(json['supportsVision'], isTrue);
      expect(json['supportsTools'], isTrue);
      expect(json['ownedBy'], 'system');

      final deserialized = ModelInfo.fromJson(json);
      expect(deserialized.id, model.id);
      expect(deserialized.provider, model.provider);
      expect(deserialized.modelName, model.modelName);
      expect(deserialized.supportsVision, model.supportsVision);
      expect(deserialized.supportsTools, model.supportsTools);
      expect(deserialized.ownedBy, model.ownedBy);
    });
  });
}
