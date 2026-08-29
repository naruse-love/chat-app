import 'dart:math' as math;
import '../../models/tool/tool.dart';

/// Exception thrown when mathematical evaluation fails.
class MathEvalException implements Exception {
  final String message;
  const MathEvalException(this.message);

  @override
  String toString() => message;
}

/// Token types recognized by the math expression lexer.
enum _TokenType {
  number,
  string,
  identifier,
  plus,
  minus,
  multiply,
  divide,
  modulo,
  power,
  factorial,
  lparen,
  rparen,
  lbracket,
  rbracket,
  comma,
  eof,
}

/// A lexical token in a mathematical expression.
class _Token {
  final _TokenType type;
  final String text;
  final dynamic value;
  final int position;

  const _Token(this.type, this.text, this.position, [this.value]);

  @override
  String toString() => '_Token($type, "$text", pos: $position)';
}

/// Lexer for mathematical and statistical expressions.
class _MathLexer {
  final String input;
  int _pos = 0;

  _MathLexer(this.input);

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (_pos < input.length) {
      final ch = input[_pos];

      // Skip whitespace
      if (_isWhitespace(ch)) {
        _pos++;
        continue;
      }

      // Numbers: integer, float, scientific notation (e.g. 1e-3, 2.5E4)
      if (_isDigit(ch) || (ch == '.' && _pos + 1 < input.length && _isDigit(input[_pos + 1]))) {
        tokens.add(_readNumber());
        continue;
      }

      // Strings: single or double quoted
      if (ch == '\'' || ch == '"') {
        tokens.add(_readString());
        continue;
      }

      // Identifiers: function names, constants, units (letters, underscore, Chinese characters)
      if (_isIdentifierStart(ch)) {
        tokens.add(_readIdentifier());
        continue;
      }

      // Operators and punctuation
      final startPos = _pos;
      if (ch == '+') {
        tokens.add(_Token(_TokenType.plus, '+', startPos));
        _pos++;
      } else if (ch == '-') {
        tokens.add(_Token(_TokenType.minus, '-', startPos));
        _pos++;
      } else if (ch == '*') {
        if (_pos + 1 < input.length && input[_pos + 1] == '*') {
          tokens.add(_Token(_TokenType.power, '**', startPos));
          _pos += 2;
        } else {
          tokens.add(_Token(_TokenType.multiply, '*', startPos));
          _pos++;
        }
      } else if (ch == '/') {
        tokens.add(_Token(_TokenType.divide, '/', startPos));
        _pos++;
      } else if (ch == '%') {
        tokens.add(_Token(_TokenType.modulo, '%', startPos));
        _pos++;
      } else if (ch == '^') {
        tokens.add(_Token(_TokenType.power, '^', startPos));
        _pos++;
      } else if (ch == '!') {
        tokens.add(_Token(_TokenType.factorial, '!', startPos));
        _pos++;
      } else if (ch == '(') {
        tokens.add(_Token(_TokenType.lparen, '(', startPos));
        _pos++;
      } else if (ch == ')') {
        tokens.add(_Token(_TokenType.rparen, ')', startPos));
        _pos++;
      } else if (ch == '[') {
        tokens.add(_Token(_TokenType.lbracket, '[', startPos));
        _pos++;
      } else if (ch == ']') {
        tokens.add(_Token(_TokenType.rbracket, ']', startPos));
        _pos++;
      } else if (ch == ',') {
        tokens.add(_Token(_TokenType.comma, ',', startPos));
        _pos++;
      } else {
        throw MathEvalException('语法错误: 无法识别的字符 "$ch" (位置: $startPos)');
      }
    }

