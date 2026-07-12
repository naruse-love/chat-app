// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelInfo _$ModelInfoFromJson(Map<String, dynamic> json) => ModelInfo(
  id: json['id'] as String,
  provider: json['provider'] as String,
  modelName: json['modelName'] as String,
  supportsVision: json['supportsVision'] as bool,
  supportsTools: json['supportsTools'] as bool,
  ownedBy: json['ownedBy'] as String?,
);

Map<String, dynamic> _$ModelInfoToJson(ModelInfo instance) => <String, dynamic>{
  'id': instance.id,
  'provider': instance.provider,
  'modelName': instance.modelName,
  'supportsVision': instance.supportsVision,
  'supportsTools': instance.supportsTools,
  'ownedBy': instance.ownedBy,
};
