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

  /// 用于后续发起精确查词的规范原词（当 kanji 带区分标签如「アクセル (accel)」时，此字段为「アクセル」）
  final String? disambiguationWord;

  const WordCandidate({
    required this.kanji,
    required this.reading,
    required this.definition,
    this.partOfSpeech = '',
    this.source = CandidateSource.weblio,
    this.disambiguationWord,
  });

  /// 获取用于后续发起精确查词的目标原词（自动剥离区分后缀或括号）
  String get searchWord {
    if (disambiguationWord != null && disambiguationWord!.trim().isNotEmpty) {
      return disambiguationWord!.trim();
    }
    if (kanji.contains('（') || kanji.contains('(') || kanji.contains('【')) {
      final base = kanji.split(RegExp(r'[（\(【]')).first.trim();
      if (base.isNotEmpty) return base;
    }
    return kanji;
  }

  Map<String, dynamic> toJson() => {
        'kanji': kanji,
        'reading': reading,
        'definition': definition,
        'partOfSpeech': partOfSpeech,
        'source': source.name,
        if (disambiguationWord != null) 'disambiguationWord': disambiguationWord,
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
      disambiguationWord: json['disambiguationWord']?.toString().trim(),
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
          source == other.source &&
          disambiguationWord == other.disambiguationWord;

  @override
  int get hashCode =>
      kanji.hashCode ^
      reading.hashCode ^
      definition.hashCode ^
      partOfSpeech.hashCode ^
      source.hashCode ^
      disambiguationWord.hashCode;

  @override
  String toString() =>
      'WordCandidate(kanji: $kanji, reading: $reading, def: $definition, pos: $partOfSpeech, source: ${source.name}, target: $searchWord)';
}
