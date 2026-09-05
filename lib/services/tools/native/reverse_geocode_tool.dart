import '../../../models/tool/tool.dart';
import '../../native/location_service.dart';
import '../../native/real_location_service.dart';

/// Reverse geocoding tool [Level 1 ReadOnly / Safe].
///
/// Converts GPS coordinates (latitude, longitude) into a structured human-readable postal address.
class ReverseGeocodeTool extends Tool {
  final ILocationService locationService;

  ReverseGeocodeTool({
    ILocationService? locationService,
  }) : locationService = locationService ?? RealLocationService();

  @override
  String get name => 'reverse_geocode';

  @override
  String get displayName => '地理逆编码';

  @override
  String get description =>
      'Converts GPS coordinates (latitude, longitude) into structured human-readable postal address components.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'latitude',
          type: 'number',
          description: '目标地理位置的纬度 (例如 39.9042)',
          required: true,
        ),
        ToolParameter(
          name: 'longitude',
          type: 'number',
          description: '目标地理位置的经度 (例如 116.4074)',
          required: true,
        ),
      ];

  @override
  String? validateArguments(Map<String, dynamic> arguments) {
    final lat = arguments['latitude'] ?? arguments['lat'] ?? arguments['y'];
    final lng = arguments['longitude'] ?? arguments['lng'] ?? arguments['lon'] ?? arguments['long'] ?? arguments['x'];
    if (lat == null || lng == null) {
      return '缺少必需的经纬度参数 (latitude, longitude)';
    }
    return null;
  }

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    try {
      final rawLat = arguments['latitude'] ?? arguments['lat'] ?? arguments['y'];
      final rawLng = arguments['longitude'] ?? arguments['lng'] ?? arguments['lon'] ?? arguments['long'] ?? arguments['x'];

      if (rawLat == null || rawLng == null) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '缺少必需的经纬度参数 (latitude, longitude)',
          content: '地理逆编码失败: 请同时提供纬度 (latitude) 与经度 (longitude)',
          executionDuration: stopwatch.elapsed,
        );
      }

      final lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
      final lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());

      if (lat == null || lat < -90.0 || lat > 90.0) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '纬度数值无效: "$rawLat" (必须介于 -90.0 与 90.0 之间)',
          content: '地理逆编码失败: 纬度必须介于 -90.0 与 90.0 之间',
          executionDuration: stopwatch.elapsed,
        );
      }

      if (lng == null || lng < -180.0 || lng > 180.0) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '经度数值无效: "$rawLng" (必须介于 -180.0 与 180.0 之间)',
          content: '地理逆编码失败: 经度必须介于 -180.0 与 180.0 之间',
          executionDuration: stopwatch.elapsed,
        );
      }

      final geoAddress = await locationService.reverseGeocode(
        latitude: lat,
        longitude: lng,
      );

      stopwatch.stop();

      final buffer = StringBuffer();
      buffer.writeln('🗺️ **地理逆编码解析结果**\n');
      buffer.writeln(geoAddress.toMarkdown());

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString().trimRight(),
        rawData: geoAddress.toJson(),
        executionDuration: stopwatch.elapsed,
        metadata: {
          'latitude': lat,
          'longitude': lng,
          'formattedAddress': geoAddress.formattedAddress,
        },
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '地理逆编码发生异常: $e',
        content: '地理逆编码发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}
