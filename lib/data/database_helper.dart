import 'dart:io';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;

  DatabaseHelper._internal();

  // Allow setting a mock database directly in unit tests
  void setMockDatabase(Database? mockDb) {
    _database = mockDb;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/app_database.db';

    try {
      return await openDatabase(
        path,
        version: 4,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // Recovery logic for database corruption: delete the file and recreate
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      return await openDatabase(
        path,
        version: 4,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE api_configs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        baseUrl TEXT NOT NULL,
        apiKeyRef TEXT NOT NULL,
        isDefault INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        apiConfigId TEXT NOT NULL,
        modelId TEXT NOT NULL,
        systemPrompt TEXT,
        isPinned INTEGER NOT NULL DEFAULT 0,
        isArchived INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (apiConfigId) REFERENCES api_configs (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoningContent TEXT,
        imagePath TEXT,
        toolCalls TEXT,
        toolCallId TEXT,
        promptTokens INTEGER,
        completionTokens INTEGER,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE system_prompts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        description TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await _createMcpServersTable(db);

    await db.execute('''
      CREATE INDEX idx_messages_conversation_id ON messages (conversationId);
    ''');

    await db.execute('''
      CREATE INDEX idx_conversations_pinned_updated ON conversations (isPinned DESC, updatedAt DESC);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_conversations_api_config_id ON conversations (apiConfigId);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages (conversationId, timestamp ASC);
    ''');
  }

  Future<void> _createMcpServersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mcp_servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        transportType TEXT NOT NULL,
        command TEXT,
        arguments TEXT,
        environment TEXT,
        workingDirectory TEXT,
        url TEXT,
        headersRef TEXT,
        isEnabled INTEGER NOT NULL DEFAULT 1,
        autoConnect INTEGER NOT NULL DEFAULT 1,
        defaultSecurityLevel INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE conversations ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE conversations ADD COLUMN isArchived INTEGER NOT NULL DEFAULT 0');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_pinned_updated ON conversations (isPinned DESC, updatedAt DESC);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_api_config_id ON conversations (apiConfigId);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages (conversationId, timestamp ASC);');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN promptTokens INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN completionTokens INTEGER');
    }
    if (oldVersion < 4) {
      await _createMcpServersTable(db);
    }
  }

  // Exposed for testing the onCreate schema creation directly
  Future<void> testOnCreate(Database db, int version) async {
    await _onCreate(db, version);
  }

  // Exposed for testing the onUpgrade schema migration directly
  Future<void> testOnUpgrade(Database db, int oldVersion, int newVersion) async {
    await _onUpgrade(db, oldVersion, newVersion);
  }
}
