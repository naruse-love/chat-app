import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/update_model.dart';

/// 版本更新与检测服务
class UpdateService {
  final Dio _dio;
  final String owner;
  final String repo;

  static const String defaultOwner = 'naruse-love';
  static const String defaultRepo = 'chat-app';
  static const String fallbackVersion = '1.43.0+44';

  UpdateService({
    Dio? dio,
    this.owner = defaultOwner,
    this.repo = defaultRepo,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'Accept': 'application/vnd.github.v3+json',
                  'User-Agent': 'chat-app-updater',
                },
              ),
            );

  /// 获取当前 App 版本号（格式: 1.43.0+44）
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;
      if (version.isNotEmpty && buildNumber.isNotEmpty) {
        return '$version+$buildNumber';
      } else if (version.isNotEmpty) {
        return version;
      }
    } catch (e) {
      debugPrint('获取当前应用版本失败，使用回退版本: $e');
    }
    return fallbackVersion;
  }

  /// 检查 GitHub Release 最新版本
  Future<UpdateInfo> checkForUpdate({String? currentVersion}) async {
    final current = currentVersion ?? await getCurrentVersion();
    final url = 'https://api.github.com/repos/$owner/$repo/releases/latest';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      if (response.statusCode == 200 && response.data != null) {
        return UpdateInfo.fromJson(
          json: response.data!,
          currentVersion: current,
        );
      } else {
        return UpdateInfo(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          releaseNotes: '暂无更新信息',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 仓库尚未发布任何 Release
        return UpdateInfo(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          releaseNotes: '当前已是最新版本',
        );
      }
      rethrow;
    }
  }

  /// 下载 APK 安装包到临时目录
  Future<String> downloadApk(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}${Platform.pathSeparator}chat-app-update.apk';

    // 如果已存在旧文件先删除
    final file = File(savePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    await _dio.download(
      downloadUrl,
      savePath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );

    return savePath;
  }

  /// 调用系统安装器打开 APK
  /// 启动成功返回 null，失败返回错误描述信息
  Future<String?> installApk(String filePath) async {
    try {
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        return result.message;
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// 在外部浏览器打开 Release 页面
  Future<bool> openReleasePage(String? url) async {
    final targetUrl = url ?? 'https://github.com/$owner/$repo/releases';
    final uri = Uri.parse(targetUrl);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
