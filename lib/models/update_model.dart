class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String? htmlUrl;
  final DateTime? publishedAt;
  final int? fileSize;
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes = '',
    this.downloadUrl,
    this.htmlUrl,
    this.publishedAt,
    this.fileSize,
    required this.hasUpdate,
  });

  /// 比较两个版本号，判断 remote 是否高于 current
  /// 支持格式如: "v1.43.0", "1.43.0", "1.42.0+43"
  static bool isVersionNewer(String remote, String current) {
    final cleanRemote = _cleanVersion(remote);
    final cleanCurrent = _cleanVersion(current);

    final remoteParts = _parseVersionParts(cleanRemote);
    final currentParts = _parseVersionParts(cleanCurrent);

    final maxLen = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;

    for (int i = 0; i < maxLen; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }

    // 主版本号完全相同时，检查 build number (+后面的数字)
    final remoteBuild = _parseBuildNumber(cleanRemote);
    final currentBuild = _parseBuildNumber(cleanCurrent);
    if (remoteBuild != null && currentBuild != null) {
      return remoteBuild > currentBuild;
    }

    return false;
  }

  static String _cleanVersion(String v) {
    var trimmed = v.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      trimmed = trimmed.substring(1);
    }
    return trimmed;
  }

  static List<int> _parseVersionParts(String version) {
    final base = version.split('+').first;
    return base
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  static int? _parseBuildNumber(String version) {
    if (!version.contains('+')) return null;
    final buildPart = version.split('+').last;
    return int.tryParse(buildPart.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  factory UpdateInfo.fromJson({
    required Map<String, dynamic> json,
    required String currentVersion,
  }) {
    final tagName = json['tag_name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final htmlUrl = json['html_url'] as String?;
    final publishedStr = json['published_at'] as String?;
    final publishedAt =
        publishedStr != null ? DateTime.tryParse(publishedStr) : null;

    String? apkUrl;
    int? size;

    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          size = asset['size'] as int?;
          break;
        }
      }
    }

    final hasUpdate = isVersionNewer(tagName, currentVersion);

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: tagName,
      releaseNotes: body,
      downloadUrl: apkUrl,
      htmlUrl: htmlUrl,
      publishedAt: publishedAt,
      fileSize: size,
      hasUpdate: hasUpdate,
    );
  }

  String get formattedFileSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
