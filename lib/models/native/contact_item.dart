import 'package:uuid/uuid.dart';

/// Represents a raw contact item from the device address book.
/// Note: Sensitive fields (note, address, unmasked phones) MUST be filtered by
/// ContactsSanitizer before exposing to LLMs.
class ContactItem {
  final String id;
  final String name;
  final List<String> phones;
  final List<String> emails;
  final String? company;
  final String? jobTitle;
  final String? address;
  final String? note;
  final Map<String, dynamic>? metadata;

  ContactItem({
    String? id,
    required this.name,
    this.phones = const [],
    this.emails = const [],
    this.company,
    this.jobTitle,
    this.address,
    this.note,
    this.metadata,
  }) : id = id ?? const Uuid().v4();

  /// Primary phone number or null if empty.
  String? get primaryPhone => phones.isNotEmpty ? phones.first : null;

  /// Primary email or null if empty.
  String? get primaryEmail => emails.isNotEmpty ? emails.first : null;

  /// Formatted single-line overview.
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write("👤 $name");
    if (company != null && company!.isNotEmpty) {
      buffer.write(" (${company!}${jobTitle != null ? ' · $jobTitle' : ''})");
    }
    if (phones.isNotEmpty) {
      buffer.write(" | 📞 ${phones.join(', ')}");
    }
    if (emails.isNotEmpty) {
      buffer.write(" | ✉️ ${emails.join(', ')}");
    }
    return buffer.toString();
  }

  /// Formats raw contact into Markdown.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln("- **$name**");
    if (company != null && company!.isNotEmpty) {
      buffer.writeln("  - **公司**: $company${jobTitle != null ? ' ($jobTitle)' : ''}");
    }
    if (phones.isNotEmpty) {
      buffer.writeln("  - **电话**: ${phones.join(', ')}");
    }
    if (emails.isNotEmpty) {
      buffer.writeln("  - **邮箱**: ${emails.join(', ')}");
    }
    if (address != null && address!.isNotEmpty) {
      buffer.writeln("  - **地址**: $address");
    }
    if (note != null && note!.isNotEmpty) {
      buffer.writeln("  - **备注**: $note");
    }
    buffer.writeln("  - **联系人ID**: `$id`");
    return buffer.toString().trimRight();
  }

  ContactItem copyWith({
    String? id,
    String? name,
    List<String>? phones,
    List<String>? emails,
    String? company,
    String? jobTitle,
    String? address,
    String? note,
    Map<String, dynamic>? metadata,
    bool clearCompany = false,
    bool clearJobTitle = false,
    bool clearAddress = false,
    bool clearNote = false,
  }) {
    return ContactItem(
      id: id ?? this.id,
      name: name ?? this.name,
      phones: phones ?? List.from(this.phones),
      emails: emails ?? List.from(this.emails),
      company: clearCompany ? null : (company ?? this.company),
      jobTitle: clearJobTitle ? null : (jobTitle ?? this.jobTitle),
      address: clearAddress ? null : (address ?? this.address),
      note: clearNote ? null : (note ?? this.note),
      metadata: metadata ?? (this.metadata != null ? Map.from(this.metadata!) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phones': phones,
      'emails': emails,
      if (company != null) 'company': company,
      if (jobTitle != null) 'jobTitle': jobTitle,
      if (address != null) 'address': address,
      if (note != null) 'note': note,
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory ContactItem.fromJson(Map<String, dynamic> json) {
    return ContactItem(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '未命名联系人',
      phones: (json['phones'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      emails: (json['emails'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      company: json['company'] as String?,
      jobTitle: json['jobTitle'] as String?,
      address: json['address'] as String?,
      note: json['note'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          company == other.company &&
          jobTitle == other.jobTitle &&
          address == other.address &&
          note == other.note;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      company.hashCode ^
      jobTitle.hashCode ^
      address.hashCode ^
      note.hashCode;

  @override
  String toString() => 'ContactItem(id: $id, name: $name, company: $company)';
}
