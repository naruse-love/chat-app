import '../models/api_config.dart';
import 'database_helper.dart';
import '../services/secure_storage_service.dart';
import 'package:sqflite/sqflite.dart';

class ApiConfigDao {
  final DatabaseHelper _dbHelper;
  final SecureStorageService _secureStorage;

  ApiConfigDao(this._dbHelper, this._secureStorage);

  Future<void> insert(ApiConfig config, String apiKey) async {
    final db = await _dbHelper.database;

    // Save plaintext apiKey to secure storage
    await _secureStorage.write(config.apiKeyRef, apiKey);

    // Save only API config (including apiKeyRef, excluding plaintext apiKey) to SQLite
    final map = config.toJson();
    map['createdAt'] = config.createdAt.toIso8601String();
    map['isDefault'] = config.isDefault ? 1 : 0;

    try {
      await db.transaction((txn) async {
        if (config.isDefault) {
          await txn.update(
            'api_configs',
            {'isDefault': 0},
          );
        }
        await txn.insert(
          'api_configs',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (e) {
      await _secureStorage.delete(config.apiKeyRef);
      rethrow;
    }
  }

  Future<ApiConfig?> getById(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'api_configs',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final map = Map<String, dynamic>.from(maps.first);
    map['isDefault'] = map['isDefault'] == 1;
    return ApiConfig.fromJson(map);
  }

  Future<String?> getApiKey(String apiKeyRef) async {
    return await _secureStorage.read(apiKeyRef);
  }

  Future<List<ApiConfig>> getAll() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('api_configs');

    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      map['isDefault'] = map['isDefault'] == 1;
      return ApiConfig.fromJson(map);
    }).toList();
  }

  Future<void> delete(String id) async {
    final config = await getById(id);
    if (config != null) {
      // Clean up secure storage
      await _secureStorage.delete(config.apiKeyRef);

      final db = await _dbHelper.database;
      await db.delete(
        'api_configs',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> update(ApiConfig config, {String? apiKey}) async {
    final db = await _dbHelper.database;

    final oldConfig = await getById(config.id);
    if (oldConfig == null) {
      throw ArgumentError('API configuration not found');
    }

    final map = config.toJson();
    map['createdAt'] = config.createdAt.toIso8601String();
    map['isDefault'] = config.isDefault ? 1 : 0;

    if (config.apiKeyRef != oldConfig.apiKeyRef) {
      final keyToWrite = apiKey ?? await _secureStorage.read(oldConfig.apiKeyRef);

      if (keyToWrite != null) {
        await _secureStorage.write(config.apiKeyRef, keyToWrite);
      }

      try {
        await db.transaction((txn) async {
          if (config.isDefault) {
            await txn.update(
              'api_configs',
              {'isDefault': 0},
              where: 'id != ?',
              whereArgs: [config.id],
            );
          }
          await txn.update(
            'api_configs',
            map,
            where: 'id = ?',
            whereArgs: [config.id],
          );
        });
      } catch (e) {
        await _secureStorage.delete(config.apiKeyRef);
        rethrow;
      }

      await _secureStorage.delete(oldConfig.apiKeyRef);
    } else {
      if (apiKey != null) {
        final oldKey = await _secureStorage.read(config.apiKeyRef);
        await _secureStorage.write(config.apiKeyRef, apiKey);
        try {
          await db.transaction((txn) async {
            if (config.isDefault) {
              await txn.update(
                'api_configs',
                {'isDefault': 0},
                where: 'id != ?',
                whereArgs: [config.id],
              );
            }
            await txn.update(
              'api_configs',
              map,
              where: 'id = ?',
              whereArgs: [config.id],
            );
          });
        } catch (e) {
          if (oldKey != null) {
            await _secureStorage.write(config.apiKeyRef, oldKey);
          } else {
            await _secureStorage.delete(config.apiKeyRef);
          }
          rethrow;
        }
      } else {
        await db.transaction((txn) async {
          if (config.isDefault) {
            await txn.update(
              'api_configs',
              {'isDefault': 0},
              where: 'id != ?',
              whereArgs: [config.id],
            );
          }
          await txn.update(
            'api_configs',
            map,
            where: 'id = ?',
            whereArgs: [config.id],
          );
        });
      }
    }
  }

  Future<ApiConfig?> getDefault() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'api_configs',
      where: 'isDefault = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = Map<String, dynamic>.from(maps.first);
    map['isDefault'] = map['isDefault'] == 1;
    return ApiConfig.fromJson(map);
  }
}
