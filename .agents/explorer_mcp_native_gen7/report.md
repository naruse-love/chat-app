# Model Context Protocol (MCP) & Mobile Native Integration Specification
## Flutter AI Chat Application — Deep Architectural Design & Roadmap

---

## 1. Executive Summary & System Vision

The **Flutter AI Chat Application (chat-app)** is evolving from a single-purpose conversational LLM client with basic web search into a full-featured, autonomous AI Agent ecosystem. To achieve desktop-grade and mobile-native autonomy while maintaining the highest standards of reliability, performance, and security, this specification establishes two foundational integration pillars:

1. **Model Context Protocol (MCP) Client Subsystem**: An implementation of the Anthropic/Open-Source Model Context Protocol over JSON-RPC 2.0 in pure Dart/Flutter. This enables dynamic discovery, schema introspection, and execution of tools and resources across remote cloud servers (via SSE), real-time bidirectional endpoints (via WebSocket), and local subprocesses (via Stdio).
2. **Mobile Native Capabilities Subsystem**: A hardened, privacy-first interface to Android hardware and operating system capabilities—including Calendar management, Exact Alarms & Local Notifications, Contacts query/sanitization, and Geolocation/Geocoding—governed by declarative runtime permissions and interactive Human-in-the-Loop safety barriers.

Both pillars integrate directly with the application's clean Riverpod state management, SQLite DAO data persistence, and robust SSE/multi-turn tool execution loop.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                            Flutter AI Chat Architecture                          │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │                              UI & Presentation Layer                       │  │
│  │   HomeScreen │ McpServersScreen │ ToolsConfigScreen │ SettingsScreen       │  │
│  │   Interactive Tool Confirmation Cards │ Collapsible Reasoning / Tool Views │  │
│  └─────────────────────────────────────┬──────────────────────────────────────┘  │
│                                        │ Riverpod Providers                      │
│  ┌─────────────────────────────────────▼──────────────────────────────────────┐  │
│  │                       Agent & Chat Orchestration Layer                     │  │
│  │   ChatNotifier │ AgentService │ ToolRegistry │ Dynamic Schema Converter    │  │
│  │   Multi-Turn Execution Loop (Max 100 Rounds) │ Token Optimizer & Summary   │  │
│  └──────────────────┬──────────────────────────────────┬──────────────────────┘  │
│                     │                                  │                         │
│  ┌──────────────────▼──────────────┐   ┌───────────────▼──────────────────────┐  │
│  │   Model Context Protocol (MCP)  │   │     Mobile Native Device Layer       │  │
│  │                                 │   │                                      │  │
│  │   ┌──────────────────────────┐  │   │   ┌───────────────────────────────┐  │  │
│  │   │ McpClient State Machine  │  │   │   │ Permission & Safety Barrier   │  │  │
│  │   └────────────┬─────────────┘  │   │   └───────────────┬───────────────┘  │  │
│  │                │ Transports     │   │                   │ Native Plugins   │  │
│  │   ┌────────────┴─────────────┐  │   │   ┌───────────────┴───────────────┐  │  │
│  │   │ SSE │ WebSocket │ Stdio  │  │   │   │ Calendar │ Notifications      │  │  │
│  │   └──────────────────────────┘  │   │   │ Contacts │ Geolocator         │  │  │
│  └──────────────────┬──────────────┘   └───────────────┬──────────────────────┘  │
│                     │                                  │                         │
│  ┌──────────────────▼──────────────────────────────────▼──────────────────────┐  │
│  │                     Data & Persistent Storage Layer                        │  │
│  │   DatabaseHelper (SQLite Schema v4) │ ApiConfigDao │ MessageDao            │  │
│  │   ConversationDao │ McpServerDao │ ToolConfigDao │ SecureStorageService    │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Model Context Protocol (MCP) Client Architecture for Flutter/Dart

### 2.1 Protocol Compliance & JSON-RPC 2.0 Specification

The Model Context Protocol establishes a standardized communication interface between LLM applications (Clients) and external tool/resource providers (Servers). All MCP exchanges strictly follow the **JSON-RPC 2.0** protocol specification.

#### 2.1.1 JSON-RPC 2.0 Message Structure

```dart
// lib/models/mcp/mcp_json_rpc.dart

import 'package:json_annotation/json_annotation.dart';

part 'mcp_json_rpc.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class JsonRpcRequest {
  final String jsonrpc;
  final dynamic id; // String or int
  final String method;
  final Map<String, dynamic>? params;

  JsonRpcRequest({
    this.jsonrpc = '2.0',
    required this.id,
    required this.method,
    this.params,
  });

  factory JsonRpcRequest.fromJson(Map<String, dynamic> json) =>
      _$JsonRpcRequestFromJson(json);
  Map<String, dynamic> toJson() => _$JsonRpcRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class JsonRpcNotification {
  final String jsonrpc;
  final String method;
  final Map<String, dynamic>? params;

  JsonRpcNotification({
    this.jsonrpc = '2.0',
    required this.method,
    this.params,
  });

  factory JsonRpcNotification.fromJson(Map<String, dynamic> json) =>
      _$JsonRpcNotificationFromJson(json);
  Map<String, dynamic> toJson() => _$JsonRpcNotificationToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class JsonRpcResponse {
  final String jsonrpc;
  final dynamic id;
  final Map<String, dynamic>? result;
  final JsonRpcError? error;

  JsonRpcResponse({
    this.jsonrpc = '2.0',
    required this.id,
    this.result,
    this.error,
  });

  bool get isSuccess => error == null;

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) =>
      _$JsonRpcResponseFromJson(json);
  Map<String, dynamic> toJson() => _$JsonRpcResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class JsonRpcError {
  final int code;
  final String message;
  final dynamic data;

  JsonRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  factory JsonRpcError.fromJson(Map<String, dynamic> json) =>
      _$JsonRpcErrorFromJson(json);
  Map<String, dynamic> toJson() => _$JsonRpcErrorToJson(this);
}
```

#### 2.1.2 Standard MCP Error Codes

