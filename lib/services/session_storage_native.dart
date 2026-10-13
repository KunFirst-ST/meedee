import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'session_storage.dart';

SessionStorage createSessionStorage() => _SecureSessionStorage();

class _SecureSessionStorage implements SessionStorage {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: 'msu_food_$key');
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'msu_food_$key', value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: 'msu_food_$key');
}