    tokens.add(_Token(_TokenType.eof, '', _pos));
    return tokens;
  }

  bool _isWhitespace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  bool _isIdentifierStart(String ch) {
    final code = ch.codeUnitAt(0);
    // a-z, A-Z, _, or non-ascii (Chinese characters, ℃, ℉, etc.)
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        ch == '_' ||
        code > 127;
  }

  bool _isIdentifierPart(String ch) {
    return _isIdentifierStart(ch) || _isDigit(ch);
  }

  _Token _readNumber() {
    final startPos = _pos;
    final buffer = StringBuffer();
    bool hasDot = false;
    bool hasExp = false;

    while (_pos < input.length) {
      final ch = input[_pos];
      if (_isDigit(ch)) {
        buffer.write(ch);
        _pos++;
      } else if (ch == '.' && !hasDot && !hasExp) {
        hasDot = true;
        buffer.write(ch);
        _pos++;
      } else if ((ch == 'e' || ch == 'E') && !hasExp) {
        hasExp = true;
        buffer.write(ch);
        _pos++;
        if (_pos < input.length && (input[_pos] == '+' || input[_pos] == '-')) {
          buffer.write(input[_pos]);
          _pos++;
        }
      } else {
        break;
      }
    }

    final numStr = buffer.toString();
    final numVal = num.tryParse(numStr);
    if (numVal == null) {
      throw MathEvalException('语法错误: 无效的数字格式 "$numStr" (位置: $startPos)');
    }
    return _Token(_TokenType.number, numStr, startPos, numVal);
  }

  _Token _readString() {
    final startPos = _pos;
    final quote = input[_pos];
    _pos++; // Skip opening quote
    final buffer = StringBuffer();

    while (_pos < input.length && input[_pos] != quote) {
      if (input[_pos] == '\\' && _pos + 1 < input.length) {
        _pos++;
        final next = input[_pos];
        if (next == 'n') {
          buffer.write('\n');
        } else if (next == 't') {
          buffer.write('\t');
        } else if (next == quote) {
          buffer.write(quote);
        } else if (next == '\\') {
          buffer.write('\\');
        } else {
          buffer.write(next);
        }
      } else {
        buffer.write(input[_pos]);
      }
      _pos++;
    }

    if (_pos >= input.length) {
      throw MathEvalException('语法错误: 字符串未闭合 (起始位置: $startPos)');
    }
    _pos++; // Skip closing quote
    return _Token(_TokenType.string, buffer.toString(), startPos, buffer.toString());
  }

  _Token _readIdentifier() {
    final startPos = _pos;
    final buffer = StringBuffer();
    while (_pos < input.length && _isIdentifierPart(input[_pos])) {
      buffer.write(input[_pos]);
      _pos++;
    }
    final text = buffer.toString();
    return _Token(_TokenType.identifier, text, startPos, text);
  }
}

/// Recursive descent parser and evaluator.
class _MathParser {
  final List<_Token> tokens;
  int _current = 0;

  _MathParser(this.tokens);

  _Token get _peek => tokens[_current];
  _Token get _previous => tokens[_current - 1];
  bool get _isAtEnd => _peek.type == _TokenType.eof;

  bool _check(_TokenType type) => !_isAtEnd && _peek.type == type;

  _Token _advance() {
    if (!_isAtEnd) _current++;
    return _previous;
  }