| Error Code | Name | Semantic Description |
|---|---|---|
| `-32700` | `ParseError` | Invalid JSON received by the server/client |
| `-32600` | `InvalidRequest` | JSON sent is not a valid Request object |
| `-32601` | `MethodNotFound` | The requested method does not exist or is not available |
| `-32602` | `InvalidParams` | Invalid method parameter(s) according to JSON Schema |
| `-32603` | `InternalError` | Internal JSON-RPC / MCP server execution error |
| `-32000` | `ConnectionTimeout` | Transport connection or request timed out |
| `-32001` | `ResourceNotFound` | Requested MCP resource URI could not be located |
| `-32002` | `ToolExecutionError` | Tool crashed or returned an unhandled exception |

---

### 2.2 Multi-Transport Layer Architecture

The MCP client architecture supports three pluggable transport protocols, unified behind a common `McpTransport` abstraction:

```dart
// lib/services/mcp/mcp_transport.dart

abstract class McpTransport {
  /// Stream of incoming JSON-RPC responses and notifications from the MCP server.
  Stream<Map<String, dynamic>> get messageStream;

  /// Stream of transport connection lifecycle state changes.
  Stream<McpTransportState> get stateStream;

  /// Current connection state.
  McpTransportState get currentState;

  /// Establishes the transport connection.
  Future<void> connect();

  /// Sends an outgoing JSON-RPC request or notification payload.
  Future<void> send(Map<String, dynamic> payload);

  /// Closes the transport connection and cleans up resources.
  Future<void> disconnect();
}

enum McpTransportState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}
```

#### 2.2.1 SSE (Server-Sent Events) Transport (`SseMcpTransport`)
- **Use Case**: Remote cloud-hosted MCP servers (e.g. GitHub MCP, Linear MCP, Postgres MCP, Web Search MCP).
- **Protocol Flow**:
  1. Client sends HTTP GET to `https://server.com/sse` with headers (e.g. `Authorization: Bearer <token>`, `Accept: text/event-stream`).
  2. Server responds with `200 OK` and `Content-Type: text/event-stream`.
  3. Server immediately emits an `endpoint` SSE event: `event: endpoint\ndata: /messages?sessionId=abc123xyz\n\n`.
  4. Client stores the POST endpoint URL (`https://server.com/messages?sessionId=abc123xyz`).
  5. Client transmits JSON-RPC requests via HTTP POST to this endpoint.
  6. Server asynchronously streams back JSON-RPC responses and notifications over the open SSE connection.
  7. Client's `SseDecoder` and `SseParser` parse incoming lines and dispatch JSON objects.
- **Resilience**: Auto-reconnect with exponential backoff (`1s`, `2s`, `4s`, `8s`, max `30s`), preserving session IDs across network drops.

```dart
// lib/services/mcp/sse_mcp_transport.dart

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'mcp_transport.dart';
import '../../utils/sse_decoder.dart';

class SseMcpTransport implements McpTransport {
  final String sseUrl;
  final Map<String, String> headers;
  final Dio _dio;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<McpTransportState>.broadcast();

  McpTransportState _state = McpTransportState.disconnected;
  String? _postEndpointUrl;
  CancelToken? _cancelToken;

  SseMcpTransport({
    required this.sseUrl,
    this.headers = const {},
    Dio? dio,
  }) : _dio = dio ?? Dio();

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<McpTransportState> get stateStream => _stateController.stream;

  @override
  McpTransportState get currentState => _state;

  void _setState(McpTransportState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> connect() async {
    if (_state == McpTransportState.connected || _state == McpTransportState.connecting) return;
    _setState(McpTransportState.connecting);
    _cancelToken = CancelToken();

    try {
      final response = await _dio.get<ResponseBody>(
        sseUrl,
        options: Options(
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            ...headers,
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );

      _setState(McpTransportState.connected);

      final stream = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const SseDecoder());

      stream.listen(
        (sseEvent) {
          if (sseEvent.event == 'endpoint') {
            final path = sseEvent.data.trim();
            if (path.startsWith('http://') || path.startsWith('https://')) {
              _postEndpointUrl = path;
            } else {
              final baseUri = Uri.parse(sseUrl);
              _postEndpointUrl = baseUri.resolve(path).toString();
            }
          } else if (sseEvent.event == 'message' || sseEvent.event.isEmpty) {
            try {
              final json = jsonDecode(sseEvent.data) as Map<String, dynamic>;
              _messageController.add(json);
            } catch (_) {}
          }
        },
        onError: (err) {
          _setState(McpTransportState.error);
        },
        onDone: () {
          _setState(McpTransportState.disconnected);
        },
        cancelOnError: true,
      );
    } catch (e) {
      _setState(McpTransportState.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> payload) async {
    if (_postEndpointUrl == null) {
      throw StateError('SSE transport not ready: POST endpoint not received from server');
    }

    await _dio.post(
      _postEndpointUrl!,
      data: payload,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _cancelToken?.cancel('Client requested disconnect');
    _setState(McpTransportState.disconnected);
  }
}
```

#### 2.2.2 WebSocket Transport (`WebSocketMcpTransport`)
- **Use Case**: Low-latency, full-duplex bi-directional communication (ideal for local network servers, microservices, or cloud agents).
- **Protocol Flow**:
  1. Client initiates connection via `WebSocket.connect(wsUrl, headers: headers)`.
  2. Messages (requests, responses, notifications) are sent and received as UTF-8 JSON text frames.
  3. Automatic ping/pong frames to verify connection liveness.

