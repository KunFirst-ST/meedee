import 'dart:async';
import '../../models/app_user.dart';
import 'package:flutter/material.dart';

import '../../services/auth_validation.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  final Db? db;

  const EditProfileScreen({super.key, required this.user, this.db});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  Db? _defaultDb;
  Db get _db => widget.db ?? (_defaultDb ??= Db());

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await _db.watchProfile(widget.user.uid).first;
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _loadError = 'กรุณาเลือกบทบาทการใช้งานก่อนแก้ไขข้อมูล';
        });
        return;
      }
      _name.text =
          (profile['displayName'] as String?) ?? widget.user.displayName ?? '';
      _phone.text = (profile['phone'] as String?) ?? '';
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'โหลดข้อมูลบัญชีไม่ได้ ตรวจการเชื่อมต่อแล้วลองใหม่';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _db
          .updateProfile(
            widget.user.uid,
            displayName: _name.text.trim(),
            phone: AuthValidation.normalizePhone(_phone.text),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลบัญชีแล้ว')));
      Navigator.pop(context);
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _saveError =
            'ยังยืนยันผลการบันทึกไม่ได้ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่ '
            'ข้อมูลอาจถูกบันทึกภายหลัง คุณสามารถกลับออกไปตรวจข้อมูลบัญชีได้',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveError = 'บันทึกไม่ได้ ตรวจการเชื่อมต่อแล้วลองใหม่');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('แก้ไขข้อมูลบัญชี')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? StatePanel(
              icon: Icons.person_outline_rounded,
              title: 'ยังแก้ไขข้อมูลไม่ได้',
              message: _loadError!,
              action: 'ลองใหม่',
              onAction: _loadProfile,
            )
          : ContentWidth(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ให้ร้านรู้จักคุณ',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ชื่อที่บันทึกจะใช้กับออเดอร์ใหม่ ประวัติออเดอร์เดิมจะเก็บชื่อ ณ เวลาที่สั่ง',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('profile-display-name'),
                          controller: _name,
                          enabled: !_saving,
                          maxLength: 120,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          validator: AuthValidation.name,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อที่ใช้รับอาหาร',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('profile-phone'),
                          controller: _phone,
                          enabled: !_saving,
                          maxLength: 24,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          validator: AuthValidation.phone,
                          onFieldSubmitted: (_) => _save(),
                          decoration: const InputDecoration(
                            labelText: 'เบอร์ติดต่อ (ไม่บังคับ)',
                            hintText: 'เช่น 0812345678',
                            prefixIcon: Icon(Icons.phone_outlined),
                            helperText:
                                'เก็บในบัญชีของคุณเพื่อใช้เป็นข้อมูลติดต่อ',
                            helperMaxLines: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.alternate_email_rounded),
                            title: Text(widget.user.email ?? 'บัญชีนี้'),
                            subtitle: const Text('อีเมลสำหรับเข้าสู่ระบบ'),
                          ),
                        ),
                        if (_saveError != null) ...[
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _saveError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('profile-save'),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              _saving ? 'กำลังบันทึก…' : 'บันทึกข้อมูล',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
