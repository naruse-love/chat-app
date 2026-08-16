/// Model representing metadata extracted from a webpage.
class FetchMetadata {
  final String title;
  final String description;
  final String author;
  final String? publishedAt;
  final String? language;
  final String? siteName;
  final String? keywords;
  final String? ogType;
  final String? ogImage;

  const FetchMetadata({
    this.title = '',
    this.description = '',
    this.author = '',
    this.publishedAt,
    this.language,
    this.siteName,
    this.keywords,
    this.ogType,
    this.ogImage,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'author': author,
      if (publishedAt != null) 'published_at': publishedAt,
      if (language != null) 'language': language,
      if (siteName != null) 'site_name': siteName,
      if (keywords != null) 'keywords': keywords,
      if (ogType != null) 'og_type': ogType,
      if (ogImage != null) 'og_image': ogImage,
    };
  }

  factory FetchMetadata.fromJson(Map<String, dynamic> json) {
    return FetchMetadata(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publishedAt: json['published_at'] as String?,
      language: json['language'] as String?,
      siteName: json['site_name'] as String?,
      keywords: json['keywords'] as String?,
      ogType: json['og_type'] as String?,
      ogImage: json['og_image'] as String?,
    );
  }
}

/// Model representing the full structured result of fetching and parsing a webpage.
class FetchResult {
  final String url;
  final String status; // 'success' | 'error'
  final String pageType; // 'article' | 'doc' | 'nav_hub' | 'login_wall' | 'captcha' | 'error_page' | 'unknown'
  final bool truncated;
  final int originalLength;
  final int maxLength;
  final double contentRatio;
  final FetchMetadata metadata;
  final String mainContent;
  final int totalLinks;
  final int internalLinks;
  final int externalLinks;
  final List<String> warnings;

  const FetchResult({
    required this.url,
    required this.status,
    required this.pageType,
    required this.truncated,
    required this.originalLength,
    required this.maxLength,
    required this.contentRatio,
    required this.metadata,
    required this.mainContent,
    this.totalLinks = 0,
    this.internalLinks = 0,
    this.externalLinks = 0,
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'status': status,
      'page_type': pageType,
      'truncated': truncated,
      'original_length': originalLength,
      'max_length': maxLength,
      'content_ratio': contentRatio,
      'metadata': metadata.toJson(),
      'main_content': mainContent,
      'links': {
        'total': totalLinks,
        'internal': internalLinks,
        'external': externalLinks,
      },
      'warnings': warnings,
    };
  }

  /// Formats the fetch result into clean, structured Markdown suitable for LLM context injection.
  String toStructuredMarkdown() {
    if (status == 'error') {
      return mainContent;
    }

    final buffer = StringBuffer();

    // 1. Title
    if (metadata.title.isNotEmpty) {
      buffer.writeln('# ${metadata.title}\n');
    }

    // 2. Metadata line
    final metaItems = <String>[];
    if (metadata.author.isNotEmpty) metaItems.add('作者: ${metadata.author}');
    if (metadata.publishedAt != null && metadata.publishedAt!.isNotEmpty) {
      metaItems.add('发布时间: ${metadata.publishedAt}');
    }
    if (metadata.siteName != null && metadata.siteName!.isNotEmpty) {
      metaItems.add('站点: ${metadata.siteName}');
    }
    if (metadata.language != null && metadata.language!.isNotEmpty) {
      metaItems.add('语言: ${metadata.language}');
    }
    if (metadata.description.isNotEmpty) {
      metaItems.add('描述: ${metadata.description}');
    }
    if (metadata.keywords != null && metadata.keywords!.isNotEmpty) {
      metaItems.add('关键词: ${metadata.keywords}');
    }

    if (metaItems.isNotEmpty) {
      buffer.writeln('> **元数据**: ${metaItems.join(' | ')}');
    }

    // 3. Status & Diagnostics bar
    final diagnostics = <String>[
      '页面类型: $pageType',
      '正文占比: ${(contentRatio * 100).toStringAsFixed(1)}%',
    ];
    if (totalLinks > 0) {
      diagnostics.add('页面链接: 共 $totalLinks 个 (站内 $internalLinks / 站外 $externalLinks)');
    }
    buffer.writeln('> **页面诊断**: ${diagnostics.join(' | ')}\n');

    // 4. Warnings if any
    if (warnings.isNotEmpty) {
      for (final warning in warnings) {
        buffer.writeln('> ⚠️ **注意**: $warning');
      }
      buffer.writeln();
    }

    // 5. Divider
    buffer.writeln('---\n');

    // 6. Main Content
    buffer.writeln(mainContent);

    // 7. Truncation notice
    if (truncated) {
      buffer.writeln('\n---');
      buffer.writeln('⚠️ **内容已截断**：原文提取长度约 $originalLength 字符，已截取前 $maxLength 字符。后续内容未显示。');
    }

    return buffer.toString().trim();
  }
}
