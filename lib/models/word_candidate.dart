/// 候选词来源
enum CandidateSource {
  /// 抓取自 Weblio 词典同音多义项
  weblio,

  /// 大模型 AI 智能推测
  aiInference,
}

/// 触发候选词确认的原因
enum CandidateReason {
  /// 纯假名输入，存在多个对应汉字或截然不同的词义
  pureKana,

  /// 词典未收录或拼写笔误，由 AI 智能推测的可能目标词
  typoOrNotFound,
}

/// 单词候选项目模型
class WordCandidate {
  /// 汉字形式或目标词原形（如「箸」、「橋」、「食べる」）
  final String kanji;

  /// 假名读音（如「はし」、「たべる」）
  final String reading;

  /// 简明释义（中文或日语）
  final String definition;

  /// 词性标记（如［名］、［動上一］）
  final String partOfSpeech;

  /// 来源（Weblio 词典或 AI 推测）
  final CandidateSource source;

  const WordCandidate({
    required this.kanji,
    required this.reading,
    required this.definition,
    this.partOfSpeech = '',
    this.source = CandidateSource.weblio,
  });

  Map<String, dynamic> toJson() => {
        'kanji': kanji,
        'reading': reading,
        'definition': definition,
        'partOfSpeech': partOfSpeech,
        'source': source.name,
      };

  factory WordCandidate.fromJson(Map<String, dynamic> json) {
    return WordCandidate(
      kanji: json['kanji']?.toString().trim() ?? '',
      reading: json['reading']?.toString().trim() ?? '',
      definition: json['definition']?.toString().trim() ?? '',
      partOfSpeech: json['partOfSpeech']?.toString().trim() ?? '',
      source: json['source'] == 'aiInference'
          ? CandidateSource.aiInference
          : CandidateSource.weblio,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordCandidate &&
          runtimeType == other.runtimeType &&
          kanji == other.kanji &&
          reading == other.reading &&
          definition == other.definition &&
          partOfSpeech == other.partOfSpeech &&
          source == other.source;

  @override
  int get hashCode =>
      kanji.hashCode ^
      reading.hashCode ^
      definition.hashCode ^
      partOfSpeech.hashCode ^
      source.hashCode;

  @override
  String toString() =>
      'WordCandidate(kanji: $kanji, reading: $reading, def: $definition, pos: $partOfSpeech, source: ${source.name})';
}
