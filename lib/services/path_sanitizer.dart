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

  /// The root directory of the safe sandbox or workspace.
  final Directory sandboxDir;

  /// Alias for [sandboxDir] representing the active workspace root.
  Directory get workspaceDir => sandboxDir;

  /// Returns the recommended fallback directory across desktop and mobile platforms.
  static Directory get defaultDirectory {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return Directory.current;
    }
    return Directory('/data/user/0/com.example.chat/app_flutter/workspace');
  }

  /// Normalized canonical path string of the sandbox/workspace.
  String get canonicalSandbox => p.canonicalize(sandboxDir.path);

  /// Resolved physical path of the sandbox/workspace with symbolic links expanded.
  String get realSandbox {
    try {
      if (sandboxDir.existsSync()) {
        return p.canonicalize(sandboxDir.resolveSymbolicLinksSync());
      }
    } catch (_) {}
    return canonicalSandbox;
  }

  /// Maximum allowed size for a single file in bytes.
  final int maxSingleFileSize;

  /// Maximum allowed cumulative size for the entire sandbox workspace in bytes.
  final int maxWorkspaceSize;

  PathSanitizer({
    required this.sandboxDir,
    this.maxSingleFileSize = defaultMaxSingleFileSize,
    this.maxWorkspaceSize = defaultMaxWorkspaceSize,
  });

  /// Factory to construct a default [PathSanitizer] rooted in `getApplicationDocumentsDirectory() / workspace`.
  static Future<PathSanitizer> createDefault({
    int maxSingleFileSize = defaultMaxSingleFileSize,
    int maxWorkspaceSize = defaultMaxWorkspaceSize,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final wsDir = Directory(p.join(docsDir.path, 'workspace'));
    if (!wsDir.existsSync()) {
      wsDir.createSync(recursive: true);
    }
    return PathSanitizer(
      sandboxDir: wsDir,
      maxSingleFileSize: maxSingleFileSize,
      maxWorkspaceSize: maxWorkspaceSize,
    );
  }

  /// Returns a copy of this [PathSanitizer] rooted in a new directory [newDir].
  PathSanitizer withDirectory(Directory newDir) {
    return PathSanitizer(
      sandboxDir: newDir,
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

  /// Detects whether [path] points to a Windows drive (e.g. `C:\`, `D:/`) or WSL mount (e.g. `/mnt/c`, `/mnt/d`).
  static bool isWindowsDriveOrMount(String path) {
    final trimmed = path.trim().replaceAll('\\', '/');
    final lower = trimmed.toLowerCase();
    // WSL /mnt/c, /mnt/d, etc.
    if (RegExp(r'^/mnt/[a-z](/|$)').hasMatch(lower)) {
      return true;
    }
    // Windows drive letter like C:, D:, etc.
    if (RegExp(r'^[a-z]:(/|$)').hasMatch(lower)) {
      return true;
    }
    return false;
  }

  /// Checks whether [targetPath] is equal to or a subdirectory of [basePath].
  bool _isSubPathOrSame(String basePath, String targetPath) {
    final normBase = p.canonicalize(basePath).toLowerCase();
    final normTarget = p.canonicalize(targetPath).toLowerCase();

    if (normTarget == normBase) return true;
    final separator = p.separator;
    return normTarget.startsWith('$normBase$separator') || normTarget.startsWith('$normBase/');
  }

  /// Android system path alias checking:
  /// 1. Internal app data: `/data/user/0/<pkg>` <=> `/data/data/<pkg>`
  /// 2. External shared storage: `/sdcard` <=> `/storage/emulated/0` <=> `/storage/self/primary`
  bool _isAndroidPathAlias(String base, String target) {
    final normBase = p.canonicalize(base).toLowerCase();
    final normTarget = p.canonicalize(target).toLowerCase();

    // 1. /data/user/0 <=> /data/data
    if (normBase.startsWith('/data/user/0/')) {
      final swapped = normBase.replaceFirst('/data/user/0/', '/data/data/');
      if (_isSubPathOrSame(swapped, normTarget)) return true;
    }
    if (normBase.startsWith('/data/data/')) {
      final swapped = normBase.replaceFirst('/data/data/', '/data/user/0/');
      if (_isSubPathOrSame(swapped, normTarget)) return true;
    }

    // 2. /sdcard <=> /storage/emulated/0 <=> /storage/self/primary
    const externalPrefixes = ['/sdcard', '/storage/emulated/0', '/storage/self/primary'];
    for (final basePrefix in externalPrefixes) {
      if (normBase == basePrefix || normBase.startsWith('$basePrefix/')) {
        for (final targetPrefix in externalPrefixes) {
          if (basePrefix != targetPrefix) {
            final swapped = normBase.replaceFirst(basePrefix, targetPrefix);
            if (_isSubPathOrSame(swapped, normTarget)) return true;
          }
        }
      }
    }

    return false;
  }

  /// Comprehensive check whether [path] resolves inside either canonical or real physical sandbox root.
  bool _isPathInsideSandbox(String path) {
    final cSandbox = canonicalSandbox;
    final rSandbox = realSandbox;
    final normPath = p.canonicalize(path);

    return _isSubPathOrSame(cSandbox, normPath) ||
        _isSubPathOrSame(rSandbox, normPath) ||
        _isAndroidPathAlias(cSandbox, normPath) ||
        _isAndroidPathAlias(rSandbox, normPath);
  }

  /// Sanitizes and canonicalizes [rawPath], guaranteeing it resolves strictly inside the sandbox/workspace.
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

    // 2. WSL and Windows mount check
    if (isWindowsDriveOrMount(trimmed)) {
      throw PathSanitizerException('【WSL 环境保护】禁止访问 Windows 挂载盘路径 ("$trimmed")，请在工作区内操作。');
    }

    final normalizedInput = trimmed.replaceAll('\\', '/');

    // 3. If absolute path, check if it resides safely within the workspace
    if (normalizedInput.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(normalizedInput)) {
      final canonicalTarget = p.canonicalize(normalizedInput);
      if (_isPathInsideSandbox(canonicalTarget)) {
        return _computeRelativeInsideSandbox(canonicalTarget);
      }
      throw PathSanitizerException('禁止使用工作区外部绝对路径: "$trimmed"');
    }

    if (normalizedInput.startsWith('~')) {
      throw PathSanitizerException('禁止使用用户根目录波浪号路径: "$trimmed"');
    }

    // 4. Resolve canonical absolute path from relative input
    final targetAbsolute = p.canonicalize(p.join(canonicalSandbox, normalizedInput));

    // 5. Verify that targetAbsolute starts with canonicalSandbox or realSandbox
    if (!_isPathInsideSandbox(targetAbsolute)) {
      throw PathSanitizerException('路径越权违规: 检测到目录遍历试图逃逸沙箱: "$trimmed"');
    }

    // 6. Return normalized relative path
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

    final file = File(p.join(canonicalSandbox, sanitizedRel));

    // Check symlink escape on the file or its parent directories if they exist
    _verifyNoSymlinkEscape(file.path, canonicalSandbox);

    return file;
  }

  /// Resolves a safe [Directory] entity guaranteed to reside within the sandbox.
  Directory resolveSafeDirectory(String relativePath) {
    ensureSandboxExists();
    final sanitizedRel = sanitizeRelativePath(relativePath);
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
        if (!_isPathInsideSandbox(realPath)) {
          throw PathSanitizerException('符号链接逃逸违规: 实体真实物理路径 ($realPath) 位于沙箱外部');
        }
      } else {
        // If target does not exist yet, check the nearest existing parent directory
        var parentDir = Directory(p.dirname(targetPath));
        while (parentDir.existsSync()) {
          final normParent = p.canonicalize(parentDir.path);
          // If parentDir is the sandbox root, we are safely inside!
          if (normParent.toLowerCase() == canonicalSandbox.toLowerCase() ||
              normParent.toLowerCase() == realSandbox.toLowerCase()) {
            break;
          }

          final realParent = p.canonicalize(parentDir.resolveSymbolicLinksSync());
          if (realParent.toLowerCase() == realSandbox.toLowerCase() ||
              realParent.toLowerCase() == canonicalSandbox.toLowerCase()) {
            break;
          }

          if (!_isPathInsideSandbox(realParent)) {
            throw PathSanitizerException('符号链接逃逸违规: 父级目录真实物理路径 ($realParent) 位于沙箱外部');
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
    return _computeRelativeInsideSandbox(p.canonicalize(entity.path));
  }

  /// Computes a clean relative path from [canonicalTarget] to the sandbox root,
  /// accounting for Android internal (/data/user/0 <=> /data/data) and external storage aliases.
  String _computeRelativeInsideSandbox(String canonicalTarget) {
    final cSandbox = canonicalSandbox;
    final rSandbox = realSandbox;

    if (_isSubPathOrSame(cSandbox, canonicalTarget)) {
      final rel = p.relative(canonicalTarget, from: cSandbox).replaceAll('\\', '/');
      return rel.isEmpty ? '.' : rel;
    }
    if (_isSubPathOrSame(rSandbox, canonicalTarget)) {
      final rel = p.relative(canonicalTarget, from: rSandbox).replaceAll('\\', '/');
      return rel.isEmpty ? '.' : rel;
    }
    if (_isAndroidPathAlias(cSandbox, canonicalTarget) || _isAndroidPathAlias(rSandbox, canonicalTarget)) {
      // 1. /data/data <=> /data/user/0
      if (canonicalTarget.startsWith('/data/data/')) {
        final swapped = canonicalTarget.replaceFirst('/data/data/', '/data/user/0/');
        if (_isSubPathOrSame(cSandbox, swapped)) {
          final rel = p.relative(swapped, from: cSandbox).replaceAll('\\', '/');
          return rel.isEmpty ? '.' : rel;
        }
        if (_isSubPathOrSame(rSandbox, swapped)) {
          final rel = p.relative(swapped, from: rSandbox).replaceAll('\\', '/');
          return rel.isEmpty ? '.' : rel;
        }
      }
      if (canonicalTarget.startsWith('/data/user/0/')) {
        final swapped = canonicalTarget.replaceFirst('/data/user/0/', '/data/data/');
        if (_isSubPathOrSame(cSandbox, swapped)) {
          final rel = p.relative(swapped, from: cSandbox).replaceAll('\\', '/');
          return rel.isEmpty ? '.' : rel;
        }
        if (_isSubPathOrSame(rSandbox, swapped)) {
          final rel = p.relative(swapped, from: rSandbox).replaceAll('\\', '/');
          return rel.isEmpty ? '.' : rel;
        }
      }

      // 2. /sdcard <=> /storage/emulated/0 <=> /storage/self/primary
      const externalPrefixes = ['/sdcard', '/storage/emulated/0', '/storage/self/primary'];
      for (final p1 in externalPrefixes) {
        if (canonicalTarget == p1 || canonicalTarget.startsWith('$p1/')) {
          for (final p2 in externalPrefixes) {
            final swapped = canonicalTarget.replaceFirst(p1, p2);
            if (_isSubPathOrSame(cSandbox, swapped)) {
              final rel = p.relative(swapped, from: cSandbox).replaceAll('\\', '/');
              return rel.isEmpty ? '.' : rel;
            }
            if (_isSubPathOrSame(rSandbox, swapped)) {
              final rel = p.relative(swapped, from: rSandbox).replaceAll('\\', '/');
              return rel.isEmpty ? '.' : rel;
            }
          }
        }
      }
    }

    final rel = p.relative(canonicalTarget, from: cSandbox).replaceAll('\\', '/');
    return rel.isEmpty ? '.' : rel;
  }

  /// Checks if [rawPath] points outside the sandbox (e.g. absolute paths, drive letters, ~ or traversal).
  bool isExternalPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == './' || trimmed == '.\\') {
      return false;
    }
    if (isWindowsDriveOrMount(trimmed)) {
      return true;
    }
    final normalized = trimmed.replaceAll('\\', '/');
    if (normalized.startsWith('~')) {
      return true;
    }
    if (normalized.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      final canonicalTarget = p.canonicalize(normalized);
      if (_isPathInsideSandbox(canonicalTarget)) {
        return false;
      }
      return true;
    }
    try {
      final targetAbsolute = p.canonicalize(p.join(canonicalSandbox, normalized));
      return !_isPathInsideSandbox(targetAbsolute);
    } catch (_) {
      return true;
    }
  }

  /// Lists all entities in the sandbox directory.
  List<FileSystemEntity> listSandboxEntities({bool recursive = false}) {
    ensureSandboxExists();
    try {
      return sandboxDir.listSync(recursive: recursive, followLinks: false);
    } catch (_) {
      return [];
    }
  }

  /// Clears all files and subdirectories inside the sandbox directory.
  Future<void> clearSandbox() async {
    ensureSandboxExists();
    try {
      final entities = sandboxDir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          entity.deleteSync(recursive: true);
        } else if (entity is File) {
          entity.deleteSync();
        }
      }
    } catch (_) {}
  }

  /// Resolves direct [File] for authorized host file access when sandbox is disabled or user approved.
  File getDirectFile(String path) {
    return File(path);
  }

  /// Resolves direct [Directory] for authorized host directory access when sandbox is disabled or user approved.
  Directory getDirectDirectory(String path) {
    return Directory(path);
  }
}
