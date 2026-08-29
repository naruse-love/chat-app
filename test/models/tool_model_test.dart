import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool.dart';

/// Test tool implementation for verifying abstract Tool behaviors.
class MockMathTool extends Tool {
  @override
  String get name => 'math_test';

  @override
  String get displayName => '数学测试工具';

  @override
  String get description => 'A test tool for mathematical evaluation.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'expression',
      type: 'string',
      description: 'The math expression to evaluate',
      required: true,
    ),
    ToolParameter(
      name: 'precision',
      type: 'integer',
      description: 'Decimal precision',
      required: false,
      defaultValue: 2,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final expr = arguments['expression'] as String;
    final precision = arguments['precision'] as int? ?? 2;
    return ToolExecutionResult.success(
      toolName: name,
      content: 'Result for $expr with precision $precision',
      rawData: {'expression': expr, 'precision': precision},
    );
  }
}

void main() {
  group('ToolSecurityLevel Tests', () {
    test('Enums, levels, labels, descriptions, and helper properties', () {
      expect(ToolSecurityLevel.safe.level, equals(0));
      expect(ToolSecurityLevel.safe.label, equals('安全'));
      expect(ToolSecurityLevel.safe.requiresConfirmation, isFalse);
      expect(ToolSecurityLevel.safe.isSafeToAutoExecute, isTrue);

      expect(ToolSecurityLevel.readOnly.level, equals(1));
      expect(ToolSecurityLevel.readOnly.label, equals('只读'));
      expect(ToolSecurityLevel.readOnly.requiresConfirmation, isFalse);
      expect(ToolSecurityLevel.readOnly.isSafeToAutoExecute, isTrue);

      expect(ToolSecurityLevel.sensitiveConfirm.level, equals(2));
      expect(ToolSecurityLevel.sensitiveConfirm.label, equals('敏感确认'));
      expect(ToolSecurityLevel.sensitiveConfirm.requiresConfirmation, isTrue);
      expect(ToolSecurityLevel.sensitiveConfirm.isSafeToAutoExecute, isFalse);

      expect(ToolSecurityLevel.privilegedNative.level, equals(3));
      expect(ToolSecurityLevel.privilegedNative.label, equals('特权原生'));
      expect(ToolSecurityLevel.privilegedNative.requiresConfirmation, isTrue);
      expect(ToolSecurityLevel.privilegedNative.isSafeToAutoExecute, isFalse);
    });

    test('Deserialization from JSON name and integer level with safe fallback', () {
      expect(ToolSecurityLevel.fromJson('safe'), equals(ToolSecurityLevel.safe));
      expect(ToolSecurityLevel.fromJson('READONLY'), equals(ToolSecurityLevel.readOnly));
      expect(ToolSecurityLevel.fromJson('sensitiveConfirm'), equals(ToolSecurityLevel.sensitiveConfirm));
      expect(ToolSecurityLevel.fromJson('privilegedNative'), equals(ToolSecurityLevel.privilegedNative));
      expect(ToolSecurityLevel.fromJson('unknown_level'), equals(ToolSecurityLevel.safe));

      expect(ToolSecurityLevel.fromLevel(0), equals(ToolSecurityLevel.safe));
      expect(ToolSecurityLevel.fromLevel(1), equals(ToolSecurityLevel.readOnly));
      expect(ToolSecurityLevel.fromLevel(2), equals(ToolSecurityLevel.sensitiveConfirm));
      expect(ToolSecurityLevel.fromLevel(3), equals(ToolSecurityLevel.privilegedNative));
      expect(ToolSecurityLevel.fromLevel(99), equals(ToolSecurityLevel.safe));

      expect(ToolSecurityLevel.safe.toJson(), equals('safe'));
      expect(ToolSecurityLevel.readOnly.toJson(), equals('readOnly'));
    });
  });

  group('ToolParameter Tests', () {
    test('Initialization and OpenAI JSON schema generation', () {
      const param = ToolParameter(
        name: 'query',
        type: 'string',
        description: 'The search query to look up on the web.',
        required: true,
      );

      expect(param.name, equals('query'));
      expect(param.type, equals('string'));
      expect(param.required, isTrue);

      final schema = param.toOpenAiSchema();
      expect(schema['type'], equals('string'));
      expect(schema['description'], equals('The search query to look up on the web.'));
      expect(schema.containsKey('enum'), isFalse);
      expect(schema.containsKey('default'), isFalse);
    });

    test('Enum constraints and default values in schema', () {
      const param = ToolParameter(
        name: 'mode',
        type: 'string',
        description: 'Execution mode',
        required: false,
        enumValues: ['fast', 'deep', 'auto'],
        defaultValue: 'auto',
      );

      final schema = param.toOpenAiSchema();
      expect(schema['type'], equals('string'));
      expect(schema['enum'], equals(['fast', 'deep', 'auto']));
      expect(schema['default'], equals('auto'));
    });

    test('Array type schema with items specification', () {
      const param = ToolParameter(
        name: 'tags',
        type: 'array',
        description: 'List of tags',
        arrayItemType: 'string',
      );

      final schema = param.toOpenAiSchema();
      expect(schema['type'], equals('array'));
      expect(schema['items'], equals({'type': 'string'}));
    });

    test('Serialization and deserialization roundtrip', () {
      const original = ToolParameter(
        name: 'count',
        type: 'integer',
        description: 'Number of items',
        required: false,
        defaultValue: 10,
        enumValues: ['5', '10', '20'],
        arrayItemType: null,
      );

      final json = original.toJson();
      final restored = ToolParameter.fromJson(json);

      expect(restored.name, equals(original.name));
      expect(restored.type, equals(original.type));
      expect(restored.description, equals(original.description));
      expect(restored.required, equals(original.required));
      expect(restored.defaultValue, equals(original.defaultValue));
      expect(restored.enumValues, equals(original.enumValues));
    });

    test('ToolParameter.validate: Required vs optional validation', () {
      const requiredParam = ToolParameter(
        name: 'target',
        description: 'Required target',
        required: true,
      );
      const optionalParam = ToolParameter(
        name: 'opt',
        description: 'Optional param',
        required: false,
      );

      expect(requiredParam.validate(null), contains("缺少必需参数 'target'"));
      expect(optionalParam.validate(null), isNull);
    });

    test('ToolParameter.validate: String type and enum constraint validation', () {
      const strParam = ToolParameter(
        name: 'unit',
        type: 'string',
        description: 'Unit of measurement',
        enumValues: ['km', 'mi', 'm'],
      );

      expect(strParam.validate('km'), isNull);
      expect(strParam.validate('m'), isNull);
      expect(strParam.validate('lightyear'), contains('不在允许的枚举范围'));
      expect(strParam.validate(123), contains("应为字符串类型 (string)"));
    });

    test('ToolParameter.validate: Number and integer validation with stringified numbers', () {
      const numParam = ToolParameter(name: 'val', type: 'number', description: 'Numeric value');
      const intParam = ToolParameter(name: 'cnt', type: 'integer', description: 'Integer count');

      expect(numParam.validate(3.14), isNull);
      expect(numParam.validate(42), isNull);
      expect(numParam.validate('3.14'), isNull);
      expect(numParam.validate('not_a_number'), contains("应为数值类型 (number)"));

      expect(intParam.validate(42), isNull);
      expect(intParam.validate('100'), isNull);
      expect(intParam.validate(3.14), contains("应为整数类型 (integer)"));
      expect(intParam.validate('3.14'), contains("应为整数类型 (integer)"));
    });

    test('ToolParameter.validate: Boolean, array, and object type validations', () {
      const boolParam = ToolParameter(name: 'flag', type: 'boolean', description: 'Flag');
      const arrayParam = ToolParameter(name: 'list', type: 'array', description: 'List');
      const objParam = ToolParameter(name: 'map', type: 'object', description: 'Object');

      expect(boolParam.validate(true), isNull);
      expect(boolParam.validate('true'), isNull);
      expect(boolParam.validate('false'), isNull);
      expect(boolParam.validate('yes'), contains("应为布尔类型 (boolean)"));

      expect(arrayParam.validate(['a', 'b']), isNull);
      expect(arrayParam.validate('a,b'), contains("应为列表类型 (array)"));

      expect(objParam.validate({'key': 'val'}), isNull);
      expect(objParam.validate(['not_a_map']), contains("应为对象类型 (object)"));
    });
  });

  group('ToolExecutionResult Tests', () {
    test('Success and failure factories with properties', () {
      final success = ToolExecutionResult.success(
        toolName: 'web_search',
        content: 'Search results formatted',
        rawData: [{'title': 'Example', 'url': 'https://example.com'}],
        executionDuration: const Duration(milliseconds: 350),
        metadata: {'query': 'flutter'},
      );

      expect(success.toolName, equals('web_search'));
      expect(success.success, isTrue);
      expect(success.content, equals('Search results formatted'));
      expect(success.errorMessage, isNull);
      expect(success.rawData, isNotNull);
      expect(success.executionDuration.inMilliseconds, equals(350));
      expect(success.toToolMessageContent(), equals('Search results formatted'));
      expect(success.toString(), contains('web_search'));

      final failure = ToolExecutionResult.failure(
        toolName: 'url_fetch',
        errorMessage: '404 Not Found',
        executionDuration: const Duration(milliseconds: 120),
      );

      expect(failure.toolName, equals('url_fetch'));
      expect(failure.success, isFalse);
      expect(failure.errorMessage, equals('404 Not Found'));
      expect(failure.content, contains('404 Not Found'));
    });

    test('Serialization and deserialization roundtrip', () {
      final original = ToolExecutionResult.success(
        toolName: 'math_eval',
        content: '42',
        rawData: 42,
        executionDuration: const Duration(milliseconds: 15),
        metadata: {'engine': 'eval'},
      );

      final json = original.toJson();
      final restored = ToolExecutionResult.fromJson(json);

      expect(restored.toolName, equals(original.toolName));
      expect(restored.success, equals(original.success));
      expect(restored.content, equals(original.content));
      expect(restored.rawData, equals(original.rawData));
      expect(restored.executionDuration.inMilliseconds, equals(15));
      expect(restored.metadata?['engine'], equals('eval'));
    });
  });

  group('Tool Base Class Tests', () {
    test('Custom tool subclass, schema export, and validateArguments', () {
      final tool = MockMathTool();

      expect(tool.name, equals('math_test'));
      expect(tool.displayName, equals('数学测试工具'));
      expect(tool.securityLevel, equals(ToolSecurityLevel.safe));

      final schema = tool.toOpenAiSchema();
      expect(schema['type'], equals('function'));
      expect(schema['function']['name'], equals('math_test'));
      expect(schema['function']['description'], equals('A test tool for mathematical evaluation.'));

      final paramsSchema = schema['function']['parameters'] as Map<String, dynamic>;
      expect(paramsSchema['type'], equals('object'));
      expect(paramsSchema['required'], equals(['expression']));
      expect((paramsSchema['properties'] as Map).containsKey('expression'), isTrue);
      expect((paramsSchema['properties'] as Map).containsKey('precision'), isTrue);

      expect(tool.validateArguments({'expression': '1 + 1', 'precision': 4}), isNull);
      expect(tool.validateArguments({'precision': 4}), contains("缺少必需参数 'expression'"));
      expect(tool.validateArguments({'expression': '1 + 1', 'precision': 'invalid'}), contains("应为整数类型"));
    });

    test('Multi-parameter validation error detection', () async {
      final tool = MockMathTool();
      final res = await tool.execute({'expression': '2^8', 'precision': 0});
      expect(res.success, isTrue);
      expect(res.content, contains('Result for 2^8 with precision 0'));
    });
  });
}
