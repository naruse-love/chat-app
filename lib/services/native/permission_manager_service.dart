import '../../models/native/app_permission.dart';

/// Exception thrown when a required permission is not granted.
class PermissionDeniedException implements Exception {
  final AppPermission permission;
  final PermissionStatus status;
  final String message;

  PermissionDeniedException({
    required this.permission,
    required this.status,
    required this.message,
  });

  @override
  String toString() => message;
}

/// Unified Permission Manager Service.
/// Manages runtime permission checks, requests, and mock states for headless CI and testing.
class PermissionManagerService {
  final Map<AppPermission, PermissionStatus> _permissionStatuses = {};

  PermissionManagerService({Map<AppPermission, PermissionStatus>? initialStatuses}) {
    if (initialStatuses != null) {
      _permissionStatuses.addAll(initialStatuses);
    } else {
      _initDefaultStatuses();
    }
  }

  void _initDefaultStatuses() {
    for (final perm in AppPermission.values) {
      _permissionStatuses[perm] = PermissionStatus.granted;
    }
  }

  /// Checks the current status of [permission].
  Future<PermissionStatus> checkPermission(AppPermission permission) async {
    return _permissionStatuses[permission] ?? PermissionStatus.granted;
  }

  /// Requests [permission]. In mock/pure Dart mode, returns the configured status.
  Future<PermissionStatus> requestPermission(AppPermission permission) async {
    return _permissionStatuses[permission] ?? PermissionStatus.granted;
  }

  /// Checks whether [permission] is currently granted.
  Future<bool> hasPermission(AppPermission permission) async {
    final status = await checkPermission(permission);
    return status.isGranted;
  }

  /// Verifies that [permission] is granted; if not, throws [PermissionDeniedException].
  Future<void> ensurePermission(AppPermission permission) async {
    final status = await checkPermission(permission);
    if (!status.isGranted) {
      final msg = getFriendlyErrorMessage(permission, status);
      throw PermissionDeniedException(
        permission: permission,
        status: status,
        message: msg,
      );
    }
  }

  /// Sets mock status for a specific permission.
  void setPermissionStatus(AppPermission permission, PermissionStatus status) {
    _permissionStatuses[permission] = status;
  }

  /// Alias for [setPermissionStatus].
  void setMockPermission(AppPermission permission, PermissionStatus status) {
    setPermissionStatus(permission, status);
  }

  /// Resets all permissions to `PermissionStatus.granted`.
  void resetAllPermissions() {
    _initDefaultStatuses();
  }

  /// Returns localized friendly Chinese fallback error message for permission denial.
  String getFriendlyErrorMessage(AppPermission permission, [PermissionStatus? status]) {
    final s = status ?? _permissionStatuses[permission] ?? PermissionStatus.denied;
    if (s.isGranted) return '';

    switch (permission) {
      case AppPermission.calendar:
        return '【权限受限】未获得日历访问权限。请前往系统设置允许应用访问日历后重试。';
      case AppPermission.notification:
        return '【权限受限】未获得系统通知权限。请前往系统设置允许通知权限后重试。';
      case AppPermission.contacts:
        return '【权限受限】未获得通讯录访问权限。请前往系统设置允许通讯录权限后重试。';
      case AppPermission.location:
        return '【权限受限】未获得设备定位权限。请前往系统设置允许位置权限后重试。';
    }
  }

  /// Alias for [getFriendlyErrorMessage].
  String getRejectionErrorMessage(AppPermission permission, [PermissionStatus? status]) {
    return getFriendlyErrorMessage(permission, status);
  }
}
