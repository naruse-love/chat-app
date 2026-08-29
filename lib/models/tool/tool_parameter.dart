/// Structured definition for an Agent tool parameter.
class ToolParameter {
  /// Parameter identifier (e.g. 'query', 'url', 'expression', 'timezone').
  final String name;

  /// JSON Schema primitive type: 'string', 'number', 'integer', 'boolean', 'array', 'object'.
  final String type;

  /// Human-readable and LLM-targeted description of this parameter.
  final String description;

  /// Whether this parameter is mandatory for tool execution. Default: true.
  final bool required;

  /// Optional enum constraints (allowed string values).
  final List<String>? enumValues;

  /// Optional default value if omitted by LLM.
  final dynamic defaultValue;

  /// Optional item type if [type] == 'array' (e.g. 'string', 'object').
  final String? arrayItemType;

  const ToolParameter({
    required this.name,
    required this.description,
    this.type = 'string',
    this.required = true,
    this.enumValues,
    this.defaultValue,
    this.arrayItemType,
  });

  /// Converts this parameter descriptor into an OpenAI Function Calling JSON Schema property map.
  Map<String, dynamic> toOpenAiSchema() {
    final map = <String, dynamic>{
      'type': type,
      'description': description,
    };
    if (enumValues != null && enumValues!.isNotEmpty) {
      map['enum'] = enumValues;
    }
    if (defaultValue != null) {
      map['default'] = defaultValue;
    }
    if (type == 'array' && arrayItemType != null) {
      map['items'] = {'type': arrayItemType};
    }
    return map;
  }

  /// Serialization to standard Map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'description': description,
      'required': required,
      if (enumValues != null) 'enumValues': enumValues,
      if (defaultValue != null) 'defaultValue': defaultValue,
      if (arrayItemType != null) 'arrayItemType': arrayItemType,
    };
  }

  /// Deserialization from Map.
  factory ToolParameter.fromJson(Map<String, dynamic> json) {
    return ToolParameter(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      required: json['required'] as bool? ?? true,
      enumValues: (json['enumValues'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      defaultValue: json['defaultValue'],
      arrayItemType: json['arrayItemType'] as String?,
    );
  }

  /// Validates a supplied runtime argument against this parameter's constraints.
  /// Returns null if valid, or a descriptive Chinese error string if invalid.
  String? validate(dynamic value) {
    if (value == null) {
      if (required) {
        return "缺少必需参数 '$name'";
      }
      return null;
    }

    switch (type) {
      case 'string':
        if (value is! String) {
          return "参数 '$name' 应为字符串类型 (string)，实际为 ${value.runtimeType}";
        }
        if (enumValues != null && enumValues!.isNotEmpty && !enumValues!.contains(value)) {
          return "参数 '$name' 值 '$value' 不在允许的枚举范围 [${enumValues!.join(', ')}] 内";
        }
        break;
      case 'number':
        if (value is! num && (value is! String || num.tryParse(value) == null)) {
          return "参数 '$name' 应为数值类型 (number)，实际为 '$value'";
        }
        break;
      case 'integer':
        if (value is! int && (value is! String || int.tryParse(value) == null)) {
          return "参数 '$name' 应为整数类型 (integer)，实际为 '$value'";
        }
        break;
      case 'boolean':
        if (value is! bool && value != 'true' && value != 'false') {
          return "参数 '$name' 应为布尔类型 (boolean)，实际为 '$value'";
        }
        break;
      case 'array':
        if (value is! List) {
          return "参数 '$name' 应为列表类型 (array)，实际为 ${value.runtimeType}";
        }
        break;
      case 'object':
        if (value is! Map) {
          return "参数 '$name' 应为对象类型 (object)，实际为 ${value.runtimeType}";
        }
        break;
    }
    return null;
  }
}
