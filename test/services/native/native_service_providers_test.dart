import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/services/native/native_services.dart';

void main() {
  test('Native Service Providers resolve properly via ProviderContainer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final calendarSvc = container.read(calendarServiceProvider);
    expect(calendarSvc, isA<ICalendarService>());
    expect(calendarSvc, isA<InMemoryCalendarService>());

    final notificationSvc = container.read(notificationServiceProvider);
    expect(notificationSvc, isA<INotificationService>());
    expect(notificationSvc, isA<InMemoryNotificationService>());

    final contactsSvc = container.read(contactsServiceProvider);
    expect(contactsSvc, isA<IContactsService>());
    expect(contactsSvc, isA<InMemoryContactsService>());

    final locationSvc = container.read(locationServiceProvider);
    expect(locationSvc, isA<ILocationService>());
    expect(locationSvc, isA<InMemoryLocationService>());

    final sanitizer = container.read(contactsSanitizerProvider);
    expect(sanitizer, isA<ContactsSanitizer>());

    final permissionMgr = container.read(permissionManagerServiceProvider);
    expect(permissionMgr, isA<PermissionManagerService>());
  });
}
