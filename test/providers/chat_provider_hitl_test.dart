import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/providers/agent_provider.dart';
import 'package:chat/providers/chat_provider.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/services/agent_service.dart';

class MockMessageDao implements MessageDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockApiConfigDao implements ApiConfigDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAgentService implements AgentService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChatProvider & AgentProvider HITL Tests', () {
    test('AgentState tracks pendingConfirmationRequest and isWaitingConfirmation', () {
      final notifier = AgentNotifier();
      expect(notifier.state.isWaitingConfirmation, isFalse);
      expect(notifier.state.pendingConfirmationRequest, isNull);

      final req = ToolConfirmationRequest(
        confirmationId: 'c_1',
        toolCallId: 't_1',
        toolName: 'file_delete',
        displayName: '沙箱文件删除',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'old.log'},
        description: '删除日志',
        previewData: {'path': 'old.log'},
        status: ToolConfirmationStatus.pending,
      );

      notifier.setPendingConfirmation(req);
      expect(notifier.state.isWaitingConfirmation, isTrue);
      expect(notifier.state.pendingConfirmationRequest, equals(req));

      notifier.clearPendingConfirmation();
      expect(notifier.state.isWaitingConfirmation, isFalse);
      expect(notifier.state.pendingConfirmationRequest, isNull);
    });

    test('ChatNotifier respondToToolConfirmation clears pending state', () async {
      final container = ProviderContainer(
        overrides: [
          messageDaoProvider.overrideWithValue(MockMessageDao()),
          apiConfigDaoProvider.overrideWithValue(MockApiConfigDao()),
          agentServiceProvider.overrideWithValue(MockAgentService()),
        ],
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final agentNotifier = container.read(agentProvider.notifier);

      final req = ToolConfirmationRequest(
        confirmationId: 'conf_abc',
        toolCallId: 't_1',
        toolName: 'code_eval',
        displayName: '代码沙箱执行',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'code': '1+1'},
        description: '测试代码',
        previewData: {'code': '1+1'},
        status: ToolConfirmationStatus.pending,
      );

      agentNotifier.setPendingConfirmation(req);
      expect(container.read(agentProvider).isWaitingConfirmation, isTrue);

      chatNotifier.respondToToolConfirmation('conf_abc', allow: true);
      expect(container.read(agentProvider).isWaitingConfirmation, isFalse);
    });

    test('ChatNotifier respondToToolConfirmation ignores mismatched request ID', () async {
      final container = ProviderContainer(
        overrides: [
          messageDaoProvider.overrideWithValue(MockMessageDao()),
          apiConfigDaoProvider.overrideWithValue(MockApiConfigDao()),
          agentServiceProvider.overrideWithValue(MockAgentService()),
        ],
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final agentNotifier = container.read(agentProvider.notifier);

      final req = ToolConfirmationRequest(
        confirmationId: 'conf_expected',
        toolCallId: 't_1',
        toolName: 'file_delete',
        displayName: '沙箱文件删除',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'important.dat'},
      );

      agentNotifier.setPendingConfirmation(req);
      expect(container.read(agentProvider).isWaitingConfirmation, isTrue);

      // Wrong ID must not clear the pending confirmation
      chatNotifier.respondToToolConfirmation('conf_wrong', allow: true);
      expect(container.read(agentProvider).isWaitingConfirmation, isTrue);

      // Correct ID clears it
      chatNotifier.respondToToolConfirmation('conf_expected', allow: false, reason: '用户拒绝');
      expect(container.read(agentProvider).isWaitingConfirmation, isFalse);
    });

    test('ChatNotifier cancelGeneration clears pending confirmation state', () async {
      final container = ProviderContainer(
        overrides: [
          messageDaoProvider.overrideWithValue(MockMessageDao()),
          apiConfigDaoProvider.overrideWithValue(MockApiConfigDao()),
          agentServiceProvider.overrideWithValue(MockAgentService()),
        ],
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final agentNotifier = container.read(agentProvider.notifier);

      final req = ToolConfirmationRequest(
        confirmationId: 'conf_cancel',
        toolCallId: 't_1',
        toolName: 'file_write',
        displayName: '沙箱文件写入',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'cancel.txt'},
        description: '取消测试',
        previewData: {},
        status: ToolConfirmationStatus.pending,
      );

      agentNotifier.setPendingConfirmation(req);
      expect(container.read(agentProvider).isWaitingConfirmation, isTrue);

      chatNotifier.cancelGeneration();
      expect(container.read(agentProvider).isWaitingConfirmation, isFalse);
    });
  });
}

