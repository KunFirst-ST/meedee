import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:msu_food2/services/api_client.dart';
import 'package:msu_food2/services/auth_service.dart';
import 'package:msu_food2/services/oauth_launcher.dart';
import 'package:msu_food2/services/session_storage.dart';

class MemoryStorage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class BrowserLauncher implements OAuthLauncher {
  final links = StreamController<Uri>.broadcast();
  Uri? initial;
  Uri? opened;
  void Function()? onOpen;
  @override
  Uri get callbackUri => Uri.parse('msufood://auth/callback');
  @override
  Stream<Uri> get callbacks => links.stream;
  @override
  Future<Uri?> initialCallback() async => initial;
  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    onOpen?.call();
    return true;
  }

  @override
  void clearCallbackUrl() {}
}

Map<String, dynamic> user({
  bool verified = true,
  String provider = 'password',
}) => {
  'uid': 'api-user',
  'displayName': 'Student',
  'email': 'student@example.com',
  'emailVerified': verified,
  'providers': [provider],
  'role': null,
  'shopId': null,
};
http.Response success(dynamic data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response failure(int status, String message) => http.Response(
  jsonEncode({'message': message}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Harness {
  final storage = MemoryStorage();
  final browser = BrowserLauncher();
  final requests = <http.Request>[];
  late final ApiClient api;
  late final AuthService auth;
  Harness(FutureOr<http.Response> Function(http.Request) respond) {
    api = ApiClient(
      baseUrl: 'https://api.example.test/api/v1',
      client: MockClient((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/capabilities')) {
          return success({'googleConfigured': true});
        }
        return respond(r);
      }),
    );
    auth = AuthService(api: api, storage: storage, oauth: browser);
  }
}
