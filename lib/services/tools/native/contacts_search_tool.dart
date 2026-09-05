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
  })  : contactsService = contactsService ?? InMemoryContactsService(seedDefaults: false),
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
      final action = arguments['action']?.toString().trim().toLowerCase();
      final nameParam = (arguments['name'] ?? arguments['add_name'])?.toString().trim();
      final phoneParam = (arguments['phone'] ?? arguments['add_phone'])?.toString().trim();

      // Support adding new contacts if action is add or name & phone are provided
      if (action == 'add' || (nameParam != null && phoneParam != null && nameParam.isNotEmpty && phoneParam.isNotEmpty)) {
        if (nameParam == null || nameParam.isEmpty) {
          stopwatch.stop();
          return ToolExecutionResult.failure(
            toolName: name,
            errorMessage: '保存联系人失败: 缺少姓名 (name)',
            content: '保存联系人失败: 缺少有效的联系人姓名',
            executionDuration: stopwatch.elapsed,
          );
        }
        if (phoneParam == null || phoneParam.isEmpty) {
          stopwatch.stop();
          return ToolExecutionResult.failure(
            toolName: name,
            errorMessage: '保存联系人失败: 缺少电话号码 (phone)',
            content: '保存联系人失败: 缺少有效的电话号码',
            executionDuration: stopwatch.elapsed,
          );
        }

        final email = arguments['email']?.toString().trim();
        final company = arguments['company']?.toString().trim();
        final jobTitle = arguments['job_title']?.toString().trim();
        final note = arguments['note']?.toString().trim();
        final address = arguments['address']?.toString().trim();

        final contactItem = ContactItem(
          id: 'contact_${DateTime.now().millisecondsSinceEpoch}',
          name: nameParam,
          phones: [phoneParam],
          emails: (email != null && email.isNotEmpty) ? [email] : const [],
          company: company,
          jobTitle: jobTitle,
          note: note,
          address: address,
        );

        await contactsService.addContact(contactItem);
        stopwatch.stop();

        final maskedPhone = contactsSanitizer.maskPhoneNumber(phoneParam);
        final buffer = StringBuffer();
        buffer.writeln('✅ **联系人已成功保存至通讯录**\n');
        buffer.writeln('- **姓名**: $nameParam');
        buffer.writeln('- **电话**: $maskedPhone');
        if (company != null && company.isNotEmpty) {
          buffer.writeln('- **公司/组织**: $company');
        }
        if (jobTitle != null && jobTitle.isNotEmpty) {
          buffer.writeln('- **职位**: $jobTitle');
        }
        if (email != null && email.isNotEmpty) {
          buffer.writeln('- **邮箱**: $email');
        }

        return ToolExecutionResult.success(
          toolName: name,
          content: buffer.toString().trimRight(),
          rawData: contactItem.toJson(),
          executionDuration: stopwatch.elapsed,
        );
      }

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
