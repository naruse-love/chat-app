import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'calendar_service.dart';
import 'notification_service.dart';
import 'contacts_service.dart';
import 'location_service.dart';
import 'contacts_sanitizer.dart';
import 'permission_manager_service.dart';

/// Provider for calendar operations.
final calendarServiceProvider = Provider<ICalendarService>((ref) {
  return InMemoryCalendarService();
});

/// Provider for local/scheduled notification operations.
final notificationServiceProvider = Provider<INotificationService>((ref) {
  return InMemoryNotificationService();
});

/// Provider for contacts address book operations.
final contactsServiceProvider = Provider<IContactsService>((ref) {
  return InMemoryContactsService();
});

/// Provider for GPS geolocation and geocoding operations.
final locationServiceProvider = Provider<ILocationService>((ref) {
  return InMemoryLocationService();
});

/// Provider for contacts privacy sanitization.
final contactsSanitizerProvider = Provider<ContactsSanitizer>((ref) {
  return const ContactsSanitizer();
});

/// Provider for unified permission management.
final permissionManagerServiceProvider = Provider<PermissionManagerService>((ref) {
  return PermissionManagerService();
});
