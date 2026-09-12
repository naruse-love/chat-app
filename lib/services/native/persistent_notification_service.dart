import 'dart:async';
import 'package:flutter/services.dart';

/// 系统通知栏常驻快捷入口服务抽象接口
abstract class IPersistentNotificationService {
  /// 显示或更新系统通知栏常驻快捷通知（支持行内输入 RemoteInput）
  Future<void> showPersistentNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  });

  /// 更新通知栏以展示查词结果（BigTextStyle 展开卡片与行内输入框）
  Future<void> updateSearchResultNotification({
    required String id,
    required String word,
    String? reading,
    String? definitionJa,
    String? definitionSc,
    String? partOfSpeech,
    bool isLoading = false,
    String? error,
  });

  /// 取消/移除指定的常驻快捷通知
  Future<void> cancelPersistentNotification(String id);

  /// 检查指定的常驻快捷通知是否处于活跃显示状态
  Future<bool> isNotificationActive(String id);

  /// 获取冷启动或外部唤醒时的通知载荷（获取后通常自动消费清空）
  Future<String?> getLaunchPayload();

  /// 用户在系统通知栏点击该常驻通知主体的广播事件流（携带 payload）
  Stream<String> get onNotificationTapped;

  /// 用户在系统通知栏行内输入框（RemoteInput）提交搜索词的广播事件流
  Stream<String> get onInlineQuerySubmitted;

  /// 获取并清空原生端待处理的行内查询列表（用于冷启动或后台引擎拉起时防丢失）
  Future<List<String>> getPendingInlineQueries();

  /// 释放服务资源
  Future<void> dispose();
}

/// 模拟通知显示的数据结构，便于单元测试与状态观察
class NotificationDisplayData {
  final String id;
  final String title;
  final String body;
  final String? payload;
  final String? word;
  final String? reading;
  final String? definitionJa;
  final String? definitionSc;
  final String? partOfSpeech;
  final bool isLoading;
  final String? error;

  const NotificationDisplayData({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
    this.word,
    this.reading,
    this.definitionJa,
    this.definitionSc,
    this.partOfSpeech,
    this.isLoading = false,
    this.error,
  });
}

