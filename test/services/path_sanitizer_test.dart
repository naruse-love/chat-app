import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:chat/services/path_sanitizer.dart';

void main() {
  late Directory tempSandboxDir;
  late PathSanitizer sanitizer;

  setUp(() {
    tempSandboxDir = Directory.systemTemp.createTempSync('sandbox_test_');
    sanitizer = PathSanitizer(
      sandboxDir: tempSandboxDir,
      maxSingleFileSize: 1024 * 1024, // 1 MB for testing
      maxWorkspaceSize: 5 * 1024 * 1024, // 5 MB for testing
    );
  });

  tearDown(() {
    if (tempSandboxDir.existsSync()) {
      tempSandboxDir.deleteSync(recursive: true);
    }
  });

  group('PathSanitizer Path Canonicalization & Jailbreak Prevention Tests', () {
    test('allows safe relative paths inside sandbox', () {
      expect(sanitizer.sanitizeRelativePath('notes/todo.txt'), equals('notes/todo.txt'));
      expect(sanitizer.sanitizeRelativePath('./src/main.dart'), equals('src/main.dart'));
      expect(sanitizer.sanitizeRelativePath('.'), equals('.'));
      expect(sanitizer.sanitizeRelativePath(''), equals('.'));
    });

    test('blocks directory traversal attempts (.. / ../ / ..\\)', () {
      expect(
        () => sanitizer.sanitizeRelativePath('../outside.txt'),
        throwsA(isA<PathSanitizerException>()),
      );
      expect(
        () => sanitizer.sanitizeRelativePath('notes/../../secret.key'),
        throwsA(isA<PathSanitizerException>()),
      );
      expect(
        () => sanitizer.sanitizeRelativePath('..\\..\\windows\\system32'),
        throwsA(isA<PathSanitizerException>()),
      );
    });

    test('blocks absolute paths and drive letters', () {
      expect(
        () => sanitizer.sanitizeRelativePath('/etc/passwd'),
        throwsA(isA<PathSanitizerException>()),
      );
      expect(
        () => sanitizer.sanitizeRelativePath('C:\\Windows\\System32'),
        throwsA(isA<PathSanitizerException>()),
      );
      expect(
        () => sanitizer.sanitizeRelativePath('D:/data/secret'),
        throwsA(isA<PathSanitizerException>()),
      );
    });

    test('blocks null byte and url-encoded escape attempts', () {
      expect(
        () => sanitizer.sanitizeRelativePath('notes\x00/exploit.txt'),
        throwsA(isA<PathSanitizerException>()),
      );
      expect(
        () => sanitizer.sanitizeRelativePath('%2e%2e/secret.txt'),
        throwsA(isA<PathSanitizerException>()),
      );
    });

    test('resolves safe file and directory inside sandbox root', () {
      final file = sanitizer.resolveSafeFile('docs/readme.md');
      expect(p.canonicalize(file.path).startsWith(p.canonicalize(tempSandboxDir.path)), isTrue);
      expect(sanitizer.isPathSafe('docs/readme.md'), isTrue);
      expect(sanitizer.isPathSafe('../escape.txt'), isFalse);
    });

    test('rejects resolving sandbox root as a single file', () {
      expect(
        () => sanitizer.resolveSafeFile('.'),
        throwsA(isA<PathSanitizerException>()),
      );
    });
  });

  group('PathSanitizer Quota & Capacity Tests', () {
    test('validates single file write size limits', () {
      // 1 MB limit in test
      expect(
        () => sanitizer.validateFileWriteSize(
          bytesToWrite: 500 * 1024,
          isAppend: false,
        ),
        returnsNormally,
      );

      expect(
        () => sanitizer.validateFileWriteSize(
          bytesToWrite: 2 * 1024 * 1024, // 2 MB > 1 MB
          isAppend: false,
        ),
        throwsA(isA<PathSanitizerException>()),
      );

      expect(
        () => sanitizer.validateFileWriteSize(
          existingBytes: 800 * 1024,
          bytesToWrite: 300 * 1024, // 1.1 MB total on append
          isAppend: true,
        ),
        throwsA(isA<PathSanitizerException>()),
      );
    });

    test('computes workspace capacity and prevents workspace overflow', () async {
      // Create initial files
      final file1 = File(p.join(tempSandboxDir.path, 'file1.dat'));
      file1.writeAsBytesSync(List.filled(100 * 1024, 0)); // 100 KB

      final currentSize = await sanitizer.computeCurrentWorkspaceSize();
      expect(currentSize, equals(100 * 1024));

      // Adding 1 MB should pass (5 MB total limit)
      await expectLater(
        sanitizer.validateWorkspaceCapacity(1024 * 1024),
        completes,
      );

      // Adding 6 MB should fail
      await expectLater(
        sanitizer.validateWorkspaceCapacity(6 * 1024 * 1024),
        throwsA(isA<PathSanitizerException>()),
      );
    });
  });
}
