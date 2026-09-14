import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/models/update_model.dart';
import 'package:chat/providers/update_provider.dart';
import 'package:chat/services/update_service.dart';

class FakeUpdateService extends UpdateService {
  UpdateInfo? mockUpdateInfo;
  bool shouldThrow = false;
  String? mockInstallError;

  @override
  Future<UpdateInfo> checkForUpdate({String? currentVersion}) async {
    if (shouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/releases/latest'),
        message: '网络连接超时',
      );
    }
    return mockUpdateInfo ??
        UpdateInfo(
          currentVersion: currentVersion ?? '1.43.0+44',
          latestVersion: '1.43.0+44',
          hasUpdate: false,
        );
  }

  @override
  Future<String> downloadApk(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (shouldThrow) {
      throw Exception('网络中断');
    }
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    return '/tmp/test-update.apk';
  }

  @override
  Future<String?> installApk(String filePath) async {
    return mockInstallError;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UpdateNotifier', () {
    test('初始状态为 idle 且自动检查默认开启', () async {
      final fakeService = FakeUpdateService();
      final notifier = UpdateNotifier(updateService: fakeService);

      expect(notifier.state.status, UpdateStatus.idle);
      expect(notifier.state.autoCheckEnabled, isTrue);
      expect(notifier.state.updateInfo, isNull);
    });

    test('checkForUpdate 发现新版本时状态流转为 available', () async {
      final fakeService = FakeUpdateService();
      fakeService.mockUpdateInfo = const UpdateInfo(
        currentVersion: '1.43.0+44',
        latestVersion: '1.44.0',
        hasUpdate: true,
        releaseNotes: '新版本发布',
        downloadUrl: 'https://example.com/app.apk',
      );

      final notifier = UpdateNotifier(updateService: fakeService);
      final info = await notifier.checkForUpdate(silent: false);

      expect(info, isNotNull);
      expect(info!.hasUpdate, isTrue);
      expect(notifier.state.status, UpdateStatus.available);
      expect(notifier.state.updateInfo?.latestVersion, '1.44.0');
    });

    test('checkForUpdate 无新版本时状态流转为 notAvailable', () async {
      final fakeService = FakeUpdateService();
      fakeService.mockUpdateInfo = const UpdateInfo(
        currentVersion: '1.43.0+44',
        latestVersion: '1.43.0+44',
        hasUpdate: false,
      );

      final notifier = UpdateNotifier(updateService: fakeService);
      final info = await notifier.checkForUpdate(silent: false);

      expect(info, isNotNull);
      expect(info!.hasUpdate, isFalse);
      expect(notifier.state.status, UpdateStatus.notAvailable);
    });

    test('checkForUpdate 非静默检测抛出异常时进入 error 状态', () async {
      final fakeService = FakeUpdateService();
      fakeService.shouldThrow = true;

      final notifier = UpdateNotifier(updateService: fakeService);
      final info = await notifier.checkForUpdate(silent: false);

      expect(info, isNull);
      expect(notifier.state.status, UpdateStatus.error);
      expect(notifier.state.errorMessage, contains('检查更新失败'));
    });

    test('checkForUpdate 静默检测异常时回到 idle 状态不打扰用户', () async {
      final fakeService = FakeUpdateService();
      fakeService.shouldThrow = true;

      final notifier = UpdateNotifier(updateService: fakeService);
      final info = await notifier.checkForUpdate(silent: true);

      expect(info, isNull);
      expect(notifier.state.status, UpdateStatus.idle);
      expect(notifier.state.errorMessage, isNull);
    });

    test('setAutoCheckEnabled 更新配置并持久化', () async {
      final fakeService = FakeUpdateService();
      final notifier = UpdateNotifier(updateService: fakeService);

      await notifier.setAutoCheckEnabled(false);
      expect(notifier.state.autoCheckEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_check_update_enabled'), isFalse);
    });

    test('downloadAndInstall 正常完成下载并尝试触发安装', () async {
      final fakeService = FakeUpdateService();
      fakeService.mockUpdateInfo = const UpdateInfo(
        currentVersion: '1.43.0+44',
        latestVersion: '1.44.0',
        hasUpdate: true,
        downloadUrl: 'https://example.com/app.apk',
      );

      final notifier = UpdateNotifier(updateService: fakeService);
      await notifier.checkForUpdate();
      await notifier.downloadAndInstall();

      expect(notifier.state.status, UpdateStatus.downloaded);
      expect(notifier.state.downloadProgress, 1.0);
      expect(notifier.state.downloadedFilePath, '/tmp/test-update.apk');
    });

    test('dismissUpdate 将状态重置为 idle', () {
      final fakeService = FakeUpdateService();
      final notifier = UpdateNotifier(updateService: fakeService);
      notifier.dismissUpdate();
      expect(notifier.state.status, UpdateStatus.idle);
    });
  });
}
