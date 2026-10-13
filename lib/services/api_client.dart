import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? errors;
  const ApiException(this.statusCode, this.message, {this.errors});
  @override
  String toString() => message;
}

/// All application requests use one HTTPS origin. Tokens never appear in URLs.
class ApiClient {
  static final instance = ApiClient();
  final String baseUrl;
  final http.Client _http;
  final Duration timeout;
  String? bearerToken;
  Future<void> Function()? onUnauthorized;

  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE_URL'))
           .replaceFirst(RegExp(r'/+$'), ''),
       _http = client ?? http.Client();

  void validateConfiguration() {
    final uri = Uri.tryParse(baseUrl);
    final loopback =
        uri != null &&
        const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw const ApiException(
        0,
        'ยังไม่ได้กำหนดที่อยู่ API แบบ HTTPS กรุณาให้ผู้ดูแลเชื่อมต่อเซิร์ฟเวอร์ก่อนใช้งาน',
      );
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    validateConfiguration();
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw const ApiException(0, 'เส้นทาง API ไม่ถูกต้อง');
    }
    final uri = Uri.parse('$baseUrl$path');
    final token = bearerToken;
    final request = http.Request(method.toUpperCase(), uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _http.send(request).timeout(timeout);
      final bytes = await response.stream.toBytes().timeout(timeout);
      Map<String, dynamic>? envelope;
      try {
        final parsed = jsonDecode(utf8.decode(bytes));
        if (parsed is Map<String, dynamic>) envelope = parsed;
      } on FormatException {
        // HTML errors and reverse-proxy responses must not count as success.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 &&
            token != null &&
            token == bearerToken) {
          await onUnauthorized?.call();
        }
        throw ApiException(
          response.statusCode,
          envelope?['message'] is String
              ? envelope!['message'] as String
              : _statusMessage(response.statusCode),
          errors: envelope?['errors'] is Map<String, dynamic>
              ? envelope!['errors'] as Map<String, dynamic>
              : null,
        );
      }
      if (response.statusCode == 204) return null;
      if (envelope == null || !envelope.containsKey('data')) {
        throw const ApiException(
          502,
          'เซิร์ฟเวอร์ส่งข้อมูลไม่ครบ กรุณาลองอีกครั้ง',
        );
      }
      return envelope['data'];
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        0,
        'เซิร์ฟเวอร์ตอบช้า กรุณาตรวจการเชื่อมต่อแล้วลองใหม่',
      );
    } catch (_) {
      throw const ApiException(
        0,
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองใหม่',
      );
    }
  }

  static String _statusMessage(int status) => switch (status) {
    401 => 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
    403 => 'บัญชีนี้ยังไม่มีสิทธิ์ดำเนินการ',
    404 => 'ไม่พบข้อมูลที่ต้องการ',
    409 => 'ข้อมูลเปลี่ยนแปลง กรุณาโหลดใหม่แล้วลองอีกครั้ง',
    422 => 'กรุณาตรวจข้อมูลที่กรอกแล้วลองใหม่',
    429 => 'มีคำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่',
    503 => 'บริการนี้ยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง',
    _ => 'เซิร์ฟเวอร์ดำเนินการไม่สำเร็จ กรุณาลองใหม่',
  };
}
