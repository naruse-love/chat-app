import 'dart:math' as math;
import '../../models/native/geo_models.dart';

/// Abstract contract for device geolocation and geocoding services.
abstract class ILocationService {
  /// Gets current GPS coordinates of the device.
  Future<GeoCoordinates> getCurrentCoordinates({bool highAccuracy = true});

  /// Reverse geocodes GPS coordinates (latitude, longitude) into a structured human-readable address.
  Future<GeoAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  });

  /// Forward geocodes a textual address into structured geographic location(s).
  Future<List<GeoAddress>> forwardGeocode({
    required String address,
  });

  /// Configures mock current coordinates for testing.
  void setCurrentCoordinates(GeoCoordinates coordinates);

  /// Adds or overrides a custom geocode mapping.
  void addGeocodeMapping({
    required String address,
    required GeoAddress geoAddress,
  });
}

/// In-memory mock implementation of [ILocationService] with built-in geocoding maps.
class InMemoryLocationService implements ILocationService {
  GeoCoordinates _currentCoordinates = GeoCoordinates(
    latitude: 39.9042,
    longitude: 116.4074,
    altitude: 43.5,
    accuracy: 4.8,
  );

  final List<GeoAddress> _knownLocations = [];

  InMemoryLocationService({GeoCoordinates? initialCoordinates}) {
    if (initialCoordinates != null) {
      _currentCoordinates = initialCoordinates;
    }
    _seedDefaultLocations();
  }

  void _seedDefaultLocations() {
    _knownLocations.clear();
    _knownLocations.addAll([
      const GeoAddress(
        formattedAddress: '北京市海淀区中关村南大街1号',
        country: '中国',
        province: '北京市',
        city: '北京市',
        district: '海淀区',
        street: '中关村南大街',
        streetNumber: '1号',
        postalCode: '100081',
        countryCode: 'CN',
        latitude: 39.9042,
        longitude: 116.4074,
      ),
      const GeoAddress(
        formattedAddress: '北京市朝阳区望京街10号望京SOHO',
        country: '中国',
        province: '北京市',
        city: '北京市',
        district: '朝阳区',
        street: '望京街',
        streetNumber: '10号',
        postalCode: '100102',
        countryCode: 'CN',
        latitude: 39.9967,
        longitude: 116.4808,
      ),
      const GeoAddress(
        formattedAddress: '上海市浦东新区张江高科技园区博云路2号',
        country: '中国',
        province: '上海市',
        city: '上海市',
        district: '浦东新区',
        street: '博云路',
        streetNumber: '2号',
        postalCode: '201203',
        countryCode: 'CN',
        latitude: 31.2034,
        longitude: 121.5977,
      ),
      const GeoAddress(
        formattedAddress: '上海市浦东新区陆家嘴环路1000号',
        country: '中国',
        province: '上海市',
        city: '上海市',
        district: '浦东新区',
        street: '陆家嘴环路',
        streetNumber: '1000号',
        postalCode: '200120',
        countryCode: 'CN',
        latitude: 31.2397,
        longitude: 121.4998,
      ),
      const GeoAddress(
        formattedAddress: '广东省深圳市南山区高新南一道科技园',
        country: '中国',
        province: '广东省',
        city: '深圳市',
        district: '南山区',
        street: '高新南一道',
        streetNumber: '8号',
        postalCode: '518057',
        countryCode: 'CN',
        latitude: 22.5431,
        longitude: 113.9465,
      ),
      const GeoAddress(
        formattedAddress: '浙江省杭州市西湖区文三路478号',
        country: '中国',
        province: '浙江省',
        city: '杭州市',
        district: '西湖区',
        street: '文三路',
        streetNumber: '478号',
        postalCode: '310012',
        countryCode: 'CN',
        latitude: 30.2741,
        longitude: 120.1551,
      ),
      const GeoAddress(
        formattedAddress: '广东省广州市天河区天河路208号',
        country: '中国',
        province: '广东省',
        city: '广州市',
        district: '天河区',
        street: '天河路',
        streetNumber: '208号',
        postalCode: '510620',
        countryCode: 'CN',
        latitude: 23.1353,
        longitude: 113.3353,
      ),
      const GeoAddress(
        formattedAddress: 'San Francisco, CA 94105, United States',
        country: 'United States',
        province: 'California',
        city: 'San Francisco',
        district: 'Financial District',
        street: 'Market St',
        streetNumber: '500',
        postalCode: '94105',
        countryCode: 'US',
        latitude: 37.7749,
        longitude: -122.4194,
      ),
      const GeoAddress(
        formattedAddress: '東京都千代田区丸の内1丁目, 日本',
        country: '日本',
        province: '東京都',
        city: '千代田区',
        district: '丸の内',
        street: '丸の内',
        streetNumber: '1丁目',
        postalCode: '100-0005',
        countryCode: 'JP',
        latitude: 35.6762,
        longitude: 139.6503,
      ),
      const GeoAddress(
        formattedAddress: 'Trafalgar Square, London WC2N 5DN, United Kingdom',
        country: 'United Kingdom',
        province: 'Greater London',
        city: 'London',
        district: 'Westminster',
        street: 'Trafalgar Square',
        postalCode: 'WC2N 5DN',
        countryCode: 'GB',
        latitude: 51.5074,
        longitude: -0.1278,
      ),
    ]);
  }

