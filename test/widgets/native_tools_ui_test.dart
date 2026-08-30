import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/widgets/chat_bubble.dart';
import 'package:chat/widgets/tool_confirmation_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('ChatBubble Native Tools Metadata & Rendering Tests', () {
    testWidgets('Renders intermediate assistant panel with calendar_query_events', (tester) async {
      final msg = ChatMessage(
        id: 'msg-cal-1',
        conversationId: 'conv-1',
        role: 'assistant',
        content: '我正在为您查询日历日程...',
        timestamp: DateTime(2026, 8, 30, 10, 0),
        toolCalls: [
          ToolCall(
            id: 'call-cal-1',
            type: 'function',
            functionName: 'calendar_query_events',
            arguments: '{"start_time":"2026-08-30"}',
          ),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: msg)));
      await tester.pumpAndSettle();

      expect(find.text('思考与工具调用 [查询日程]'), findsOneWidget);

      // Expand panel
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('查询日程'), findsOneWidget);
      expect(find.text('设备日历'), findsOneWidget);
      expect(find.text('特权 Level 3'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    });

    testWidgets('Renders intermediate assistant panel with calendar_create_event', (tester) async {
      final msg = ChatMessage(
        id: 'msg-cal-2',
        conversationId: 'conv-1',
        role: 'assistant',
        content: '准备创建日程...',
        timestamp: DateTime(2026, 8, 30, 10, 1),
        toolCalls: [
          ToolCall(
            id: 'call-cal-2',
            type: 'function',
            functionName: 'calendar_create_event',
            arguments: '{"title":"团队例会"}',
          ),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: msg)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('创建日程'), findsOneWidget);
      expect(find.text('设备日历'), findsOneWidget);
      expect(find.text('特权 Level 3'), findsOneWidget);
      expect(find.byIcon(Icons.event_available), findsOneWidget);
    });

    testWidgets('Renders notification tools in intermediate assistant panel', (tester) async {
      final msg = ChatMessage(
        id: 'msg-notif',
        conversationId: 'conv-1',
        role: 'assistant',
        content: '处理系统通知...',
        timestamp: DateTime(2026, 8, 30, 10, 2),
        toolCalls: [
          ToolCall(
            id: 'call-notif-1',
            type: 'function',
            functionName: 'notification_schedule',
            arguments: '{"title":"喝水"}',
          ),
          ToolCall(
            id: 'call-notif-2',
            type: 'function',
            functionName: 'notification_cancel',
            arguments: '{"notification_id":"n1"}',
          ),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: msg)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('设置通知'), findsOneWidget);
      expect(find.text('取消通知'), findsOneWidget);
      expect(find.text('系统通知'), findsNWidgets(2));
      expect(find.byIcon(Icons.notification_add), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off), findsOneWidget);
    });

    testWidgets('Renders contacts_search, geolocation_get, and reverse_geocode', (tester) async {
      final msg = ChatMessage(
        id: 'msg-multi',
        conversationId: 'conv-1',
        role: 'assistant',
        content: '定位与通讯录检索...',
        timestamp: DateTime(2026, 8, 30, 10, 3),
        toolCalls: [
          ToolCall(
            id: 'call-contacts',
            type: 'function',
            functionName: 'contacts_search',
            arguments: '{"query":"张"}',
          ),
          ToolCall(
            id: 'call-geo',
            type: 'function',
            functionName: 'geolocation_get',
            arguments: '{}',
          ),
          ToolCall(
            id: 'call-rev',
            type: 'function',
            functionName: 'reverse_geocode',
            arguments: '{"latitude":39.9,"longitude":116.4}',
          ),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: msg)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('搜索通讯录'), findsOneWidget);
      expect(find.text('设备通讯录'), findsOneWidget);
      expect(find.byIcon(Icons.contacts), findsOneWidget);

      expect(find.text('获取当前定位'), findsOneWidget);
      expect(find.text('设备定位'), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      expect(find.text('地理逆编码'), findsOneWidget);
      expect(find.text('地理服务'), findsOneWidget);
      expect(find.text('只读 Level 1'), findsOneWidget);
      expect(find.byIcon(Icons.pin_drop), findsOneWidget);
    });
  });

  group('ToolConfirmationCard Native Privileged Previews & Interaction Tests', () {
    testWidgets('Renders specialized preview for calendar_create_event', (tester) async {
      bool? decisionAllowed;
      String? decisionReason;

      final request = ToolConfirmationRequest(
        confirmationId: 'req-cal-001',
        toolCallId: 'call-cal-001',
        toolName: 'calendar_create_event',
        displayName: '创建日程',
        securityLevel: ToolSecurityLevel.privilegedNative,
        description: '模型请求在设备日历中创建新日程，需要您的确认。',
        arguments: {
          'title': '季度OKR对齐研讨',
          'start_time': '2026-08-30 14:00',
          'end_time': '2026-08-30 16:00',
          'location': '大会议室 801',
          'description': '梳理下季度核心指标',
          'reminder_minutes': 20,
        },
        previewData: {
          'title': '季度OKR对齐研讨',
          'start_time': '2026-08-30 14:00',
          'end_time': '2026-08-30 16:00',
          'location': '大会议室 801',
          'description': '梳理下季度核心指标',
          'reminder_minutes': 20,
          'is_all_day': false,
        },
      );

      await tester.pumpWidget(buildTestableWidget(
        ToolConfirmationCard(
          request: request,
          onDecision: ({required bool allow, String? reason}) {
            decisionAllowed = allow;
            decisionReason = reason;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('创建日程'), findsOneWidget);
      expect(find.text('特权原生'), findsOneWidget);
      expect(find.text('季度OKR对齐研讨'), findsOneWidget);
      expect(find.text('时间: 2026-08-30 14:00 至 2026-08-30 16:00'), findsOneWidget);
      expect(find.text('地点: 大会议室 801'), findsOneWidget);
      expect(find.text('提前 20 分钟提醒'), findsOneWidget);
      expect(find.text('备注: 梳理下季度核心指标'), findsOneWidget);

      // Tap Allow
      await tester.tap(find.text('允许执行'));
      await tester.pumpAndSettle();

      expect(decisionAllowed, isTrue);
      expect(decisionReason, isNull);
    });

    testWidgets('Renders specialized preview for notification_schedule and handles rejection with reason', (tester) async {
      bool? decisionAllowed;
      String? decisionReason;

      final request = ToolConfirmationRequest(
        confirmationId: 'req-notif-001',
        toolCallId: 'call-notif-001',
        toolName: 'notification_schedule',
        displayName: '设置通知',
        securityLevel: ToolSecurityLevel.privilegedNative,
        description: '模型请求设定本地定时提醒，需要您的确认。',
        arguments: {
          'title': '喝水与伸展提醒',
          'body': '已经工作1小时了，起来活动一下吧！',
          'scheduled_time': '2026-08-30 15:00:00',
          'is_exact_alarm': true,
        },
        previewData: {
          'title': '喝水与伸展提醒',
          'body': '已经工作1小时了，起来活动一下吧！',
          'scheduled_time': '2026-08-30 15:00:00',
          'is_exact_alarm': true,
        },
      );

      await tester.pumpWidget(buildTestableWidget(
        ToolConfirmationCard(
          request: request,
          onDecision: ({required bool allow, String? reason}) {
            decisionAllowed = allow;
            decisionReason = reason;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('设置通知'), findsOneWidget);
      expect(find.text('喝水与伸展提醒'), findsOneWidget);
      expect(find.text('已经工作1小时了，起来活动一下吧！'), findsOneWidget);
      expect(find.text('预定时间: 2026-08-30 15:00:00'), findsOneWidget);
      expect(find.text('精确闹钟'), findsOneWidget);

      // Open reason input
      await tester.tap(find.text('拒绝理由'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '我现在正在开会，稍后再提醒');
      await tester.pumpAndSettle();

      // Tap Reject
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      expect(decisionAllowed, isFalse);
      expect(decisionReason, '我现在正在开会，稍后再提醒');
    });
  });
}
