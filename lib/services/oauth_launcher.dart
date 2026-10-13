import 'oauth_launcher_native.dart'
    if (dart.library.js_interop) 'oauth_launcher_web.dart'
    as platform;

abstract class OAuthLauncher {
  static OAuthLauncher create() => platform.createOAuthLauncher();
  Uri get callbackUri;
  Stream<Uri> get callbacks;
  Future<Uri?> initialCallback();
  Future<bool> open(Uri uri);
  void clearCallbackUrl();
}
