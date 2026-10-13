import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

Future<void> showAccountHelp(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ใช้งาน MSU FOOD',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const _HelpItem(
              icon: Icons.storefront_outlined,
              title: 'สั่งแล้วรับอาหารที่ร้าน',
              text:
                  'เลือกเมนู ตรวจตะกร้าและจุดรับอาหารก่อนยืนยัน เมื่อร้านแจ้งว่าพร้อมรับ ให้แสดงรหัสออเดอร์ที่ร้าน',
            ),
            const _HelpItem(
              icon: Icons.payments_outlined,
              title: 'ชำระเงินกับร้าน',
              text:
                  'แอปนี้ใช้การชำระเงินเมื่อรับอาหาร ตรวจยอดในออเดอร์และชำระกับร้านโดยตรงตามช่องทางที่ร้านรับ',
            ),
            const _HelpItem(
              icon: Icons.receipt_long_outlined,
              title: 'ติดตามและยกเลิกออเดอร์',
              text:
                  'เปิด “ออเดอร์ของฉัน” เพื่อติดตามสถานะ ลูกค้ายกเลิกได้ขณะที่ร้านยังไม่รับออเดอร์ หากร้านรับแล้ว ให้ติดต่อร้านที่จุดรับอาหาร',
            ),
            const _HelpItem(
              icon: Icons.lock_outline_rounded,
              title: 'ดูแลบัญชีให้ปลอดภัย',
              text:
                  'บัญชีอีเมลเปลี่ยนรหัสผ่านได้ที่ “บัญชีและความปลอดภัย” โดยยืนยันรหัสเดิม หากลืมรหัส ใช้ “ลืมรหัสผ่าน” ที่หน้าเข้าสู่ระบบ บัญชี Google จัดการรหัสผ่านผ่าน Google',
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('เข้าใจแล้ว'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(text, style: const TextStyle(color: AppTheme.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}
