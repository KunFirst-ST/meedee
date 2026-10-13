import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class ImageService {
  static const int maxBytes = 200 * 1024;
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAsBase64(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 60,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    if (bytes.length > maxBytes) {
      throw Exception(
        'รูปมีขนาด ${bytes.length ~/ 1024} KB เกิน 200 KB กรุณาเลือกรูปอื่น',
      );
    }
    return base64Encode(bytes);
  }

  static Uint8List? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return base64Decode(text);
    } catch (_) {
      return null;
    }
  }

  static String encode(Uint8List bytes) => base64Encode(bytes);
}
