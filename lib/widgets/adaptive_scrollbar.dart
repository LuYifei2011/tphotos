import 'dart:io';
import 'package:flutter/material.dart';

/// 自适应滚动条组件
///
/// 根据平台（移动端/桌面端）自动调整滚动条样式：
/// - 移动端：滚动时显示圆角滚动条，支持拖拽
/// - 桌面端：常驻显示滚动条和轨道
class AdaptiveScrollbar extends StatelessWidget {
  /// 滚动控制器
  final ScrollController controller;

  /// 子组件（通常是 CustomScrollView 或 ListView）
  final Widget child;

  /// 是否为移动端（默认自动检测）
  final bool? isMobile;

  /// 移动端滚动条厚度（默认 12）
  final double mobileThickness;

  /// 移动端滚动条圆角半径（默认 12）
  final Radius mobileRadius;

  const AdaptiveScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.isMobile,
    this.mobileThickness = 12.0,
    this.mobileRadius = const Radius.circular(12),
  });

  bool get _isMobile => isMobile ?? (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    if (_isMobile) {
      return Scrollbar(
        controller: controller,
        thumbVisibility: false, // 仅滚动时显示
        trackVisibility: false,
        interactive: true,
        thickness: mobileThickness,
        radius: mobileRadius,
        child: child,
      );
    } else {
      return Scrollbar(
        controller: controller,
        thumbVisibility: true, // 常驻显示
        trackVisibility: true,
        interactive: true,
        child: child,
      );
    }
  }
}
