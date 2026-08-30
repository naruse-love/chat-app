import '../../models/native/contact_item.dart';

/// Abstract contract for contacts address book service.
abstract class IContactsService {
  /// Searches contacts matching [query] across name, phones, company, emails, and job title.
  Future<List<ContactItem>> searchContacts(String query, {int limit = 20});

  /// Retrieves all contacts up to [limit].
  Future<List<ContactItem>> getAllContacts({int limit = 50});

  /// Retrieves a specific contact by [id], or null if not found.
  Future<ContactItem?> getContactById(String id);

  /// Adds or updates a contact.
  Future<void> addContact(ContactItem contact);

  /// Resets contacts to the initial sample seed data.
  Future<void> resetToDefaultSeed();
}

/// In-memory mock implementation of [IContactsService] with realistic sample contacts.
class InMemoryContactsService implements IContactsService {
  final Map<String, ContactItem> _contacts = {};

  InMemoryContactsService({bool seedDefaults = true}) {
    if (seedDefaults) {
      _seedDefaultContacts();
    }
  }

  void _seedDefaultContacts() {
    _contacts.clear();
    final seeds = [
      ContactItem(
        id: 'contact-1',
        name: '张伟',
        phones: ['13812345678', '+86 13812345678'],
        emails: ['zhangwei@futuretech.com'],
        company: '未来科技',
        jobTitle: '技术总监',
        address: '北京市海淀区中关村南大街1号',
        note: '核心业务负责人，微信同手机号，负责整体技术架构',
      ),
      ContactItem(
        id: 'contact-2',
        name: '李娜',
        phones: ['13987654321'],
        emails: ['lina@geeksoft.cn'],
        company: '极客软件',
        jobTitle: '产品负责人',
        address: '上海市浦东新区张江高科技园区',
        note: '负责Agent工具平台与移动端交互设计',
      ),
      ContactItem(
        id: 'contact-3',
        name: '王芳',
        phones: ['13600112233'],
        emails: ['wangfang@innovate.org'],
        company: '创新工场',
        jobTitle: '投资总监',
        address: '深圳市南山区科技园',
        note: '关注移动端AI与大模型应用生态',
      ),
      ContactItem(
        id: 'contact-4',
        name: '张强',
        phones: ['13555556666'],
        emails: ['zhangqiang@futuretech.com'],
        company: '未来科技',
        jobTitle: '高级前端架构师',
        address: '北京市朝阳区望京SOHO',
        note: '精通Flutter与原生通道通信',
      ),
      ContactItem(
        id: 'contact-5',
        name: '刘洋',
        phones: ['18611223344', '010-88889999'],
        emails: ['liuyang@chinacloud.com'],
        company: '华云科技',
        jobTitle: '基础设施VP',
        address: '北京市海淀区上地十街',
        note: '机房与服务器运维核心对接人',
      ),
      ContactItem(
        id: 'contact-6',
        name: '陈敏',
        phones: ['13799887766'],
        emails: ['chenmin@openai-hub.cn'],
        company: '极客软件',
        jobTitle: '算法研究员',
        address: '杭州市西湖区文三路',
        note: '负责大模型微调与RAG调优',
      ),
      ContactItem(
        id: 'contact-7',
        name: 'Alice Smith',
        phones: ['+1 (555) 123-4567', '+1 555-0199'],
        emails: ['alice.smith@acme.global'],
        company: 'Acme Corp',
        jobTitle: 'VP of Engineering',
        address: 'San Francisco, CA 94105, USA',
        note: 'Overseas partner technical lead',
      ),
      ContactItem(
        id: 'contact-8',
        name: 'Bob Johnson',
        phones: ['+1 555-0288'],
        emails: ['bob.j@globallogistics.com'],
        company: 'Global Logistics',
        jobTitle: 'Supply Chain Lead',
        address: 'Seattle, WA 98101, USA',
        note: 'Logistics coordination and API integration',
      ),
    ];

    for (final contact in seeds) {
      _contacts[contact.id] = contact;
    }
  }

  @override
  Future<List<ContactItem>> searchContacts(String query, {int limit = 20}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return getAllContacts(limit: limit);
    }

    final queryDigits = cleanQuery.replaceAll(RegExp(r'\D'), '');

    final results = _contacts.values.where((c) {
      // 1. Name match (case-insensitive substring)
      if (c.name.toLowerCase().contains(cleanQuery)) return true;

      // 2. Company match
      if (c.company != null && c.company!.toLowerCase().contains(cleanQuery)) {
        return true;
      }

      // 3. Job title match
      if (c.jobTitle != null && c.jobTitle!.toLowerCase().contains(cleanQuery)) {
        return true;
      }

      // 4. Emails match
      for (final email in c.emails) {
        if (email.toLowerCase().contains(cleanQuery)) return true;
      }

      // 5. Phone match (exact substring or pure digit match)
      for (final phone in c.phones) {
        if (phone.toLowerCase().contains(cleanQuery)) return true;
        if (queryDigits.isNotEmpty) {
          final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
          if (phoneDigits.contains(queryDigits)) return true;
        }
      }

      return false;
    }).toList();

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<List<ContactItem>> getAllContacts({int limit = 50}) async {
    final list = _contacts.values.toList();
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<ContactItem?> getContactById(String id) async {
    return _contacts[id];
  }

  @override
  Future<void> addContact(ContactItem contact) async {
    _contacts[contact.id] = contact;
  }

  @override
  Future<void> resetToDefaultSeed() async {
    _seedDefaultContacts();
  }
}
