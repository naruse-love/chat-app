import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('UpdateService', () {
    test('正确解析 GitHub Releases 200 响应并返回更新信息', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('/releases/latest')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'tag_name': 'v1.44.0',
                    'body': '新特性上线',
                    'html_url': 'https://github.com/naruse-love/chat-app/releases/tag/v1.44.0',
                    'published_at': '2026-09-14T10:00:00Z',
                    'assets': [
                      {
                        'name': 'chat-app-v1.44.0.apk',
                        'browser_download_url':
                            'https://github.com/naruse-love/chat-app/releases/download/v1.44.0/chat-app.apk',
                        'size': 30 * 1024 * 1024,
                      }
                    ],
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final service = UpdateService(dio: dio);
      final updateInfo = await service.checkForUpdate(currentVersion: '1.43.0+44');

      expect(updateInfo.hasUpdate, isTrue);
      expect(updateInfo.latestVersion, 'v1.44.0');
      expect(updateInfo.currentVersion, '1.43.0+44');
      expect(updateInfo.releaseNotes, '新特性上线');
      expect(updateInfo.downloadUrl, contains('.apk'));
      expect(updateInfo.fileSize, 30 * 1024 * 1024);
    });

    test('当远程返回 404（无 Release）时优雅降级为无更新', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 404,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = UpdateService(dio: dio);
      final updateInfo = await service.checkForUpdate(currentVersion: '1.43.0+44');

      expect(updateInfo.hasUpdate, isFalse);
      expect(updateInfo.releaseNotes, '当前已是最新版本');
    });

    test('当遇到 500 服务器错误时抛出 DioException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 500,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = UpdateService(dio: dio);
      expect(
        () => service.checkForUpdate(currentVersion: '1.43.0+44'),
        throwsA(isA<DioException>()),
      );
    });

    test('getCurrentVersion 在未初始化测试环境下安全回退', () async {
      final service = UpdateService();
      final version = await service.getCurrentVersion();
      // 在无原生环境的命令行单元测试下，应安全回退到 fallbackVersion
      expect(version.isNotEmpty, isTrue);
      expect(version, contains('.'));
    });
  });
}
