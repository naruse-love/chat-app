import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import '../../models/native/geo_models.dart';
import 'location_service.dart';

/// Real device location service dynamically querying real-time IP Geolocation
/// and global reverse geocoding via public REST endpoints with offline fallback.
class RealLocationService extends InMemoryLocationService {
  final Dio _dio;
  bool _customCoordinatesSet = false;
  GeoAddress? _cachedAddress;
  GeoCoordinates? _cachedCoordinates;

  RealLocationService({
    Dio? dio,
    super.initialCoordinates,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: {
                  'User-Agent': 'ChatApp/1.0 (https://github.com/naruse-love/chat-app)',
                  'Accept': 'application/json',
                },
              ),
            );

  /// Currently cached real address if available from IP geolocation.
  GeoAddress? get cachedAddress => _cachedAddress;

  @override
  void setCurrentCoordinates(GeoCoordinates coordinates) {
    _customCoordinatesSet = true;
    _cachedCoordinates = coordinates;
    super.setCurrentCoordinates(coordinates);
  }

  @override
  Future<GeoCoordinates> getCurrentCoordinates({bool highAccuracy = true}) async {
    if (_customCoordinatesSet) {
      return super.getCurrentCoordinates(highAccuracy: highAccuracy);
    }

    // 1. Primary: ip-api.com
    try {
      final response = await _dio.get('http://ip-api.com/json/?lang=zh-CN');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            final country = data['country']?.toString() ?? '中国';
            final countryCode = data['countryCode']?.toString() ?? 'CN';
            final province = data['regionName']?.toString() ?? '';
            final city = data['city']?.toString() ?? '';
            final zip = data['zip']?.toString();

            final parts = [country, province, city].where((s) => s.isNotEmpty).toList();
            final formatted = parts.isNotEmpty ? parts.join(' ') : '经纬度 ($lat, $lon) 位置';

            _cachedAddress = GeoAddress(
              formattedAddress: formatted,
              country: country.isNotEmpty ? country : '中国',
              province: province.isNotEmpty ? province : (city.isNotEmpty ? city : '未知省份'),
              city: city.isNotEmpty ? city : (province.isNotEmpty ? province : '未知城市'),
              district: city,
              street: '当前网络接入点',
              postalCode: (zip != null && zip.isNotEmpty) ? zip : null,
              countryCode: countryCode,
              latitude: lat,
              longitude: lon,
            );

            final coords = GeoCoordinates(
              latitude: lat,
              longitude: lon,
              altitude: 0.0,
              accuracy: 1000.0,
              timestamp: DateTime.now(),
            );
            _cachedCoordinates = coords;
            super.setCurrentCoordinates(coords);
            return coords;
          }
        }
      }
    } catch (e) {
      developer.log('ip-api.com lookup failed: $e', name: 'RealLocationService');
    }

    // 2. Secondary: freeipapi.com
    try {
      final response = await _dio.get('https://freeipapi.com/api/json');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          final country = data['countryName']?.toString() ?? '中国';
          final countryCode = data['countryCode']?.toString() ?? 'CN';
          final province = data['regionName']?.toString() ?? '';
          final city = data['cityName']?.toString() ?? '';
          final zip = data['zipCode']?.toString();

          final parts = [country, province, city].where((s) => s.isNotEmpty).toList();
          final formatted = parts.isNotEmpty ? parts.join(' ') : '经纬度 ($lat, $lon) 位置';

          _cachedAddress = GeoAddress(
            formattedAddress: formatted,
            country: country.isNotEmpty ? country : '中国',
            province: province.isNotEmpty ? province : (city.isNotEmpty ? city : '未知省份'),
            city: city.isNotEmpty ? city : (province.isNotEmpty ? province : '未知城市'),
            district: city,
            street: '当前网络接入点',
            postalCode: (zip != null && zip.isNotEmpty) ? zip : null,
            countryCode: countryCode,
            latitude: lat,
            longitude: lon,
          );

          final coords = GeoCoordinates(
            latitude: lat,
            longitude: lon,
            altitude: 0.0,
            accuracy: 1500.0,
            timestamp: DateTime.now(),
          );
          _cachedCoordinates = coords;
          super.setCurrentCoordinates(coords);
          return coords;
        }
      }
    } catch (e) {
      developer.log('freeipapi lookup failed: $e', name: 'RealLocationService');
    }

    // 3. Fallback to cached/pre-set coordinates
    return super.getCurrentCoordinates(highAccuracy: highAccuracy);
  }

  @override
  Future<GeoAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    // 0. Check cached address from real IP location if close (~5km)
    if (_cachedAddress != null && _cachedCoordinates != null) {
      final dLat = (latitude - _cachedCoordinates!.latitude).abs();
      final dLon = (longitude - _cachedCoordinates!.longitude).abs();
      if (dLat < 0.05 && dLon < 0.05) {
        return _cachedAddress!;
      }
    }

    // 1. Try BigDataCloud reverse geocode client API (Free, fast, no API key needed)
    try {
      final url =
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=zh';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final country = data['countryName'] as String? ?? '';
        final countryCode = data['countryCode'] as String? ?? '';
        final province = data['principalSubdivision'] as String? ?? '';
        final city = data['city'] as String? ?? '';
        final locality = data['locality'] as String? ?? '';
        final postalCode = data['postcode'] as String? ?? '';

        final addrParts = <String>[];
        if (country.isNotEmpty) addrParts.add(country);
        if (province.isNotEmpty && province != country) addrParts.add(province);
        if (city.isNotEmpty && city != province) addrParts.add(city);
        if (locality.isNotEmpty && locality != city) addrParts.add(locality);

        final formattedAddress = addrParts.isNotEmpty
            ? addrParts.join('')
            : '经纬度 ($latitude, $longitude) 位置';

        return GeoAddress(
          formattedAddress: formattedAddress,
          country: country.isNotEmpty ? country : '未知国家',
          province: province.isNotEmpty ? province : '未知省份',
          city: city.isNotEmpty ? city : (province.isNotEmpty ? province : '未知城市'),
          district: locality.isNotEmpty ? locality : '未知区域',
          street: locality.isNotEmpty ? locality : '未知街道',
          postalCode: postalCode.isNotEmpty ? postalCode : null,
          countryCode: countryCode.isNotEmpty ? countryCode : 'UN',
          latitude: latitude,
          longitude: longitude,
        );
      }
    } catch (e) {
      developer.log('BigDataCloud reverse geocode failed: $e', name: 'RealLocationService');
    }

    // 2. Try OpenStreetMap Nominatim API
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&accept-language=zh-Hans,zh';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final displayName = data['display_name'] as String? ?? '';
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        final country = addr['country'] as String? ?? '';
        final countryCode = (addr['country_code'] as String? ?? 'un').toUpperCase();
        final province = addr['state'] as String? ?? addr['province'] as String? ?? '';
        final city = addr['city'] as String? ?? addr['town'] as String? ?? addr['county'] as String? ?? '';
        final district = addr['suburb'] as String? ?? addr['district'] as String? ?? '';
        final road = addr['road'] as String? ?? '';
        final houseNumber = addr['house_number'] as String? ?? '';
        final postcode = addr['postcode'] as String? ?? '';

        return GeoAddress(
          formattedAddress: displayName.isNotEmpty ? displayName : '$province$city$district$road$houseNumber',
          country: country.isNotEmpty ? country : '未知国家',
          province: province.isNotEmpty ? province : '未知省份',
          city: city.isNotEmpty ? city : '未知城市',
          district: district.isNotEmpty ? district : '未知区域',
          street: road.isNotEmpty ? road : '未知街道',
          streetNumber: houseNumber.isNotEmpty ? houseNumber : null,
          postalCode: postcode.isNotEmpty ? postcode : null,
          countryCode: countryCode,
          latitude: latitude,
          longitude: longitude,
        );
      }
    } catch (e) {
      developer.log('Nominatim reverse geocode failed: $e', name: 'RealLocationService');
    }

    // 3. Fallback to local known/heuristic database or cached IP location
    final fallback = await super.reverseGeocode(latitude: latitude, longitude: longitude);
    if (fallback.formattedAddress.contains('坐标位置') && _cachedAddress != null) {
      final country = _cachedAddress!.country;
      final province = _cachedAddress!.province;
      final city = _cachedAddress!.city;
      return GeoAddress(
        formattedAddress: '$country $province $city (经纬度: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
        country: country,
        province: province,
        city: city,
        district: _cachedAddress!.district,
        street: '位置坐标点',
        postalCode: _cachedAddress!.postalCode,
        countryCode: _cachedAddress!.countryCode,
        latitude: latitude,
        longitude: longitude,
      );
    }
    return fallback;
  }

  @override
  Future<List<GeoAddress>> forwardGeocode({
    required String address,
  }) async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(address)}&format=json&limit=3&accept-language=zh-Hans,zh';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is List) {
        final list = response.data as List;
        final results = <GeoAddress>[];
        for (final item in list) {
          if (item is Map) {
            final lat = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
            final lon = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
            final displayName = item['display_name'] as String? ?? address;
            results.add(GeoAddress(
              formattedAddress: displayName,
              country: '',
              province: '',
              city: '',
              district: '',
              street: '',
              latitude: lat,
              longitude: lon,
            ));
          }
        }
        if (results.isNotEmpty) return results;
      }
    } catch (e) {
      developer.log('Nominatim forward geocode failed: $e', name: 'RealLocationService');
    }

    return super.forwardGeocode(address: address);
  }
}