```dart
// lib/services/mcp/websocket_mcp_transport.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mcp_transport.dart';

class WebSocketMcpTransport implements McpTransport {
  final String wsUrl;
  final Map<String, dynamic> headers;

  WebSocket? _socket;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<McpTransportState>.broadcast();
  McpTransportState _state = McpTransportState.disconnected;

  WebSocketMcpTransport({
    required this.wsUrl,
    this.headers = const {},
  });

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<McpTransportState> get stateStream => _stateController.stream;

  @override
  McpTransportState get currentState => _state;

  void _setState(McpTransportState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> connect() async {
    if (_state == McpTransportState.connected) return;
    _setState(McpTransportState.connecting);

    try {
      _socket = await WebSocket.connect(
        wsUrl,
        headers: headers.map((k, v) => MapEntry(k, v.toString())),
      );
      _setState(McpTransportState.connected);

      _socket!.listen(
        (data) {
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              _messageController.add(json);
            } catch (_) {}
          }
        },
        onError: (err) {
          _setState(McpTransportState.error);
        },
        onDone: () {
          _setState(McpTransportState.disconnected);
        },
      );
    } catch (e) {
      _setState(McpTransportState.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> payload) async {
    if (_socket == null || _state != McpTransportState.connected) {
      throw StateError('WebSocket is not connected');
    }
    _socket!.add(jsonEncode(payload));
  }

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _setState(McpTransportState.disconnected);
  }
}
```

#### 2.2.3 Stdio Transport (`StdioMcpTransport`)
- **Use Case**: Local subprocess execution on Desktop (Windows, macOS, Linux) and Android environments with executable support (Termux, proot, or bundled pre-compiled binaries).
- **Protocol Flow**:
  1. Client spawns subprocess: `Process.start(command, arguments, environment: env)`.
  2. Communication occurs over standard input (`process.stdin`) and standard output (`process.stdout`).
  3. Newline-delimited JSON (`\n`) is written to `stdin` and read from `stdout`.
  4. Diagnostics and errors from `process.stderr` are captured and routed to the logging system.
  5. On app teardown or disconnect, `process.kill(ProcessSignal.sigterm)` is executed to prevent orphan zombie processes.

```dart
// lib/services/mcp/stdio_mcp_transport.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mcp_transport.dart';

class StdioMcpTransport implements McpTransport {
  final String command;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;

  Process? _process;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<McpTransportState>.broadcast();
  McpTransportState _state = McpTransportState.disconnected;

  StdioMcpTransport({
    required this.command,
    this.arguments = const [],
    this.environment = const {},
    this.workingDirectory,
  });

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<McpTransportState> get stateStream => _stateController.stream;

  @override
  McpTransportState get currentState => _state;

  void _setState(McpTransportState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> connect() async {
    if (_state == McpTransportState.connected) return;
    _setState(McpTransportState.connecting);

    try {
      _process = await Process.start(
        command,
        arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        runInShell: Platform.isWindows,
      );

      _setState(McpTransportState.connected);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.trim().isEmpty) return;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            _messageController.add(json);
          } catch (_) {}
        },
        onError: (err) => _setState(McpTransportState.error),
        onDone: () => _setState(McpTransportState.disconnected),
      );

      _process!.exitCode.then((code) {
        _setState(McpTransportState.disconnected);
      });
    } catch (e) {
      _setState(McpTransportState.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> payload) async {
    if (_process == null || _state != McpTransportState.connected) {
      throw StateError('Stdio process is not running');
    }
    final rawLine = jsonEncode(payload);
    _process!.stdin.writeln(rawLine);
    await _process!.stdin.flush();
  }

  @override
  Future<void> disconnect() async {
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    _setState(McpTransportState.disconnected);
  }
}
```

---

### 2.3 McpClient State Machine & Lifecycle

The `McpClient` manages the full lifecycle of an MCP session, from handshake negotiation to tool invocation and resource fetching.

```
┌─────────────────┐       connect()        ┌─────────────────┐
│  Disconnected   │ ─────────────────────► │   Connecting    │
└─────────────────┘                        └────────┬────────┘
         ▲                                          │ Transport Connected
         │                                          ▼
         │  disconnect() / Error           ┌─────────────────┐
         ├──────────────────────────────── │  Initializing   │ (initialize handshake)
         │                                 └────────┬────────┘
         │                                          │ Handshake OK + initialized notification
         │                                          ▼
┌─────────────────┐      tools/list        ┌─────────────────┐
│     Active      │ ◄────────────────────► │    Connected    │ (Ping / CallTool / ListResources)
└─────────────────┘                        └─────────────────┘
```

#### 2.3.1 McpClient Implementation

