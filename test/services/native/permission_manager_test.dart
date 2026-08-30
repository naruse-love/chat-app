import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/native/app_permission.dart';
import 'package:chat/services/native/permission_manager_service.dart';

void main() {
  group('AppPermission & PermissionStatus Enums Tests', () {
    test('AppPermission properties and Chinese messages', () {
      expect(AppPermission.calendar.displayName, '日历');
      expect(AppPermission.notification.displayName, '系统通知');
      expect(AppPermission.contacts.displayName, '通讯录');
      expect(AppPermission.location.displayName, '设备定位');

      expect(
        AppPermission.calendar.defaultDeniedMessage,
        '【权限受限】未获得日历访问权限。请前往系统设置允许应用访问日历后重试。',
      );
      expect(
        AppPermission.notification.defaultDeniedMessage,
        '【权限受限】未获得系统通知权限。请前往系统设置允许通知权限后重试。',
      );
      expect(
        AppPermission.contacts.defaultDeniedMessage,
        '【权限受限】未获得通讯录访问权限。请前往系统设置允许通讯录权限后重试。',
      );
      expect(
        AppPermission.location.defaultDeniedMessage,
        '【权限受限】未获得设备定位权限。请前往系统设置允许位置权限后重试。',
      );
    });

    test('PermissionStatus flags', () {
      expect(PermissionStatus.granted.isGranted, isTrue);
      expect(PermissionStatus.granted.isDenied, isFalse);

      expect(PermissionStatus.denied.isGranted, isFalse);
      expect(PermissionStatus.denied.isDenied, isTrue);

      expect(PermissionStatus.permanentlyDenied.isPermanentlyDenied, isTrue);
    });
  });

  group('PermissionManagerService Tests', () {
    late PermissionManagerService manager;

    setUp(() {
      manager = PermissionManagerService();
    });

    test('All permissions default to granted', () async {
      for (final perm in AppPermission.values) {
        final status = await manager.checkPermission(perm);
        expect(status, PermissionStatus.granted);
        expect(await manager.hasPermission(perm), isTrue);
      }
    });

    test('ensurePermission passes without error when granted', () async {
      await expectLater(manager.ensurePermission(AppPermission.calendar), completes);
    });

    test('setPermissionStatus denies permission and yields exact Chinese error', () async {
      manager.setPermissionStatus(AppPermission.calendar, PermissionStatus.denied);
      expect(await manager.hasPermission(AppPermission.calendar), isFalse);

      final errorMsg = manager.getFriendlyErrorMessage(AppPermission.calendar);
      expect(errorMsg, '【权限受限】未获得日历访问权限。请前往系统设置允许应用访问日历后重试。');

      expect(
        () async => await manager.ensurePermission(AppPermission.calendar),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'message',
          '【权限受限】未获得日历访问权限。请前往系统设置允许应用访问日历后重试。',
        )),
      );
    });

    test('All 4 permission error messages verify exactly against requirements', () {
      manager.setPermissionStatus(AppPermission.notification, PermissionStatus.permanentlyDenied);
      manager.setPermissionStatus(AppPermission.contacts, PermissionStatus.restricted);
      manager.setPermissionStatus(AppPermission.location, PermissionStatus.denied);

      expect(
        manager.getFriendlyErrorMessage(AppPermission.notification),
        '【权限受限】未获得系统通知权限。请前往系统设置允许通知权限后重试。',
      );
      expect(
        manager.getFriendlyErrorMessage(AppPermission.contacts),
        '【权限受限】未获得通讯录访问权限。请前往系统设置允许通讯录权限后重试。',
      );
      expect(
        manager.getFriendlyErrorMessage(AppPermission.location),
        '【权限受限】未获得设备定位权限。请前往系统设置允许位置权限后重试。',
      );
    });

    test('resetAllPermissions restores all to granted', () async {
      manager.setPermissionStatus(AppPermission.calendar, PermissionStatus.denied);
      manager.setPermissionStatus(AppPermission.location, PermissionStatus.denied);

      expect(await manager.hasPermission(AppPermission.calendar), isFalse);

      manager.resetAllPermissions();
      expect(await manager.hasPermission(AppPermission.calendar), isTrue);
      expect(await manager.hasPermission(AppPermission.location), isTrue);
    });
  });
}