  bool _match(List<_TokenType> types) {
    for (final type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  _Token _consume(_TokenType type, String message) {
    if (_check(type)) return _advance();
    throw MathEvalException(message);
  }

  dynamic parse() {
    if (_check(_TokenType.eof)) {
      throw const MathEvalException('表达式不能为空');
    }
    final result = _expression();
    if (!_isAtEnd) {
      throw MathEvalException('语法错误: 多余的标记 "${_peek.text}" (位置: ${_peek.position})');
    }
    return result;
  }

  dynamic _expression() => _addition();

  dynamic _addition() {
    dynamic expr = _multiplication();

    while (_match([_TokenType.plus, _TokenType.minus])) {
      final operator = _previous;
      final right = _multiplication();

      if (expr is String || right is String) {
        if (operator.type == _TokenType.plus) {
          expr = '$expr$right';
        } else {
          throw const MathEvalException('语法错误: 字符串不支持减法操作');
        }
      } else if (expr is num && right is num) {
        if (operator.type == _TokenType.plus) {
          expr = expr + right;
        } else {
          expr = expr - right;
        }
      } else {
        throw MathEvalException('语法错误: 无法在 ${expr.runtimeType} 和 ${right.runtimeType} 之间执行 ${operator.text}');
      }
    }

    return expr;
  }

  dynamic _multiplication() {
    dynamic expr = _power();

    while (_match([_TokenType.multiply, _TokenType.divide, _TokenType.modulo])) {
      final operator = _previous;
      final right = _power();

      if (expr is! num || right is! num) {
        throw const MathEvalException('语法错误: 算术乘除运算操作数必须为数值类型');
      }

      if (operator.type == _TokenType.multiply) {
        expr = expr * right;
      } else if (operator.type == _TokenType.divide) {
        if (right == 0) {
          throw const MathEvalException('计算错误: 除数不能为零');
        }
        expr = expr / right;
      } else if (operator.type == _TokenType.modulo) {
        if (right == 0) {
          throw const MathEvalException('计算错误: 模运算除数不能为零');
        }
        expr = expr % right;
      }
    }

    return expr;
  }

  dynamic _power() {
    dynamic expr = _unary();

    if (_match([_TokenType.power])) {
      final right = _power(); // Right-associative
      if (expr is! num || right is! num) {
        throw const MathEvalException('语法错误: 幂运算操作数必须为数值类型');
      }
      final result = math.pow(expr, right);
      if (result.isNaN) {
        throw MathEvalException('计算错误: 无效的幂运算结果 ($expr ^ $right)');
      }
      return result;
    }

    return expr;
  }

  dynamic _unary() {
    if (_match([_TokenType.plus, _TokenType.minus])) {
      final operator = _previous;
      final right = _unary();
      if (right is! num) {
        throw const MathEvalException('语法错误: 一元正负号后必须为数值');
      }
      final val = operator.type == _TokenType.minus ? -right : right;
      return _checkFactorial(val);
    }

    final primaryVal = _primary();
    return _checkFactorial(primaryVal);
  }

  dynamic _checkFactorial(dynamic val) {
    while (_match([_TokenType.factorial])) {
      if (val is! num) {
        throw const MathEvalException('语法错误: 阶乘操作数必须为数值类型');
      }
      val = _MathFunctions.factorial(val);
    }
    return val;
  }

  dynamic _primary() {
    if (_match([_TokenType.number])) {
      return _previous.value;
    }

    if (_match([_TokenType.string])) {
      return _previous.value;
    }

    if (_match([_TokenType.lparen])) {
      final expr = _expression();
      _consume(_TokenType.rparen, '语法错误: 缺少闭合括号 ")"');
      return expr;
    }

    if (_match([_TokenType.lbracket])) {
      final elements = <dynamic>[];
      if (!_check(_TokenType.rbracket)) {
        do {
          elements.add(_expression());
        } while (_match([_TokenType.comma]));
      }
      _consume(_TokenType.rbracket, '语法错误: 缺少闭合方括号 "]"');
      return elements;
    }

    if (_match([_TokenType.identifier])) {
      final name = _previous.text;

      // Function call
      if (_match([_TokenType.lparen])) {
        final args = <dynamic>[];
        if (!_check(_TokenType.rparen)) {
          do {
            args.add(_expression());
          } while (_match([_TokenType.comma]));
        }
        _consume(_TokenType.rparen, '语法错误: 函数调用缺少闭合括号 ")"');
        return _MathFunctions.callFunction(name, args);
      }

      // Constant or standalone identifier
      return _MathFunctions.resolveConstantOrIdentifier(name);
    }

    if (_isAtEnd) {
      throw const MathEvalException('语法错误: 表达式不完整，缺少操作数');
    }

    throw MathEvalException('语法错误: 无法解析的标记 "${_peek.text}" (位置: ${_peek.position})');
  }
}

/// Evaluation functions, constants, statistics, and unit conversions.
class _MathFunctions {
  static const double pi = math.pi;
  static const double e = math.e;
  static const double tau = 6.28318530717958647692;
  static const double phi = 1.61803398874989484820;

  static dynamic resolveConstantOrIdentifier(String name) {
    final lower = name.toLowerCase();
    switch (lower) {
      case 'pi':
      case 'π':
        return pi;
      case 'e':
        return e;
      case 'tau':
      case 'τ':
        return tau;
      case 'phi':
      case 'φ':
        return phi;
      default:
        // Returns string itself as potential unit name or identifier
        return name;
    }
  }

  static dynamic callFunction(String name, List<dynamic> args) {
    final lower = name.toLowerCase();

    // 1. Unit conversion
    if (lower == 'convert') {
      if (args.length != 3) {
        throw const MathEvalException('convert 函数需要 3 个参数: convert(数值, 源单位, 目标单位)');
      }
      final val = args[0];
      final from = args[1]?.toString() ?? '';
      final to = args[2]?.toString() ?? '';
      if (val is! num) {
        throw MathEvalException('convert 转换数值必须为数字类型，实际为: $val');
      }
      return convertUnits(val.toDouble(), from, to);
    }

    // 2. Trigonometry & Advanced Math
    switch (lower) {
      case 'sqrt':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        if (x < 0) {
          throw MathEvalException('计算错误: 负数不能在实数范围内开平方根: $x');
        }
        return math.sqrt(x);

      case 'cbrt':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        return x >= 0 ? math.pow(x, 1 / 3.0).toDouble() : -math.pow(-x, 1 / 3.0).toDouble();

      case 'abs':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        return x.abs();

      case 'floor':
        _requireArgCount(name, args, 1);
        return _asNum(name, args[0]).floorToDouble();

      case 'ceil':
        _requireArgCount(name, args, 1);
        return _asNum(name, args[0]).ceilToDouble();

      case 'round':
        if (args.isEmpty || args.length > 2) {
          throw const MathEvalException('round 函数需要 1 或 2 个参数: round(x [, decimals])');
        }
        final x = _asNum(name, args[0]);
        if (args.length == 1) {
          return x.roundToDouble();
        } else {
          final decimals = _asNum(name, args[1]).toInt();
          final factor = math.pow(10, decimals);
          return (x * factor).roundToDouble() / factor;
        }

      case 'sin':
        _requireArgCount(name, args, 1);
        return math.sin(_asNum(name, args[0]));

      case 'cos':
        _requireArgCount(name, args, 1);
        return math.cos(_asNum(name, args[0]));

      case 'tan':
        _requireArgCount(name, args, 1);
        return math.tan(_asNum(name, args[0]));

      case 'asin':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        if (x < -1.0 || x > 1.0) {
          throw MathEvalException('计算错误: asin 参数范围必须在 [-1, 1] 之间: $x');
        }
        return math.asin(x);

      case 'acos':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        if (x < -1.0 || x > 1.0) {
          throw MathEvalException('计算错误: acos 参数范围必须在 [-1, 1] 之间: $x');
        }
        return math.acos(x);

      case 'atan':
        _requireArgCount(name, args, 1);
        return math.atan(_asNum(name, args[0]));

      case 'atan2':
        _requireArgCount(name, args, 2);
        return math.atan2(_asNum(name, args[0]), _asNum(name, args[1]));

      case 'sinh':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        return (math.exp(x) - math.exp(-x)) / 2.0;

      case 'cosh':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        return (math.exp(x) + math.exp(-x)) / 2.0;

      case 'tanh':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        return (math.exp(x) - math.exp(-x)) / (math.exp(x) + math.exp(-x));

      case 'exp':
        _requireArgCount(name, args, 1);
        return math.exp(_asNum(name, args[0]));

      case 'ln':
      case 'log':
        if (args.length == 1) {
          final x = _asNum(name, args[0]);
          if (x <= 0) {
            throw MathEvalException('计算错误: 对数真数必须大于零: $x');
          }
          return math.log(x);
        } else if (args.length == 2) {
          final x = _asNum(name, args[0]);
          final base = _asNum(name, args[1]);
          if (x <= 0 || base <= 0 || base == 1) {
            throw MathEvalException('计算错误: 对数参数无效: log($x, base=$base)');
          }
          return math.log(x) / math.log(base);
        } else {
          throw const MathEvalException('log 函数需要 1 或 2 个参数: log(x [, base])');
        }

      case 'log10':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        if (x <= 0) {
          throw MathEvalException('计算错误: 对数真数必须大于零: $x');
        }
        return math.log(x) / math.ln10;

      case 'log2':
        _requireArgCount(name, args, 1);
        final x = _asNum(name, args[0]);
        if (x <= 0) {
          throw MathEvalException('计算错误: 对数真数必须大于零: $x');
        }
        return math.log(x) / math.ln2;

      case 'pow':
        _requireArgCount(name, args, 2);
        return math.pow(_asNum(name, args[0]), _asNum(name, args[1]));

      case 'deg2rad':
        _requireArgCount(name, args, 1);
        return _asNum(name, args[0]) * math.pi / 180.0;

      case 'rad2deg':
        _requireArgCount(name, args, 1);
        return _asNum(name, args[0]) * 180.0 / math.pi;

      case 'factorial':
      case 'fact':
        _requireArgCount(name, args, 1);
        return factorial(_asNum(name, args[0]));
    }

    // 3. Statistical Functions
    final statsList = _extractNumberList(name, args);
    switch (lower) {
      case 'sum':
        return statsList.fold<double>(0.0, (prev, element) => prev + element);

      case 'count':
        return statsList.length.toDouble();

      case 'min':
        if (statsList.isEmpty) throw const MathEvalException('min 函数参数列表不能为空');
        return statsList.reduce((a, b) => a < b ? a : b);

      case 'max':
        if (statsList.isEmpty) throw const MathEvalException('max 函数参数列表不能为空');
        return statsList.reduce((a, b) => a > b ? a : b);

      case 'mean':
      case 'avg':
      case 'average':
        if (statsList.isEmpty) throw const MathEvalException('mean 函数参数列表不能为空');
        final sum = statsList.fold<double>(0.0, (prev, element) => prev + element);
        return sum / statsList.length;

      case 'median':
        if (statsList.isEmpty) throw const MathEvalException('median 函数参数列表不能为空');
        final sorted = List<double>.from(statsList)..sort();
        final mid = sorted.length ~/ 2;
        if (sorted.length % 2 == 1) {
          return sorted[mid];
        } else {
          return (sorted[mid - 1] + sorted[mid]) / 2.0;
        }

      case 'mode':
        if (statsList.isEmpty) throw const MathEvalException('mode 函数参数列表不能为空');
        final freq = <double, int>{};
        for (final item in statsList) {
          freq[item] = (freq[item] ?? 0) + 1;
        }
        double bestItem = statsList.first;
        int maxCount = 0;
        for (final entry in freq.entries) {
          if (entry.value > maxCount) {
            maxCount = entry.value;
            bestItem = entry.key;
          }
        }
        return bestItem;

      case 'variance':
        if (statsList.isEmpty) throw const MathEvalException('variance 函数参数列表不能为空');
        final mean = statsList.fold<double>(0.0, (prev, e) => prev + e) / statsList.length;
        final sumSqDiff = statsList.fold<double>(0.0, (prev, e) => prev + math.pow(e - mean, 2));
        return sumSqDiff / statsList.length;

      case 'stddev':
      case 'stdev':
        if (statsList.isEmpty) throw const MathEvalException('stddev 函数参数列表不能为空');
        final mean = statsList.fold<double>(0.0, (prev, e) => prev + e) / statsList.length;
        final sumSqDiff = statsList.fold<double>(0.0, (prev, e) => prev + math.pow(e - mean, 2));
        final variance = sumSqDiff / statsList.length;
        return math.sqrt(variance);

      default:
        throw MathEvalException('未知函数或常量: "$name"');
    }
  }

  static double factorial(num n) {
    if (n < 0 || n.floorToDouble() != n) {
      throw MathEvalException('计算错误: 阶乘只能计算非负整数: $n');
    }
    final intVal = n.toInt();
    if (intVal > 170) {
      throw const MathEvalException('计算错误: 阶乘数值过大，超出浮点数范围 (>170!)');
    }
    double result = 1.0;
    for (int i = 2; i <= intVal; i++) {
      result *= i;
    }
    return result;
  }

  static void _requireArgCount(String name, List<dynamic> args, int count) {
    if (args.length != count) {
      throw MathEvalException('函数 $name 需要 $count 个参数，实际提供了 ${args.length} 个');
    }
  }

  static num _asNum(String name, dynamic val) {
    if (val is num) return val;
    throw MathEvalException('函数 $name 参数必须为数值类型，实际为: $val');
  }

  static List<double> _extractNumberList(String name, List<dynamic> args) {
    if (args.isEmpty) {
      throw MathEvalException('函数 $name 参数不能为空');
    }
    final list = <double>[];
    if (args.length == 1 && args[0] is List) {
      for (final item in args[0] as List) {
        if (item is num) {
          list.add(item.toDouble());
        } else {
          throw MathEvalException('函数 $name 列表参数中包含非数值元素: $item');
        }
      }
    } else {
      for (final item in args) {
        if (item is num) {
          list.add(item.toDouble());
        } else {
          throw MathEvalException('函数 $name 参数必须全部为数值，实际包含: $item');
        }
      }
    }
    return list;
  }

  // --- Unit Conversion System ---

  static double convertUnits(double value, String fromUnit, String toUnit) {
    final fromNorm = _normalizeUnit(fromUnit);
    final toNorm = _normalizeUnit(toUnit);

    final fromCat = _unitCategory(fromNorm);
    final toCat = _unitCategory(toNorm);

    if (fromCat == null) {
      throw MathEvalException('不支持的单位: "$fromUnit"');
    }
    if (toCat == null) {
      throw MathEvalException('不支持的单位: "$toUnit"');
    }
    if (fromCat != toCat) {
      throw MathEvalException('无法在不同类别单位间转换: 从 "$fromUnit" (${_catName(fromCat)}) 到 "$toUnit" (${_catName(toCat)})');
    }

    if (fromCat == _UnitCategory.temperature) {
      return _convertTemperature(value, fromNorm, toNorm);
    }

    final fromRatio = _unitFactors[fromNorm]!;
    final toRatio = _unitFactors[toNorm]!;

    // Base value = value * fromRatio; result = base / toRatio
    final baseValue = value * fromRatio;
    return baseValue / toRatio;
  }

  static String _normalizeUnit(String raw) {
    final trimmed = raw.trim().toLowerCase();
    // Normalize aliases
    const aliases = {
      '摄氏度': 'c', 'celsius': 'c', '℃': 'c',
      '华氏度': 'f', 'fahrenheit': 'f', '℉': 'f',
      '开尔文': 'k', 'kelvin': 'k',
      '米': 'm', 'meter': 'm', 'meters': 'm',
      '千米': 'km', '公里': 'km', 'kilometer': 'km', 'kilometers': 'km',
      '厘米': 'cm', 'centimeter': 'cm', 'centimeters': 'cm',
      '毫米': 'mm', 'millimeter': 'mm', 'millimeters': 'mm',
      '微米': 'um', 'micrometer': 'um',
      '纳米': 'nm_len', 'nanometer': 'nm_len',
      '英里': 'mi', 'mile': 'mi', 'miles': 'mi',
      '码': 'yd', 'yard': 'yd', 'yards': 'yd',
      '英尺': 'ft', 'foot': 'ft', 'feet': 'ft',
      '英寸': 'in', 'inch': 'in', 'inches': 'in',
      '海里': 'nmi', 'nautical_mile': 'nmi',
      '克': 'g', 'gram': 'g', 'grams': 'g',
      '千克': 'kg', '公斤': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
      '毫克': 'mg', 'milligram': 'mg', 'milligrams': 'mg',
      '吨': 't', 'ton': 't', 'tons': 't',
      '磅': 'lb', 'pound': 'lb', 'pounds': 'lb',
      '盎司': 'oz', 'ounce': 'oz', 'ounces': 'oz',
      '斤': 'jin', '市斤': 'jin',
      '两': 'liang',
      'byte': 'b', 'bytes': 'b', '字节': 'b',
      'kb': 'kb', 'kilobyte': 'kb',
      'mb': 'mb', 'megabyte': 'mb',
      'gb': 'gb', 'gigabyte': 'gb',
      'tb': 'tb', 'terabyte': 'tb',
      'pb': 'pb', 'petabyte': 'pb',
      'bit': 'bit', 'bits': 'bit', '比特': 'bit',
      'm/s': 'mps', 'mps': 'mps', '米/秒': 'mps',
      'km/h': 'kph', 'kph': 'kph', '千米/时': 'kph', '公里/小时': 'kph',
      'mph': 'mph', '英里/小时': 'mph',
      'knot': 'knot', 'knots': 'knot', '节': 'knot',
      'm2': 'm2', 'sqm': 'm2', '平方米': 'm2',
      'km2': 'km2', 'sqkm': 'km2', '平方千米': 'km2', '平方公里': 'km2',
      'ha': 'ha', '公顷': 'ha',
      'mu': 'mu', '亩': 'mu',
      'sqft': 'sqft', '平方英尺': 'sqft',
      'acre': 'acre', 'acres': 'acre', '英亩': 'acre',
      's': 's', 'sec': 's', 'second': 's', 'seconds': 's', '秒': 's',
      'ms': 'ms', 'millisecond': 'ms', 'milliseconds': 'ms', '毫秒': 'ms',
      'min': 'min', 'minute': 'min', 'minutes': 'min', '分': 'min', '分钟': 'min',
      'h': 'h', 'hr': 'h', 'hour': 'h', 'hours': 'h', '小时': 'h', '时': 'h',
      'd': 'd', 'day': 'd', 'days': 'd', '天': 'd', '日': 'd',
      'w': 'w', 'wk': 'w', 'week': 'w', 'weeks': 'w', '周': 'w', '星期': 'w',
    };
    return aliases[trimmed] ?? trimmed;
  }

  static _UnitCategory? _unitCategory(String normUnit) {
    if (normUnit == 'c' || normUnit == 'f' || normUnit == 'k') {
      return _UnitCategory.temperature;
    }
    return _unitCategories[normUnit];
  }

  static String _catName(_UnitCategory cat) {
    switch (cat) {
      case _UnitCategory.temperature: return '温度';
      case _UnitCategory.length: return '长度';
      case _UnitCategory.weight: return '质量/重量';
      case _UnitCategory.storage: return '数据存储';
      case _UnitCategory.speed: return '速度';
      case _UnitCategory.area: return '面积';
      case _UnitCategory.time: return '时间';
    }
  }

  static double _convertTemperature(double val, String from, String to) {
    if (from == to) return val;
    // Normalize to Celsius
    double c;
    if (from == 'c') {
      c = val;
    } else if (from == 'f') {
      c = (val - 32.0) * 5.0 / 9.0;
    } else if (from == 'k') {
      c = val - 273.15;
    } else {
      throw MathEvalException('不支持的温度单位: $from');
    }

    // Convert from Celsius to Target
    if (to == 'c') return c;
    if (to == 'f') return c * 9.0 / 5.0 + 32.0;
    if (to == 'k') return c + 273.15;
    throw MathEvalException('不支持的温度单位: $to');
  }

  static const Map<String, _UnitCategory> _unitCategories = {
    // Length (Base: m)
    'm': _UnitCategory.length,
    'km': _UnitCategory.length,
    'cm': _UnitCategory.length,
    'mm': _UnitCategory.length,
    'um': _UnitCategory.length,
    'nm_len': _UnitCategory.length,
    'mi': _UnitCategory.length,
    'yd': _UnitCategory.length,
    'ft': _UnitCategory.length,
    'in': _UnitCategory.length,
    'nmi': _UnitCategory.length,

    // Weight (Base: g)
    'g': _UnitCategory.weight,
    'kg': _UnitCategory.weight,
    'mg': _UnitCategory.weight,
    't': _UnitCategory.weight,
    'lb': _UnitCategory.weight,
    'oz': _UnitCategory.weight,
    'jin': _UnitCategory.weight,
    'liang': _UnitCategory.weight,

    // Storage (Base: B)
    'b': _UnitCategory.storage,
    'kb': _UnitCategory.storage,
    'mb': _UnitCategory.storage,
    'gb': _UnitCategory.storage,
    'tb': _UnitCategory.storage,
    'pb': _UnitCategory.storage,
    'bit': _UnitCategory.storage,

    // Speed (Base: mps)
    'mps': _UnitCategory.speed,
    'kph': _UnitCategory.speed,
    'mph': _UnitCategory.speed,
    'knot': _UnitCategory.speed,

    // Area (Base: m2)
    'm2': _UnitCategory.area,
    'km2': _UnitCategory.area,
    'ha': _UnitCategory.area,
    'mu': _UnitCategory.area,
    'sqft': _UnitCategory.area,
    'acre': _UnitCategory.area,

    // Time (Base: s)
    's': _UnitCategory.time,
    'ms': _UnitCategory.time,
    'min': _UnitCategory.time,
    'h': _UnitCategory.time,
    'd': _UnitCategory.time,
    'w': _UnitCategory.time,
  };

  static const Map<String, double> _unitFactors = {
    // Length (Base: m)
    'm': 1.0,
    'km': 1000.0,
    'cm': 0.01,
    'mm': 0.001,
    'um': 0.000001,
    'nm_len': 0.000000001,
    'mi': 1609.344,
    'yd': 0.9144,
    'ft': 0.3048,
    'in': 0.0254,
    'nmi': 1852.0,

    // Weight (Base: g)
    'g': 1.0,
    'kg': 1000.0,
    'mg': 0.001,
    't': 1000000.0,
    'lb': 453.59237,
    'oz': 28.349523125,
    'jin': 500.0,
    'liang': 50.0,

    // Storage (Base: B)
    'b': 1.0,
    'kb': 1024.0,
    'mb': 1048576.0,
    'gb': 1073741824.0,
    'tb': 1099511627776.0,
    'pb': 1125899906842624.0,
    'bit': 0.125,

    // Speed (Base: m/s)
    'mps': 1.0,
    'kph': 1.0 / 3.6,
    'mph': 0.44704,
    'knot': 0.5144444444444445,

    // Area (Base: m2)
    'm2': 1.0,
    'km2': 1000000.0,
    'ha': 10000.0,
    'mu': 666.6666666666666,
    'sqft': 0.09290304,
    'acre': 4046.8564224,

    // Time (Base: s)
    's': 1.0,
    'ms': 0.001,
    'min': 60.0,
    'h': 3600.0,
    'd': 86400.0,
    'w': 604800.0,
  };
}

enum _UnitCategory {
  temperature,
  length,
  weight,
  storage,
  speed,
  area,
  time,
}

/// Pure Dart recursive descent mathematical, statistical, and unit conversion tool.
class MathEvalTool extends Tool {
  const MathEvalTool();

  @override
  String get name => 'math_eval';

  @override
  String get displayName => '数学计算器';

  @override
  String get description =>
      'High-precision mathematical expression evaluator. Supports arithmetic (+, -, *, /, %, ^, **), scientific/trigonometric functions (sqrt, cbrt, abs, ceil, floor, round, sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, ln, log10, log2, exp, factorial), statistics (mean, median, mode, stddev, variance, sum, min, max, count), and unit conversions (convert(val, "from", "to") for temperature, length, weight, storage, speed, area, time).';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'expression',
      type: 'string',
      description:
          'The mathematical expression, statistical formula, or unit conversion function to evaluate (e.g. "(3 + 5) * 2 ^ 3", "sqrt(16) + sin(pi / 2)", "mean([1, 2, 3, 4, 5])", "stddev([2, 4, 4, 4, 5, 5, 7, 9])", "convert(100, \'km\', \'mi\')", "convert(37, \'C\', \'F\')").',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final expr = (arguments['expression'] as String? ?? '').trim();

    if (expr.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '表达式不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final lexer = _MathLexer(expr);
      final tokens = lexer.tokenize();
      final parser = _MathParser(tokens);
      final rawResult = parser.parse();
      stopwatch.stop();

      final formattedResult = _formatResult(rawResult);
      final markdown = '**计算表达式**: `$expr`\n**计算结果**: **`$formattedResult`**';

      return ToolExecutionResult.success(
        toolName: name,
        content: markdown,
        rawData: {
          'expression': expr,
          'result': rawResult,
          'formattedResult': formattedResult,
        },
        executionDuration: stopwatch.elapsed,
        metadata: {
          'expression': expr,
        },
      );
    } on MathEvalException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '计算失败: ${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {'expression': expr},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '计算异常: $e',
        content: '计算失败: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'expression': expr},
      );
    }
  }

  String _formatResult(dynamic val) {
    if (val is double) {
      if (val.isNaN) return 'NaN';
      if (val.isInfinite) return val.isNegative ? '-Infinity' : 'Infinity';
      if (val == val.roundToDouble()) {
        return val.toInt().toString();
      }
      // Trim redundant trailing zeros for clean presentation
      final str = val.toStringAsFixed(10);
      final trimmed = str.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return trimmed;
    } else if (val is int) {
      return val.toString();
    } else if (val is List) {
      return '[${val.map(_formatResult).join(', ')}]';
    }
    return val.toString();
  }
}
