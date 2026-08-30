/// Represents raw GPS geographic coordinates.
class GeoCoordinates {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final DateTime timestamp;

  GeoCoordinates({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.accuracy = 5.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Formats coordinates into standard decimal degree string (e.g. "39.9042°N, 116.4074°E ±5.0m").
  String toFormattedString() {
    final latDir = latitude >= 0 ? "N" : "S";
    final lngDir = longitude >= 0 ? "E" : "W";
    return "${latitude.abs().toStringAsFixed(4)}°$latDir, ${longitude.abs().toStringAsFixed(4)}°$lngDir (精度: ±${accuracy.toStringAsFixed(1)}m)";
  }

  /// Formats coordinates into Degrees, Minutes, Seconds (DMS) string.
  String toDmsString() {
    return "${_toDms(latitude, true)}, ${_toDms(longitude, false)}";
  }

  static String _toDms(double val, bool isLat) {
    final dir = isLat ? (val >= 0 ? "N" : "S") : (val >= 0 ? "E" : "W");
    final absVal = val.abs();
    final d = absVal.floor();
    final mVal = (absVal - d) * 60;
    final m = mVal.floor();
    final s = ((mVal - m) * 60).toStringAsFixed(1);
    return "$d°$m'$s\"$dir";
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GeoCoordinates.fromJson(Map<String, dynamic> json) {
    return GeoCoordinates(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 5.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoCoordinates &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitude == other.altitude &&
          accuracy == other.accuracy;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      altitude.hashCode ^
      accuracy.hashCode;

  @override
  String toString() => 'GeoCoordinates(${toFormattedString()})';
}

/// Represents a reverse/forward geocoded structured geographic address.
class GeoAddress {
  final String formattedAddress;
  final String country;
  final String province;
  final String city;
  final String district;
  final String street;
  final String? streetNumber;
  final String? postalCode;
  final String countryCode;
  final double? latitude;
  final double? longitude;

  const GeoAddress({
    required this.formattedAddress,
    required this.country,
    required this.province,
    required this.city,
    required this.district,
    required this.street,
    this.streetNumber,
    this.postalCode,
    this.countryCode = 'CN',
    this.latitude,
    this.longitude,
  });

  /// Short address: e.g. "北京市海淀区中关村南大街1号".
  String toFormattedString() => formattedAddress;

  /// Formatted as Markdown for LLM output.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln("- **地址**: $formattedAddress");
    buffer.writeln("  - **国家/地区**: $country ($countryCode)");
    buffer.writeln("  - **省/市/区**: $province $city $district");
    if (street.isNotEmpty) {
      buffer.writeln("  - **街道**: $street${streetNumber != null ? ' $streetNumber' : ''}");
    }
    if (postalCode != null && postalCode!.isNotEmpty) {
      buffer.writeln("  - **邮政编码**: $postalCode");
    }
    if (latitude != null && longitude != null) {
      buffer.writeln("  - **坐标**: ${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}");
    }
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() {
    return {
      'formattedAddress': formattedAddress,
      'country': country,
      'province': province,
      'city': city,
      'district': district,
      'street': street,
      if (streetNumber != null) 'streetNumber': streetNumber,
      if (postalCode != null) 'postalCode': postalCode,
      'countryCode': countryCode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }

  factory GeoAddress.fromJson(Map<String, dynamic> json) {
    return GeoAddress(
      formattedAddress: json['formattedAddress'] as String? ?? '',
      country: json['country'] as String? ?? '',
      province: json['province'] as String? ?? '',
      city: json['city'] as String? ?? '',
      district: json['district'] as String? ?? '',
      street: json['street'] as String? ?? '',
      streetNumber: json['streetNumber'] as String?,
      postalCode: json['postalCode'] as String?,
      countryCode: json['countryCode'] as String? ?? 'CN',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoAddress &&
          runtimeType == other.runtimeType &&
          formattedAddress == other.formattedAddress &&
          country == other.country &&
          province == other.province &&
          city == other.city &&
          district == other.district &&
          street == other.street &&
          streetNumber == other.streetNumber &&
          postalCode == other.postalCode;

  @override
  int get hashCode =>
      formattedAddress.hashCode ^
      country.hashCode ^
      province.hashCode ^
      city.hashCode ^
      district.hashCode ^
      street.hashCode ^
      streetNumber.hashCode ^
      postalCode.hashCode;

  @override
  String toString() => 'GeoAddress($formattedAddress)';
}
