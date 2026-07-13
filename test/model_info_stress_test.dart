import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/model_info.dart';

void main() {
  group('ModelInfo.fromApiResponse Stress and Edge Case Tests', () {
    
    group('Edge Case: Empty or Invalid Model ID', () {
      test('should parse when ID is empty string', () {
        final json = {'id': ''};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, '');
        expect(model.provider, 'unknown');
        expect(model.modelName, '');
      });

      test('should throw TypeError when ID is missing', () {
        final json = {'owned_by': 'system'};
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });

      test('should throw TypeError when ID is null', () {
        final json = {'id': null};
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });

      test('should throw TypeError when ID is of incorrect type (int)', () {
        final json = {'id': 123};
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });

      test('should throw TypeError when ID is of incorrect type (List)', () {
        final json = {
          'id': ['openai', 'gpt-4o']
        };
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });
    });

    group('Edge Case: Custom Provider/Model Names with Multiple Slashes', () {
      test('should split correctly with three levels (provider/subprovider/model)', () {
        final json = {'id': 'openai/azure/gpt-4o'};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, 'openai/azure/gpt-4o');
        expect(model.provider, 'openai');
        expect(model.modelName, 'azure/gpt-4o');
      });

      test('should split correctly with many levels (a/b/c/d/e/f)', () {
        final json = {'id': 'a/b/c/d/e/f'};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, 'a/b/c/d/e/f');
        expect(model.provider, 'a');
        expect(model.modelName, 'b/c/d/e/f');
      });

      test('should handle leading slash', () {
        final json = {'id': '/provider/model'};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, '/provider/model');
        expect(model.provider, '');
        expect(model.modelName, 'provider/model');
      });

      test('should handle trailing slash', () {
        final json = {'id': 'provider/model/'};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, 'provider/model/');
        expect(model.provider, 'provider');
        expect(model.modelName, 'model/');
      });

      test('should handle consecutive slashes', () {
        final json = {'id': 'provider//model'};
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, 'provider//model');
        expect(model.provider, 'provider');
        expect(model.modelName, '/model');
      });
    });

    group('Edge Case: Corrupted JSON Responses', () {
      test('should not throw TypeError when supports_vision is not a boolean (string) and should infer based on model ID', () {
        final json = {
          'id': 'openai/gpt-4o',
          'supports_vision': 'true',
        };
        final model = ModelInfo.fromApiResponse(json);
        expect(model.supportsVision, isTrue);
      });

      test('should throw TypeError when supports_tools is not a boolean (int)', () {
        final json = {
          'id': 'openai/gpt-4o',
          'supports_tools': 1,
        };
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });

      test('should throw TypeError when owned_by is not a String (List)', () {
        final json = {
          'id': 'openai/gpt-4o',
          'owned_by': ['system'],
        };
        expect(() => ModelInfo.fromApiResponse(json), throwsA(isA<TypeError>()));
      });

      test('should successfully parse with extra unknown keys in JSON', () {
        final json = {
          'id': 'openai/gpt-4o',
          'owned_by': 'openai',
          'extra_key_1': 'some value',
          'extra_key_2': 12345,
          'nested_extra': {
            'deep': [1, 2, 3]
          }
        };
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, 'openai/gpt-4o');
        expect(model.provider, 'openai');
        expect(model.modelName, 'gpt-4o');
        expect(model.ownedBy, 'openai');
      });
    });

    group('Edge Case: Large JSON Responses', () {
      test('should parse efficiently a very large number of models in a list', () {
        final stopwatch = Stopwatch()..start();
        
        final List<Map<String, dynamic>> largeList = List.generate(5000, (index) {
          return {
            'id': 'provider_$index/model_name_$index',
            'owned_by': 'owner_$index',
            'supports_vision': index % 2 == 0,
            'supports_tools': index % 3 == 0,
            'metadata': {
              'description': 'This is a description for model $index ' * 10,
              'parameters': index * 1000000,
              'tags': ['tag1', 'tag2', 'tag3', 'tag4', 'tag5'],
            }
          };
        });

        final models = largeList.map((j) => ModelInfo.fromApiResponse(j)).toList();
        
        stopwatch.stop();
        expect(models.length, 5000);
        expect(models[0].id, 'provider_0/model_name_0');
        expect(models[0].provider, 'provider_0');
        expect(models[0].modelName, 'model_name_0');
        expect(models[0].supportsVision, isTrue);
        expect(models[0].supportsTools, isTrue);

        expect(models[4999].id, 'provider_4999/model_name_4999');
        expect(models[4999].provider, 'provider_4999');
        expect(models[4999].modelName, 'model_name_4999');
        expect(models[4999].supportsVision, isFalse);
        expect(models[4999].supportsTools, isFalse);

        // Ensure performance is acceptable (under 500ms for 5000 models is extremely safe)
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      });

      test('should handle extremely long strings in ID and other fields', () {
        final longId = 'provider/${'a' * 10000}';
        final longOwner = 'b' * 10000;
        final json = {
          'id': longId,
          'owned_by': longOwner,
        };
        final model = ModelInfo.fromApiResponse(json);
        expect(model.id, longId);
        expect(model.provider, 'provider');
        expect(model.modelName, 'a' * 10000);
        expect(model.ownedBy, longOwner);
      });
    });
  });
}
