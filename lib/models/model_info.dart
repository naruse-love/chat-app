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

    bool? explicitVision;
    if (json['supports_vision'] is bool) {
      explicitVision = json['supports_vision'];
    } else if (json['supportsVision'] is bool) {
      explicitVision = json['supportsVision'];
    } else if (json['vision'] is bool) {
      explicitVision = json['vision'];
    }

    bool visionSupport = explicitVision ?? false;
    if (explicitVision == null) {
      // 检查 architecture 字段
      final architecture = json['architecture'] as Map<String, dynamic>?;
      if (architecture != null) {
        final modality = architecture['modality'] as String?;
        if (modality != null && (modality.contains('image') || modality.contains('vision'))) {
          visionSupport = true;
        }
        final inputModalities = architecture['input_modalities'] as List?;
        if (inputModalities != null && inputModalities.any((m) => m.toString().contains('image') || m.toString().contains('vision'))) {
          visionSupport = true;
        }
      }

      // 检查顶层 modalities 字段
      final modalities = json['modalities'] as List?;
      if (modalities != null && modalities.any((m) => m.toString().contains('image') || m.toString().contains('vision'))) {
        visionSupport = true;
      }
      final inputModalities = json['input_modalities'] as List?;
      if (inputModalities != null && inputModalities.any((m) => m.toString().contains('image') || m.toString().contains('vision'))) {
        visionSupport = true;
      }

      // 如果上述字段都没有明确指示，则使用启发式推理
      if (!visionSupport) {
        visionSupport = _inferVisionSupport(provider, modelName);
      }
    }

    final supportsTools = json['supports_tools'] as bool? ??
        json['supportsTools'] as bool? ??
        _inferToolsSupport(provider, modelName);

    return ModelInfo(
      id: id,
      provider: provider,
      modelName: modelName,
      supportsVision: visionSupport,
      supportsTools: supportsTools,
      ownedBy: ownedBy,
    );
  }

  static bool _inferVisionSupport(String provider, String modelName) {
    final nameLower = modelName.toLowerCase();
    
    // Explicit indicators in name
    if (nameLower.contains('vision') || 
        nameLower.contains('vl') || 
        nameLower.contains('vlm') || 
        nameLower.contains('pixtral') || 
        nameLower.contains('llava') || 
        nameLower.contains('paligemma') ||
        nameLower.contains('glm-4v') ||
        nameLower.contains('qwen-vl') ||
        nameLower.contains('internvl') ||
        nameLower.contains('minicpm-v')) {
      return true;
    }
    
    // Known models/families
    if (nameLower.startsWith('gpt-4o') || 
        nameLower.startsWith('gpt-4.1') ||
        nameLower.startsWith('gpt-5') ||
        nameLower.startsWith('gpt-4-vision')) {
      return true;
    }
    if (nameLower.startsWith('claude-3') || 
        nameLower.startsWith('claude-4') || 
        nameLower.contains('claude-sonnet') || 
        nameLower.contains('claude-opus') || 
        nameLower.contains('claude-haiku')) {
      return true;
    }
    if (nameLower.startsWith('gemini') && !nameLower.contains('embedding')) {
      return true;
    }
    if (nameLower.startsWith('llama-3.2-11b') || 
        nameLower.startsWith('llama-3.2-90b')) {
      return true;
    }
    if (nameLower.contains('gemma-3')) {
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
