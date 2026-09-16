import '../models/vocabulary_entry.dart';

/// Anki 导出结果模型
class AnkiExportResult {
  final int successCount;
  final int skipCount;
  final List<VocabularyEntry> failedEntries;
  final List<String> errors;
  final String? modelUpgradedFrom;
  final String? modelUpgradedTo;

  const AnkiExportResult({
    this.successCount = 0,
    this.skipCount = 0,
    this.failedEntries = const [],
    this.errors = const [],
    this.modelUpgradedFrom,
    this.modelUpgradedTo,
  });

  bool get isSuccess => failedEntries.isEmpty && errors.isEmpty;
  int get totalProcessed => successCount + skipCount + failedEntries.length;

  @override
  String toString() =>
      'AnkiExportResult(success: $successCount, skipped: $skipCount, failed: ${failedEntries.length}, errors: $errors, modelUpgradedFrom: $modelUpgradedFrom, modelUpgradedTo: $modelUpgradedTo)';
}

/// Anki 导出服务抽象接口
abstract class AnkiExportServiceInterface {
  /// 检测 AnkiDroid 是否在当前设备上可用
  Future<bool> isAnkiDroidAvailable();

  /// 请求 AnkiDroid Content Provider 授权
  Future<bool> requestPermission();

  /// 批量导出生词条目到指定牌组与卡片模板
  Future<AnkiExportResult> exportEntries(
    List<VocabularyEntry> entries, {
    String? deckName,
    String? modelName,
  });
}