```dart
// lib/services/mcp/mcp_client.dart

import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../models/mcp/mcp_json_rpc.dart';
import '../../models/mcp/mcp_server_config.dart';
import 'mcp_transport.dart';

class McpClient {
  final McpServerConfig config;
  final McpTransport transport;
  final _pendingRequests = <String, Completer<JsonRpcResponse>>{};
  final _uuid = const Uuid();

  Map<String, dynamic>? serverCapabilities;
  Map<String, dynamic>? serverInfo;
  String protocolVersion = '2024-11-05';
  bool _isInitialized = false;

  McpClient({
    required this.config,
    required this.transport,
  }) {
    transport.messageStream.listen(_handleIncomingMessage);
  }

  bool get isReady => transport.currentState == McpTransportState.connected && _isInitialized;

  /// Connects transport and performs the MCP initialize handshake.
  Future<void> initialize() async {
    await transport.connect();

    // 1. Send 'initialize' request
    final initResponse = await sendRequest('initialize', {
      'protocolVersion': protocolVersion,
      'capabilities': {
        'roots': {'listChanged': true},
        'sampling': {},
      },
      'clientInfo': {
        'name': 'chat-app-flutter',
        'version': '1.08.0',
      },
    });

    if (initResponse.error != null) {
      throw Exception('MCP initialization failed: ${initResponse.error!.message}');
    }

    final result = initResponse.result ?? {};
    serverCapabilities = result['capabilities'] as Map<String, dynamic>?;
    serverInfo = result['serverInfo'] as Map<String, dynamic>?;
    protocolVersion = result['protocolVersion'] as String? ?? protocolVersion;

    // 2. Send 'notifications/initialized'
    await sendNotification('notifications/initialized');
    _isInitialized = true;
  }

  /// Sends a JSON-RPC request and awaits the correlated response.
  Future<JsonRpcResponse> sendRequest(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    final id = _uuid.v4();
    final completer = Completer<JsonRpcResponse>();
    _pendingRequests[id] = completer;

    final request = JsonRpcRequest(
      id: id,
      method: method,
      params: params,
    );

    try {
      await transport.send(request.toJson());
      return await completer.future.timeout(timeout, onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('MCP request $method ($id) timed out after ${timeout.inSeconds}s');
      });
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  /// Sends a JSON-RPC notification (no response expected).
  Future<void> sendNotification(String method, [Map<String, dynamic>? params]) async {
    final notification = JsonRpcNotification(
      method: method,
      params: params,
    );
    await transport.send(notification.toJson());
  }

  /// Checks server liveness and returns round-trip latency in milliseconds.
  Future<int> ping() async {
    final stopwatch = Stopwatch()..start();
    final response = await sendRequest('ping', null, const Duration(seconds: 5));
    stopwatch.stop();
    if (response.error != null) {
      throw Exception('Ping failed: ${response.error!.message}');
    }
    return stopwatch.elapsedMilliseconds;
  }

  /// Lists all tools exposed by this MCP server.
  Future<List<Map<String, dynamic>>> listTools() async {
    final response = await sendRequest('tools/list');
    if (response.error != null) {
      throw Exception('Failed to list tools: ${response.error!.message}');
    }
    final tools = response.result?['tools'] as List<dynamic>? ?? [];
    return tools.cast<Map<String, dynamic>>();
  }

  /// Invokes a specific tool on this MCP server.
  Future<McpToolCallResult> callTool(String name, Map<String, dynamic> arguments) async {
    final response = await sendRequest('tools/call', {
      'name': name,
      'arguments': arguments,
    }, const Duration(seconds: 60));

    if (response.error != null) {
      return McpToolCallResult(
        isError: true,
        content: 'MCP Error [${response.error!.code}]: ${response.error!.message}',
      );
    }

    final result = response.result ?? {};
    final isError = result['isError'] as bool? ?? false;
    final contentList = result['content'] as List<dynamic>? ?? [];

    final buffer = StringBuffer();
    for (final item in contentList) {
      if (item is Map<String, dynamic>) {
        if (item['type'] == 'text') {
          buffer.writeln(item['text'] as String? ?? '');
        } else if (item['type'] == 'image') {
          buffer.writeln('[Image data (${item['mimeType']}) omitted]');
        } else if (item['type'] == 'resource') {
          buffer.writeln('[Resource URI: ${item['resource']?['uri']}]');
        }
      }
    }

    return McpToolCallResult(
      isError: isError,
      content: buffer.toString().trim(),
      rawResult: result,
    );
  }

  /// Lists all resources exposed by this MCP server.
  Future<List<Map<String, dynamic>>> listResources() async {
    final response = await sendRequest('resources/list');
    if (response.error != null) {
      throw Exception('Failed to list resources: ${response.error!.message}');
    }
    final resources = response.result?['resources'] as List<dynamic>? ?? [];
    return resources.cast<Map<String, dynamic>>();
  }

  /// Reads a specific resource by URI.
  Future<String> readResource(String uri) async {
    final response = await sendRequest('resources/read', {'uri': uri});
    if (response.error != null) {
      throw Exception('Failed to read resource $uri: ${response.error!.message}');
    }
    final contents = response.result?['contents'] as List<dynamic>? ?? [];
    if (contents.isEmpty) return '';
    final first = contents.first as Map<String, dynamic>;
    return first['text'] as String? ?? first['blob'] as String? ?? '';
  }

  void _handleIncomingMessage(Map<String, dynamic> json) {
    if (json.containsKey('id') && json['id'] != null) {
      // It's a response
      final id = json['id'].toString();
      final completer = _pendingRequests.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(JsonRpcResponse.fromJson(json));
      }
    } else if (json.containsKey('method')) {
      // It's a notification from server
      _handleServerNotification(json['method'] as String, json['params'] as Map<String, dynamic>?);
    }
  }

  void _handleServerNotification(String method, Map<String, dynamic>? params) {
    if (method == 'notifications/progress') {
      // Progress notification: params['progressToken'], params['progress'], params['total']
    } else if (method == 'notifications/message') {
      // Server log message
    } else if (method == 'notifications/tools/list_changed') {
      // Server toolset updated dynamically
    }
  }

  Future<void> disconnect() async {
    _isInitialized = false;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Client disconnected'));
      }
    }
    _pendingRequests.clear();
    await transport.disconnect();
  }
}

class McpToolCallResult {
  final bool isError;
  final String content;
  final Map<String, dynamic>? rawResult;

  McpToolCallResult({
    required this.isError,
    required this.content,
    this.rawResult,
  });
}
```

---

### 2.4 McpServerConfig & SQLite Persistence (`McpServerDao`)

User-configured MCP servers are persisted to SQLite so connections can be automatically restored or toggled across app sessions.

#### 2.4.1 Data Model

```dart
// lib/models/mcp/mcp_server_config.dart

import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'mcp_server_config.g.dart';

enum McpTransportType {
  @JsonValue('sse')
  sse,
  @JsonValue('websocket')
  websocket,
  @JsonValue('stdio')
  stdio,
}

@JsonSerializable(explicitToJson: true)
class McpServerConfig {
  final String id;
  final String name;
  final McpTransportType transportType;
  final String endpointOrCommand; // URL or executable command path
  final List<String> commandArgs;
  final Map<String, String> headers;
  final Map<String, String> environment;
  final bool isEnabled;
  final bool autoConnect;
  final DateTime createdAt;
  final DateTime updatedAt;

  McpServerConfig({
    required this.id,
    required this.name,
    required this.transportType,
    required this.endpointOrCommand,
    this.commandArgs = const [],
    this.headers = const {},
    this.environment = const {},
    this.isEnabled = true,
    this.autoConnect = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      _$McpServerConfigFromJson(json);
  Map<String, dynamic> toJson() => _$McpServerConfigToJson(this);

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'name': name,
      'transportType': transportType.name,
      'endpointOrCommand': endpointOrCommand,
      'commandArgsJson': jsonEncode(commandArgs),
      'headersJson': jsonEncode(headers),
      'environmentJson': jsonEncode(environment),
      'isEnabled': isEnabled ? 1 : 0,
      'autoConnect': autoConnect ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory McpServerConfig.fromDbMap(Map<String, dynamic> map) {
    return McpServerConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      transportType: McpTransportType.values.byName(map['transportType'] as String),
      endpointOrCommand: map['endpointOrCommand'] as String,
      commandArgs: map['commandArgsJson'] != null
          ? (jsonDecode(map['commandArgsJson'] as String) as List<dynamic>).cast<String>()
          : const [],
      headers: map['headersJson'] != null
          ? (jsonDecode(map['headersJson'] as String) as Map<String, dynamic>).cast<String, String>()
          : const {},
      environment: map['environmentJson'] != null
          ? (jsonDecode(map['environmentJson'] as String) as Map<String, dynamic>).cast<String, String>()
          : const {},
      isEnabled: (map['isEnabled'] as int) == 1,
      autoConnect: (map['autoConnect'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
```

