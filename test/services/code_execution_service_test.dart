import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/code_execution_service.dart';
import 'package:chat/services/tools/code_eval_tool.dart';

void main() {
  late CodeExecutionService service;
  late CodeEvalTool evalTool;

  setUp(() {
    service = CodeExecutionService();
    evalTool = CodeEvalTool(codeExecutionService: service);
  });

  group('CodeExecutionService Unit Tests', () {
    test('evaluates simple expressions and captures return value', () async {
      final res = await service.execute(code: '2 + 3 * 4');
      expect(res.success, isTrue);
      expect(res.result, equals(14));
      expect(res.isTimedOut, isFalse);
    });

    test('executes multi-line scripts with variables, conditionals, and loops', () async {
      const code = '''
var sum = 0;
for (var i = 1; i <= 10; i++) {
  sum += i;
}
return sum;
''';
      final res = await service.execute(code: code);
      expect(res.success, isTrue);
      expect(res.result, equals(55));
    });

    test('captures print statements into stdout', () async {
      const code = '''
print("Step 1: start");
print("Step 2: in progress");
print("Step 3: done");
var answer = 42;
return answer;
''';
      final res = await service.execute(code: code);
      expect(res.success, isTrue);
      expect(res.stdout, contains('Step 1: start'));
      expect(res.stdout, contains('Step 3: done'));
      expect(res.result, equals(42));
    });

    test('handles standard library functions: math, json, strings', () async {
      const code = '''
var x = sqrt(16) + abs(-10);
var data = jsonDecode('{"name": "Flutter", "version": 3}');
return {
  "math": x,
  "name": data["name"]
};
''';
      final res = await service.execute(code: code);
      expect(res.success, isTrue);
      expect(res.result, isA<Map>());
      final map = res.result as Map;
      expect(map['math'], equals(14));
      expect(map['name'], equals('Flutter'));
    });

    test('handles runtime errors and division by zero gracefully', () async {
      final res = await service.execute(code: '10 / 0');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('除数不能为零'));
    });

    test('enforces hard timeout and terminates infinite loop without freezing UI', () async {
      const infiniteLoop = '''
while (true) {
  // busy wait
}
''';
      // Use 600ms timeout for test speed
      final res = await service.execute(
        code: infiniteLoop,
        timeout: const Duration(milliseconds: 600),
      );

      expect(res.success, isFalse);
      expect(res.isTimedOut, isTrue);
      expect(res.errorMessage, contains('超时'));
    });
  });

  group('CodeEvalTool Tool Interface Tests', () {
    test('declares correct metadata and sensitive security level', () {
      expect(evalTool.name, equals('code_eval'));
      expect(evalTool.displayName, equals('代码执行'));
      expect(evalTool.securityLevel, equals(ToolSecurityLevel.sensitiveConfirm));
      expect(evalTool.parameters.any((p) => p.name == 'code'), isTrue);
    });

    test('executes code through Tool interface and formats markdown output', () async {
      final res = await evalTool.execute({
        'code': 'print("Hello from Tool"); var y = 100; return y * 2;',
      });

      expect(res.success, isTrue);
      expect(res.content, contains('沙箱代码执行完成'));
      expect(res.content, contains('Hello from Tool'));
      expect(res.content, contains('200'));
    });

    test('rejects empty code with clear error', () async {
      final res = await evalTool.execute({'code': '   '});
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('代码不能为空'));
    });
  });
}
