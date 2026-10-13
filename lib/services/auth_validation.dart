class AuthValidation {
  static String normalizeEmail(String value) => value.trim().toLowerCase();
  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'กรุณากรอกอีเมล';
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'กรุณากรอกอีเมลให้ถูกต้อง';
    }
    return null;
  }

  static String? name(String? value) {
    final name = (value ?? '').trim();
    return name.isEmpty || name.length > 120
        ? 'ชื่อผู้ใช้ต้องมี 1–120 ตัวอักษร'
        : null;
  }

  static String? loginPassword(String? value) =>
      (value ?? '').isEmpty ? 'กรุณากรอกรหัสผ่าน' : null;
  static String? password(String? value) {
    final password = value ?? '';
    if (password.trim().isEmpty || password.length < 8) {
      return 'ใช้รหัสผ่านอย่างน้อย 8 ตัวอักษร';
    }
    if (password.length > 128) return 'รหัสผ่านต้องไม่เกิน 128 ตัวอักษร';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'กรุณายืนยันรหัสผ่าน';
    return value == password ? null : 'รหัสผ่านทั้งสองช่องไม่ตรงกัน';
  }

  static String normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  static String? phone(String? value) {
    final phone = normalizePhone(value ?? '');
    return phone.isEmpty || RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)
        ? null
        : 'กรอกเบอร์โทร 8–15 หลัก หรือเว้นว่าง';
  }
}
