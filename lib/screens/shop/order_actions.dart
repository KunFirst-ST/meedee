import 'package:flutter/material.dart';
import '../../models/food_order.dart';

Future<bool> confirmOrderDelivery(
  BuildContext context,
  FoodOrder order,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ส่งมอบอาหารเรียบร้อยแล้ว?'),
        content: Text(
          'ยืนยันว่าลูกค้า ${order.customerName} รับอาหารและชำระเงินกับร้านแล้ว '
          'เมื่อยืนยัน ออเดอร์จะปิดและรวมในยอดส่งมอบของร้าน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยังไม่ส่งมอบ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ยืนยันส่งมอบแล้ว'),
          ),
        ],
      ),
    ) ??
    false;