#### 2.4.2 SQLite DAO (`McpServerDao`)

```dart
// lib/data/mcp_server_dao.dart

import 'package:sqflite/sqflite.dart';
import '../models/mcp/mcp_server_config.dart';
import 'database_helper.dart';

class McpServerDao {
  final DatabaseHelper _dbHelper;

  McpServerDao([DatabaseHelper? dbHelper]) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<List<McpServerConfig>> getAllServers() async {
    final db = await _dbHelper.database;
    final maps = await db.query('mcp_servers', orderBy: 'createdAt ASC');
    return maps.map((m) => McpServerConfig.fromDbMap(m)).toList();
  }

  Future<McpServerConfig?> getServerById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('mcp_servers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return McpServerConfig.fromDbMap(maps.first);
  }

  Future<void> insertServer(McpServerConfig config) async {
    final db = await _dbHelper.database;
    await db.insert(
      'mcp_servers',
      config.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateServer(McpServerConfig config) async {
    final db = await _dbHelper.database;
    await db.update(
      'mcp_servers',
      config.toDbMap(),
      where: 'id = ?',
      whereArgs: [config.id],
    );
  }

  Future<void> deleteServer(String id) async {
    final db = await _dbHelper.database;
    await db.delete('mcp_servers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleEnabled(String id, bool isEnabled) async {
    final db = await _dbHelper.database;
    await db.update(
      'mcp_servers',
      {'isEnabled': isEnabled ? 1 : 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
```

---

### 2.5 Dynamic Tool Discovery, Namespacing & OpenAI Schema Conversion

When an MCP client connects, it queries `tools/list`. To make these tools callable by OpenAI-compatible models (like DeepSeek, GPT-4o, Claude 3.5 Sonnet) without colliding across multiple servers, the client performs **namespacing and schema projection**.

#### 2.5.1 Namespace Isolation Rule

Tool names are prefixed with `mcp__<serverId>__<toolName>`.

- **Example**: An MCP server named `github` with ID `srv_gh` exposing `create_issue` becomes:
  `mcp__srv_gh__create_issue`
- **Routing**: When the LLM outputs a tool call to `mcp__srv_gh__create_issue`, the registry extracts the prefix `srv_gh`, routes the arguments to the `McpClient` for `srv_gh`, and calls `callTool('create_issue', args)`.

#### 2.5.2 Schema Mapping Blueprint

```dart
// lib/services/mcp/mcp_schema_converter.dart

class McpSchemaConverter {
  /// Converts an MCP tool definition into an OpenAI Function Calling JSON Schema.
  static Map<String, dynamic> toOpenAiFunction({
    required String serverId,
    required Map<String, dynamic> mcpTool,
  }) {
    final originalName = mcpTool['name'] as String;
    final namespacedName = 'mcp__${serverId}__$originalName';
    final description = mcpTool['description'] as String? ?? 'MCP Tool ($originalName)';
    final inputSchema = mcpTool['inputSchema'] as Map<String, dynamic>? ?? {
      'type': 'object',
      'properties': {},
    };

    return {
      'type': 'function',
      'function': {
        'name': namespacedName,
        'description': '[MCP Server: $serverId] $description',
        'parameters': inputSchema,
      },
    };
  }

  /// Parses a namespaced tool name into (serverId, originalToolName).
  static (String serverId, String originalName)? parseNamespacedName(String name) {
    if (!name.startsWith('mcp__')) return null;
    final parts = name.split('__');
    if (parts.length < 3) return null;
    final serverId = parts[1];
    final originalName = parts.sublist(2).join('__');
    return (serverId, originalName);
  }
}
```

---

### 2.6 User Interface: `McpServersScreen` & Tool Inspector Drawer

The MCP Management UI provides users with total visibility and control over external tools:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ☰  MCP 服务管理 (Model Context Protocol)                       [ + 添加服务 ] │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 🟢 GitHub MCP Server (SSE)                                 [ 38ms ]  │  │
│  │    URL: https://mcp.github.com/sse                                   │  │
│  │    已发现 6 个工具: create_issue, get_file, list_repos...   [ ⚙ ] [ 🗑 ] │  │
│  │    [ 查看可用工具 (6) ]                                               │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 🟢 SQLite Local MCP (Stdio)                                [ 4ms ]   │  │
│  │    CMD: /data/data/com.example.chat/files/sqlite-mcp                 │  │
│  │    已发现 3 个工具: query_db, list_tables, explain_query     [ ⚙ ] [ 🗑 ] │  │
│  │    [ 查看可用工具 (3) ]                                               │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 🔴 Linear Workspace (WebSocket)                          [ 连接断开 ] │  │
│  │    WS: wss://api.linear.app/mcp                                      │  │
│  │    未连接 - 点击重新连接                                    [ ⚙ ] [ 🗑 ] │  │
│  │    [ 重试连接 ]                                                       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

#### UI Feature Specifications
1. **Server Status Indicators**:
   - `Connected` (Green Chip): Displays live round-trip ping latency (e.g. `38ms`).
   - `Connecting` (Amber Pulsing Chip): Connecting or performing initialize handshake.
   - `Disconnected` / `Error` (Red Chip): Error description with "Retry" action.
