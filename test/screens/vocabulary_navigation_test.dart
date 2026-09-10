import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:chat/app.dart';
import 'package:chat/data/database_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('vocab_nav_test_');
    final dbPath = p.join(tempDir.path, 'app.db');
    db = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.testOnCreate(db, version);
      },
    );
    DatabaseHelper.instance.setMockDatabase(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.instance.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('Drawer contains 📚 单词本 button and navigates to VocabularyScreen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: App(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Drawer via ScaffoldState
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    // Verify '📚 单词本' button is present
    expect(find.text('📚 单词本'), findsOneWidget);

    // Tap the button
    await tester.tap(find.text('📚 单词本'));
    await tester.pumpAndSettle();

    // Verify navigated to VocabularyScreen
    expect(find.text('输入日语单词（如：食べる、美しい）'), findsOneWidget);

    // Drain sqflite lock timer (10s timeout)
    await tester.pump(const Duration(seconds: 11));
  });
}
