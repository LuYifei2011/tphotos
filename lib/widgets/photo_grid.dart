import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/photo_list_models.dart';
import 'photo_item.dart';

class PhotoGrid extends StatelessWidget {
  final List<PhotoItem> items;
  final void Function(PhotoItem) onPhotoTap;
  final Map<String, ValueNotifier<Uint8List?>> thumbNotifiers;
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  /// 可选的网格布局代理；为 null 时使用默认 maxCrossAxisExtent: 120
  final SliverGridDelegate? gridDelegate;

  /// 可选的外边距；为 null 时使用默认 8.0 水平边距
  final EdgeInsetsGeometry? padding;

  const PhotoGrid({
    super.key,
    required this.items,
    required this.onPhotoTap,
    required this.thumbNotifiers,
    required this.ensureThumbLoaded,
    this.gridDelegate,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) {
          final p = items[i];
          final notifier = thumbNotifiers.putIfAbsent(
            p.thumbnailPath,
            () => ValueNotifier<Uint8List?>(null),
          );
          return PhotoItemWidget(
            photo: p,
            thumbNotifier: notifier,
            onTap: () => onPhotoTap(p),
            ensureThumbLoaded: ensureThumbLoaded,
          );
        }, childCount: items.length),
        gridDelegate:
            gridDelegate ??
            const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
      ),
    );
  }
}
