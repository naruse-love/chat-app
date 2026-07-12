import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/model_info.dart';
import 'sse_parser.dart';
import '../utils/sse_decoder.dart';

/// Service class to communicate with the 9Router (OpenAI-compatible) API.
/// Supports chat streaming, vision multi-modal message formats, tool calling configuration,
/// request cancellation, and model list fetching.
class ChatService {
  final Dio _dio;

  ChatService({Dio? dio}) : _dio = dio ?? Dio();

  /// Requests a streaming response from the /v1/chat/completions endpoint.
  /// Converts [messages] into the appropriate format (including base64 vision images),
  /// binds any [tools] configured, and yields parsed SSE stream chunks as JSON [Map]s.
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) async* {
    final List<Map<String, dynamic>> apiMessages = [];
    for (final message in messages) {
      apiMessages.add(await _convertMessageToApiFormat(message));
    }

    final body = {
      'model': model,
      'messages': apiMessages,
      'stream': true,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };

    final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = '$cleanBaseUrl/chat/completions';

    final options = Options(
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      responseType: ResponseType.stream,
    );

    final response = await _dio.post(
      url,
      data: body,
      options: options,
      cancelToken: cancelToken,
    );

    final responseBody = response.data;
    if (responseBody is! ResponseBody) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Expected ResponseBody stream but got ${responseBody.runtimeType}',
      );
    }

    yield* SseParser.parse(responseBody.stream.transform(const SseDecoder()));
  }

  /// Fetches the list of available models from the /v1/models endpoint,
  /// parses each to a list of [ModelInfo] objects.
  Future<List<ModelInfo>> getModels({
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = '$cleanBaseUrl/models';

    final options = Options(
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
    );

    final response = await _dio.get(
      url,
      options: options,
      cancelToken: cancelToken,
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = response.data is String
          ? json.decode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      final List<dynamic> list = data['data'] as List<dynamic>? ?? [];
      return list.map((item) {
        return ModelInfo.fromApiResponse(item as Map<String, dynamic>);
      }).toList();
    } else {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
  }

  /// Converts a [ChatMessage] object to the JSON payload map expected by OpenAI-compatible APIs.
  /// If the message has an [imagePath], it reads the file and encodes it as base64 for vision capabilities.
  Future<Map<String, dynamic>> _convertMessageToApiFormat(ChatMessage message) async {
    if (message.imagePath == null || message.imagePath!.isEmpty) {
      return {
        'role': message.role,
        'content': message.content,
        if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
          'tool_calls': message.toolCalls!.map((tc) => tc.toJson()).toList(),
        if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
      };
    }

    String base64Image;
    String mimeType = 'image/jpeg';
    final path = message.imagePath!;

    if (path.startsWith('data:image/')) {
      base64Image = path;
    } else {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final encoded = base64Encode(bytes);
          final extension = path.split('.').last.toLowerCase();
          if (extension == 'png') {
            mimeType = 'image/png';
          } else if (extension == 'webp') {
            mimeType = 'image/webp';
          } else if (extension == 'gif') {
            mimeType = 'image/gif';
          }
          base64Image = 'data:$mimeType;base64,$encoded';
        } else {
          base64Image = path; // Fallback to raw string if file does not exist
        }
      } catch (e) {
        base64Image = path; // Fallback on exception
      }
    }

    final contentParts = [
      {
        'type': 'text',
        'text': message.content,
      },
      {
        'type': 'image_url',
        'image_url': {
          'url': base64Image,
        },
      },
    ];

    return {
      'role': message.role,
      'content': contentParts,
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
        'tool_calls': message.toolCalls!.map((tc) => tc.toJson()).toList(),
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
    };
  }
}
