import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/native/native_services.dart';
import 'package:chat/services/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryCalendarService calendarService;
  late InMemoryNotificationService notificationService;
  late InMemoryContactsService contactsService;
  late InMemoryLocationService locationService;
  late ContactsSanitizer contactsSanitizer;
  late PermissionManagerService permissionService;
  late ToolRegistry registry;

  setUp(() {
    calendarService = InMemoryCalendarService();
    notificationService = InMemoryNotificationService();
    contactsService = InMemoryContactsService();
    locationService = InMemoryLocationService();
    contactsSanitizer = const ContactsSanitizer();
    permissionService = PermissionManagerService();

    registry = ToolRegistry.defaultRegistry(
      calendarService: calendarService,
      notificationService: notificationService,
      contactsService: contactsService,
      locationService: locationService,
      contactsSanitizer: contactsSanitizer,
      permissionManagerService: permissionService,
    );
  });

  group('ToolRegistry Native Privileged Tools Integration Tests', () {
    test('Default registry contains all 7 native tools and total 22 tools', () {
      expect(registry.getAllTools().length, 22);

      expect(registry.hasTool('calendar_query_events'), isTrue);
      expect(registry.hasTool('calendar_create_event'), isTrue);
      expect(registry.hasTool('notification_schedule'), isTrue);
      expect(registry.hasTool('notification_cancel'), isTrue);
      expect(registry.hasTool('contacts_search'), isTrue);
      expect(registry.hasTool('geolocation_get'), isTrue);
      expect(registry.hasTool('reverse_geocode'), isTrue);
    });

    test('Dynamic enable / disable toggle works for native tools', () {
      expect(registry.isToolEnabled('calendar_query_events'), isTrue);
      registry.setToolEnabled('calendar_query_events', false);
      expect(registry.isToolEnabled('calendar_query_events'), isFalse);

      final enabledNames = registry.getEnabledNames();
      expect(enabledNames, isNot(contains('calendar_query_events')));
      expect(enabledNames, contains('calendar_create_event'));

      registry.setToolEnabled('calendar_query_events', true);
      expect(registry.isToolEnabled('calendar_query_events'), isTrue);
    });

    test('Export OpenAI schemas properly exports schemas for all 7 native tools', () {
      final schemas = registry.exportOpenAiSchemas();
      expect(schemas.length, 22);

      final names = schemas.map((s) => s['function']['name']).toList();
      expect(names, containsAll([
        'calendar_query_events',
        'calendar_create_event',
        'notification_schedule',
        'notification_cancel',
        'contacts_search',
        'geolocation_get',
        'reverse_geocode',
      ]));

      // Verify calendar_create_event schema structure
      final calSchema = schemas.firstWhere((s) => s['function']['name'] == 'calendar_create_event');
      final params = calSchema['function']['parameters']['properties'] as Map<String, dynamic>;
      expect(params.containsKey('title'), isTrue);
      expect(params.containsKey('start_time'), isTrue);
      expect(params.containsKey('end_time'), isTrue);
      expect(calSchema['function']['parameters']['required'], containsAll(['title', 'start_time', 'end_time']));
    });

    test('Export OpenAI schemas filters by maxSecurityLevel', () {
      // Level 1 readOnly should include reverse_geocode (Level 1) but NOT Level 3 native tools
      final readOnlySchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.readOnly);
      final readOnlyNames = readOnlySchemas.map((s) => s['function']['name']).toList();
      expect(readOnlyNames, contains('reverse_geocode'));
      expect(readOnlyNames, isNot(contains('calendar_create_event')));
      expect(readOnlyNames, isNot(contains('geolocation_get')));
      expect(readOnlyNames, isNot(contains('contacts_search')));

      // Level 3 privilegedNative should include all 22 tools
      final privilegedSchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.privilegedNative);
      expect(privilegedSchemas.length, 22);
    });

    test('Dispatches execution through registry for native tools', () async {
      // 1. Query events
      final qResult = await registry.execute('calendar_query_events', {});
      expect(qResult.success, isTrue);
      expect(qResult.rawData['count'], 4);

      // 2. Geolocation get
      final geoResult = await registry.execute('geolocation_get', {});
      expect(geoResult.success, isTrue);
      expect(geoResult.rawData['latitude'], 39.9042);

      // 3. Reverse geocode
      final revResult = await registry.execute('reverse_geocode', {
        'latitude': 39.9042,
        'longitude': 116.4074,
      });
      expect(revResult.success, isTrue);
      expect(revResult.content, contains('北京市海淀区中关村南大街1号'));
    });

    test('Returns failure when tool is disabled or parameter validation fails', () async {
      registry.setToolEnabled('geolocation_get', false);
      final disResult = await registry.execute('geolocation_get', {});
      expect(disResult.success, isFalse);
      expect(disResult.errorMessage, contains('当前已被禁用'));

      // Parameter validation failure for reverse_geocode (missing required args)
      final valResult = await registry.execute('reverse_geocode', {});
      expect(valResult.success, isFalse);
      expect(valResult.errorMessage, contains('参数校验失败'));
    });
  });
}
