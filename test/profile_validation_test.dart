import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/services/db.dart';

void main() {
  test('profile names trim surrounding whitespace and respect the limit', () {
    expect(ProfileValidation.normalizeName('  กานต์  '), 'กานต์');
    expect(ProfileValidation.normalizeName('ก' * 120), 'ก' * 120);
    for (final name in ['', ' \n\t ', 'ก' * 121]) {
      expect(
        () => ProfileValidation.normalizeName(name),
        throwsA(isA<ProfileValidationException>()),
      );
    }
  });

  test(
    'optional profile phone is stored in canonical digits with a leading +',
    () {
      expect(ProfileValidation.normalizePhone(''), '');
      expect(ProfileValidation.normalizePhone('  '), '');
      expect(ProfileValidation.normalizePhone('081-234-5678'), '0812345678');
      expect(
        ProfileValidation.normalizePhone(' +66 (81) 234-5678 '),
        '+66812345678',
      );
      expect(ProfileValidation.normalizePhone('12345678'), '12345678');
      expect(
        ProfileValidation.normalizePhone('+123456789012345'),
        '+123456789012345',
      );
      for (final phone in [
        '1234567',
        '1234567890123456',
        '++66812345678',
        '0812345678 ext 9',
        '0812abc678',
        '๐๘๑๒๓๔๕๖๗๘',
      ]) {
        expect(
          () => ProfileValidation.normalizePhone(phone),
          throwsA(isA<ProfileValidationException>()),
        );
      }
    },
  );
}
