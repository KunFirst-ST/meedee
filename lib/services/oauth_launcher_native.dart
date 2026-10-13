import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'oauth_launcher.dart';

OAuthLauncher createOAuthLauncher() => _NativeOAuthLauncher();

class _NativeOAuthLauncher implements OAuthLauncher {
  final _links = AppLinks();
  @override
  Uri get callbackUri => Uri.parse('msufood://auth/callback');
  @override
  Stream<Uri> get callbacks => _links.uriLinkStream;
  @override
  Future<Uri?> initialCallback() => _links.getInitialLink();
  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  @override
  void clearCallbackUrl() {}
}
