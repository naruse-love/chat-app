import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/path_sanitizer.dart';
import 'package:chat/services/tools/file_read_tool.dart';
import 'package:chat/services/tools/file_write_tool.dart';
import 'package:chat/services/tools/file_list_tool.dart';
import 'package:chat/services/tools/file_delete_tool.dart';

void main() {
  late Directory tempSandboxDir;
  late PathSanitizer sanitizer;
  late FileReadTool readTool;
  late FileWriteTool writeTool;
  late FileListTool listTool;
  late FileDeleteTool deleteTool;

  setUp(() {
    tempSandboxDir = Directory.systemTemp.createTempSync('file_tools_test_');
    sanitizer = PathSanitizer(
      sandboxDir: tempSandboxDir,
      maxSingleFileSize: 2 * 1024 * 1024,
      maxWorkspaceSize: 10 * 1024 * 1024,
    );

    readTool = FileReadTool(pathSanitizer: sanitizer);
    writeTool = FileWriteTool(pathSanitizer: sanitizer);
    listTool = FileListTool(pathSanitizer: sanitizer);
    deleteTool = FileDeleteTool(pathSanitizer: sanitizer);
  });

  tearDown(() {
    if (tempSandboxDir.existsSync()) {
      tempSandboxDir.deleteSync(recursive: true);
    }
  });

  group('FileWriteTool & FileReadTool Workflow Tests', () {
    test('writes and reads file successfully with pagination and diff', () async {
      expect(writeTool.securityLevel, equals(ToolSecurityLevel.sensitiveConfirm));
      expect(readTool.securityLevel, equals(ToolSecurityLevel.readOnly));

      // 1. Write initial file
      final writeRes = await writeTool.execute({
        'path': 'docs/welcome.txt',
        'content': 'Line 1: Hello\nLine 2: World\nLine 3: Dart\nLine 4: Flutter\nLine 5: Agent',
        'mode': 'overwrite',
      });

      expect(writeRes.success, isTrue);
      expect(writeRes.content, contains('文件写入成功'));

      // 2. Read lines 2 to 4
      final readRes = await readTool.execute({
        'path': 'docs/welcome.txt',
        'start_line': 2,
        'end_line': 4,
      });

      expect(readRes.success, isTrue);
      expect(readRes.content, contains('Line 2: World'));
      expect(readRes.content, contains('Line 4: Flutter'));
      expect(readRes.rawData['linesRead'], equals(3));
      expect(readRes.rawData['totalLines'], equals(5));

      // 3. Append to file
      final appendRes = await writeTool.execute({
        'path': 'docs/welcome.txt',
        'content': '\nLine 6: Appended',
        'mode': 'append',
      });
      expect(appendRes.success, isTrue);

      final fullReadRes = await readTool.execute({'path': 'docs/welcome.txt'});
      expect(fullReadRes.content, contains('Line 6: Appended'));
    });

    test('create_new mode fails if file already exists', () async {
      await writeTool.execute({
        'path': 'unique.txt',
        'content': 'first content',
      });

      final duplicateRes = await writeTool.execute({
        'path': 'unique.txt',
        'content': 'second content',
        'mode': 'create_new',
      });

      expect(duplicateRes.success, isFalse);
      expect(duplicateRes.errorMessage, contains('create_new 模式拒绝覆盖'));
    });

    test('generateDiffPreview generates accurate diff before writing', () {
      sanitizer.resolveSafeFile('test_diff.txt').writeAsStringSync('Original A\nOriginal B');
      final preview = writeTool.generateDiffPreview('test_diff.txt', 'Original A\nModified B\nNew C');

      expect(preview.fileExisted, isTrue);
      expect(preview.diffSummary.additions, equals(2));
      expect(preview.diffSummary.deletions, equals(1));
    });

    test('read returns friendly error when file is missing', () async {
      final res = await readTool.execute({'path': 'non_existent.md'});
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('文件未找到'));
    });
  });

  group('FileListTool & FileDeleteTool Tests', () {
    test('lists files and directories with pattern and recursive options', () async {
      // Create nested file structure
      await writeTool.execute({'path': 'src/main.dart', 'content': 'void main() {}'});
      await writeTool.execute({'path': 'src/utils/math.dart', 'content': 'int add(int a, int b) => a + b;'});
      await writeTool.execute({'path': 'notes.md', 'content': '# Notes'});

      // 1. Root listing non-recursive
      final rootRes = await listTool.execute({'directory': '.', 'recursive': false});
      expect(rootRes.success, isTrue);
      expect(rootRes.content, contains('notes.md'));

      // 2. Recursive listing with *.dart pattern
      final dartFilesRes = await listTool.execute({
        'directory': '.',
        'recursive': true,
        'pattern': '*.dart',
      });
      expect(dartFilesRes.success, isTrue);
      expect(dartFilesRes.rawData['count'], equals(2));
    });

    test('deletes file safely and rejects root directory deletion', () async {
      await writeTool.execute({'path': 'to_delete.txt', 'content': 'temporary'});

      // Delete file
      final deleteFileRes = await deleteTool.execute({'path': 'to_delete.txt'});
      expect(deleteFileRes.success, isTrue);
      expect(deleteFileRes.content, contains('文件删除成功'));

      // Root directory deletion protection
      final rootDeleteRes = await deleteTool.execute({'path': '.'});
      expect(rootDeleteRes.success, isFalse);
      expect(rootDeleteRes.errorMessage, contains('禁止删除沙箱根目录'));
    });

    test('directory deletion requires recursive: true for non-empty directory', () async {
      await writeTool.execute({'path': 'folder/nested.txt', 'content': 'nested data'});

      // Delete non-empty folder without recursive -> fail
      final nonRecRes = await deleteTool.execute({'path': 'folder', 'recursive': false});
      expect(nonRecRes.success, isFalse);
      expect(nonRecRes.errorMessage, contains('目录非空'));

      // Delete non-empty folder with recursive: true -> success
      final recRes = await deleteTool.execute({'path': 'folder', 'recursive': true});
      expect(recRes.success, isTrue);
      expect(recRes.content, contains('目录删除成功'));
    });
  });
}