/// 内存模拟实现的常驻通知服务（适用于单元测试与 Headless 环境）
class InMemoryPersistentNotificationService
    implements IPersistentNotificationService {
  final Set<String> _activeIds = {};
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  final StreamController<String> _inlineQueryController =
      StreamController<String>.broadcast();
  String? _launchPayload;
  final Map<String, NotificationDisplayData> _displayedNotifications = {};

  NotificationDisplayData? getNotificationData(String id) =>
      _displayedNotifications[id];

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
    _displayedNotifications[id] = NotificationDisplayData(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<void> updateSearchResultNotification({
    required String id,
    required String word,
    String? reading,
    String? definitionJa,
    String? definitionSc,
    String? partOfSpeech,
    bool isLoading = false,
    String? error,
  }) async {
    _activeIds.add(id);
    final title = isLoading
        ? '🔍 正在查询「$word」...'
        : (error != null
            ? '⚠️ 未找到「$word」的释义'
            : (reading != null && reading.isNotEmpty && reading != word
                ? '📖 $word【$reading】'
                : '📖 $word'));
    final body = isLoading
        ? '正在获取释义与翻译，请稍候...'
        : (error ?? definitionSc ?? definitionJa ?? '');

    _displayedNotifications[id] = NotificationDisplayData(
      id: id,
      title: title,
      body: body,
      word: word,
      reading: reading,
      definitionJa: definitionJa,
      definitionSc: definitionSc,
      partOfSpeech: partOfSpeech,
      isLoading: isLoading,
      error: error,
    );
  }

  @override
  Future<void> cancelPersistentNotification(String id) async {
    _activeIds.remove(id);
    _displayedNotifications.remove(id);
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

  @override
  Stream<String> get onInlineQuerySubmitted => _inlineQueryController.stream;

  /// 用于测试：模拟用户点击了通知栏
  void simulateTap(String payload) {
    if (!_tapController.isClosed) {
      _tapController.add(payload);
    }
  }

  /// 用于测试：模拟用户在通知栏行内输入框提交了单词
  void simulateInlineQuery(String query) {
    if (!_inlineQueryController.isClosed) {
      _inlineQueryController.add(query);
    }
  }

  final List<String> _pendingQueries = [];

  /// 用于测试：添加原生待处理查询
  void addPendingQuery(String query) {
    _pendingQueries.add(query);
  }

  @override
  Future<List<String>> getPendingInlineQueries() async {
    final list = List<String>.from(_pendingQueries);
    _pendingQueries.clear();
    return list;
  }

  /// 用于测试：设置启动载荷
  void setLaunchPayload(String? payload) {
    _launchPayload = payload;
  }

  @override
  Future<void> dispose() async {
    _activeIds.clear();
    _displayedNotifications.clear();
    _pendingQueries.clear();
    await _tapController.close();
    await _inlineQueryController.close();
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
  final StreamController<String> _inlineQueryController =
      StreamController<String>.broadcast();
  String? _fallbackLaunchPayload;
  final Map<String, NotificationDisplayData> _fallbackNotifications = {};

  NotificationDisplayData? getFallbackNotification(String id) =>
      _fallbackNotifications[id];

  MethodChannelPersistentNotificationService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(defaultChannelName) {
    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      _channel.invokeMethod('clientReady').catchError((_) => null);
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
    } else if (call.method == 'onInlineQuerySubmitted') {
      String query = '';
      if (call.arguments is Map) {
        query = (call.arguments['query'] ?? '').toString();
      } else if (call.arguments != null) {
        query = call.arguments.toString();
      }
      final trimmed = query.trim();
      if (trimmed.isNotEmpty && !_inlineQueryController.isClosed) {
        _inlineQueryController.add(trimmed);
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
    _fallbackNotifications[id] = NotificationDisplayData(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );

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
  Future<void> updateSearchResultNotification({
    required String id,
    required String word,
    String? reading,
    String? definitionJa,
    String? definitionSc,
    String? partOfSpeech,
    bool isLoading = false,
    String? error,
  }) async {
    _fallbackActiveIds.add(id);
    final title = isLoading
        ? '🔍 正在查询「$word」...'
        : (error != null
            ? '⚠️ 未找到「$word」的释义'
            : (reading != null && reading.isNotEmpty && reading != word
                ? '📖 $word【$reading】'
                : '📖 $word'));
    final body = isLoading
        ? '正在获取释义与翻译，请稍候...'
        : (error ?? definitionSc ?? definitionJa ?? '');

    _fallbackNotifications[id] = NotificationDisplayData(
      id: id,
      title: title,
      body: body,
      word: word,
      reading: reading,
      definitionJa: definitionJa,
      definitionSc: definitionSc,
      partOfSpeech: partOfSpeech,
      isLoading: isLoading,
      error: error,
    );

    try {
      await _channel.invokeMethod('updateSearchResultNotification', {
        'id': id,
        'word': word,
        'reading': reading,
        'definitionJa': definitionJa,
        'definitionSc': definitionSc,
        'partOfSpeech': partOfSpeech,
        'isLoading': isLoading,
        'error': error,
      });
    } on MissingPluginException {
      // 桌面平台、Web 或测试环境优雅降级
    } on PlatformException {
      // 平台异常优雅降级
    } catch (_) {
      // 防止非受检异常中断业务流程
    }
  }

  @override
  Future<void> cancelPersistentNotification(String id) async {
    _fallbackActiveIds.remove(id);
    _fallbackNotifications.remove(id);

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
  Stream<String> get onInlineQuerySubmitted => _inlineQueryController.stream;

  @override
  Future<List<String>> getPendingInlineQueries() async {
    try {
      final res =
          await _channel.invokeMethod<List<dynamic>>('getPendingInlineQueries');
      if (res == null) return [];
      final list = <String>[];
      for (final item in res) {
        if (item is String && item.trim().isNotEmpty) {
          list.add(item.trim());
        } else if (item is Map) {
          final q = item['query']?.toString().trim();
          if (q != null && q.isNotEmpty) {
            list.add(q);
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    _fallbackActiveIds.clear();
    _fallbackNotifications.clear();
    await _tapController.close();
    await _inlineQueryController.close();
  }
}
