import '../../models/native/contact_item.dart';

/// Represents a privacy-sanitized contact safe for LLM context and tool returns.
/// Sensitive fields (addresses, private notes, unmasked phone numbers) are stripped.
class SanitizedContactItem {
  final String id;
  final String name;
  final List<String> maskedPhones;
  final List<String> emails;
  final String? company;

  const SanitizedContactItem({
    required this.id,
    required this.name,
    required this.maskedPhones,
    required this.emails,
    this.company,
  });

  /// Single line formatted view.
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write("👤 $name");
    if (company != null && company!.isNotEmpty) {
      buffer.write(" ($company)");
    }
    if (maskedPhones.isNotEmpty) {
      buffer.write(" | 📞 ${maskedPhones.join(', ')}");
    }
    if (emails.isNotEmpty) {
      buffer.write(" | ✉️ ${emails.join(', ')}");
    }
    return buffer.toString();
  }

  /// Formats this sanitized contact into clean Markdown.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln("- **$name**");
    if (company != null && company!.isNotEmpty) {
      buffer.writeln("  - **公司/组织**: $company");
    }
    if (maskedPhones.isNotEmpty) {
      buffer.writeln("  - **电话 (脱敏)**: ${maskedPhones.join(', ')}");
    }
    if (emails.isNotEmpty) {
      buffer.writeln("  - **邮箱**: ${emails.join(', ')}");
    }
    buffer.writeln("  - **联系人ID**: `$id`");
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'maskedPhones': maskedPhones,
      'emails': emails,
      if (company != null) 'company': company,
    };
  }

  factory SanitizedContactItem.fromJson(Map<String, dynamic> json) {
    return SanitizedContactItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名联系人',
      maskedPhones: (json['maskedPhones'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      emails: (json['emails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      company: json['company'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SanitizedContactItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          company == other.company;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ company.hashCode;

  @override
  String toString() => 'SanitizedContactItem($name, $company, $maskedPhones)';
}

/// Result of contacts sanitization, including truncation metadata.
class SanitizeResult {
  final List<SanitizedContactItem> items;
  final int totalFound;
  final bool isTruncated;
  final String? truncationNote;

  const SanitizeResult({
    required this.items,
    required this.totalFound,
    required this.isTruncated,
    this.truncationNote,
  });

  /// Formats the sanitized result into Markdown for LLM output.
  String toMarkdown() {
    if (items.isEmpty) {
      return "未找到匹配的联系人信息。";
    }

    final buffer = StringBuffer();
    buffer.writeln("找到以下联系人信息（已执行隐私脱敏与安全过滤）：\n");
    for (final item in items) {
      buffer.writeln(item.toMarkdown());
    }

    if (isTruncated && truncationNote != null) {
      buffer.writeln("\n> 💡 **提示**: $truncationNote");
    }

    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'totalFound': totalFound,
      'isTruncated': isTruncated,
      if (truncationNote != null) 'truncationNote': truncationNote,
    };
  }
}

/// Privacy Data Sanitizer Gateway.
/// Provides E.164 phone masking, strict whitelist filtering, prompt injection defense,
/// and a hard 5-result limit.
class ContactsSanitizer {
  static const int defaultMaxResults = 5;

  const ContactsSanitizer();

  /// Masks a phone number preserving country/area code and masking the middle digits.
  /// Examples:
  /// - "+86 13812345678" -> "+86 138****5678"
  /// - "+86-13812345678" -> "+86-138****5678"
  /// - "13812345678"     -> "138****5678"
  /// - "010-88889999"    -> "010-****9999"
  /// - "(010) 88889999"  -> "(010) ****9999"
  /// - "+1 555-1234567"  -> "+1 555-****4567"
  String maskPhoneNumber(String rawPhone) {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) return trimmed;

    // Check for country code prefix like +86, +1, etc.
    final countryCodeMatch = RegExp(r'^(\+\d{1,4}[\s\-]?)').firstMatch(trimmed);
    String prefix = '';
    String remaining = trimmed;

    if (countryCodeMatch != null) {
      prefix = countryCodeMatch.group(1)!;
      remaining = trimmed.substring(countryCodeMatch.end);
    }

    // Check for area code prefix like (010) or 010-
    final areaCodeMatch = RegExp(r'^(\(\d{2,4}\)[\s\-]?|\d{3,4}[\-])').firstMatch(remaining);
    if (areaCodeMatch != null) {
      prefix += areaCodeMatch.group(1)!;
      remaining = remaining.substring(areaCodeMatch.end);
    }

    // Extract digits in remaining part
    final digits = remaining.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 11) {
      // Standard 11-digit mobile: 3 head, 4 tail
      final head = digits.substring(0, 3);
      final tail = digits.substring(7);
      return "$prefix$head****$tail";
    } else if (digits.length >= 12) {
      // 12+ digits: keep first 3, mask middle, keep last 4
      final head = digits.substring(0, 3);
      final tail = digits.substring(digits.length - 4);
      return "$prefix$head****$tail";
    } else if (digits.length == 7 || digits.length == 8) {
      // 7-8 digits local phone number
      if (prefix.isNotEmpty) {
        // Area code or country code already present: mask local prefix and keep last 4 digits
        final tail = digits.substring(digits.length - 4);
        return "$prefix****$tail";
      } else {
        final head = digits.substring(0, 2);
        final tail = digits.substring(digits.length - 2);
        return "$head****$tail";
      }
    } else if (digits.length >= 9) {
      final head = digits.substring(0, 3);
      final tail = digits.substring(digits.length - 4);
      return "$prefix$head****$tail";
    } else if (digits.length >= 5) {
      // 5-6 digits: keep 2 head, 2 tail
      final head = digits.substring(0, 2);
      final tail = digits.substring(digits.length - 2);
      return "$prefix$head****$tail";
    } else if (digits.length >= 3) {
      final head = digits.substring(0, 1);
      final tail = digits.substring(digits.length - 1);
      return "$prefix$head**$tail";
    }

    return trimmed;
  }

  /// Sanitizes text to defend against prompt injection, control tokens, and markdown exploits.
  String sanitizeText(String? input) {
    if (input == null) return '';
    var text = input.trim();

    // 1. Remove null bytes and control chars (except \n, \t)
    text = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // 2. Neutralize Tool Calling & System tokens
    text = text.replaceAll(RegExp(r'<\/?tool_call>', caseSensitive: false), '[tool_call_tag]');
    text = text.replaceAll(RegExp(r'<\/?system>', caseSensitive: false), '[system_tag]');
    text = text.replaceAll(RegExp(r'\[\/?INST\]', caseSensitive: false), '[inst_tag]');
    text = text.replaceAll(RegExp(r'<\/?｜｜DSML｜｜tool_calls>', caseSensitive: false), '[dsml_tag]');
    text = text.replaceAll(RegExp(r'<\/?user>', caseSensitive: false), '[user_tag]');
    text = text.replaceAll(RegExp(r'<\/?assistant>', caseSensitive: false), '[assistant_tag]');

    // 3. Neutralize curly braces to prevent template injection / JSON format hijacking
    text = text.replaceAll('{', '｛').replaceAll('}', '｝');

    // 4. Neutralize markdown image/link injection exploits (e.g. javascript:, data:, vbscript:)
    text = text.replaceAll(RegExp(r'javascript:', caseSensitive: false), 'javascript_:');
    text = text.replaceAll(RegExp(r'data:text\/html', caseSensitive: false), 'data_html:');
    text = text.replaceAll(RegExp(r'vbscript:', caseSensitive: false), 'vbscript_:');

    return text;
  }

  /// Sanitizes a single [ContactItem] into a [SanitizedContactItem] using strict whitelist.
  SanitizedContactItem sanitizeContact(ContactItem contact) {
    final cleanName = sanitizeText(contact.name);
    final cleanCompany = contact.company != null ? sanitizeText(contact.company!) : null;

    final maskedPhones = contact.phones.map((p) => maskPhoneNumber(p)).toList();
    final cleanEmails = contact.emails.map((e) => sanitizeText(e)).toList();

    return SanitizedContactItem(
      id: contact.id,
      name: cleanName.isNotEmpty ? cleanName : '未命名联系人',
      maskedPhones: maskedPhones,
      emails: cleanEmails,
      company: cleanCompany,
    );
  }

  /// Sanitizes a list of [ContactItem]s, applying strict whitelist filtering, prompt injection defense,
  /// and capping output to [maxLimit] (default 5).
  SanitizeResult sanitizeContactList(
    List<ContactItem> contacts, {
    int maxLimit = defaultMaxResults,
  }) {
    final total = contacts.length;
    final isTruncated = total > maxLimit;
    final rawSlice = isTruncated ? contacts.sublist(0, maxLimit) : contacts;

    final sanitizedItems = rawSlice.map((c) => sanitizeContact(c)).toList();

    String? note;
    if (isTruncated) {
      note = "共匹配到 $total 位联系人，根据隐私安全规则仅展示前 $maxLimit 条脱敏结果。如需查找特定联系人，请提供更精确的姓名或所属公司。";
    }

    return SanitizeResult(
      items: sanitizedItems,
      totalFound: total,
      isTruncated: isTruncated,
      truncationNote: note,
    );
  }
}
