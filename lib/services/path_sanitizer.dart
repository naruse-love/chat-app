import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown when a file path violates sandbox constraints or exceeds quotas.
class PathSanitizerException implements Exception {
  final String message;
  const PathSanitizerException(this.message);

  @override
  String toString() => message;
}

/// Security barrier and path sanitizer for sandboxed local file operations.
///
/// Defends against:
/// 1. Directory traversal attacks (`..`, `../`, `..\`, `%2e%2e`, `\x00`).
/// 2. Absolute path privilege escalation (e.g. accessing `C:\Windows`, `/etc/passwd`).
/// 3. Symbolic link / junction point escapes via `resolveSymbolicLinksSync()`.
/// 4. Storage exhaustion via single file quota (5 MB) and total workspace quota (50 MB).
class PathSanitizer {
  static const int defaultMaxSingleFileSize = 5 * 1024 * 1024; // 5 MB
  static const int defaultMaxWorkspaceSize = 50 * 1024 * 1024; // 50 MB

  /// The root directory of the safe sandbox.
  final Directory sandboxDir;

  /// Maximum allowed size for a single file in bytes.
  final int maxSingleFileSize;

  /// Maximum allowed cumulative size for the entire sandbox workspace in bytes.
  final int maxWorkspaceSize;

  PathSanitizer({
    required this.sandboxDir,
    this.maxSingleFileSize = defaultMaxSingleFileSize,
    this.maxWorkspaceSize = defaultMaxWorkspaceSize,
  });

  /// Factory to construct a default [PathSanitizer] rooted in `getApplicationDocumentsDirectory() / sandbox`.
  static Future<PathSanitizer> createDefault({
    int maxSingleFileSize = defaultMaxSingleFileSize,
    int maxWorkspaceSize = defaultMaxWorkspaceSize,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final sandbox = Directory(p.join(docsDir.path, 'sandbox'));
    if (!sandbox.existsSync()) {
      sandbox.createSync(recursive: true);
    }
    return PathSanitizer(
      sandboxDir: sandbox,
      maxSingleFileSize: maxSingleFileSize,
      maxWorkspaceSize: maxWorkspaceSize,
    );
  }

  /// Ensures the sandbox root directory exists on disk.
  void ensureSandboxExists() {
    if (!sandboxDir.existsSync()) {
      sandboxDir.createSync(recursive: true);
    }
  }

  /// Sanitizes and canonicalizes [rawPath], guaranteeing it resolves strictly inside the sandbox.
  ///
  /// Returns a clean relative path from the sandbox root (e.g. `notes/todo.txt` or `.`).
  String sanitizeRelativePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == './' || trimmed == '.\\') {
      return '.';
    }

    // 1. Detect null bytes or URL-encoded path traversal sequences
    if (trimmed.contains('\x00')) {
      throw const PathSanitizerException('路径非法: 包含空字节 (Null Byte)');
    }
    final lower = trimmed.toLowerCase();
    if (lower.contains('%2e%2e') || lower.contains('%2f') || lower.contains('%5c')) {
      throw const PathSanitizerException('路径非法: 包含 URL 编码的越权路径序列');
    }

