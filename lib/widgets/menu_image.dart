import 'dart:typed_data';

import 'package:flutter/material.dart';

class MenuImage extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  final bool grayscale;

  const MenuImage({
    super.key,
    required this.bytes,
    this.size = 56,
    this.grayscale = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? Container(
                color: Colors.grey.shade200,
                child: Icon(
                  Icons.restaurant,
                  color: Colors.grey.shade500,
                  size: size * 0.5,
                ),
              )
            : ColorFiltered(
                colorFilter: grayscale
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.srcOver,
                      ),
                child: Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFFFFEEE7),
                    child: const Icon(Icons.restaurant_rounded),
                  ),
                ),
              ),
      ),
    );
  }
}
