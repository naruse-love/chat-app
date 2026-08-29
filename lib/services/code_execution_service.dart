import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

/// Execution result returned by [CodeExecutionService].
class CodeExecutionResult {
  /// Whether the code finished successfully without unhandled exceptions or timeout.
  final bool success;

  /// Combined output text formatted for user/LLM display.
  final String output;

  /// Standard output text captured from `print()` statements.
  final String stdout;

  /// Standard error or exception stack text if failed.
  final String? stderr;

  /// The returned evaluation value or expression result.
  final dynamic result;

  /// Total execution duration.
  final Duration executionDuration;

  /// Whether execution was forcibly killed due to timeout (e.g. 3000ms limit).
  final bool isTimedOut;

  /// User-friendly error message in Chinese if execution failed.
  final String? errorMessage;

  const CodeExecutionResult({
    required this.success,
    required this.output,
    required this.stdout,
    this.stderr,
    this.result,
    required this.executionDuration,
    this.isTimedOut = false,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'output': output,
      'stdout': stdout,
      if (stderr != null) 'stderr': stderr,
      if (result != null) 'result': result.toString(),
      'executionDurationMs': executionDuration.inMilliseconds,
      'isTimedOut': isTimedOut,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  @override
  String toString() =>
      'CodeExecutionResult(success: $success, timedOut: $isTimedOut, duration: ${executionDuration.inMilliseconds}ms)';
}

/// Message payload passed to Worker Isolate.
class _WorkerRequest {
  final String code;
  final SendPort sendPort;

  const _WorkerRequest({required this.code, required this.sendPort});
}

/// Message payload returned by Worker Isolate.
class _WorkerResponse {
  final bool success;
  final String stdout;
  final String? stderr;
  final dynamic result;
  final String? errorMessage;

  const _WorkerResponse({
    required this.success,
    required this.stdout,
    this.stderr,
    this.result,
    this.errorMessage,
  });
}

/// Service providing isolated code execution sandbox via Worker [Isolate.spawn].
///
/// Features:
/// 1. Runs pure Dart scripts/expressions in an independent OS thread/heap.
/// 2. Hard 3000ms timeout with `isolate.kill(priority: Isolate.immediate)` for deadlock prevention.
/// 3. Captures `print()` stdout logs and return values.
/// 4. Safe evaluation of math, strings, lists, maps, loops, and control flow.
class CodeExecutionService {
  static const Duration defaultTimeout = Duration(milliseconds: 3000);
  static const Duration maxTimeout = Duration(milliseconds: 5000);

  /// Executes [code] in a separate Worker Isolate with hard [timeout].
  Future<CodeExecutionResult> execute({
    required String code,
    Duration timeout = defaultTimeout,
  }) async {
    final effectiveTimeout = timeout > maxTimeout ? maxTimeout : timeout;
    final stopwatch = Stopwatch()..start();

    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    Isolate? workerIsolate;
    Timer? timeoutTimer;
    bool isCompleted = false;

    final completer = Completer<CodeExecutionResult>();

    // Hard timeout callback
    timeoutTimer = Timer(effectiveTimeout, () {
      if (!isCompleted) {
        isCompleted = true;
        stopwatch.stop();
        try {
          workerIsolate?.kill(priority: Isolate.immediate);
        } catch (_) {}
        receivePort.close();
        errorPort.close();

        final timeoutResult = CodeExecutionResult(
          success: false,
          output: '执行超时: 代码运行超过 ${effectiveTimeout.inMilliseconds}ms 硬限制，已强制终止 Worker Isolate 进程。',
          stdout: '',
          stderr: 'TimeoutException: Execution exceeded ${effectiveTimeout.inMilliseconds}ms',
          isTimedOut: true,
          errorMessage: '代码执行超时 (${effectiveTimeout.inMilliseconds}ms 硬限制)',
          executionDuration: stopwatch.elapsed,
        );
        completer.complete(timeoutResult);
      }
    });

    // Error port listener
    errorPort.listen((errorData) {
      if (!isCompleted) {
        isCompleted = true;
        timeoutTimer?.cancel();
        stopwatch.stop();
        try {
          workerIsolate?.kill(priority: Isolate.immediate);
        } catch (_) {}
        receivePort.close();
        errorPort.close();

        final errorStr = errorData is List ? errorData.join('\n') : errorData.toString();
        final failureResult = CodeExecutionResult(
          success: false,
          output: 'Isolate 运行时未捕获异常: $errorStr',
          stdout: '',
          stderr: errorStr,
          isTimedOut: false,
          errorMessage: '运行时异常: $errorStr',
          executionDuration: stopwatch.elapsed,
        );
        completer.complete(failureResult);
      }
    });

    // Receive port listener
    receivePort.listen((message) {
      if (!isCompleted) {
        isCompleted = true;
        timeoutTimer?.cancel();
        stopwatch.stop();
        try {
          workerIsolate?.kill(priority: Isolate.immediate);
        } catch (_) {}
        receivePort.close();
        errorPort.close();

        if (message is _WorkerResponse) {
          final buffer = StringBuffer();
          if (message.stdout.isNotEmpty) {
            buffer.writeln('【标准输出 stdout】');
            buffer.writeln(message.stdout);
          }
          if (message.success) {
            if (message.result != null) {
              if (buffer.isNotEmpty) buffer.writeln();
              buffer.writeln('【返回值 result】');
              buffer.writeln(formatResult(message.result));
            } else if (message.stdout.isEmpty) {
              buffer.writeln('代码执行成功（无输出与返回值）。');
            }
          } else {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln('【执行错误 error】');
            buffer.writeln(message.errorMessage ?? message.stderr ?? '未知错误');
          }

          final execResult = CodeExecutionResult(
            success: message.success,
            output: buffer.toString().trim(),
            stdout: message.stdout,
            stderr: message.stderr,
            result: message.result,
            isTimedOut: false,
            errorMessage: message.errorMessage,
            executionDuration: stopwatch.elapsed,
          );
          completer.complete(execResult);
        } else {
          completer.complete(CodeExecutionResult(
            success: false,
            output: '通信协议异常: 未知响应 $message',
            stdout: '',
            stderr: 'Unknown response type: ${message.runtimeType}',
            executionDuration: stopwatch.elapsed,
          ));
        }
      }
    });

    try {
      workerIsolate = await Isolate.spawn<_WorkerRequest>(
        _isolateEntryPoint,
        _WorkerRequest(code: code, sendPort: receivePort.sendPort),
        onError: errorPort.sendPort,
      );
    } catch (e) {
      if (!isCompleted) {
        isCompleted = true;
        timeoutTimer.cancel();
        stopwatch.stop();
        receivePort.close();
        errorPort.close();
        completer.complete(CodeExecutionResult(
          success: false,
          output: '无法启动 Worker Isolate: $e',
          stdout: '',
          stderr: e.toString(),
          errorMessage: 'Isolate 启动失败: $e',
          executionDuration: stopwatch.elapsed,
        ));
      }
    }

    return completer.future;
  }

  static String formatResult(dynamic val) {
    if (val is String) return val;
    if (val is Map || val is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(val);
      } catch (_) {
        return val.toString();
      }
    }
    return val.toString();
  }

  /// Entry point executed inside the spawned Worker Isolate.
  static void _isolateEntryPoint(_WorkerRequest request) {
    final stdoutBuffer = StringBuffer();

    // Custom print zone
    runZoned(
      () {
        try {
          final interpreter = _ScriptInterpreter(
            code: request.code,
            onPrint: (msg) {
              if (stdoutBuffer.length < 50000) {
                stdoutBuffer.writeln(msg);
              }
            },
          );
          final result = interpreter.run();
          request.sendPort.send(_WorkerResponse(
            success: true,
            stdout: stdoutBuffer.toString().trimRight(),
            result: result,
          ));
        } on _InterpreterException catch (e) {
          request.sendPort.send(_WorkerResponse(
            success: false,
            stdout: stdoutBuffer.toString().trimRight(),
            stderr: e.toString(),
            errorMessage: e.message,
          ));
        } catch (e, st) {
          request.sendPort.send(_WorkerResponse(
            success: false,
            stdout: stdoutBuffer.toString().trimRight(),
            stderr: '$e\n$st',
            errorMessage: '运行时异常: $e',
          ));
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (stdoutBuffer.length < 50000) {
            stdoutBuffer.writeln(line);
          }
        },
      ),
    );
  }
}

class _InterpreterException implements Exception {
  final String message;
  const _InterpreterException(this.message);