    // 2. Reject absolute paths or drive letters
    final normalizedInput = trimmed.replaceAll('\\', '/');
    if (normalizedInput.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalizedInput) ||
        normalizedInput.startsWith('~')) {
      throw PathSanitizerException('禁止使用绝对路径，必须使用沙箱内的相对路径: "$trimmed"');
    }

    // 3. Resolve canonical absolute path
    final canonicalSandbox = p.canonicalize(sandboxDir.path);
    final targetAbsolute = p.canonicalize(p.join(canonicalSandbox, normalizedInput));

    // 4. Verify that targetAbsolute starts with canonicalSandbox
    if (!_isSubPathOrSame(canonicalSandbox, targetAbsolute)) {
      throw PathSanitizerException('路径越权违规: 检测到目录遍历试图逃逸沙箱: "$trimmed"');
    }

    // 5. Return normalized relative path
    final rel = p.relative(targetAbsolute, from: canonicalSandbox).replaceAll('\\', '/');
    return rel.isEmpty ? '.' : rel;
  }

  /// Resolves a safe [File] entity guaranteed to reside within the sandbox.
  File resolveSafeFile(String relativePath) {
    ensureSandboxExists();
    final sanitizedRel = sanitizeRelativePath(relativePath);
    if (sanitizedRel == '.') {
      throw const PathSanitizerException('路径非法: 目标不能是沙箱根目录');
    }

    final canonicalSandbox = p.canonicalize(sandboxDir.path);
    final file = File(p.join(canonicalSandbox, sanitizedRel));

    // Check symlink escape on the file or its parent directories if they exist
    _verifyNoSymlinkEscape(file.path, canonicalSandbox);

    return file;
  }

  /// Resolves a safe [Directory] entity guaranteed to reside within the sandbox.
  Directory resolveSafeDirectory(String relativePath) {
    ensureSandboxExists();
    final sanitizedRel = sanitizeRelativePath(relativePath);
    final canonicalSandbox = p.canonicalize(sandboxDir.path);
    final dir = Directory(p.join(canonicalSandbox, sanitizedRel));

    _verifyNoSymlinkEscape(dir.path, canonicalSandbox);

    return dir;
  }

  /// Checks if [path] is safe without throwing.
  bool isPathSafe(String path) {
    try {
      sanitizeRelativePath(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether [targetPath] is equal to or a subdirectory of [basePath].
  bool _isSubPathOrSame(String basePath, String targetPath) {
    final normBase = p.canonicalize(basePath).toLowerCase();
    final normTarget = p.canonicalize(targetPath).toLowerCase();

    if (normTarget == normBase) return true;
    final separator = p.separator;
    return normTarget.startsWith('$normBase$separator') || normTarget.startsWith('$normBase/');
  }

  /// Verifies that no existing parent directory or file symlink escapes the sandbox root.
  void _verifyNoSymlinkEscape(String targetPath, String canonicalSandbox) {
    try {
      final entity = FileSystemEntity.typeSync(targetPath, followLinks: false);
      if (entity != FileSystemEntityType.notFound) {
        // Entity exists on disk, resolve physical symbolic link
        final realPath = p.canonicalize(
          FileSystemEntity.isLinkSync(targetPath)
              ? Link(targetPath).resolveSymbolicLinksSync()
              : File(targetPath).resolveSymbolicLinksSync(),
        );
        if (!_isSubPathOrSame(canonicalSandbox, realPath)) {
          throw PathSanitizerException('符号链接逃逸违规: 实体真实物理路径 ($realPath) 位于沙箱外部');
        }
      } else {
        // If target does not exist yet, check the nearest existing parent directory
        var parentDir = Directory(p.dirname(targetPath));
        while (parentDir.existsSync()) {
          final realParent = p.canonicalize(parentDir.resolveSymbolicLinksSync());
          if (!_isSubPathOrSame(canonicalSandbox, realParent)) {
            throw PathSanitizerException('符号链接逃逸违规: 父级目录真实物理路径 ($realParent) 位于沙箱外部');
          }
          if (p.canonicalize(parentDir.path).toLowerCase() == canonicalSandbox.toLowerCase()) {
            break;
          }
          final nextParent = parentDir.parent;
          if (nextParent.path == parentDir.path) break;
          parentDir = nextParent;
        }
      }
    } on PathSanitizerException {
      rethrow;
    } catch (_) {
      // In case of permission errors during symlink inspection, default to safe path check
    }
  }

  /// Validates that a file write operation will not exceed the single-file size quota.
  void validateFileWriteSize({
    int existingBytes = 0,
    required int bytesToWrite,
    bool isAppend = false,
  }) {
    final finalSize = isAppend ? existingBytes + bytesToWrite : bytesToWrite;
    if (finalSize > maxSingleFileSize) {
      final maxMb = (maxSingleFileSize / (1024 * 1024)).toStringAsFixed(1);
      final actualMb = (finalSize / (1024 * 1024)).toStringAsFixed(2);
      throw PathSanitizerException(
        '文件大小超出限制: 写入后文件大小 ($actualMb MB / $finalSize 字节) 超出单个文件最大配额 ($maxMb MB)',
      );
    }
  }

  /// Computes the current total size (in bytes) of all files in the sandbox.
  Future<int> computeCurrentWorkspaceSize() async {
    ensureSandboxExists();
    int totalBytes = 0;
    try {
      final entities = sandboxDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          totalBytes += entity.lengthSync();
        }
      }
    } catch (_) {
      // Graceful fallback
    }
    return totalBytes;
  }

  /// Validates that adding [bytesToAdd] will not exceed the overall sandbox workspace quota.
  Future<void> validateWorkspaceCapacity(int bytesToAdd) async {
    final currentSize = await computeCurrentWorkspaceSize();
    final resultingSize = currentSize + bytesToAdd;
    if (resultingSize > maxWorkspaceSize) {
      final maxMb = (maxWorkspaceSize / (1024 * 1024)).toStringAsFixed(1);
      final resultMb = (resultingSize / (1024 * 1024)).toStringAsFixed(2);
      final currentMb = (currentSize / (1024 * 1024)).toStringAsFixed(2);
      throw PathSanitizerException(
        '沙箱容量已超限: 当前已使用 $currentMb MB，写入后将达到 $resultMb MB，超出总工作区配额 ($maxMb MB)',
      );
    }
  }

  /// Converts a physical entity inside the sandbox into a relative path from the sandbox root.
  String getRelativePath(FileSystemEntity entity) {
    final canonicalSandbox = p.canonicalize(sandboxDir.path);
    final canonicalTarget = p.canonicalize(entity.path);
    final rel = p.relative(canonicalTarget, from: canonicalSandbox).replaceAll('\\', '/');
    return rel.isEmpty ? '.' : rel;
  }
}
