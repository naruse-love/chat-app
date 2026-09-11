import 'dart:async';
import 'package:flutter/services.dart';

/// 系统通知栏常驻快捷入口服务抽象接口
abstract class IPersistentNotificationService {
  /// 显示或更新系统通知栏常驻快捷通知
  Future<void> showPersistentNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  });

  /// 取消/移除指定的常驻快捷通知
  Future<void> cancelPersistentNotification(String id);

  /// 检查指定的常驻快捷通知是否处于活跃显示状态
  Future<bool> isNotificationActive(String id);

  /// 获取冷启动或外部唤醒时的通知载荷（获取后通常自动消费清空）
  Future<String?> getLaunchPayload();

  /// 用户在系统通知栏点击该常驻通知时的广播事件流（携带 payload）
  Stream<String> get onNotificationTapped;

  /// 释放服务资源
  Future<void> dispose();
}

/// 内存模拟实现的常驻通知服务（适用于单元测试与 Headless 环境）
class InMemoryPersistentNotificationService
    implements IPersistentNotificationService {
  final Set<String> _activeIds = {};
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  String? _launchPayload;

  @override
  Future<void> showPersistentNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  }) async {
    _activeIds.add(id);
    if (payload != null) {
      _launchPayload = payload;
    }
  }

  @override
  Future<void> cancelPersistentNotification(String id) async {
    _activeIds.remove(id);
  }

  @override
  Future<bool> isNotificationActive(String id) async {
    return _activeIds.contains(id);
  }

  @override
  Future<String?> getLaunchPayload() async {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  @override
  Stream<String> get onNotificationTapped => _tapController.stream;

  /// 用于测试：模拟用户点击了通知栏
  void simulateTap(String payload) {
    if (!_tapController.isClosed) {
      _tapController.add(payload);
    }
  }

  /// 用于测试：设置启动载荷
  void setLaunchPayload(String? payload) {
    _launchPayload = payload;
  }

  @override
  Future<void> dispose() async {
    _activeIds.clear();
    await _tapController.close();
  }
}

/// 基于 Android MethodChannel 的真实系统通知栏常驻服务
/// 支持在非 Android 或 Headless 环境下安全降级与异常保护
class MethodChannelPersistentNotificationService
    implements IPersistentNotificationService {
  static const String defaultChannelName =
      'com.example.chat/persistent_notification';

  final MethodChannel _channel;
  final Set<String> _fallbackActiveIds = {};
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  String? _fallbackLaunchPayload;

  MethodChannelPersistentNotificationService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(defaultChannelName) {
    try {
      _channel.setMethodCallHandler(_handleMethodCall);
    } catch (_) {
      // 单元测试或无 Binding 环境下优雅降级
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNotificationTapped') {
      final payload = call.arguments?.toString() ?? '';
      if (!_tapController.isClosed) {
        _tapController.add(payload);
      }
    }
    return null;
  }

  @override
  Future<void> showPersistentNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  }) async {
    _fallbackActiveIds.add(id);
    _fallbackLaunchPayload = payload;

    try {
      await _channel.invokeMethod('showPersistentNotification', {
        'id': id,
        'title': title,
        'body': body,
        'payload': payload,
      });
    } on MissingPluginException {
      // 桌面平台、Web 或测试环境优雅降级
    } on PlatformException {
      // 权限未授予或其他平台级限制优雅降级
    } catch (_) {
      // 防止非受检异常中断业务流程
    }
  }

  @override
  Future<void> cancelPersistentNotification(String id) async {
    _fallbackActiveIds.remove(id);

    try {
      await _channel.invokeMethod('cancelPersistentNotification', {'id': id});
    } on MissingPluginException {
      // 降级保护
    } on PlatformException {
      // 降级保护
    } catch (_) {}
  }

  @override
  Future<bool> isNotificationActive(String id) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'isNotificationActive',
        {'id': id},
      );
      if (res != null) return res;
    } catch (_) {}
    return _fallbackActiveIds.contains(id);
  }

  @override
  Future<String?> getLaunchPayload() async {
    try {
      final res = await _channel.invokeMethod<String>('getLaunchPayload');
      if (res != null && res.isNotEmpty) {
        return res;
      }
    } catch (_) {}

    final fallback = _fallbackLaunchPayload;
    _fallbackLaunchPayload = null;
    return fallback;
  }

  @override
  Stream<String> get onNotificationTapped => _tapController.stream;

  @override
  Future<void> dispose() async {
    _fallbackActiveIds.clear();
    await _tapController.close();
  }
}