  @override
  String toString() => message;
}

/// Pure Dart AST & statement script interpreter for sandboxed execution.
class _ScriptInterpreter {
  final String code;
  final void Function(String) onPrint;
  final Map<String, dynamic> _globals = {};

  _ScriptInterpreter({required this.code, required this.onPrint}) {
    _initStandardLibrary();
  }

  void _initStandardLibrary() {
    _globals['pi'] = math.pi;
    _globals['e'] = math.e;
    _globals['print'] = (List<dynamic> args) {
      final msg = args.map((e) => e?.toString() ?? 'null').join(' ');
      onPrint(msg);
      return null;
    };
    _globals['sqrt'] = (List<dynamic> args) => math.sqrt(_asNum(args[0]));
    _globals['pow'] = (List<dynamic> args) => math.pow(_asNum(args[0]), _asNum(args[1]));
    _globals['abs'] = (List<dynamic> args) => (_asNum(args[0])).abs();
    _globals['min'] = (List<dynamic> args) => math.min(_asNum(args[0]), _asNum(args[1]));
    _globals['max'] = (List<dynamic> args) => math.max(_asNum(args[0]), _asNum(args[1]));
    _globals['round'] = (List<dynamic> args) => (_asNum(args[0])).round();
    _globals['floor'] = (List<dynamic> args) => (_asNum(args[0])).floor();
    _globals['ceil'] = (List<dynamic> args) => (_asNum(args[0])).ceil();
    _globals['sin'] = (List<dynamic> args) => math.sin(_asNum(args[0]));
    _globals['cos'] = (List<dynamic> args) => math.cos(_asNum(args[0]));
    _globals['tan'] = (List<dynamic> args) => math.tan(_asNum(args[0]));
    _globals['log'] = (List<dynamic> args) => math.log(_asNum(args[0]));
    _globals['exp'] = (List<dynamic> args) => math.exp(_asNum(args[0]));
    _globals['jsonEncode'] = (List<dynamic> args) => json.encode(args[0]);
    _globals['jsonDecode'] = (List<dynamic> args) => json.decode(args[0].toString());
    _globals['now'] = (List<dynamic> args) => DateTime.now().toIso8601String();
  }

