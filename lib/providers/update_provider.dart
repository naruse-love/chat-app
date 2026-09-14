import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/update_model.dart';
import '../services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  notAvailable,
  downloading,
  downloaded,
  error,
}

class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? updateInfo;
  final double downloadProgress; // 0.0 ~ 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? downloadedFilePath;
  final String? errorMessage;
  final bool autoCheckEnabled;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.updateInfo,
    this.downloadProgress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.downloadedFilePath,
    this.errorMessage,
    this.autoCheckEnabled = true,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? updateInfo,
    bool clearUpdateInfo = false,
    double? downloadProgress,
    int? receivedBytes,
    int? totalBytes,
    String? downloadedFilePath,
    bool clearDownloadedFilePath = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? autoCheckEnabled,
  }) {
    return UpdateState(
      status: status ?? this.status,
      updateInfo: clearUpdateInfo ? null : (updateInfo ?? this.updateInfo),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedFilePath: clearDownloadedFilePath
          ? null
          : (downloadedFilePath ?? this.downloadedFilePath),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
    );
  }
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;
  CancelToken? _cancelToken;
  static const String _autoCheckKey = 'auto_check_update_enabled';

  UpdateNotifier({
    UpdateService? updateService,
    bool autoCheckEnabled = true,
  })  : _updateService = updateService ?? UpdateService(),
        super(UpdateState(autoCheckEnabled: autoCheckEnabled)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final enabled = prefs.getBool(_autoCheckKey) ?? true;
      state = state.copyWith(autoCheckEnabled: enabled);
    } catch (_) {}
  }

  /// 切换是否在启动时自动检测更新
  Future<void> setAutoCheckEnabled(bool enabled) async {
    state = state.copyWith(autoCheckEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoCheckKey, enabled);
    } catch (_) {}
  }

  /// 检查新版本
  /// [silent] 为 true 时表示静默检查，失败不进入 error 状态打扰用户
  Future<UpdateInfo?> checkForUpdate({bool silent = false}) async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading) {
      return state.updateInfo;
    }

    state = state.copyWith(
      status: UpdateStatus.checking,
      clearErrorMessage: true,
    );

    try {
      final info = await _updateService.checkForUpdate();
      if (!mounted) return null;

      if (info.hasUpdate) {
        state = state.copyWith(
          status: UpdateStatus.available,
          updateInfo: info,
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.notAvailable,
          updateInfo: info,
        );
      }
      return info;
    } catch (e) {
      if (!mounted) return null;
      if (!silent) {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: '检查更新失败，请确认网络连接后重试',
        );
      } else {
        state = state.copyWith(status: UpdateStatus.idle);
      }
      return null;
    }
  }

  /// 开始下载并安装 APK
  Future<void> downloadAndInstall() async {
    final info = state.updateInfo;
    final downloadUrl = info?.downloadUrl;

    if (downloadUrl == null || downloadUrl.isEmpty) {
      // 若没有 APK 直接附件，跳转浏览器网页
      await _updateService.openReleasePage(info?.htmlUrl);
      return;
    }

    _cancelToken = CancelToken();
    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0.0,
      receivedBytes: 0,
      totalBytes: 0,
      clearErrorMessage: true,
    );

    try {
      final filePath = await _updateService.downloadApk(
        downloadUrl,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloadProgress: progress.clamp(0.0, 1.0),
            receivedBytes: received,
            totalBytes: total,
          );
        },
      );

      if (!mounted) return;

      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadedFilePath: filePath,
        downloadProgress: 1.0,
      );

      // 触发安装
      final installError = await _updateService.installApk(filePath);
      if (installError != null) {
        if (!mounted) return;
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: '启动安装器失败: $installError，可尝试前往发布页手动下载。',
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        state = state.copyWith(status: UpdateStatus.available);
      } else {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: '下载安装包失败，请检查网络或前往浏览器下载',
        );
      }
    }
  }

  /// 取消当前下载
  void cancelDownload() {
    _cancelToken?.cancel('用户取消下载');
    _cancelToken = null;
    state = state.copyWith(
      status: UpdateStatus.available,
      downloadProgress: 0.0,
      receivedBytes: 0,
      totalBytes: 0,
    );
  }

  /// 打开网页端 Releases
  Future<void> openReleaseInBrowser() async {
    await _updateService.openReleasePage(state.updateInfo?.htmlUrl);
  }

  /// 关闭/忽略更新弹窗
  void dismissUpdate() {
    state = state.copyWith(status: UpdateStatus.idle);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  final service = ref.watch(updateServiceProvider);
  return UpdateNotifier(updateService: service);
});
