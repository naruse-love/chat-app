import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/native/contact_item.dart';
import 'package:chat/services/native/contacts_service.dart';

void main() {
  group('ContactItem Model Tests', () {
    test('Constructor and getters', () {
      final contact = ContactItem(
        id: 'c-1',
        name: '张三',
        phones: ['13800001111', '010-12345678'],
        emails: ['zhangsan@example.com'],
        company: '示范科技',
        jobTitle: '高级工程师',
        address: '北京市海淀区',
        note: '好友',
      );

      expect(contact.id, 'c-1');
      expect(contact.name, '张三');
      expect(contact.primaryPhone, '13800001111');
      expect(contact.primaryEmail, 'zhangsan@example.com');
      expect(contact.toFormattedString(), contains('👤 张三 (示范科技 · 高级工程师)'));
      expect(contact.toMarkdown(), contains('**张三**'));
      expect(contact.toMarkdown(), contains('示范科技'));
    });

    test('Json serialization & deserialization', () {
      final contact = ContactItem(
        id: 'c-2',
        name: '李四',
        phones: ['13900002222'],
        emails: ['lisi@example.com'],
        company: '极客联盟',
        jobTitle: '产品经理',
        address: '上海市浦东新区',
        note: '合作方对接人',
        metadata: {'vip': true},
      );

      final json = contact.toJson();
      final restored = ContactItem.fromJson(json);

      expect(restored.id, 'c-2');
      expect(restored.name, '李四');
      expect(restored.phones, ['13900002222']);
      expect(restored.emails, ['lisi@example.com']);
      expect(restored.company, '极客联盟');
      expect(restored.jobTitle, '产品经理');
      expect(restored.address, '上海市浦东新区');
      expect(restored.note, '合作方对接人');
      expect(restored.metadata?['vip'], true);
    });
  });

  group('InMemoryContactsService Tests', () {
    late InMemoryContactsService service;

    setUp(() {
      service = InMemoryContactsService(seedDefaults: true);
    });

    test('Loads default seed contacts', () async {
      final contacts = await service.getAllContacts();
      expect(contacts.length, greaterThanOrEqualTo(6));
      expect(contacts.any((c) => c.name == '张伟'), isTrue);
      expect(contacts.any((c) => c.name == 'Alice Smith'), isTrue);
    });

    test('Fuzzy search by name', () async {
      final results = await service.searchContacts('张');
      expect(results.length, greaterThanOrEqualTo(2));
      expect(results.any((c) => c.name == '张伟'), isTrue);
      expect(results.any((c) => c.name == '张强'), isTrue);
    });

    test('Fuzzy search by company', () async {
      final results = await service.searchContacts('未来科技');
      expect(results.length, 2);
      expect(results.every((c) => c.company == '未来科技'), isTrue);
    });

    test('Fuzzy search by phone number', () async {
      final results = await service.searchContacts('13812345678');
      expect(results.length, 1);
      expect(results.first.name, '张伟');

      final partialDigits = await service.searchContacts('55556666');
      expect(partialDigits.first.name, '张强');
    });

    test('Fuzzy search by email', () async {
      final results = await service.searchContacts('acme.global');
      expect(results.length, 1);
      expect(results.first.name, 'Alice Smith');
    });

    test('addContact, getContactById, and resetToDefaultSeed', () async {
      final newContact = ContactItem(
        id: 'new-c-1',
        name: '王小二',
        phones: ['18812345678'],
        company: '测试中心',
      );

      await service.addContact(newContact);
      final found = await service.getContactById('new-c-1');
      expect(found?.name, '王小二');

      await service.resetToDefaultSeed();
      final resetFound = await service.getContactById('new-c-1');
      expect(resetFound, isNull);
    });
  });
}
