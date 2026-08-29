import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';

void main() {
  group('ToolConfirmationStatus Enum Tests', () {
    test('serializes and deserializes correctly', () {
      expect(ToolConfirmationStatus.pending.toJson(), equals('pending'));
      expect(ToolConfirmationStatus.approved.toJson(), equals('approved'));
      expect(ToolConfirmationStatus.rejected.toJson(), equals('rejected'));
      expect(ToolConfirmationStatus.cancelled.toJson(), equals('cancelled'));

      expect(ToolConfirmationStatus.fromJson('pending'), equals(ToolConfirmationStatus.pending));
      expect(ToolConfirmationStatus.fromJson('approved'), equals(ToolConfirmationStatus.approved));
      expect(ToolConfirmationStatus.fromJson('rejected'), equals(ToolConfirmationStatus.rejected));
      expect(ToolConfirmationStatus.fromJson('cancelled'), equals(ToolConfirmationStatus.cancelled));
      expect(ToolConfirmationStatus.fromJson('unknown'), equals(ToolConfirmationStatus.pending));
    });
  });

  group('ToolConfirmationDecision Tests', () {
    test('approve constructor initializes with isApproved = true', () {
      final decision = ToolConfirmationDecision.approve();
      expect(decision.isApproved, isTrue);
      expect(decision.rejectionReason, isNull);
      expect(decision.timestamp, isNotNull);

      final json = decision.toJson();
      expect(json['isApproved'], isTrue);
      expect(json['rejectionReason'], isNull);

      final fromJson = ToolConfirmationDecision.fromJson(json);
      expect(fromJson.isApproved, isTrue);
      expect(fromJson.rejectionReason, isNull);
    });

    test('reject constructor initializes with isApproved = false and reason', () {
      final decision = ToolConfirmationDecision.reject('操作存在安全风险');
      expect(decision.isApproved, isFalse);
      expect(decision.rejectionReason, equals('操作存在安全风险'));

      final json = decision.toJson();
      expect(json['isApproved'], isFalse);
      expect(json['rejectionReason'], equals('操作存在安全风险'));

      final fromJson = ToolConfirmationDecision.fromJson(json);
      expect(fromJson.isApproved, isFalse);
      expect(fromJson.rejectionReason, equals('操作存在安全风险'));
    });

    test('cancel constructor initializes with cancellation reason', () {
      final decision = ToolConfirmationDecision.cancel('用户中断会话');
      expect(decision.isApproved, isFalse);
      expect(decision.rejectionReason, equals('用户中断会话'));
    });
  });

  group('ToolConfirmationRequest Tests', () {
    test('initializes with default and custom properties', () {
      final request = ToolConfirmationRequest(
        confirmationId: 'conf_001',
        toolCallId: 'call_123',
        toolName: 'file_write',
        displayName: '写入文件',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'notes/todo.md', 'content': 'Hello world'},
        description: '在沙箱中创建或修改文件',
        previewData: {'diff': '+ Hello world'},
      );

      expect(request.confirmationId, equals('conf_001'));
      expect(request.toolCallId, equals('call_123'));
      expect(request.toolName, equals('file_write'));
      expect(request.displayName, equals('写入文件'));
      expect(request.securityLevel, equals(ToolSecurityLevel.sensitiveConfirm));
      expect(request.status, equals(ToolConfirmationStatus.pending));
      expect(request.decision, isNull);

      // JSON serialization roundtrip
      final json = request.toJson();
      expect(json['confirmationId'], equals('conf_001'));
      expect(json['toolName'], equals('file_write'));
      expect(json['securityLevel'], equals('sensitiveConfirm'));
      expect(json['status'], equals('pending'));

      final deserialized = ToolConfirmationRequest.fromJson(json);
      expect(deserialized.confirmationId, equals('conf_001'));
      expect(deserialized.toolName, equals('file_write'));
      expect(deserialized.arguments['path'], equals('notes/todo.md'));
      expect(deserialized.status, equals(ToolConfirmationStatus.pending));
    });

    test('copyWith properly updates status and decision', () {
      final original = ToolConfirmationRequest(
        confirmationId: 'conf_002',
        toolCallId: 'call_456',
        toolName: 'file_delete',
        displayName: '删除文件',
        arguments: {'path': 'temp.txt'},
      );

      final decision = ToolConfirmationDecision.approve();
      final updated = original.copyWith(
        status: ToolConfirmationStatus.approved,
        decision: decision,
      );

      expect(updated.confirmationId, equals('conf_002'));
      expect(updated.status, equals(ToolConfirmationStatus.approved));
      expect(updated.decision?.isApproved, isTrue);
      expect(original.status, equals(ToolConfirmationStatus.pending));
    });
  });
}
