import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/menu_item.dart';
import '../../services/db.dart';
import '../../services/image_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import '../../widgets/menu_image.dart';

class MenuManageScreen extends StatefulWidget {
  final String shopId;
  const MenuManageScreen({super.key, required this.shopId});
  @override
  State<MenuManageScreen> createState() => _MenuManageScreenState();
}

class _MenuManageScreenState extends State<MenuManageScreen> {
  late Stream<List<MenuItem>> _stream;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _stream = Db().watchMenu(widget.shopId);
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _delete(MenuItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบเมนูนี้?'),
        content: Text('${item.name}\nประวัติออเดอร์เดิมยังคงอยู่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบเมนู'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _run(item.id, () => Db().deleteMenuItem(item.id));
    }
  }

  Future<void> _form(MenuItem? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(text: item?.price.toString() ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final category = TextEditingController(text: item?.category ?? '');
    String? image;
    String? error;
    var removeImage = false;
    var saving = false;
    var picking = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final preview = image != null
              ? ImageService.decode(image)
              : removeImage
              ? null
              : item?.imageBytes;
          Future<void> pick(ImageSource source) async {
            if (picking || saving) return;
            refresh(() {
              picking = true;
              error = null;
            });
            try {
              final result = await ImageService().pickAsBase64(source);
              if (ctx.mounted && result != null) {
                refresh(() {
                  image = result;
                  removeImage = false;
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                refresh(
                  () => error = e.toString().replaceFirst('Exception: ', ''),
                );
              }
            } finally {
              if (ctx.mounted) refresh(() => picking = false);
            }
          }

          Future<void> save() async {
            if (saving || picking) return;
            final p = num.tryParse(price.text.trim());
            if (name.text.trim().isEmpty || p == null) {
              refresh(() => error = 'กรอกชื่อเมนูและราคาให้ครบ');
              return;
            }
            try {
              OrderValidation.priceInSatang(p);
            } catch (e) {
              refresh(() => error = e.toString());
              return;
            }
            refresh(() {
              saving = true;
              error = null;
            });
            try {
              if (item == null) {
                await Db().addMenuItem(
                  widget.shopId,
                  name.text,
                  p,
                  imageBase64: image,
                  category: category.text,
                  description: description.text,
                );
              } else {
                await Db().updateMenuItem(
                  item.id,
                  name.text,
                  p,
                  imageBase64: image,
                  removeImage: removeImage,
                  category: category.text,
                  description: description.text,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (_) {
              if (ctx.mounted) {
                refresh(() {
                  saving = false;
                  error = 'บันทึกไม่ได้ กรุณาตรวจข้อมูลแล้วลองใหม่';
                });
              }
            }
          }

          return PopScope(
            canPop: !saving && !picking,
            child: AlertDialog(
              title: Text(item == null ? 'เพิ่มเมนูใหม่' : 'แก้ไขเมนู'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MenuImage(bytes: preview, size: 120),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'ถ่ายรูป',
                            onPressed: saving || picking
                                ? null
                                : () => pick(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'เลือกรูป',
                            onPressed: saving || picking
                                ? null
                                : () => pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                          ),
                          if (preview != null)
                            IconButton(
                              tooltip: 'นำรูปออก',
                              onPressed: saving || picking
                                  ? null
                                  : () => refresh(() {
                                      image = null;
                                      removeImage = true;
                                    }),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: name,
                        enabled: !saving,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อเมนู',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: price,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ราคา (บาท)',
                          hintText: 'เช่น 45.00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: category,
                        enabled: !saving,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'ประเภทอาหาร',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: description,
                        enabled: !saving,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'คำอธิบายเมนู',
                        ),
                      ),
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving || picking
                      ? null
                      : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: saving || picking ? null : save,
                  child: Text(saving ? 'กำลังบันทึก…' : 'บันทึก'),
                ),
              ],
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    price.dispose();
    category.dispose();
    description.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('จัดการเมนูอาหาร')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _form(null),
      icon: const Icon(Icons.add_rounded),
      label: const Text('เพิ่มเมนู'),
    ),
    body: StreamBuilder<List<MenuItem>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return StatePanel(
            title: 'โหลดเมนูไม่ได้',
            message: 'ตรวจการเชื่อมต่อแล้วลองใหม่',
            action: 'ลองใหม่',
            onAction: () => setState(_connect),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return StatePanel(
            icon: Icons.restaurant_menu_rounded,
            title: 'เริ่มสร้างเมนูของร้าน',
            message: 'เพิ่มชื่อ ราคา และรูปอาหาร เพื่อให้ลูกค้าเลือกสั่ง',
            action: 'เพิ่มเมนูแรก',
            onAction: () => _form(null),
          );
        }
        return ContentWidth(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final item = items[i];
              final busy = _busy.contains(item.id);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          MenuImage(
                            bytes: item.imageBytes,
                            size: 72,
                            grayscale: !item.available,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  money(item.price),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: item.available,
                            onChanged: busy
                                ? null
                                : (value) => _run(
                                    item.id,
                                    () => Db().setAvailable(item.id, value),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.available ? 'พร้อมขาย' : 'หมดชั่วคราว',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: busy ? null : () => _form(item),
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('แก้ไข'),
                          ),
                          IconButton(
                            tooltip: 'ลบ ${item.name}',
                            onPressed: busy ? null : () => _delete(item),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
