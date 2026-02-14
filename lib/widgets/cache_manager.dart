import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 通用缓存管理器基类，提供：
/// - 内存 LRU 缓存管理
/// - Future 去重（in-flight dedupe）
/// - stamp/版本校验
/// - 调试日志
///
/// 子类可继承此基类，添加磁盘缓存、并发队列等特定需求。
abstract class CacheManager<K, V> {
  final int _memoryCapacity;
  final LinkedHashMap<K, V> _memoryCache;
  final Map<K, Future<V>> _inFlight;

  /// 用于日志的前缀，子类可覆盖
  String get debugPrefix => 'CacheManager';

  CacheManager({int memoryCapacity = 40})
      : _memoryCapacity = memoryCapacity,
        _memoryCache = LinkedHashMap(),
        _inFlight = {};

  /// 从缓存中加载 key，如果不存在则调用 fetcher 获取
  ///
  /// Parameters:
  /// - [key] - 缓存键
  /// - [fetcher] - 取值函数，返回 `Future<V>`
  /// - [stamp] - 可选的版本标记，用于校验缓存有效性
  /// - [prioritize] - 是否优先加载（子类可实现优先级队列）
  Future<V> load(
    K key,
    Future<V> Function() fetcher, {
    int? stamp,
    bool prioritize = true,
  }) async {
    // 1. 检查内存缓存
    final memEntry = _memoryCache.remove(key);
    if (memEntry != null) {
      final isValid = _validateStamp(key, stamp);
      if (isValid) {
        debugPrint('[$debugPrefix] Memory cache HIT for: $key');
        _memoryCache[key] = memEntry; // LRU：重新添加到末尾
        return memEntry;
      }
    }
    debugPrint('[$debugPrefix] Memory cache MISS for: $key');

    // 2. 检查在途请求（去重）
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      debugPrint('[$debugPrefix] Request already in-flight for: $key');
      return inFlight;
    }

    // 3. 发起新请求
    debugPrint('[$debugPrefix] Starting NEW request for: $key');
    final future = _executeLoad(key, fetcher, stamp);
    _inFlight[key] = future;

    return future.whenComplete(() {
      _inFlight.remove(key);
      debugPrint('[$debugPrefix] Removed from in-flight: $key');
    });
  }

  /// 执行加载逻辑，可子类覆盖以添加磁盘缓存等
  Future<V> _executeLoad(
    K key,
    Future<V> Function() fetcher,
    int? stamp,
  ) async {
    try {
      final value = await fetcher();
      _putToMemory(key, value);
      await _onValueLoaded(key, value, stamp);
      return value;
    } catch (e) {
      debugPrint('[$debugPrefix] Load failed for $key: $e');
      rethrow;
    }
  }

  /// stamp 校验钩子，子类可覆盖以实现自定义逻辑
  bool _validateStamp(K key, int? requestedStamp) => true;

  /// 值加载完成后的钩子，可用于磁盘缓存等
  Future<void> _onValueLoaded(K key, V value, int? stamp) async {}

  /// 将值写入内存缓存
  void _putToMemory(K key, V value) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    }
    _memoryCache[key] = value;
    debugPrint(
      '[$debugPrefix] Saved to memory cache: $key (total: ${_memoryCache.length})',
    );

    // LRU 驱逐
    if (_memoryCache.length > _memoryCapacity) {
      final removed = _memoryCache.keys.first;
      _memoryCache.remove(removed);
      onMemoryEvicted(removed);
      debugPrint('[$debugPrefix] Evicted from memory cache: $removed');
    }
  }

  /// 内存驱逐时的钩子，可用于清理相关资源
  void onMemoryEvicted(K key) {}

  /// 手动清空所有缓存
  void clearAll() {
    _memoryCache.clear();
    _inFlight.clear();
    debugPrint('[$debugPrefix] Cleared all caches');
  }

  /// 获取当前内存缓存大小
  int get memoryCacheSize => _memoryCache.length;

  /// 获取当前在途请求数
  int get inFlightCount => _inFlight.length;

  /// 同步检查缓存中是否存在该键
  V? getIfPresent(K key) {
    return _memoryCache[key];
  }
}

/// 仅内存的缓存管理器（用于 PhotoViewer）
class MemoryCacheManager<K, V> extends CacheManager<K, V> {
  @override
  String get debugPrefix => 'MemoryCacheManager';

  MemoryCacheManager({super.memoryCapacity = 40});
}
