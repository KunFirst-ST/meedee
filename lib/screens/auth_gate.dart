import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../widgets/food_ui.dart';
import 'login_screen.dart';
import 'role_gate.dart';
import 'email_verification_screen.dart';

class AuthGate extends StatefulWidget {
  final AuthService? authService;
  final Widget Function(AppUser)? authenticatedBuilder;
  const AuthGate({super.key, this.authService, this.authenticatedBuilder});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = widget.authService ?? AuthService.instance;
  late Stream<AppUser?> _users = _auth.userChanges;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppUser?>(
    stream: _users,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: StatePanel(
            title: 'เชื่อมต่อบัญชีไม่ได้',
            message: 'ตรวจการเชื่อมต่อแล้วลองอีกครั้ง',
            action: 'ลองใหม่',
            onAction: () => setState(() => _users = _auth.userChanges),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      // Login and restored sessions are accepted only from an API response.
      final user = snapshot.data;
      if (user == null) return LoginScreen(authService: _auth);
      if (AuthService.requiresEmailVerification(user)) {
        return EmailVerificationScreen(
          key: ValueKey('verify_${user.uid}'),
          user: user,
          authService: _auth,
        );
      }
      return widget.authenticatedBuilder?.call(user) ??
          RoleGate(key: ValueKey(user.uid), user: user);
    },
  );
}
