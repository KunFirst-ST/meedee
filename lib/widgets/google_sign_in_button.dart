import 'package:flutter/material.dart';
import 'auth_form_layout.dart';

/// Google logo source:
/// https://developers.google.com/static/identity/images/g-logo.png
/// Branding reference: https://developers.google.com/identity/branding-guidelines
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleSignInButton({super.key, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: loading ? null : onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1F1F1F),
      side: const BorderSide(color: Color(0xFF747775)),
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    child: Row(
      children: [
        Image.asset(
          'assets/images/google-g.png',
          width: 20,
          height: 20,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            loading ? 'กำลังเชื่อมต่อ Google…' : 'เข้าสู่ระบบด้วย Google',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        const SizedBox(width: 10),
        if (loading) const AuthProgress() else const SizedBox(width: 20),
      ],
    ),
  );
}
