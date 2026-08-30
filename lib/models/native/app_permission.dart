/// Application permissions for privileged mobile capabilities.
enum AppPermission {
  calendar('日历', '访问与管理系统日历日程', '【权限受限】未获得日历访问权限。请前往系统设置允许应用访问日历后重试。'),
  notification('系统通知', '发送本地提醒与闹钟通知', '【权限受限】未获得系统通知权限。请前往系统设置允许通知权限后重试。'),
  contacts('通讯录', '安全检索通讯录联系人', '【权限受限】未获得通讯录访问权限。请前往系统设置允许通讯录权限后重试。'),
  location('设备定位', '获取GPS经纬度与地理位置', '【权限受限】未获得设备定位权限。请前往系统设置允许位置权限后重试。');

  final String displayName;
  final String description;
  final String defaultDeniedMessage;

  const AppPermission(this.displayName, this.description, this.defaultDeniedMessage);
}

/// Status of an application permission.
enum PermissionStatus {
  /// Permission has been granted by user or system.
  granted('已允许'),

  /// Permission was denied by user but can be re-requested.
  denied('已拒绝'),

  /// Permission was permanently denied (user selected 'Don't ask again' or restricted by OS).
  permanentlyDenied('永久拒绝'),

  /// Permission is restricted by system policy (e.g. parental controls).
  restricted('受限制');

  final String displayName;

  const PermissionStatus(this.displayName);

  /// True if permission is granted.
  bool get isGranted => this == PermissionStatus.granted;

  /// True if permission is not granted.
  bool get isDenied => this != PermissionStatus.granted;

  /// True if permanently denied.
  bool get isPermanentlyDenied => this == PermissionStatus.permanentlyDenied;
}
