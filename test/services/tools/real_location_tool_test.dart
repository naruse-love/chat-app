import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/native/real_location_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/native/native_tools.dart';
import 'package:chat/services/tools/file_read_tool.dart';

void main() {
  group('RealLocationService & Native Tool Tests', () {
    test('RealLocationService handles mock custom coordinates properly', () async {
      final service = RealLocationService();
      final custom = service.getCurrentCoordinates();
      expect(custom, completes);

      final geoGetTool = GeolocationGetTool(locationService: service);
      final result = await geoGetTool.execute({});
      expect(result.success, isTrue);
      expect(result.rawData.containsKey('latitude'), isTrue);
      expect(result.rawData.containsKey('longitude'), isTrue);
    });

    test('RealLocationService parses reverse geocode successfully with fallback', () async {
      final service = RealLocationService();
      final revTool = ReverseGeocodeTool(locationService: service);

      // Even if network fails in test environment, it falls back cleanly
      final result = await revTool.execute({
        'latitude': 31.2304,
        'longitude': 121.4737,
      });

      expect(result.success, isTrue);
      expect(result.rawData['city'], isNotNull);
    });

    test('ToolRegistry.updateWorkspacePath dynamically retargets file tools', () async {
      final registry = ToolRegistry.defaultRegistry();
      final tempDir = Directory.systemTemp.createTempSync('reg_ws_test_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      File('${tempDir.path}/hello.txt').writeAsStringSync('world');

      registry.updateWorkspacePath(tempDir.path);

      final fileRead = registry.getTool('file_read') as FileReadTool;
      final readRes = await fileRead.execute({'path': 'hello.txt'});
      expect(readRes.success, isTrue);
      expect(readRes.content, contains('world'));
    });
  });
}
