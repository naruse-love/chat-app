import '../../../models/native/native_models.dart';
import '../../../models/tool/tool.dart';
import '../../native/contacts_sanitizer.dart';
import '../../native/contacts_service.dart';
import '../../native/permission_manager_service.dart';

/// Privacy-sanitized contacts search tool [Level 3 Privileged].
///
/// Searches contacts from the address book, applying E.164 phone masking,
/// strict whitelist filtering, and prompt injection defense.
class ContactsSearchTool extends Tool {
  final IContactsService contactsService;
  final ContactsSanitizer contactsSanitizer;
  final PermissionManagerService permissionService;

  ContactsSearchTool({
    IContactsService? contactsService,
    ContactsSanitizer? contactsSanitizer,
    PermissionManagerService? permissionService,
  })  : contactsService = contactsService ?? InMemoryContactsService(),
        contactsSanitizer = contactsSanitizer ?? const ContactsSanitizer(),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'contacts_search';

  @override
  String get displayName => '搜索通讯录';

  @override
  String get description =>
      'Searches contacts from the device address book. Privacy-sanitized with E.164 phone masking, strict whitelist filtering, and prompt injection defense. Maximum 5 results.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'query',
          type: 'string',
          description: '联系人搜索关键词 (可匹配姓名、公司、职位、邮箱或手机号，留空时查询前列联系人)',
          required: false,
          defaultValue: '',
        ),
        ToolParameter(
          name: 'limit',
          type: 'integer',
          description: '返回结果数量上限 (默认 5，根据隐私规则最大限制 5 条)',
          required: false,
          defaultValue: 5,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.contacts);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.contacts);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'contacts', 'granted': false},
      );
    }

    try {
      final query = arguments['query']?.toString().trim() ?? '';
      final rawLimit = (arguments['limit'] as num?)?.toInt() ?? 5;
      final effectiveLimit = (rawLimit > 0 && rawLimit <= 5) ? rawLimit : 5;

      final rawContacts = await contactsService.searchContacts(query, limit: 20);
      final sanitizeResult = contactsSanitizer.sanitizeContactList(
        rawContacts,
        maxLimit: effectiveLimit,
      );

      stopwatch.stop();

      final markdown = sanitizeResult.toMarkdown();

      return ToolExecutionResult.success(
        toolName: name,
        content: markdown,
        rawData: sanitizeResult.toJson(),
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'totalFound': sanitizeResult.totalFound,
          'returnedCount': sanitizeResult.items.length,
          'isTruncated': sanitizeResult.isTruncated,
        },
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '检索通讯录发生异常: $e',
        content: '检索通讯录发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}