2. **Tool Inspector BottomSheet / Drawer**:
   - Tapping "查看可用工具" slides up a structured sheet detailing all registered tools from that server.
   - Each tool card displays its description, parameter schema, required fields, and sample invocation payload.
3. **Add/Edit Server Dialog**:
   - Transport Selector: `SSE (Remote HTTP)` / `WebSocket` / `Stdio (Local Command)`.
   - URL or Command Path input with validation.
   - Headers/Auth Token key-value editor (tokens stored securely).
   - "测试连接" (Test Connection) button that validates transport connectivity, handshake, and `tools/list` retrieval before saving.

---

## 3. Mobile Native Device Capabilities on Android/Flutter

### 3.1 Plugin Ecosystem Selection & Trade-Off Analysis

| Capability | Chosen Plugin | Version | Key Architectural Trade-Offs & Rationale |
|---|---|---|---|
| **Calendar** | `device_calendar` | `^4.3.2` | • Full support for querying Android Calendar Provider (`CalendarContract`).<br>• Supports event recurrence (RRULE), attendee lists, custom reminder alarms.<br>• Clean async API returning typed `Calendar` and `Event` objects. |
| **Notifications & Alarms** | `flutter_local_notifications` | `^17.2.2` | • Direct integration with Android Notification Channels (`NotificationChannelGroup`).<br>• High-precision scheduled reminders using `AlarmManager.setExactAndAllowWhileIdle()`.<br>• Handles Android 13+ runtime permission and Android 12+ exact alarm policy. |
| **Background Scheduling** | `android_alarm_manager_plus` | `^3.0.4` | • Reliable periodic background tasks even when app is suspended/killed.<br>• Wakes device from Doze mode for critical alarms. |
| **Contacts** | `flutter_contacts` | `^1.1.9+2` | • Fast indexed querying with name search filter.<br>• Direct property retrieval (phones, emails, addresses, avatars).<br>• Safe read/write interface with batch capability. |
| **Geolocation** | `geolocator` | `^12.0.0` | • High-precision GPS and coarse network location retrieval.<br>• Direct check of location services enablement and GPS provider status.<br>• Distance calculation and geofencing support. |
| **Geocoding** | `geocoding` | `^3.0.0` | • Native Android `Geocoder` integration for reverse geocoding (Lat/Lng ➔ Address/City).<br>• Forward geocoding (Address ➔ Lat/Lng coordinates). |
| **Permissions** | `permission_handler` | `^11.3.1` | • Declarative permission status checks (`isGranted`, `isPermanentlyDenied`).<br>• Direct routing to system settings via `openAppSettings()`. |

---

### 3.2 Native Capability Implementations & API Contracts

#### 3.2.1 Calendar Service (`CalendarNativeService`)

```dart
// lib/services/native/calendar_native_service.dart

import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarNativeService {
  final DeviceCalendarPlugin _deviceCalendar;

  CalendarNativeService([DeviceCalendarPlugin? deviceCalendar])
      : _deviceCalendar = deviceCalendar ?? DeviceCalendarPlugin();

  Future<bool> requestPermissions() async {
    final permissionsGranted = await _deviceCalendar.hasPermissions();
    if (permissionsGranted.isSuccess && (permissionsGranted.data ?? false)) {
      return true;
    }
    final result = await _deviceCalendar.requestPermissions();
    return result.isSuccess && (result.data ?? false);
  }

  Future<List<Calendar>> getCalendars() async {
    final res = await _deviceCalendar.retrieveCalendars();
    if (!res.isSuccess || res.data == null) return [];
    return res.data!;
  }

  Future<List<Event>> getEvents({
    required DateTime startDate,
    required DateTime endDate,
    String? calendarId,
  }) async {
    String? targetCalendarId = calendarId;
    if (targetCalendarId == null) {
      final cals = await getCalendars();
      final defaultCal = cals.firstWhere((c) => c.isDefault ?? false, orElse: () => cals.first);
      targetCalendarId = defaultCal.id;
    }

    final params = RetrieveEventsParams(
      startDate: startDate,
      endDate: endDate,
    );
    final res = await _deviceCalendar.retrieveEvents(targetCalendarId, params);
    if (!res.isSuccess || res.data == null) return [];
    return res.data!;
  }

  Future<String> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? location,
    int? reminderMinutesBefore,
    String? calendarId,
  }) async {
    String? targetCalId = calendarId;
    if (targetCalId == null) {
      final cals = await getCalendars();
      if (cals.isEmpty) throw StateError('No writable calendar found on device');
      final defaultCal = cals.firstWhere((c) => !(c.isReadOnly ?? false), orElse: () => cals.first);
      targetCalId = defaultCal.id;
    }

    final event = Event(
      targetCalId,
      title: title,
      description: description,
      location: location,
      start: tz.TZDateTime.from(startTime, tz.local),
      end: tz.TZDateTime.from(endTime, tz.local),
    );

    if (reminderMinutesBefore != null) {
      event.reminders = [Reminder(minutes: reminderMinutesBefore)];
    }

    final res = await _deviceCalendar.createOrUpdateEvent(event);
    if (!res.isSuccess || res.data == null) {
      throw Exception('Failed to create calendar event: ${res.errors.map((e) => e.errorMessage).join(", ")}');
    }
    return res.data!;
  }
}
```

#### 3.2.2 Local Notifications & Alarms Service (`NotificationNativeService`)

```dart
// lib/services/native/notification_native_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationNativeService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin;

  NotificationNativeService([FlutterLocalNotificationsPlugin? plugin])
      : _notificationsPlugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);

    // Create default notification channel
    const channel = AndroidNotificationChannel(
      'chat_agent_reminders',
      'AI 助手提醒与通知',
      description: '由 AI 智能体创建的定时提醒与待办通知',
      importance: Importance.high,
      enableVibration: true,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(channel);
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_agent_reminders',
      'AI 助手提醒与通知',
      channelDescription: '由 AI 智能体创建的定时提醒与待办通知',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
```

#### 3.2.3 Contacts Service (`ContactsNativeService`)

