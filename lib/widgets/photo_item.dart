import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/photo_list_models.dart';

/// 统一的照片/视频缩略图 item 组件
///
/// 支持：
/// - 视频时长 overlay（type == 1 时在右下角显示时长）
/// - 收藏标识（isCollect == 1 时显示星标）
/// - 选择模式（可选的复选框 overlay）
class PhotoItemWidget extends StatelessWidget {
  final PhotoItem photo;
  final ValueNotifier<Uint8List?> thumbNotifier;
  final void Function() onTap;
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  /// 是否显示选择复选框
  final bool showSelection;

  /// 选中状态（仅在 showSelection=true 时生效）
  final bool isSelected;

  /// 选择状态变更回调
  final ValueChanged<bool>? onSelectionChanged;

  const PhotoItemWidget({
    super.key,
    required this.photo,
    required this.thumbNotifier,
    required this.onTap,
    required this.ensureThumbLoaded,
    this.showSelection = false,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showSelection
          ? () => onSelectionChanged?.call(!isSelected)
          : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 缩略图
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

            // 视频标识 overlay
            if (photo.type == 1)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.videocam,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),

            // 收藏标识
            if (photo.isCollect == 1)
              Positioned(
                left: 4,
                bottom: 4,
                child: Icon(
                  Icons.star,
                  size: 16,
                  color: Colors.amber.withValues(alpha: 0.9),
                ),
              ),

            // 选择复选框
            if (showSelection)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
