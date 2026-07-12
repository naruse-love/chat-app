import 'package:json_annotation/json_annotation.dart';

part 'model_info.g.dart';

@JsonSerializable()
class ModelInfo {
  final String id;
  final String provider;
  final String modelName;
  final bool supportsVision;
  final bool supportsTools;
  final String? ownedBy;

  ModelInfo({
    required this.id,
    required this.provider,
    required this.modelName,
    required this.supportsVision,
    required this.supportsTools,
    this.ownedBy,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) => _$ModelInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ModelInfoToJson(this);

  factory ModelInfo.fromApiResponse(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final ownedBy = json['owned_by'] as String? ?? json['ownedBy'] as String?;
    
    final parts = id.split('/');
    final provider = parts.length > 1 ? parts[0] : 'unknown';
    final modelName = parts.length > 1 ? parts.sublist(1).join('/') : id;

    final supportsVision = json['supports_vision'] as bool? ??
        json['supportsVision'] as bool? ??
        _inferVisionSupport(provider, modelName);

    final supportsTools = json['supports_tools'] as bool? ??
        json['supportsTools'] as bool? ??
        _inferToolsSupport(provider, modelName);

    return ModelInfo(
      id: id,
      provider: provider,
      modelName: modelName,
      supportsVision: supportsVision,
      supportsTools: supportsTools,
      ownedBy: ownedBy,
    );
  }

  static bool _inferVisionSupport(String provider, String modelName) {
    final nameLower = modelName.toLowerCase();
    
    // Explicit indicators in name
    if (nameLower.contains('vision') || 
        nameLower.contains('vl') || 
        nameLower.contains('pixtral') || 
        nameLower.contains('llava') || 
        nameLower.contains('paligemma')) {
      return true;
    }
    
    // Known models/families
    if (nameLower.startsWith('gpt-4o') || 
        nameLower.startsWith('gpt-4-vision')) {
      return true;
    }
    if (nameLower.startsWith('claude-3')) {
      return true;
    }
    if (nameLower.startsWith('gemini-1.5') || 
        nameLower.startsWith('gemini-2.0') || 
        nameLower.startsWith('gemini-2.5')) {
      return true;
    }
    if (nameLower.startsWith('llama-3.2-11b') || 
        nameLower.startsWith('llama-3.2-90b')) {
      return true;
    }
    
    return false;
  }

  static bool _inferToolsSupport(String provider, String modelName) {
    final nameLower = modelName.toLowerCase();
    final providerLower = provider.toLowerCase();

    // Exclude non-chat tasks
    if (nameLower.contains('embedding') || 
        nameLower.contains('rerank') || 
        nameLower.contains('moderation') || 
        nameLower.contains('whisper') || 
        nameLower.contains('tts') || 
        nameLower.contains('dall-e')) {
      return false;
    }

    // Known providers that support tool calling in modern chat models
    if (providerLower == 'openai' || 
        providerLower == 'anthropic' || 
        providerLower == 'google' || 
        providerLower == 'mistral' || 
        providerLower == 'deepseek') {
      // Exclude legacy models
      if (nameLower.contains('gpt-3.5-turbo-0301')) {
        return false;
      }
      return true;
    }

    // Known tool calling model families
    if (nameLower.contains('gpt-4') || 
        nameLower.contains('gpt-3.5') || 
        nameLower.contains('claude-3') || 
        nameLower.contains('gemini') || 
        nameLower.contains('llama-3') || 
        nameLower.contains('qwen') || 
        nameLower.contains('mistral') || 
        nameLower.contains('mixtral') || 
        nameLower.contains('deepseek')) {
      return true;
    }

    return false;
  }
}
