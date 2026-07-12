import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:path/path.dart' as p;

abstract class ImagePlatform {
  Future<XFile?> pickImage(ImageSource source);
  Future<Directory> getApplicationSupportDirectory();
  Future<XFile?> compressAndGetFile(
    String sourcePath,
    String targetPath, {
    int? minWidth,
    int? minHeight,
    int? quality,
  });
}

class ProductionImagePlatform implements ImagePlatform {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<XFile?> pickImage(ImageSource source) async {
    return await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
    );
  }

  @override
  Future<Directory> getApplicationSupportDirectory() async {
    return await pp.getApplicationSupportDirectory();
  }

  @override
  Future<XFile?> compressAndGetFile(
    String sourcePath,
    String targetPath, {
    int? minWidth,
    int? minHeight,
    int? quality,
  }) async {
    return await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: minWidth ?? 1024,
      minHeight: minHeight ?? 1024,
      quality: quality ?? 80,
      format: CompressFormat.jpeg,
    );
  }
}

// Exception hierarchy
abstract class ImageServiceException implements Exception {
  final String message;
  const ImageServiceException(this.message);

  @override
  String toString() => message;
}

class ImagePermissionDeniedException extends ImageServiceException {
  const ImagePermissionDeniedException(super.message);
}

class ImagePickerException extends ImageServiceException {
  const ImagePickerException(super.message);
}

class ImageFileNotFoundException extends ImageServiceException {
  const ImageFileNotFoundException(super.message);
}

class ImageCompressionException extends ImageServiceException {
  const ImageCompressionException(super.message);
}

class ImageSaveException extends ImageServiceException {
  const ImageSaveException(super.message);
}

class ImageService {
  final ImagePlatform _platform;

  ImageService({ImagePlatform? platform})
      : _platform = platform ?? ProductionImagePlatform();

  Future<String?> pickImage({required ImageSource source}) async {
    try {
      final XFile? pickedFile = await _platform.pickImage(source);
      return pickedFile?.path;
    } on PlatformException catch (e) {
      if (e.code == 'photo_access_denied' || e.code == 'camera_access_denied') {
        throw ImagePermissionDeniedException(
          'Access to ${source == ImageSource.camera ? "camera" : "gallery"} was denied.'
        );
      }
      throw ImagePickerException('Failed to pick image: ${e.message}');
    } catch (e) {
      throw ImagePickerException('An unexpected error occurred while picking: $e');
    }
  }

  Future<String> compressAndSaveImage({
    required String sourcePath,
    required String messageId,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw ImageFileNotFoundException('Source file not found at: $sourcePath');
    }

    // 1. Resolve target destination directory (support directory)
    String targetPath;
    try {
      final supportDir = await _platform.getApplicationSupportDirectory();
      final imagesDir = Directory(p.join(supportDir.path, 'images'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      targetPath = p.join(imagesDir.path, '$messageId.jpg');
    } catch (e) {
      throw ImageSaveException('Failed to create permanent image folder: $e');
    }

    // 2. Resolve image dimensions to compute aspect-ratio-friendly bounds
    int targetWidth;
    int targetHeight;
    try {
      final bytes = await sourceFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final originalWidth = frameInfo.image.width;
      final originalHeight = frameInfo.image.height;

      targetWidth = originalWidth;
      targetHeight = originalHeight;

      if (originalWidth > 1024 || originalHeight > 1024) {
        if (originalWidth > originalHeight) {
          targetWidth = 1024;
          targetHeight = (originalHeight * 1024 / originalWidth).round();
        } else {
          targetHeight = 1024;
          targetWidth = (originalWidth * 1024 / originalHeight).round();
        }
      }
    } catch (e) {
      throw ImageCompressionException('Failed to decode image dimensions: $e');
    }

    // 3. Iterative quality compression loop targeting size < 1MB
    int quality = 85;
    int fileSize = 0;
    XFile? compressedFile;

    do {
      try {
        compressedFile = await _platform.compressAndGetFile(
          sourcePath,
          targetPath,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: quality,
        );

        if (compressedFile == null) {
          throw const ImageCompressionException('Compression library output was null');
        }

        fileSize = await File(compressedFile.path).length();
        if (fileSize < 1024 * 1024) {
          break; // Compression successful and target file size met
        }
        quality -= 15;
      } catch (e) {
        if (e is ImageServiceException) rethrow;
        throw ImageCompressionException('Failed during image compression: $e');
      }
    } while (quality >= 20);

    if (fileSize >= 1024 * 1024) {
      throw ImageCompressionException(
        'Unable to compress image under 1MB (final size: $fileSize bytes at quality: $quality)'
      );
    }

    return targetPath;
  }

  Future<void> deleteImage(String absolutePath) async {
    try {
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Warning: Failed to delete image file at $absolutePath: $e');
    }
  }
}