  num _asNum(dynamic val) {
    if (val is num) return val;
    final parsed = num.tryParse(val?.toString() ?? '');
    if (parsed != null) return parsed;
    throw _InterpreterException('参数必须为数值类型，实际为: $val');
  }

  dynamic run() {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;

    final tokens = _tokenize(trimmed);
    final parser = _Parser(tokens, this);
    return parser.parseAndExecute();
  }

  List<_ScriptToken> _tokenize(String src) {
    final tokens = <_ScriptToken>[];
    int pos = 0;

    while (pos < src.length) {
      final ch = src[pos];

      // Skip whitespace
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        pos++;
        continue;
      }

      // Comments // ... or /* ... */
      if (ch == '/' && pos + 1 < src.length) {
        if (src[pos + 1] == '/') {
          pos += 2;
          while (pos < src.length && src[pos] != '\n') {
            pos++;
          }
          continue;
        } else if (src[pos + 1] == '*') {
          pos += 2;
          while (pos + 1 < src.length && !(src[pos] == '*' && src[pos + 1] == '/')) {
            pos++;
          }
          pos += 2;
          continue;
        }
      }

      // Numbers
      if (_isDigit(ch) || (ch == '.' && pos + 1 < src.length && _isDigit(src[pos + 1]))) {
        final start = pos;
        while (pos < src.length && (_isDigit(src[pos]) || src[pos] == '.')) {
          pos++;
        }
        final numStr = src.substring(start, pos);
        tokens.add(_ScriptToken(_TokenType.number, numStr, num.tryParse(numStr) ?? 0));
        continue;
      }

      // Strings ('...' or "...")
      if (ch == '\'' || ch == '"') {
        final quote = ch;
        pos++;
        final buf = StringBuffer();
        while (pos < src.length && src[pos] != quote) {
          if (src[pos] == '\\' && pos + 1 < src.length) {
            pos++;
            final next = src[pos];
            if (next == 'n') {
              buf.write('\n');
            } else if (next == 't') {
              buf.write('\t');
            } else if (next == '\\') {
              buf.write('\\');
            } else if (next == quote) {
              buf.write(quote);
            } else {
              buf.write(next);
            }
          } else {
            buf.write(src[pos]);
          }
          pos++;
        }
        if (pos < src.length && src[pos] == quote) {
          pos++;
        }
        tokens.add(_ScriptToken(_TokenType.string, buf.toString(), buf.toString()));
        continue;
      }

      // Identifiers / Keywords
      if (_isLetter(ch) || ch == '_') {
        final start = pos;
        while (pos < src.length && (_isLetter(src[pos]) || _isDigit(src[pos]) || src[pos] == '_')) {
          pos++;
        }
        final word = src.substring(start, pos);
        tokens.add(_ScriptToken(_TokenType.identifier, word, word));
        continue;
      }

      // Multi-char operators
      if (pos + 1 < src.length) {
        final two = src.substring(pos, pos + 2);
        if (two == '==' ||
            two == '!=' ||
            two == '<=' ||
            two == '>=' ||
            two == '&&' ||
            two == '||' ||
            two == '+=' ||
            two == '-=' ||
            two == '*=' ||
            two == '/=' ||
            two == '++' ||
            two == '--') {
          tokens.add(_ScriptToken(_TokenType.operator, two, two));
          pos += 2;
          continue;
        }
      }

      // Single-char operators and punctuation
      tokens.add(_ScriptToken(_TokenType.symbol, ch, ch));
      pos++;
    }

