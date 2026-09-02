import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/code_execution_service.dart';

void main() {
  group('CodeExecutionService & Interpreter Extended Tests', () {
    late CodeExecutionService service;

    setUp(() {
      service = CodeExecutionService();
    });

    test('Executes void main() function automatically and strips imports', () async {
      const code = '''
import 'dart:math';
import 'dart:convert';

void main() {
  var a = 10;
  var b = 25;
  print("Result is: " + (a + b).toString());
}
''';
      final result = await service.executeDart(code: code);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Result is: 35'));
    });

    test('Supports Math object global methods', () async {
      const code = '''
var r1 = Math.sqrt(144);
var r2 = Math.pow(2, 8);
var r3 = Math.max(10, 99);
var r4 = Math.abs(-42);
print("Math: " + r1.toString() + ", " + r2.toString() + ", " + r3.toString() + ", " + r4.toString());
''';
      final result = await service.executeDart(code: code);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Math: 12.0, 256.0, 99, 42'));
    });

    test('Supports console.log global logging', () async {
      const code = '''
console.log("Hello from console.log!", 123, true);
''';
      final result = await service.executeDart(code: code);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Hello from console.log! 123 true'));
    });

    test('Supports len and range helper functions', () async {
      const code = '''
var list = [1, 2, 3, 4, 5];
var l = len(list);
var r = range(0, 5);
print("Length: " + l.toString() + ", Range len: " + len(r).toString());
''';
      final result = await service.executeDart(code: code);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Length: 5, Range len: 5'));
    });

    test('Supports custom user-defined functions', () async {
      const code = '''
int multiply(int x, int y) {
  return x * y;
}

void main() {
  var val = multiply(6, 7);
  print("Multiplied: " + val.toString());
}
''';
      final result = await service.executeDart(code: code);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Multiplied: 42'));
    });
  });
}
