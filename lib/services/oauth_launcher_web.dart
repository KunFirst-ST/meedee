import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;
import 'oauth_launcher.dart';

OAuthLauncher createOAuthLauncher() => _WebOAuthLauncher();

class _WebOAuthLauncher implements OAuthLauncher {
  @override
  Uri get callbackUri => Uri.base.resolve('/auth/callback');
  @override
  Stream<Uri> get callbacks => const Stream<Uri>.empty();
  @override
  Future<Uri?> initialCallback() async =>
      Uri.base.path == callbackUri.path ? Uri.base : null;
  @override
  Future<bool> open(Uri uri) => launchUrl(uri, webOnlyWindowName: '_self');
  @override
  void clearCallbackUrl() => web.window.history.replaceState(null, '', '/');
}