    tokens.add(const _ScriptToken(_TokenType.eof, '', ''));
    return tokens;
  }

  bool _isDigit(String s) => s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
  bool _isLetter(String s) {
    final c = s.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c > 127;
  }
}

enum _TokenType { number, string, identifier, operator, symbol, eof }

class _ScriptToken {
  final _TokenType type;
  final String text;
  final dynamic value;
  const _ScriptToken(this.type, this.text, this.value);

  @override
  String toString() => '_ScriptToken($type, "$text")';
}

class _ReturnException {
  final dynamic value;
  const _ReturnException(this.value);
}

class _BreakException {
  const _BreakException();
}

class _ContinueException {
  const _ContinueException();
}

class _Parser {
  final List<_ScriptToken> tokens;
  final _ScriptInterpreter interpreter;
  int _idx = 0;
  final Map<String, dynamic> _env = {};

  _Parser(this.tokens, this.interpreter);

  _ScriptToken get _cur => _idx < tokens.length ? tokens[_idx] : tokens.last;
  _ScriptToken get _prev => _idx > 0 ? tokens[_idx - 1] : tokens.first;

  bool _check(String text) =>
      _cur.text == text &&
      _cur.type != _TokenType.string &&
      _cur.type != _TokenType.number &&
      _cur.type != _TokenType.eof;
  bool get _isAtEnd => _cur.type == _TokenType.eof;

  _ScriptToken _advance() {
    if (!_isAtEnd) _idx++;
    return _prev;
  }

