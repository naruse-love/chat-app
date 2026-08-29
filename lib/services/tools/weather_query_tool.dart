import 'package:dio/dio.dart';
import '../../models/tool/tool.dart';

/// Exception thrown when weather queries fail.
class WeatherQueryException implements Exception {
  final String message;
  final int? statusCode;
  const WeatherQueryException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Weather Query Tool querying real-time weather and forecasts via Open-Meteo REST API.
class WeatherQueryTool extends Tool {
  final Dio _dio;

  WeatherQueryTool({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  'User-Agent': 'ChatApp/1.0 (https://github.com/naruse-love/chat-app)',
                  'Accept': 'application/json',
                },
              ),
            );

  @override
  String get name => 'weather_query';

  @override
  String get displayName => '天气查询';

  @override
  String get description =>
      'Query real-time weather conditions and 1 to 7 days forecast for any city or region worldwide via Open-Meteo API.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'city',
      type: 'string',
      description:
          'City name in Chinese or English (e.g. "北京", "Shanghai", "Tokyo", "New York", "London", "巴黎").',
      required: true,
    ),
    ToolParameter(
      name: 'forecastDays',
      type: 'integer',
      description: 'Number of forecast days (1 to 7). Default: 3.',
      required: false,
      defaultValue: 3,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final city = (arguments['city'] as String? ?? '').trim();

    if (city.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '城市名称不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    final rawDays = arguments['forecastDays'];
    int forecastDays = 3;
    if (rawDays is int) {
      forecastDays = rawDays.clamp(1, 7);
    } else if (rawDays is String) {
      forecastDays = (int.tryParse(rawDays) ?? 3).clamp(1, 7);
    }

    try {
      // 1. Geocoding lookup
      final geoUrl =
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=zh&format=json';
      final geoResponse = await _dio.get(geoUrl);

      final geoData = geoResponse.data;
      if (geoData is! Map || geoData['results'] == null || (geoData['results'] as List).isEmpty) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '未找到城市 "$city" 的地理位置信息，请检查城市名称拼写。',
          content: '查询天气失败: 未找到城市 "$city" 的地理位置信息。',
          executionDuration: stopwatch.elapsed,
          metadata: {'city': city},
        );
      }

      final firstResult = (geoData['results'] as List).first as Map<String, dynamic>;
      final lat = (firstResult['latitude'] as num).toDouble();
      final lng = (firstResult['longitude'] as num).toDouble();
      final cityName = firstResult['name'] as String? ?? city;
      final country = firstResult['country'] as String? ?? '';
      final admin1 = firstResult['admin1'] as String? ?? '';

      // 2. Weather forecast query
      final forecastUrl =
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true&hourly=relative_humidity_2m,apparent_temperature&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum,windspeed_10m_max&timezone=auto';

      final forecastResponse = await _dio.get(forecastUrl);
      final forecastData = forecastResponse.data as Map<String, dynamic>;

      // 3. Parse current weather
      final currentWeather = forecastData['current_weather'] as Map<String, dynamic>? ?? {};
      final temp = (currentWeather['temperature'] as num?)?.toDouble() ?? 0.0;
      final windspeed = (currentWeather['windspeed'] as num?)?.toDouble() ?? 0.0;
      final winddirection = (currentWeather['winddirection'] as num?)?.toInt() ?? 0;
      final weathercode = (currentWeather['weathercode'] as num?)?.toInt() ?? 0;
      final timeStr = currentWeather['time'] as String? ?? '';

      final condition = _getWmoCondition(weathercode);
      final windDirText = _getWindDirectionText(winddirection);

      // Hourly apparent temp and humidity at current hour
      final hourly = forecastData['hourly'] as Map<String, dynamic>?;
      double? apparentTemp;
      int? humidity;
      if (hourly != null && hourly['time'] is List) {
        final times = hourly['time'] as List;
        final apparentList = hourly['apparent_temperature'] as List?;
        final humidityList = hourly['relative_humidity_2m'] as List?;
        final index = times.indexOf(timeStr);
        if (index != -1) {
          if (apparentList != null && index < apparentList.length) {
            apparentTemp = (apparentList[index] as num?)?.toDouble();
          }
          if (humidityList != null && index < humidityList.length) {
            humidity = (humidityList[index] as num?)?.toInt();
          }
        }
      }

      // 4. Parse daily forecasts
      final daily = forecastData['daily'] as Map<String, dynamic>? ?? {};
      final dailyTimes = (daily['time'] as List?)?.cast<String>() ?? [];
      final dailyCodes = (daily['weathercode'] as List?)?.cast<num>() ?? [];
      final dailyMaxTemps = (daily['temperature_2m_max'] as List?)?.cast<num>() ?? [];
      final dailyMinTemps = (daily['temperature_2m_min'] as List?)?.cast<num>() ?? [];
      final dailyPrecip = (daily['precipitation_sum'] as List?)?.cast<num>() ?? [];
      final dailyWinds = (daily['windspeed_10m_max'] as List?)?.cast<num>() ?? [];

      final dailyList = <Map<String, dynamic>>[];
      final daysToInclude = dailyTimes.length < forecastDays ? dailyTimes.length : forecastDays;

      for (int i = 0; i < daysToInclude; i++) {
        final dTime = dailyTimes[i];
        final dCode = i < dailyCodes.length ? dailyCodes[i].toInt() : 0;
        final dMax = i < dailyMaxTemps.length ? dailyMaxTemps[i].toDouble() : 0.0;
        final dMin = i < dailyMinTemps.length ? dailyMinTemps[i].toDouble() : 0.0;
        final dPrecip = i < dailyPrecip.length ? dailyPrecip[i].toDouble() : 0.0;
        final dWind = i < dailyWinds.length ? dailyWinds[i].toDouble() : 0.0;
        final dCond = _getWmoCondition(dCode);

        dailyList.add({
          'date': dTime,
          'relativeDay': _relativeDayText(i),
          'weatherCode': dCode,
          'condition': dCond.text,
          'icon': dCond.icon,
          'maxTemp': dMax,
          'minTemp': dMin,
          'precipitationSum': dPrecip,
          'maxWindSpeed': dWind,
        });
      }

      stopwatch.stop();

      // 5. Format Markdown Output
      final regionParts = <String>[];
      if (admin1.isNotEmpty && admin1 != cityName) regionParts.add(admin1);
      if (country.isNotEmpty) regionParts.add(country);
      final locationTitle = regionParts.isNotEmpty ? '$cityName (${regionParts.join(', ')})' : cityName;

      final buffer = StringBuffer();
      buffer.writeln('### 📍 $locationTitle 实时天气与预报\n');
      buffer.writeln('**当前天气 ($timeStr)**:');
      buffer.writeln('- **天气状况**: ${condition.icon} ${condition.text}');
      buffer.write('- **实时气温**: $temp °C');
      if (apparentTemp != null) {
        buffer.write(' (体感温度: $apparentTemp °C)');
      }
      buffer.writeln();
      if (humidity != null) {
        buffer.writeln('- **相对湿度**: $humidity %');
      }
      buffer.writeln('- **风速风向**: $windspeed km/h ($windDirText $winddirection°)\n');

      if (dailyList.isNotEmpty) {
        buffer.writeln('#### 📅 未来 ${dailyList.length} 天天气预报:');
        buffer.writeln('| 日期 | 天气状况 | 气温范围 | 降水量 | 最大风速 |');
        buffer.writeln('| :--- | :--- | :--- | :--- | :--- |');
        for (final item in dailyList) {
          final dateStr = item['relativeDay'] != null && (item['relativeDay'] as String).isNotEmpty
              ? '${item['date']} (${item['relativeDay']})'
              : '${item['date']}';
          final condStr = '${item['icon']} ${item['condition']}';
          final tempRange = '${item['minTemp']}°C ~ ${item['maxTemp']}°C';
          final precipStr = '${item['precipitationSum']} mm';
          final windStr = '${item['maxWindSpeed']} km/h';
          buffer.writeln('| $dateStr | $condStr | $tempRange | $precipStr | $windStr |');
        }
      }

      final markdown = buffer.toString().trim();

      return ToolExecutionResult.success(
        toolName: name,
        content: markdown,
        rawData: {
          'location': {
            'queryCity': city,
            'name': cityName,
            'country': country,
            'admin1': admin1,
            'latitude': lat,
            'longitude': lng,
          },
          'current': {
            'time': timeStr,
            'weatherCode': weathercode,
            'condition': condition.text,
            'icon': condition.icon,
            'temperature': temp,
            'apparentTemperature': apparentTemp,
            'relativeHumidity': humidity,
            'windSpeed': windspeed,
            'windDirection': winddirection,
            'windDirectionText': windDirText,
          },
          'daily': dailyList,
        },
        executionDuration: stopwatch.elapsed,
        metadata: {
          'city': city,
          'resolvedCity': cityName,
          'forecastDays': dailyList.length,
        },
      );
    } on DioException catch (e) {
      stopwatch.stop();
      String message;
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        message = '天气查询网络请求超时，请检查网络连接。';
      } else if (e.response?.statusCode != null) {
        message = '天气服务响应异常 (HTTP ${e.response?.statusCode})。';
      } else {
        message = '天气查询网络连接失败: ${e.message}';
      }
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: message,
        content: '查询天气失败: $message',
        executionDuration: stopwatch.elapsed,
        metadata: {'city': city, 'dioError': e.type.name},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '查询天气出现异常: $e',
        content: '查询天气失败: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'city': city},
      );
    }
  }

  static String _relativeDayText(int index) {
    switch (index) {
      case 0: return '今天';
      case 1: return '明天';
      case 2: return '后天';
      default: return '';
    }
  }

  static String _getWindDirectionText(int deg) {
    if (deg >= 337.5 || deg < 22.5) return '北风';
    if (deg >= 22.5 && deg < 67.5) return '东北风';
    if (deg >= 67.5 && deg < 112.5) return '东风';
    if (deg >= 112.5 && deg < 157.5) return '东南风';
    if (deg >= 157.5 && deg < 202.5) return '南风';
    if (deg >= 202.5 && deg < 247.5) return '西南风';
    if (deg >= 247.5 && deg < 292.5) return '西风';
    return '西北风';
  }

  static _WmoCondition _getWmoCondition(int code) {
    switch (code) {
      case 0: return const _WmoCondition('晴天', '☀️');
      case 1: return const _WmoCondition('大部晴朗', '🌤️');
      case 2: return const _WmoCondition('局部多云', '⛅');
      case 3: return const _WmoCondition('阴天', '☁️');
      case 45: return const _WmoCondition('大雾', '🌫️');
      case 48: return const _WmoCondition('沉积雾凇 / 冰雾', '🌫️❄️');
      case 51: return const _WmoCondition('轻度毛毛雨', '🌧️');
      case 53: return const _WmoCondition('中度毛毛雨', '🌧️');
      case 55: return const _WmoCondition('高密度毛毛雨', '🌧️');
      case 56: return const _WmoCondition('轻度冻毛毛雨', '🌧️❄️');
      case 57: return const _WmoCondition('重度冻毛毛雨', '🌧️❄️');
      case 61: return const _WmoCondition('小雨', '🌦️');
      case 63: return const _WmoCondition('中雨', '🌧️');
      case 65: return const _WmoCondition('大雨', '🌧️🌧️');
      case 66: return const _WmoCondition('轻度冻雨', '🌧️❄️');
      case 67: return const _WmoCondition('重度冻雨', '🌧️❄️');
      case 71: return const _WmoCondition('小雪', '🌨️');
      case 73: return const _WmoCondition('中雪', '🌨️❄️');
      case 75: return const _WmoCondition('大雪', '❄️❄️');
      case 77: return const _WmoCondition('雪粒', '🌨️');
      case 80: return const _WmoCondition('微弱阵雨', '🌦️');
      case 81: return const _WmoCondition('中度阵雨', '🌧️');
      case 82: return const _WmoCondition('强暴阵雨', '⛈️');
      case 85: return const _WmoCondition('微弱阵雪', '🌨️');
      case 86: return const _WmoCondition('强阵雪', '🌨️❄️');
      case 95: return const _WmoCondition('雷暴', '⛈️');
      case 96: return const _WmoCondition('雷暴伴有轻度冰雹', '⛈️🌨️');
      case 99: return const _WmoCondition('雷暴伴有强冰雹', '⛈️🌨️');
      default: return _WmoCondition('未知天气 (代码: $code)', '❓');
    }
  }
}

class _WmoCondition {
  final String text;
  final String icon;
  const _WmoCondition(this.text, this.icon);
}