  @override
  Future<GeoCoordinates> getCurrentCoordinates({bool highAccuracy = true}) async {
    return _currentCoordinates;
  }

  @override
  Future<GeoAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    // Find closest match by Euclidean distance
    GeoAddress? closest;
    double minDistance = double.infinity;

    for (final loc in _knownLocations) {
      if (loc.latitude != null && loc.longitude != null) {
        final dLat = loc.latitude! - latitude;
        final dLng = loc.longitude! - longitude;
        final dist = math.sqrt(dLat * dLat + dLng * dLng);
        if (dist < minDistance) {
          minDistance = dist;
          closest = loc;
        }
      }
    }

    // If within ~0.005 degree (~500m), return closest landmark with precise street address
    if (closest != null && minDistance < 0.005) {
      return GeoAddress(
        formattedAddress: closest.formattedAddress,
        country: closest.country,
        province: closest.province,
        city: closest.city,
        district: closest.district,
        street: closest.street,
        streetNumber: closest.streetNumber,
        postalCode: closest.postalCode,
        countryCode: closest.countryCode,
        latitude: latitude,
        longitude: longitude,
      );
    }

    // If within 0.3 degree (~30km), return city-level region without faking exact building
    if (closest != null && minDistance < 0.3) {
      final parts = [closest.country, closest.province, closest.city]
          .where((s) => s.isNotEmpty && !s.contains('未知'))
          .toSet()
          .toList();
      final region = parts.isNotEmpty ? parts.join(' ') : '当前区域';
      final latStr = latitude.toStringAsFixed(4);
      final lngStr = longitude.toStringAsFixed(4);
      return GeoAddress(
        formattedAddress: '$region 附近 (经纬度: $latStr, $lngStr)',
        country: closest.country,
        province: closest.province,
        city: closest.city,
        district: closest.district,
        street: '周边区域',
        postalCode: closest.postalCode,
        countryCode: closest.countryCode,
        latitude: latitude,
        longitude: longitude,
      );
    }

    // Generic fallback for custom coordinates
    final latStr = latitude.toStringAsFixed(4);
    final lngStr = longitude.toStringAsFixed(4);
    return GeoAddress(
      formattedAddress: '坐标位置 ($latStr, $lngStr)',
      country: '未知国家',
      province: '未知省份',
      city: '未知城市',
      district: '未知区域',
      street: '位置坐标点',
      countryCode: 'UN',
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<List<GeoAddress>> forwardGeocode({
    required String address,
  }) async {
    final clean = address.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final matches = _knownLocations.where((loc) {
      return loc.formattedAddress.toLowerCase().contains(clean) ||
          loc.city.toLowerCase().contains(clean) ||
          loc.district.toLowerCase().contains(clean) ||
          loc.street.toLowerCase().contains(clean) ||
          loc.province.toLowerCase().contains(clean) ||
          loc.country.toLowerCase().contains(clean);
    }).toList();

    if (matches.isNotEmpty) {
      return matches;
    }

    // Fallback single synthesized address if not in presets
    return [
      GeoAddress(
        formattedAddress: address.trim(),
        country: '中国',
        province: '待定',
        city: '待定',
        district: '待定',
        street: address.trim(),
        latitude: 39.9042,
        longitude: 116.4074,
      )
    ];
  }

  @override
  void setCurrentCoordinates(GeoCoordinates coordinates) {
    _currentCoordinates = coordinates;
  }

  @override
  void addGeocodeMapping({
    required String address,
    required GeoAddress geoAddress,
  }) {
    _knownLocations.removeWhere((l) => l.formattedAddress == address);
    _knownLocations.insert(0, geoAddress);
  }
}
