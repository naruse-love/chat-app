import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/update_model.dart';
import 'package:chat/widgets/update_dialog.dart';

void main() {
  testWidgets('UpdateDialog 正常渲染版本信息与操作按钮', (tester) async {
    const updateInfo = UpdateInfo(
      currentVersion: '1.43.0+44',
      latestVersion: 'v1.44.0',
      hasUpdate: true,
      releaseNotes: '### 更新内容\n- 修复已知缺陷\n- 新增特性',
      downloadUrl: 'https://example.com/app.apk',
      fileSize: 20 * 1024 * 1024,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UpdateDialog(updateInfo: updateInfo),
          ),
        ),
      ),
    );

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('1.43.0+44 → v1.44.0'), findsOneWidget);
    expect(find.text('包体大小: 20.0 MB'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);
    expect(find.text('前往发布页'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });
}
