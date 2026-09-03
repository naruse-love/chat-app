import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:chat/services/path_sanitizer.dart';
import 'package:chat/services/tools/file_list_tool.dart';
import 'package:chat/services/tools/file_read_tool.dart';
import 'package:chat/services/tools/file_write_tool.dart';
import 'package:chat/services/tools/file_delete_tool.dart';

void main() {
  group('PathSanitizer Workspace & WSL Protection Tests', () {
    late Directory tempDir;
    late PathSanitizer sanitizer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sanitizer_ws_test_');
      sanitizer = PathSanitizer(sandboxDir: tempDir);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('isWindowsDriveOrMount detects WSL mounts and Windows drive letters', () {
      expect(PathSanitizer.isWindowsDriveOrMount('/mnt/c'), isTrue);
      expect(PathSanitizer.isWindowsDriveOrMount('/mnt/c/Users/test'), isTrue);
      expect(PathSanitizer.isWindowsDriveOrMount('/mnt/d/work'), isTrue);
      expect(PathSanitizer.isWindowsDriveOrMount('C:\\Windows\\System32'), isTrue);
      expect(PathSanitizer.isWindowsDriveOrMount('d:/projects'), isTrue);

      expect(PathSanitizer.isWindowsDriveOrMount('/home/as/chat'), isFalse);
      expect(PathSanitizer.isWindowsDriveOrMount('lib/main.dart'), isFalse);
      expect(PathSanitizer.isWindowsDriveOrMount('./README.md'), isFalse);
    });

    test('sanitizeRelativePath rejects WSL mount paths with protection notice', () {
      expect(
        () => sanitizer.sanitizeRelativePath('/mnt/c/foo.txt'),
        throwsA(predicate((e) =>
            e is PathSanitizerException &&
            e.message.contains('【WSL 环境保护】'))),
      );

      expect(
        () => sanitizer.sanitizeRelativePath('/mnt/d/test'),
        throwsA(predicate((e) =>
            e is PathSanitizerException &&
            e.message.contains('【WSL 环境保护】'))),
      );
    });

    test('sanitizeRelativePath converts in-workspace absolute path to relative path', () {
      final insideFile = File(p.join(tempDir.path, 'sub', 'test.txt'));
      insideFile.parent.createSync(recursive: true);
      insideFile.writeAsStringSync('hello inside');

      final rel = sanitizer.sanitizeRelativePath(insideFile.path);
      expect(rel, equals('sub/test.txt'));

      final resolved = sanitizer.resolveSafeFile(insideFile.path);
      expect(resolved.existsSync(), isTrue);
      expect(resolved.readAsStringSync(), equals('hello inside'));
    });

    test('sanitizeRelativePath rejects absolute paths outside workspace', () {
      final outsideDir = Directory.systemTemp.createTempSync('outside_ws_');
      addTearDown(() {
        try {
          outsideDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(
        () => sanitizer.sanitizeRelativePath(outsideDir.path),
        throwsA(isA<PathSanitizerException>()),
      );
    });

    test('FileListTool filters out .git, build, .dart_tool, node_modules', () async {
      // Create subdirectories
      final gitDir = Directory(p.join(tempDir.path, '.git'))..createSync();
      File(p.join(gitDir.path, 'config')).writeAsStringSync('git config');

      final buildDir = Directory(p.join(tempDir.path, 'build'))..createSync();
      File(p.join(buildDir.path, 'app.apk')).writeAsStringSync('apk');

      final normalDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
      File(p.join(normalDir.path, 'main.dart')).writeAsStringSync('void main() {}');

      final listTool = FileListTool(pathSanitizer: sanitizer);
      final result = await listTool.execute({'directory': '.', 'recursive': true});

      expect(result.success, isTrue);
      final items = (result.rawData['items'] as List).cast<Map<String, dynamic>>();
      final names = items.map((e) => e['name']).toList();

      expect(names.contains('main.dart'), isTrue);
      expect(names.contains('config'), isFalse);
      expect(names.contains('app.apk'), isFalse);
    });

    test('FileListTool and FileReadTool block WSL mounts safely', () async {
      final listTool = FileListTool(pathSanitizer: sanitizer);
      final readTool = FileReadTool(pathSanitizer: sanitizer);

      final listRes = await listTool.execute({'directory': '/mnt/c'});
      expect(listRes.success, isFalse);
      expect(listRes.errorMessage, contains('【WSL 环境保护】'));

      final readRes = await readTool.execute({'path': '/mnt/d/test.txt'});
      expect(readRes.success, isFalse);
      expect(readRes.errorMessage, contains('【WSL 环境保护】'));
    });

    test('PathSanitizer handles Android internal /data/user/0 <=> /data/data symlink aliases', () {
      final androidSanitizer = PathSanitizer(
        sandboxDir: Directory('/data/user/0/com.example.chat/app_flutter/workspace'),
      );

      final rel = androidSanitizer.sanitizeRelativePath(
        '/data/data/com.example.chat/app_flutter/workspace/notes/test.txt',
      );
      expect(rel, equals('notes/test.txt'));
      expect(
        androidSanitizer.isExternalPath('/data/data/com.example.chat/app_flutter/workspace/notes/test.txt'),
        isFalse,
      );
    });

    test('PathSanitizer handles Android external storage /sdcard <=> /storage/emulated/0 aliases', () {
      final sdcardSanitizer = PathSanitizer(
        sandboxDir: Directory('/sdcard/Download/ChatWorkspace'),
      );

      final rel = sdcardSanitizer.sanitizeRelativePath(
        '/storage/emulated/0/Download/ChatWorkspace/data/file.csv',
      );
      expect(rel, equals('data/file.csv'));
      expect(
        sdcardSanitizer.isExternalPath('/storage/emulated/0/Download/ChatWorkspace/data/file.csv'),
        isFalse,
      );
    });

    test('PathSanitizer.defaultDirectory provides persistent workspace and tools construct cleanly', () {
      expect(PathSanitizer.defaultDirectory.path, isNotEmpty);

      final rTool = FileReadTool();
      final wTool = FileWriteTool();
      final lTool = FileListTool();
      final dTool = FileDeleteTool();

      expect(rTool.name, equals('file_read'));
      expect(wTool.name, equals('file_write'));
      expect(lTool.name, equals('file_list'));
      expect(dTool.name, equals('file_delete'));
    });
  });
}
