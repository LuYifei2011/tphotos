import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/photo_list_models.dart';

class PhotoItemWidget extends StatelessWidget {
  final PhotoItem photo;
  final ValueNotifier<Uint8List?> thumbNotifier;
  final void Function() onTap;
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  const PhotoItemWidget({
    super.key,
    required this.photo,
    required this.thumbNotifier,
    required this.onTap,
    required this.ensureThumbLoaded,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<Uint8List?>(
              valueListenable: thumbNotifier,
              builder: (context, bytes, _) {
                if (bytes == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(ensureThumbLoaded(photo));
                  });
                  return const ColoredBox(
                    color: Color(0x11000000),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
          ],
        ),
      ),
    );
  }
}
