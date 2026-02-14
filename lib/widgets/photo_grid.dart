import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/photo_list_models.dart';

class PhotoGrid extends StatelessWidget {
  final List<PhotoItem> items;
  final void Function(PhotoItem) onPhotoTap;
  final Map<String, ValueNotifier<Uint8List?>> thumbNotifiers;
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  const PhotoGrid({
    super.key,
    required this.items,
    required this.onPhotoTap,
    required this.thumbNotifiers,
    required this.ensureThumbLoaded,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) {
          final p = items[i];
          final notifier = thumbNotifiers.putIfAbsent(
            p.thumbnailPath,
            () => ValueNotifier<Uint8List?>(null),
          );
          return GestureDetector(
            onTap: () => onPhotoTap(p),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<Uint8List?>(
                    valueListenable: notifier,
                    builder: (context, bytes, _) {
                      if (bytes == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(ensureThumbLoaded(p));
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
        }, childCount: items.length),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
      ),
    );
  }
}
