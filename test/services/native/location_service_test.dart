import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/native/geo_models.dart';
import 'package:chat/services/native/location_service.dart';

void main() {
  group('GeoModels Tests', () {
    test('GeoCoordinates formatting and serialization', () {
      final coords = GeoCoordinates(
        latitude: 39.9042,
        longitude: 116.4074,
        altitude: 50.0,
        accuracy: 3.5,
        timestamp: DateTime(2026, 8, 30, 12, 0),
      );

      expect(coords.toFormattedString(), contains('39.9042°N, 116.4074°E'));
      expect(coords.toDmsString(), contains('39°54\'15.1"N'));

      final json = coords.toJson();
      final restored = GeoCoordinates.fromJson(json);

      expect(restored.latitude, 39.9042);
      expect(restored.longitude, 116.4074);
      expect(restored.altitude, 50.0);
      expect(restored.accuracy, 3.5);
    });

    test('GeoAddress formatting and serialization', () {
      const address = GeoAddress(
        formattedAddress: '北京市海淀区中关村南大街1号',
        country: '中国',
        province: '北京市',
        city: '北京市',
        district: '海淀区',
        street: '中关村南大街',
        streetNumber: '1号',
        postalCode: '100081',
        latitude: 39.9042,
        longitude: 116.4074,
      );

      expect(address.toFormattedString(), '北京市海淀区中关村南大街1号');
      expect(address.toMarkdown(), contains('**地址**: 北京市海淀区中关村南大街1号'));
      expect(address.toMarkdown(), contains('海淀区'));

      final json = address.toJson();
      final restored = GeoAddress.fromJson(json);

      expect(restored.formattedAddress, '北京市海淀区中关村南大街1号');
      expect(restored.country, '中国');
      expect(restored.postalCode, '100081');
    });
  });

  group('InMemoryLocationService Tests', () {
    late InMemoryLocationService service;

    setUp(() {
      service = InMemoryLocationService();
    });

    test('getCurrentCoordinates returns default coordinates and setCurrentCoordinates updates it', () async {
      final defaultCoords = await service.getCurrentCoordinates();
      expect(defaultCoords.latitude, closeTo(39.9042, 0.01));
      expect(defaultCoords.longitude, closeTo(116.4074, 0.01));

      service.setCurrentCoordinates(GeoCoordinates(
        latitude: 31.2304,
        longitude: 121.4737,
      ));

      final updated = await service.getCurrentCoordinates();
      expect(updated.latitude, closeTo(31.2304, 0.001));
      expect(updated.longitude, closeTo(121.4737, 0.001));
    });

    test('reverseGeocode resolves known presets', () async {
      // Beijing Zhongguancun
      final bjAddr = await service.reverseGeocode(latitude: 39.9042, longitude: 116.4074);
      expect(bjAddr.city, '北京市');
      expect(bjAddr.formattedAddress, contains('中关村'));

      // Shanghai Zhangjiang
      final shAddr = await service.reverseGeocode(latitude: 31.2034, longitude: 121.5977);
      expect(shAddr.city, '上海市');
      expect(shAddr.formattedAddress, contains('张江'));

      // San Francisco
      final sfAddr = await service.reverseGeocode(latitude: 37.7749, longitude: -122.4194);
      expect(sfAddr.city, 'San Francisco');
    });

    test('reverseGeocode provides fallback for unknown distant coordinates', () async {
      final remoteAddr = await service.reverseGeocode(latitude: -75.2509, longitude: -0.0713);
      expect(remoteAddr.formattedAddress, contains('坐标位置'));
    });

    test('forwardGeocode searches matching addresses', () async {
      final results = await service.forwardGeocode(address: '望京');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.formattedAddress, contains('望京'));

      final customFallback = await service.forwardGeocode(address: '成都天府广场');
      expect(customFallback.isNotEmpty, isTrue);
      expect(customFallback.first.formattedAddress, '成都天府广场');
    });

    test('addGeocodeMapping custom override', () async {
      const custom = GeoAddress(
        formattedAddress: '苏州市工业园区星湖街328号',
        country: '中国',
        province: '江苏省',
        city: '苏州市',
        district: '工业园区',
        street: '星湖街',
        streetNumber: '328号',
        latitude: 31.2990,
        longitude: 120.7300,
      );

      service.addGeocodeMapping(address: '苏州市工业园区星湖街328号', geoAddress: custom);
      final results = await service.forwardGeocode(address: '星湖街');
      expect(results.first.city, '苏州市');
    });
  });
}