```dart
// lib/services/native/contacts_native_service.dart

import 'package:flutter_contacts/flutter_contacts.dart';

class ContactsNativeService {
  Future<bool> requestPermission() async {
    return await FlutterContacts.requestPermission(readonly: true);
  }

  Future<List<Map<String, dynamic>>> searchContacts(String query, {int limit = 10}) async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      throw StateError('Contacts permission denied');
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withAccounts: false,
    );

    final lowerQuery = query.toLowerCase();
    final filtered = contacts.where((c) {
      final nameMatches = c.displayName.toLowerCase().contains(lowerQuery);
      final phoneMatches = c.phones.any((p) => p.number.contains(query));
      return nameMatches || phoneMatches;
    }).take(limit);

    // Apply strict privacy sanitization (strip notes, addresses, account IDs)
    return filtered.map((c) => {
      'id': c.id,
      'name': c.displayName,
      'phones': c.phones.map((p) => p.number).toList(),
      'emails': c.emails.map((e) => e.address).toList(),
    }).toList();
  }
}
```

#### 3.2.4 Geolocation & Geocoding Service (`LocationNativeService`)

```dart
// lib/services/native/location_native_service.dart

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationNativeService {
  Future<Map<String, dynamic>> getCurrentDeviceLocation({bool highAccuracy = false}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Location services are disabled on device');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw StateError('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError('Location permission permanently denied. Please enable in Settings.');
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 15),
    );

    // Reverse geocode to human-readable address
    String? address;
    String? city;
    String? country;
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        city = p.locality ?? p.subAdministrativeArea;
        country = p.country;
        address = '${p.country ?? ""} ${p.administrativeArea ?? ""} ${p.locality ?? ""} ${p.thoroughfare ?? ""} ${p.subThoroughfare ?? ""}'.trim();
      }
    } catch (_) {}

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracyMeters': position.accuracy,
      'city': city,
      'country': country,
      'formattedAddress': address,
      'timestamp': position.timestamp.toIso8601String(),
    };
  }
}
```

---

### 3.3 Android Manifest, Permissions & OS Version Adaptation

To support modern Android releases (Android 12 Snow Cone, Android 13 Tiramisu, Android 14 Upside Down Cake, Android 15+), the `AndroidManifest.xml` and runtime permission workflows require specific declarations:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <!-- Calendar Permissions -->
    <uses-permission android:name="android.permission.READ_CALENDAR"/>
    <uses-permission android:name="android.permission.WRITE_CALENDAR"/>

    <!-- Notification & Alarm Permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <!-- Android 12+ Exact Alarms -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <!-- Android 13+ Use Exact Alarms for calendar/alarms -->
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>

    <!-- Contacts Permissions -->
    <uses-permission android:name="android.permission.READ_CONTACTS"/>
    <uses-permission android:name="android.permission.WRITE_CONTACTS"/>

    <!-- Location Permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

    <application
        android:label="chat"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Local Notification Boot Receiver -->
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

---

### 3.4 Safety Barriers, Privacy Protections & Human-in-the-Loop Dialogs

