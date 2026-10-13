import 'package:web/web.dart' as web;
import 'session_storage.dart';

SessionStorage createSessionStorage() => _TabSessionStorage();

/// Tab lifetime only: do not leave bearer tokens in persistent localStorage.
/// The API uses explicit bearer headers, not ambient authentication cookies.
class _TabSessionStorage implements SessionStorage {
  @override
  Future<String?> read(String key) async =>
      web.window.sessionStorage.getItem('msu_food_$key');
  @override
  Future<void> write(String key, String value) async =>
      web.window.sessionStorage.setItem('msu_food_$key', value);
  @override
  Future<void> delete(String key) async =>
      web.window.sessionStorage.removeItem('msu_food_$key');
}
