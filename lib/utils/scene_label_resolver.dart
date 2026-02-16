import 'package:flutter/foundation.dart';

/// 场景标签翻译器，可在运行时注入字典并触发 UI 更新。
class SceneLabelResolver {
  SceneLabelResolver._internal();

  static final SceneLabelResolver instance = SceneLabelResolver._internal();

  final ValueNotifier<int> _version = ValueNotifier<int>(0);
  Map<String, String> _dict = const {};

  /// 设置/替换翻译字典；变更会通知监听方重建 UI。
  void setDict(Map<String, String> dict) {
    _dict = Map<String, String>.from(dict);
    _version.value++; // bump to notify listeners
  }

  /// 获取翻译后的标签，若不存在则返回原文。
  String translate(String raw) => _dict[raw] ?? raw;

  /// 用于监听字典版本变化的可监听对象。
  ValueListenable<int> get versionListenable => _version;
}
