import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native/native_services.dart';

/// 常驻通知状态
class PersistentNotificationState {
  final bool isEnabled;
  final bool isInitializing;

  const PersistentNotificationState({
    this.isEnabled = false,
    this.isInitializing = true,
  });

  PersistentNotificationState copyWith({
    bool? isEnabled,
    bool? isInitializing,
  }) {
    return PersistentNotificationState(
      isEnabled: isEnabled ?? this.isEnabled,
      isInitializing: isInitializing ?? this.isInitializing,
    );
  }
}

/// 系统通知栏常驻查词快捷入口状态管理
class PersistentNotificationNotifier
    extends StateNotifier<PersistentNotificationState> {
  static const String prefKey = 'persistent_vocab_shortcut_enabled';
  static const String notificationId = 'chat_persistent_vocab';
  static const String notificationTitle = '📚 日语生词快捷查询';
  static const String notificationBody = '点击快速进入生词查询与 Anki 词卡';
  static const String notificationPayload = '/vocabulary';

  final IPersistentNotificationService _notificationService;

  PersistentNotificationNotifier(this._notificationService)
      : super(const PersistentNotificationState()) {
    _initPreference();
  }

  Future<void> _initPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final enabled = prefs.getBool(prefKey) ?? false;
      if (enabled) {
        await _notificationService.showPersistentNotification(
          id: notificationId,
          title: notificationTitle,
          body: notificationBody,
          payload: notificationPayload,
        );
        if (!mounted) return;
      }

      state = state.copyWith(
        isEnabled: enabled,
        isInitializing: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isInitializing: false);
    }
  }

  /// 切换常驻通知栏快捷入口开关
  Future<void> togglePersistentNotification(bool enable) async {
    state = state.copyWith(isEnabled: enable);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, enable);

      if (enable) {
        await _notificationService.showPersistentNotification(
          id: notificationId,
          title: notificationTitle,
          body: notificationBody,
          payload: notificationPayload,
        );
      } else {
        await _notificationService.cancelPersistentNotification(notificationId);
      }
    } catch (_) {}

    if (!mounted) return;
    state = state.copyWith(isEnabled: enable);
  }
}

/// Provider for PersistentNotificationNotifier
final persistentNotificationProvider = StateNotifierProvider<
    PersistentNotificationNotifier, PersistentNotificationState>((ref) {
  final service = ref.watch(persistentNotificationServiceProvider);
  return PersistentNotificationNotifier(service);
});
