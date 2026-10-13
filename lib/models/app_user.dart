import 'package:flutter/foundation.dart';

/// Identity returned by the application's API, independent of auth vendors.
@immutable
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool emailVerified;
  final List<String> providers;
  final String? phone;
  final String? role;
  final String? shopId;

  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.emailVerified = false,
    this.providers = const [],
    this.phone,
    this.role,
    this.shopId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    if (uid is! String || uid.trim().isEmpty) {
      throw const FormatException('The API did not return a user identity.');
    }
    return AppUser(
      uid: uid,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      emailVerified: json['emailVerified'] == true,
      providers: List<String>.unmodifiable(
        (json['providers'] as List? ?? const []).cast<String>(),
      ),
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      shopId: json['shopId'] as String?,
    );
  }

  bool get hasPassword => providers.contains('password');
}
