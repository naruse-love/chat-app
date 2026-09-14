import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/update_model.dart';

void main() {
  group('UpdateInfo - isVersionNewer', () {
    test('比较大版本号更高', () {
      expect(UpdateInfo.isVersionNewer('2.0.0', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('v2.0.0', '1.42.0+43'), isTrue);
      expect(UpdateInfo.isVersionNewer('1.0.0', '2.0.0'), isFalse);
    });

    test('比较次版本号更高', () {
      expect(UpdateInfo.isVersionNewer('1.43.0', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('v1.43.0', '1.42.0+43'), isTrue);
      expect(UpdateInfo.isVersionNewer('1.41.0', '1.42.0'), isFalse);
    });

    test('比较修订版本号更高', () {
      expect(UpdateInfo.isVersionNewer('1.42.1', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('v1.42.1', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('1.42.0', '1.42.1'), isFalse);
    });

    test('版本号相同时比较构建号', () {
      expect(UpdateInfo.isVersionNewer('1.42.0+44', '1.42.0+43'), isTrue);
      expect(UpdateInfo.isVersionNewer('1.42.0+43', '1.42.0+44'), isFalse);
      expect(UpdateInfo.isVersionNewer('1.42.0+43', '1.42.0+43'), isFalse);
    });

    test('版本完全相同时返回 false', () {
      expect(UpdateInfo.isVersionNewer('1.42.0', '1.42.0'), isFalse);
      expect(UpdateInfo.isVersionNewer('v1.42.0', '1.42.0'), isFalse);
    });

    test('前缀 v 和 V 均能正确清洗', () {
      expect(UpdateInfo.isVersionNewer('v1.43.0', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('V1.43.0', '1.42.0'), isTrue);
      expect(UpdateInfo.isVersionNewer('v1.42.0', 'v1.42.0'), isFalse);
    });
  });

  group('UpdateInfo - fromJson', () {
    test('正确解析包含 APK 附件的 GitHub Release JSON', () {
      final json = {
        'tag_name': 'v1.43.0',
        'body': '## 更新日志\n- 添加自动构建\n- 添加应用内更新检测',
        'html_url': 'https://github.com/naruse-love/chat-app/releases/tag/v1.43.0',
        'published_at': '2026-09-14T12:00:00Z',
        'assets': [
          {
            'name': 'source.tar.gz',
            'browser_download_url': 'https://github.com/.../source.tar.gz',
            'size': 1024,
          },
          {
            'name': 'chat-app-v1.43.0.apk',
            'browser_download_url':
                'https://github.com/naruse-love/chat-app/releases/download/v1.43.0/chat-app-v1.43.0.apk',
            'size': 25 * 1024 * 1024, // 25 MB
          }
        ]
      };

      final info = UpdateInfo.fromJson(
        json: json,
        currentVersion: '1.42.0+43',
      );

      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, 'v1.43.0');
      expect(info.currentVersion, '1.42.0+43');
      expect(info.releaseNotes, contains('添加自动构建'));
      expect(info.downloadUrl, contains('.apk'));
      expect(info.fileSize, 25 * 1024 * 1024);
      expect(info.formattedFileSize, '25.0 MB');
      expect(info.htmlUrl, contains('releases/tag/v1.43.0'));
      expect(info.publishedAt, isNotNull);
    });

    test('正确处理无 APK 资产但有 Release 的情况', () {
      final json = {
        'tag_name': 'v1.42.0',
        'body': '修复已知问题',
        'assets': <Map<String, dynamic>>[],
      };

      final info = UpdateInfo.fromJson(
        json: json,
        currentVersion: '1.42.0',
      );

      expect(info.hasUpdate, isFalse);
      expect(info.downloadUrl, isNull);
      expect(info.fileSize, isNull);
      expect(info.formattedFileSize, '');
    });

    test('文件大小格式化小于 1MB 时以 KB 显示', () {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.0.1',
        hasUpdate: true,
        fileSize: 512 * 1024, // 512 KB
      );
      expect(info.formattedFileSize, '512.0 KB');
    });
  });
}
