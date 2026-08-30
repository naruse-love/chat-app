import '../../../models/native/native_models.dart';
import '../../../models/tool/tool.dart';
import '../../native/location_service.dart';
import '../../native/permission_manager_service.dart';

/// GPS Geolocation tool [Level 3 Privileged].
///
/// Retrieves current GPS coordinates of the device,
/// checking [AppPermission.location] permission beforehand.
class GeolocationGetTool extends Tool {
  final ILocationService locationService;
  final PermissionManagerService permissionService;

  GeolocationGetTool({
    ILocationService? locationService,
    PermissionManagerService? permissionService,
  })  : locationService = locationService ?? InMemoryLocationService(),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'geolocation_get';

  @override
  String get displayName => '获取当前定位';

  @override
  String get description =>
      'Gets the current GPS geographic coordinates (latitude, longitude, altitude, accuracy) of the device.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'high_accuracy',
          type: 'boolean',
          description: '是否请求高精度 GPS 卫星定位 (默认为 true)',
          required: false,
          defaultValue: true,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.location);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.location);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'location', 'granted': false},
      );
    }

    try {
      final highAccuracy = arguments['high_accuracy'] as bool? ?? true;
      final coords = await locationService.getCurrentCoordinates(highAccuracy: highAccuracy);

      stopwatch.stop();

      final buffer = StringBuffer();
      buffer.writeln('📍 **当前设备定位成功**\n');
      buffer.writeln('- **标准坐标**: ${coords.toFormattedString()}');
      buffer.writeln('- **DMS 格式**: ${coords.toDmsString()}');
      buffer.writeln('- **纬度 (Latitude)**: `${coords.latitude.toStringAsFixed(6)}`');
      buffer.writeln('- **经度 (Longitude)**: `${coords.longitude.toStringAsFixed(6)}`');
      buffer.writeln('- **海拔 (Altitude)**: ${coords.altitude.toStringAsFixed(1)} 米');
      buffer.writeln('- **定位精度 (Accuracy)**: ±${coords.accuracy.toStringAsFixed(1)} 米');
      buffer.writeln('- **定位时间**: ${coords.timestamp.toIso8601String()}');

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString().trimRight(),
        rawData: coords.toJson(),
        executionDuration: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '获取设备定位发生异常: $e',
        content: '获取设备定位发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}