#### 3.4.1 Risk Classification Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Tool Risk Tier Classification                         │
├──────────────────────┬─────────────────────────────┬────────────────────────┤
│ Tier Level           │ Included Tools              │ Safety Barrier Policy  │
├──────────────────────┼─────────────────────────────┼────────────────────────┤
│ **Tier 0 (Safe)**    │ math_eval, time_calculator, │ Auto-Executed          │
│ Pure compute & info  │ weather_query, wiki_lookup  │ No confirmation needed │
├──────────────────────┼─────────────────────────────┼────────────────────────┤
│ **Tier 1 (Read PII)**│ calendar_get_events,        │ Runtime Permission     │
│ Read private data    │ contacts_search, location   │ + Privacy Sanitizer    │
├──────────────────────┼─────────────────────────────┼────────────────────────┤
│ **Tier 2 (Mutate)**  │ calendar_create_event,      │ Mandatory Interactive  │
│ Device state write   │ notification_schedule,      │ Confirmation Card      │
│                      │ file_write, clipboard_set   │ (Human-in-the-Loop)    │
├──────────────────────┼─────────────────────────────┼────────────────────────┤
│ **Tier 3 (Execute)** │ code_eval, shell_exec       │ Sandboxed Environment  │
│ Arbitrary execution  │                             │ + 5s Timeout + Dialog  │
└──────────────────────┴─────────────────────────────┴────────────────────────┘
```

#### 3.4.2 Human-in-the-Loop Confirmation Card (UI Component)

When the Agent decides to execute a Tier 2 tool (e.g. `calendar_create_event`), the stream pauses and yields an interactive confirmation card into the chat flow:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ⚠️ AI 智能体请求执行操作: 创建日历日程                                     │
├────────────────────────────────────────────────────────────────────────────┤
│ • 标题: 项目周例会 & 架构评审                                              │
│ • 时间: 2026-08-29 14:00 - 15:30                                           │
│ • 地点: 3号会议室 (线上腾讯会议同步)                                       │
│ • 提前提醒: 15 分钟                                                        │
├────────────────────────────────────────────────────────────────────────────┤
│                    [ ✕ 拒绝取消 ]       [ ✓ 确认执行 ]                     │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Testing, Mocking & CI/CD Verification Strategy

To guarantee that `flutter test` executes with **100% pass rate (0 failures)** in headless Windows/Linux CI environments without real Android devices, all native Platform Channels and FFI calls are completely intercepted and mocked.

### 4.1 Headless Platform Channel Mocking (`MockNativeChannelHelper`)

```dart
// test/mocks/mock_native_channel_helper.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MockNativeChannelHelper {
  static void setupAllMocks() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // 1. Mock permission_handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return 1; // PermissionStatus.granted
        } else if (methodCall.method == 'requestPermissions') {
          final permissions = methodCall.arguments as List<dynamic>;
          return {for (var p in permissions) p: 1};
        }
        return null;
      },
    );

    // 2. Mock geolocator
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isLocationServiceEnabled') {
          return true;
        } else if (methodCall.method == 'getCurrentPosition') {
          return {
            'latitude': 39.9042,
            'longitude': 116.4074,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'accuracy': 5.0,
            'altitude': 0.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
          };
        }
        return null;
      },
    );

    // 3. Mock flutter_local_notifications
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'initialize') return true;
        if (methodCall.method == 'zonedSchedule') return null;
        if (methodCall.method == 'cancel') return null;
        return null;
      },
    );

    // 4. Mock device_calendar
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.builttoroam.com/device_calendar'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'hasPermissions') return true;
        if (methodCall.method == 'requestPermissions') return true;
        if (methodCall.method == 'retrieveCalendars') {
          return '[{"id":"1","name":"Personal Calendar","isReadOnly":false,"isDefault":true}]';
        }
        if (methodCall.method == 'createOrUpdateEvent') {
          return 'mock_event_id_12345';
        }
        return null;
      },
    );

    // 5. Mock flutter_contacts
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('github.com/Quis/flutter_contacts'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'requestPermission') return true;
        if (methodCall.method == 'select') return [];
        return null;
      },
    );
  }
}
```

---

## 5. Comprehensive Milestone Breakdown & Roadmap (Milestones 23 - 27+)

```
Milestone 23 ──► Milestone 24 ──► Milestone 25 ──► Milestone 26 ──► Milestone 27
[Core Tool]     [File & Code]   [Native Device]   [MCP Protocol]   [Hardening &]
[Registry &]    [Execution  ]   [Capabilities ]   [Client & UI ]   [Release Pkg]
[Basic Tools]   [Sandboxing ]   [Permissions  ]   [Transports  ]   [Token Opt  ]
```

### 5.1 Milestone 23: Core Tool Registry Foundation & Basic Built-in Tools

- **Objective**: Establish the pluggable `ToolRegistry` architecture, decouple tool execution from hardcoded `AgentService` conditionals, and implement the first suite of zero-permission utility tools.
- **Tools Included**:
  - `math_eval`: High-precision math expression evaluator (arithmetic, trigonometry, algebra, statistics).
  - `time_calculator`: Timezone conversions, timestamp calculations, and relative offsets.
  - `weather_query`: Live weather and forecast query via Open-Meteo API.
  - `wiki_lookup`: Wikipedia / encyclopedic knowledge article fetch and summary.
- **Database Schema**: Upgrade to `version: 4` (create `tool_configs` table for user enable/disable toggles).
- **Quality Gates**: `flutter analyze` 0 issues, 100% unit tests passing.

---

### 5.2 Milestone 24: Local File System & Sandboxed Code Execution

- **Objective**: Provide secure local file operations and isolated script execution within application sandbox directories.
- **Tools Included**:
  - `file_read`: Read text/markdown/code files within `$APP_DIR/documents/agent_sandbox/`.
  - `file_write`: Write generated summaries/reports (Tier 2 confirmation barrier).
  - `file_list`: List directory entries with size, modification dates, and file types.
  - `code_eval`: Sandboxed expression / Dart AST interpreter (5s execution timeout).
  - `clipboard_get` & `clipboard_set`: System clipboard inspection and copy operations.
- **Quality Gates**: Directory path traversal attack prevention (`../` sanitization), file size quota limits (max 10MB).

---

### 5.3 Milestone 25: Mobile Native Device Capabilities & Permission Layer

- **Objective**: Integrate Android device features (Calendar, Notifications, Contacts, Geolocation) with declarative permission flows and PII sanitization.
- **Tools Included**:
  - `calendar_get_events` & `calendar_create_event` (via `device_calendar`).
  - `notification_schedule` & `alarm_set` (via `flutter_local_notifications`).
  - `contacts_search` (via `flutter_contacts` with privacy filtering).
  - `location_get` & `address_lookup` (via `geolocator` and `geocoding`).
- **Android Manifest & Permissions**: Add runtime declarations for API 31+ and API 33+.
- **Testing**: Complete platform channel mock suite (`MockNativeChannelHelper`).

---

### 5.4 Milestone 26: Client-Side MCP Protocol Integration & Management UI

- **Objective**: Implement the full Model Context Protocol (MCP) JSON-RPC 2.0 client supporting SSE, WebSocket, and Stdio transports with dynamic tool discovery and management screens.
- **Components Included**:
  - `McpClient`, `SseMcpTransport`, `WebSocketMcpTransport`, `StdioMcpTransport`.
  - `McpServerDao` and SQLite persistence for configured servers.
  - Dynamic `tools/list` introspector, namespace routing (`mcp__<serverId>__<toolName>`), and OpenAI schema projector.
  - `McpServersScreen`: Add/edit server dialog, connection test button, live latency ping chip, tool inspector drawer.
- **Testing**: Mock SSE streaming server, mock WebSocket server, JSON-RPC 2.0 error handling tests.

---

### 5.5 Milestone 27: Ecosystem Hardening, Adversarial Testing, Token Optimization & Release Packaging

- **Objective**: System-wide hardening, multi-turn loop optimization, adversarial prompt injection defense, token usage minimization, and production Release APK signing.
- **Features Included**:
  - **Tool Loop Cycle Detection**: Detect repetitive identical tool calls and break out with summary synthesis.
  - **Token Optimization**: Dynamic truncation and AST compression of tool results to preserve context window.
  - **Adversarial Hardening**: Defend against malicious tool outputs attempting system prompt overrides.
  - **Release APK**: Production signing keystore setup and release build verification (`flutter build apk --release`).
- **Quality Gates**: 220+ automated tests passing with 100% rate, 0 analyzer issues, Release APK generated under 35MB.

---

## 6. Verification & Quality Gates

To verify that all architecture, schemas, and specifications meet benchmark standards:

```bash
# 1. Static Analysis Verification
D:\work\flutter-sdk\flutter\bin\flutter.bat analyze

# 2. Complete Automated Test Suite (100% Pass Rate)
D:\work\flutter-sdk\flutter\bin\flutter.bat test

# 3. Release / Debug Build Check
D:\work\flutter-sdk\flutter\bin\flutter.bat build apk --debug
```
