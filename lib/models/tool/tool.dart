import 'tool_parameter.dart';
import 'tool_security_level.dart';
import 'tool_execution_result.dart';

export 'tool_parameter.dart';
export 'tool_security_level.dart';
export 'tool_execution_result.dart';

/// Abstract base contract for all pluggable Agent tools.
abstract class Tool {
  const Tool();

  /// Unique programmatic identifier (e.g. 'web_search', 'math_eval', 'wiki_lookup').
  String get name;

  /// Human-friendly localized display name (e.g. '网络搜索', '数学计算器').
  String get displayName;

  /// Functional description passed to LLM for function calling matching.
  String get description;

  /// Security classification level (Level 0 safe to Level 3 privileged).
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  /// List of parameter descriptors accepted by this tool.
  List<ToolParameter> get parameters => const [];

  /// Exports standard OpenAI Function Calling JSON Schema.
  Map<String, dynamic> toOpenAiSchema() {
    final properties = <String, dynamic>{};
    final requiredList = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toOpenAiSchema();
      if (param.required) {
        requiredList.add(param.name);
      }
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': requiredList,
        },
      },
    };
  }

  /// Validates input arguments against defined [parameters].
  /// Returns `null` if arguments are valid, or a descriptive Chinese error message.
  String? validateArguments(Map<String, dynamic> arguments) {
    for (final param in parameters) {
      final value = arguments[param.name];
      final error = param.validate(value);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  /// Executes the tool logic with arguments.
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments);
}
