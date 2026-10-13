import 'session_storage_native.dart'
    if (dart.library.js_interop) 'session_storage_web.dart'
    as platform;

abstract class SessionStorage {
  static SessionStorage create() => platform.createSessionStorage();
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