  bool _match(List<String> list) {
    for (final s in list) {
      if (_check(s)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  _ScriptToken _consume(String text, String errorMsg) {
    if (_check(text)) return _advance();
    throw _InterpreterException(errorMsg);
  }

  dynamic parseAndExecute() {
    dynamic lastVal;
    try {
      while (!_isAtEnd) {
        lastVal = _statement();
      }
    } on _ReturnException catch (e) {
      return e.value;
    }
    return lastVal;
  }

  dynamic _statement() {
    // Semicolons
    if (_match([';'])) return null;

    // return statement
    if (_match(['return'])) {
      dynamic retVal;
      if (!_check(';') && !_isAtEnd) {
        retVal = _expression();
      }
      _match([';']);
      throw _ReturnException(retVal);
    }

    // break statement
    if (_match(['break'])) {
      _match([';']);
      throw const _BreakException();
    }

    // continue statement
    if (_match(['continue'])) {
      _match([';']);
      throw const _ContinueException();
    }

    // var / final / let / const declarations
    if (_match(['var', 'final', 'let', 'const', 'int', 'double', 'String', 'bool', 'List', 'Map', 'dynamic'])) {
      final name = _advance().text;
      dynamic val;
      if (_match(['='])) {
        val = _expression();
      }
      _setVar(name, val);
      _match([';']);
      return val;
    }

    // if statement
    if (_match(['if'])) {
      _consume('(', 'if 条件缺少左括号 "("');
      final cond = _expression();
      _consume(')', 'if 条件缺少右括号 ")"');

      dynamic branchRes;
      if (_isTruthy(cond)) {
        branchRes = _blockOrStatement();
        if (_match(['else'])) {
          _skipBlockOrStatement();
        }
      } else {
        _skipBlockOrStatement();
        if (_match(['else'])) {
          branchRes = _blockOrStatement();
        }
      }
      return branchRes;
    }

    // while statement
    if (_match(['while'])) {
      _consume('(', 'while 条件缺少左括号 "("');
      final condIndex = _idx;
      _skipExpression();
      _consume(')', 'while 条件缺少右括号 ")"');

      final bodyStart = _idx;
      _skipBlockOrStatement();
      final bodyEnd = _idx;

      dynamic lastLoopRes;
      while (true) {
        _idx = condIndex;
        final cond = _expression();
        if (!_isTruthy(cond)) break;

        _idx = bodyStart;
        try {
          lastLoopRes = _blockOrStatement();
        } on _BreakException {
          break;
        } on _ContinueException {
          continue;
        }
      }
      _idx = bodyEnd;
      return lastLoopRes;
    }

    // for statement: for (var i = 0; i < N; i++) { ... } or for (var x in list)
    if (_match(['for'])) {
      _consume('(', 'for 循环缺少左括号 "("');
      if (_match(['var', 'final', 'let', 'int'])) {
        final varName = _advance().text;
        if (_match(['in'])) {
          // for (var item in list)
          final iterableVal = _expression();
          _consume(')', 'for-in 循环缺少右括号 ")"');
          final bodyStart = _idx;
          _skipBlockOrStatement();
          final bodyEnd = _idx;

          dynamic loopRes;
          if (iterableVal is Iterable) {
            for (final item in iterableVal) {
              _setVar(varName, item);
              _idx = bodyStart;
              try {
                loopRes = _blockOrStatement();
              } on _BreakException {
                break;
              } on _ContinueException {
                continue;
              }
            }
          }
          _idx = bodyEnd;
          return loopRes;
        } else {
          // Standard for loop
          _consume('=', 'for 循环初始赋值缺少 "="');
          final initVal = _expression();
          _setVar(varName, initVal);
          _consume(';', 'for 循环缺少第一分号 ";"');

          final condIdx = _idx;
          _skipExpression();
          _consume(';', 'for 循环缺少第二分号 ";"');

          final stepIdx = _idx;
          _skipExpression();
          _consume(')', 'for 循环缺少右括号 ")"');

          final bodyStart = _idx;
          _skipBlockOrStatement();
          final bodyEnd = _idx;

          dynamic loopRes;
          while (true) {
            _idx = condIdx;
            final condVal = _expression();
            if (!_isTruthy(condVal)) break;

            _idx = bodyStart;
            try {
              loopRes = _blockOrStatement();
            } on _BreakException {
              break;
            } on _ContinueException {
              // proceed to step
            }

            // Step
            _idx = stepIdx;
            _expression();
          }

          _idx = bodyEnd;
          return loopRes;
        }
      }
    }

    // Block { ... }
    if (_check('{')) {
      return _block();
    }

    // General expression statement
    final val = _expression();
    _match([';']);
    return val;
  }

  dynamic _blockOrStatement() {
    if (_check('{')) return _block();
    return _statement();
  }

  dynamic _block() {
    _consume('{', '缺少左花括号 "{"');
    dynamic lastVal;
    while (!_check('}') && !_isAtEnd) {
      lastVal = _statement();
    }
    _consume('}', '缺少闭合花括号 "}"');
    return lastVal;
  }

  void _skipBlockOrStatement() {
    if (_check('{')) {
      int depth = 1;
      _advance();
      while (!_isAtEnd && depth > 0) {
        if (_check('{')) depth++;
        if (_check('}')) depth--;
        _advance();
      }
    } else {
      while (!_check(';') && !_check('}') && !_isAtEnd) {
        _advance();
      }
      _match([';']);
    }
  }

  void _skipExpression() {
    int depth = 0;
    while (!_isAtEnd) {
      if (_check('(') || _check('[') || _check('{')) depth++;
      if (_check(')') || _check(']') || _check('}')) {
        if (depth == 0) break;
        depth--;
      }
      if (_check(';') && depth == 0) break;
      _advance();
    }
  }

  dynamic _expression() => _assignment();

  dynamic _assignment() {
    final expr = _logicalOr();
    final targetVar = _prevAssignVar;

    if (_match(['=', '+=', '-=', '*=', '/='])) {
      final op = _prev.text;
      final right = _assignment();

      if (targetVar != null) {
        final current = _getVar(targetVar);
        dynamic newVal;
        if (op == '=') {
          newVal = right;
        } else if (op == '+=') {
          newVal = (current is String || right is String) ? '$current$right' : (current as num) + (right as num);
        } else if (op == '-=') {
          newVal = (current as num) - (right as num);
        } else if (op == '*=') {
          newVal = (current as num) * (right as num);
        } else if (op == '/=') {
          newVal = (current as num) / (right as num);
        }
        _setVar(targetVar, newVal);
        return newVal;
      }
    }

    return expr;
  }

  String? _prevAssignVar;

  dynamic _logicalOr() {
    dynamic expr = _logicalAnd();
    while (_match(['||'])) {
      final right = _logicalAnd();
      expr = _isTruthy(expr) || _isTruthy(right);
    }
    return expr;
  }

  dynamic _logicalAnd() {
    dynamic expr = _equality();
    while (_match(['&&'])) {
      final right = _equality();
      expr = _isTruthy(expr) && _isTruthy(right);
    }
    return expr;
  }

  dynamic _equality() {
    dynamic expr = _relational();
    while (_match(['==', '!='])) {
      final op = _prev.text;
      final right = _relational();
      if (op == '==') {
        expr = (expr == right);
      } else {
        expr = (expr != right);
      }
    }
    return expr;
  }

  dynamic _relational() {
    dynamic expr = _additive();
    while (_match(['<', '<=', '>', '>='])) {
      final op = _prev.text;
      final right = _additive();
      if (expr is num && right is num) {
        if (op == '<') expr = expr < right;
        if (op == '<=') expr = expr <= right;
        if (op == '>') expr = expr > right;
        if (op == '>=') expr = expr >= right;
      } else if (expr is String && right is String) {
        if (op == '<') expr = expr.compareTo(right) < 0;
        if (op == '<=') expr = expr.compareTo(right) <= 0;
        if (op == '>') expr = expr.compareTo(right) > 0;
        if (op == '>=') expr = expr.compareTo(right) >= 0;
      } else {
        expr = false;
      }
    }
    return expr;
  }

  dynamic _additive() {
    dynamic expr = _multiplicative();
    while (_match(['+', '-'])) {
      final op = _prev.text;
      final right = _multiplicative();
      if (expr is String || right is String) {
        if (op == '+') {
          expr = '$expr$right';
        } else {
          throw const _InterpreterException('字符串不支持减法操作');
        }
      } else if (expr is num && right is num) {
        expr = op == '+' ? expr + right : expr - right;
      } else {
        throw _InterpreterException('无法对 ${expr.runtimeType} 和 ${right.runtimeType} 进行 $op');
      }
    }
    return expr;
  }

  dynamic _multiplicative() {
    dynamic expr = _unary();
    while (_match(['*', '/', '%', '^'])) {
      final op = _prev.text;
      final right = _unary();
      if (expr is! num || right is! num) {
        throw const _InterpreterException('算术乘除运算操作数必须为数值');
      }
      if (op == '*') expr = expr * right;
      if (op == '/') {
        if (right == 0) throw const _InterpreterException('除数不能为零');
        expr = expr / right;
      }
      if (op == '%') {
        if (right == 0) throw const _InterpreterException('模数不能为零');
        expr = expr % right;
      }
      if (op == '^') expr = math.pow(expr, right);
    }
    return expr;
  }

  dynamic _unary() {
    if (_match(['!', '-'])) {
      final op = _prev.text;
      final right = _unary();
      if (op == '!') return !_isTruthy(right);
      if (op == '-') {
        if (right is num) return -right;
        throw const _InterpreterException('负号操作数必须为数值');
      }
    }
    if (_match(['++'])) {
      final vName = _advance().text;
      final old = (_getVar(vName) as num? ?? 0) + 1;
      _setVar(vName, old);
      return old;
    }
    return _callAndAccess();
  }

  dynamic _callAndAccess() {
    dynamic expr = _primary();

    while (true) {
      if (_match(['('])) {
        final args = <dynamic>[];
        if (!_check(')')) {
          do {
            args.add(_expression());
          } while (_match([',']));
        }
        _consume(')', '函数调用缺少闭合括号 ")"');

        if (expr is Function) {
          try {
            expr = Function.apply(expr, [args]);
          } catch (_) {
            expr = Function.apply(expr, args);
          }
        } else {
          throw _InterpreterException('目标对象不可作为函数调用: $expr');
        }
      } else if (_match(['['])) {
        final indexVal = _expression();
        _consume(']', '索引访问缺少闭合方括号 "]"');

        if (expr is List) {
          final idx = (indexVal as num).toInt();
          expr = expr[idx];
        } else if (expr is Map) {
          expr = expr[indexVal];
        } else if (expr is String) {
          final idx = (indexVal as num).toInt();
          expr = expr[idx];
        } else {
          throw _InterpreterException('不支持索引访问的对象类型: ${expr.runtimeType}');
        }
      } else if (_match(['.'])) {
        final memberName = _advance().text;
        if (_match(['('])) {
          final args = <dynamic>[];
          if (!_check(')')) {
            do {
              args.add(_expression());
            } while (_match([',']));
          }
          _consume(')', '方法调用缺少闭合括号 ")"');
          expr = _invokeMember(expr, memberName, args);
        } else {
          expr = _getMember(expr, memberName);
        }
      } else if (_match(['++'])) {
        if (_prevAssignVar != null) {
          final vName = _prevAssignVar!;
          final old = _getVar(vName) as num? ?? 0;
          _setVar(vName, old + 1);
          return old;
        }
      } else {
        break;
      }
    }

    return expr;
  }

  dynamic _getMember(dynamic target, String name) {
    if (target is List) {
      if (name == 'length') return target.length;
      if (name == 'first') return target.first;
      if (name == 'last') return target.last;
      if (name == 'isEmpty') return target.isEmpty;
      if (name == 'isNotEmpty') return target.isNotEmpty;
    }
    if (target is Map) {
      if (name == 'length') return target.length;
      if (name == 'keys') return target.keys.toList();
      if (name == 'values') return target.values.toList();
      if (name == 'isEmpty') return target.isEmpty;
      if (name == 'isNotEmpty') return target.isNotEmpty;
      if (target.containsKey(name)) return target[name];
    }
    if (target is String) {
      if (name == 'length') return target.length;
      if (name == 'isEmpty') return target.isEmpty;
      if (name == 'isNotEmpty') return target.isNotEmpty;
    }
    throw _InterpreterException('对象不存在属性: .$name');
  }

  dynamic _invokeMember(dynamic target, String name, List<dynamic> args) {
    if (target is List) {
      if (name == 'add' || name == 'push') {
        target.add(args[0]);
        return target;
      }
      if (name == 'contains') return target.contains(args[0]);
      if (name == 'join') return target.join(args.isNotEmpty ? args[0]?.toString() ?? '' : '');
      if (name == 'indexOf') return target.indexOf(args[0]);
      if (name == 'remove') return target.remove(args[0]);
      if (name == 'clear') {
        target.clear();
        return null;
      }
    }
    if (target is String) {
      if (name == 'toLowerCase') return target.toLowerCase();
      if (name == 'toUpperCase') return target.toUpperCase();
      if (name == 'trim') return target.trim();
      if (name == 'contains') return target.contains(args[0]?.toString() ?? '');
      if (name == 'split') return target.split(args.isNotEmpty ? args[0]?.toString() ?? '' : '');
      if (name == 'substring') {
        final start = (args[0] as num).toInt();
        final end = args.length > 1 ? (args[1] as num).toInt() : target.length;
        return target.substring(start, end);
      }
      if (name == 'replaceAll') {
        return target.replaceAll(args[0].toString(), args[1].toString());
      }
    }
    if (target is Map) {
      if (name == 'containsKey') return target.containsKey(args[0]);
      if (name == 'containsValue') return target.containsValue(args[0]);
      if (name == 'remove') return target.remove(args[0]);
    }
    throw _InterpreterException('对象不支持方法: .$name(${args.join(', ')})');
  }

  dynamic _primary() {
    _prevAssignVar = null;

    if (_cur.type == _TokenType.number || _cur.type == _TokenType.string) {
      return _advance().value;
    }

    if (_match(['true'])) return true;
    if (_match(['false'])) return false;
    if (_match(['null'])) return null;

    if (_cur.type == _TokenType.identifier) {
      final name = _advance().text;
      _prevAssignVar = name;
      return _getVar(name);
    }

    if (_match(['('])) {
      final expr = _expression();
      _consume(')', '缺少闭合括号 ")"');
      return expr;
    }

    // List literal [1, 2, 3]
    if (_match(['['])) {
      final list = <dynamic>[];
      if (!_check(']')) {
        do {
          list.add(_expression());
        } while (_match([',']));
      }
      _consume(']', '缺少闭合方括号 "]"');
      return list;
    }

    // Map literal {'key': value}
    if (_match(['{'])) {
      final map = <String, dynamic>{};
      if (!_check('}')) {
        do {
          final key = _expression()?.toString() ?? '';
          _consume(':', 'Map 键值缺少冒号 ":"');
          final val = _expression();
          map[key] = val;
        } while (_match([',']));
      }
      _consume('}', '缺少闭合花括号 "}"');
      return map;
    }

    throw _InterpreterException('无法解析的标记: "${_cur.text}"');
  }

  bool _isTruthy(dynamic v) {
    if (v == null || v == false) return false;
    if (v == 0 || v == '') return false;
    return true;
  }

  dynamic _getVar(String name) {
    if (_env.containsKey(name)) return _env[name];
    if (interpreter._globals.containsKey(name)) return interpreter._globals[name];
    return null;
  }

  void _setVar(String name, dynamic value) {
    _env[name] = value;
  }
}
