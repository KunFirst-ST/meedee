import 'dart:async';
import '../models/app_user.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  final AppUser user;
  final AuthService authService;
  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.authService,
  });
  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _seconds = 0;
  bool _sending = false;
  bool _checking = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) _refresh(quiet: true);
  }

  Future<void> _send() async {
    if (_sending || _checking || _seconds > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    final error = await widget.authService.sendVerificationEmail();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null) {
        _message = 'ส่งลิงก์ยืนยันแล้ว กรุณาตรวจกล่องจดหมายและจดหมายขยะ';
        _seconds = 60;
      }
    });
    if (error == null) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _seconds <= 1) {
          timer.cancel();
          if (mounted) setState(() => _seconds = 0);
        } else {
          setState(() => _seconds--);
        }
      });
    }
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_checking || _sending) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final error = await widget.authService.refreshUser();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = error;
      if (error == null &&
          widget.authService.currentUser?.emailVerified != true &&
          !quiet) {
        _message = 'ยังไม่พบการยืนยัน กดลิงก์ในอีเมลแล้วลองตรวจอีกครั้ง';
      }
    });
  }

  Future<void> _signOut() async {
    if (_checking || _sending) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.authService.signOut();
    } catch (_) {
      if (mounted) setState(() => _error = 'ออกจากระบบไม่ได้ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ยืนยันบัญชี')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: Color(0xFFFFEEE7),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: 36,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'อีกขั้นเดียว\nบัญชีก็พร้อมใช้งาน',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'ยืนยันอีเมลก่อนสั่งอาหารหรือจัดการร้าน เพื่อให้บัญชีเป็นของคุณจริง',
                  style: TextStyle(color: AppTheme.muted, height: 1.7),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.alternate_email_rounded,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.user.email ?? 'ไม่พบอีเมลในบัญชี'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_message != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      style: const TextStyle(color: AppTheme.green),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending || _checking || _seconds > 0
                        ? null
                        : _send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      _sending
                          ? 'กำลังส่งอีเมล…'
                          : _seconds > 0
                          ? 'ส่งอีกครั้งได้ใน $_seconds วินาที'
                          : 'ส่งลิงก์ยืนยันอีเมล',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checking || _sending ? null : _refresh,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('ยืนยันแล้ว ตรวจอีกครั้ง'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _checking || _sending ? null : _signOut,
                  child: const Text('ใช้บัญชีอื่น / ออกจากระบบ'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
