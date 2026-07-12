import 'package:json_annotation/json_annotation.dart';

part 'api_config.g.dart';

@JsonSerializable()
class ApiConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final bool isDefault;
  final DateTime createdAt;

  ApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.isDefault,
    required this.createdAt,
  });

  factory ApiConfig.fromJson(Map<String, dynamic> json) => _$ApiConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ApiConfigToJson(this);

  ApiConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
