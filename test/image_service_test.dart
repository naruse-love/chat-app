import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:chat/services/image_service.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/models/chat_message.dart';
import 'package:path/path.dart' as p;

class MockImagePlatform implements ImagePlatform {
  XFile? Function(ImageSource source)? onPickImage;
  Directory Function()? onGetApplicationSupportDirectory;
  XFile? Function(
    String sourcePath,
    String targetPath, {
    int? minWidth,
    int? minHeight,
    int? quality,
  })? onCompressAndGetFile;

  @override
  Future<XFile?> pickImage(ImageSource source) async {
    if (onPickImage != null) return onPickImage!(source);
    return null;
  }

  @override
  Future<Directory> getApplicationSupportDirectory() async {
    if (onGetApplicationSupportDirectory != null) {
      return onGetApplicationSupportDirectory!();
    }
    throw UnimplementedError();
  }

  @override
  Future<XFile?> compressAndGetFile(
    String sourcePath,
    String targetPath, {
    int? minWidth,
    int? minHeight,
    int? quality,
  }) async {
    if (onCompressAndGetFile != null) {
      return onCompressAndGetFile!(
        sourcePath,
        targetPath,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
      );
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to generate PNG bytes of specific dimensions
  Future<List<int>> generatePngBytes(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  group('ImageService Tests', () {
    late MockImagePlatform mockPlatform;
    late ImageService imageService;
    late Directory tempDir;

    setUp(() async {
      mockPlatform = MockImagePlatform();
      imageService = ImageService(platform: mockPlatform);
      tempDir = await Directory.systemTemp.createTemp('image_service_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('pickImage maps photo_access_denied PlatformException to ImagePermissionDeniedException', () async {
      mockPlatform.onPickImage = (_) => throw PlatformException(
            code: 'photo_access_denied',
            message: 'Permission denied',
          );

      expect(
        () => imageService.pickImage(source: ImageSource.gallery),
        throwsA(isA<ImagePermissionDeniedException>()),
      );
    });

    test('pickImage maps camera_access_denied PlatformException to ImagePermissionDeniedException', () async {
      mockPlatform.onPickImage = (_) => throw PlatformException(
            code: 'camera_access_denied',
            message: 'Permission denied',
          );

      expect(
        () => imageService.pickImage(source: ImageSource.camera),
        throwsA(isA<ImagePermissionDeniedException>()),
      );
    });

    test('pickImage maps general PlatformException to ImagePickerException', () async {
      mockPlatform.onPickImage = (_) => throw PlatformException(
            code: 'other_error',
            message: 'Some other error',
          );

      expect(
        () => imageService.pickImage(source: ImageSource.gallery),
        throwsA(isA<ImagePickerException>()),
      );
    });

    test('pickImage returns null when selection is cancelled', () async {
      mockPlatform.onPickImage = (_) => null;

      final path = await imageService.pickImage(source: ImageSource.gallery);
      expect(path, isNull);
    });

    test('compressAndSaveImage throws ImageFileNotFoundException if source file does not exist', () async {
      expect(
        () => imageService.compressAndSaveImage(
          sourcePath: p.join(tempDir.path, 'non_existent.jpg'),
          messageId: 'msg_123',
        ),
        throwsA(isA<ImageFileNotFoundException>()),
      );
    });

    test('compressAndSaveImage calculates bounds and compresses successfully under 1MB', () async {
      // 1. Generate a mock image of 2048x1024
      final sourceBytes = await generatePngBytes(2048, 1024);
      final sourceFile = File(p.join(tempDir.path, 'source.png'));
      await sourceFile.writeAsBytes(sourceBytes);

      // 2. Set up support directory mock
      final supportDir = Directory(p.join(tempDir.path, 'support'));
      await supportDir.create();
      mockPlatform.onGetApplicationSupportDirectory = () => supportDir;

      // 3. Stub compressor to verify dimensions and write a small file
      int? capturedWidth;
      int? capturedHeight;
      mockPlatform.onCompressAndGetFile = (source, target, {minWidth, minHeight, quality}) {
        capturedWidth = minWidth;
        capturedHeight = minHeight;
        // Mock a 500KB file
        final compressedFile = File(target);
        compressedFile.writeAsBytesSync(List.filled(500 * 1024, 0));
        return XFile(compressedFile.path);
      };

      final resultPath = await imageService.compressAndSaveImage(
        sourcePath: sourceFile.path,
        messageId: 'msg_123',
      );

      // Verify targeted dimensions (scaled preserving 2:1 aspect ratio)
      expect(capturedWidth, 1024);
      expect(capturedHeight, 512);
      expect(resultPath, p.join(supportDir.path, 'images', 'msg_123.jpg'));
      expect(File(resultPath).existsSync(), isTrue);
      expect(File(resultPath).lengthSync(), 500 * 1024);
    });

    test('compressAndSaveImage retry logic: iterative quality compression down to quality 20 until size < 1MB', () async {
      final sourceBytes = await generatePngBytes(2048, 1024);
      final sourceFile = File(p.join(tempDir.path, 'source.png'));
      await sourceFile.writeAsBytes(sourceBytes);

      final supportDir = Directory(p.join(tempDir.path, 'support'));
      await supportDir.create();
      mockPlatform.onGetApplicationSupportDirectory = () => supportDir;

      final qualitiesTried = <int>[];
      mockPlatform.onCompressAndGetFile = (source, target, {minWidth, minHeight, quality}) {
        qualitiesTried.add(quality!);
        final compressedFile = File(target);
        if (quality == 85) {
          // First attempt: 1.5MB (too large)
          compressedFile.writeAsBytesSync(List.filled(1500 * 1024, 0));
        } else if (quality == 70) {
          // Second attempt: 1.2MB (too large)
          compressedFile.writeAsBytesSync(List.filled(1200 * 1024, 0));
        } else if (quality == 55) {
          // Third attempt: 800KB (acceptable)
          compressedFile.writeAsBytesSync(List.filled(800 * 1024, 0));
        }
        return XFile(compressedFile.path);
      };

      final resultPath = await imageService.compressAndSaveImage(
        sourcePath: sourceFile.path,
        messageId: 'msg_123',
      );

      expect(qualitiesTried, [85, 70, 55]);
      expect(File(resultPath).existsSync(), isTrue);
      expect(File(resultPath).lengthSync(), 800 * 1024);
    });

    test('compressAndSaveImage throws ImageCompressionException if size is >= 1MB even at quality 20', () async {
      final sourceBytes = await generatePngBytes(100, 100);
      final sourceFile = File(p.join(tempDir.path, 'source.png'));
      await sourceFile.writeAsBytes(sourceBytes);

      final supportDir = Directory(p.join(tempDir.path, 'support'));
      await supportDir.create();
      mockPlatform.onGetApplicationSupportDirectory = () => supportDir;

      final qualitiesTried = <int>[];
      mockPlatform.onCompressAndGetFile = (source, target, {minWidth, minHeight, quality}) {
        qualitiesTried.add(quality!);
        final compressedFile = File(target);
        // Always return 1.5MB
        compressedFile.writeAsBytesSync(List.filled(1500 * 1024, 0));
        return XFile(compressedFile.path);
      };

      try {
        await imageService.compressAndSaveImage(
          sourcePath: sourceFile.path,
          messageId: 'msg_123',
        );
        fail('Should have thrown ImageCompressionException');
      } catch (e) {
        expect(e, isA<ImageCompressionException>());
      }

      expect(qualitiesTried, [85, 70, 55, 40, 25]);
    });
  });

  group('MessageDao Path Translation Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late MessageDao messageDao;
    late Directory mockSupportDir;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      mockSupportDir = await Directory.systemTemp.createTemp('message_dao_test_support');
      dbHelper = DatabaseHelper.instance;
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbHelper.setMockDatabase(db);
      await dbHelper.testOnCreate(db, 2);

      messageDao = MessageDao(dbHelper, supportDirResolver: () async => mockSupportDir);

      // Seed standard conversation for foreign key
      await db.insert('conversations', {
        'id': 'conv_123',
        'title': 'Test Conv',
        'apiConfigId': 'api_config_123',
        'modelId': 'model_123',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });

    tearDown(() async {
      dbHelper.setMockDatabase(null);
      await db.close();
      await mockSupportDir.delete(recursive: true);
    });

    test('MessageDao translates absolute path to relative path on insert, and back to absolute on load', () async {
      final absoluteImagePath = p.join(mockSupportDir.path, 'images', 'my_image.jpg');
      final message = ChatMessage(
        id: 'msg_001',
        conversationId: 'conv_123',
        role: 'user',
        content: 'Hello with image',
        imagePath: absoluteImagePath,
        timestamp: DateTime.now(),
      );

      // 1. Insert message
      await messageDao.insert(message);

      // 2. Query raw DB to check that the path stored is relative
      final List<Map<String, dynamic>> rawRecords = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg_001'],
      );
      expect(rawRecords.length, 1);
      final rawPath = rawRecords.first['imagePath'] as String;
      expect(rawPath, 'images/my_image.jpg'); // Verify relative path translation!

      // 3. Query through DAO to verify absolute path reconstruction
      final retrieved = await messageDao.getById('msg_001');
      expect(retrieved, isNotNull);
      expect(retrieved!.imagePath, absoluteImagePath); // Restored!

      // 4. Test getMessagesForConversation
      final list = await messageDao.getMessagesForConversation('conv_123');
      expect(list.length, 1);
      expect(list.first.imagePath, absoluteImagePath);
    });

    test('MessageDao does not translate data URLs or pre-existing relative paths', () async {
      const dataUrl = 'data:image/jpeg;base64,QUJD';
      final messageData = ChatMessage(
        id: 'msg_data',
        conversationId: 'conv_123',
        role: 'user',
        content: 'Data url msg',
        imagePath: dataUrl,
        timestamp: DateTime.now(),
      );

      final messageRel = ChatMessage(
        id: 'msg_rel',
        conversationId: 'conv_123',
        role: 'user',
        content: 'Relative path msg',
        imagePath: 'images/pre_existing.jpg',
        timestamp: DateTime.now(),
      );

      await messageDao.insert(messageData);
      await messageDao.insert(messageRel);

      // Verify raw storage
      final rawDataRecord = await db.query('messages', where: 'id = ?', whereArgs: ['msg_data']);
      expect(rawDataRecord.first['imagePath'], dataUrl);

      final rawRelRecord = await db.query('messages', where: 'id = ?', whereArgs: ['msg_rel']);
      expect(rawRelRecord.first['imagePath'], 'images/pre_existing.jpg');

      // Verify query output
      final retrievedData = await messageDao.getById('msg_data');
      expect(retrievedData!.imagePath, dataUrl);

      final retrievedRel = await messageDao.getById('msg_rel');
      expect(retrievedRel!.imagePath, p.join(mockSupportDir.path, 'images', 'pre_existing.jpg'));
    });
  });
}
