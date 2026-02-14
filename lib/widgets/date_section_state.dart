import 'dart:async';

import '../models/photo_list_models.dart';

/// 管理单个日期分组的加载状态与缓存
///
/// 替代原有的多个独立 Map：
/// - _datePhotoCache / _videoDateCache
/// - _loadingDates / _videoLoadingDates
/// - _dateStarted / _videoDateStarted
/// - _dateItems / _videoDateItems
/// - _dateFutures / _videoDateFutures
class DateSectionState<T extends PhotoListData> {
  final int timestamp; // 日期 key

  // 缓存与加载状态
  T? _cached;
  bool _started = false;
  final Set<int> _loadingDates = {}; // 用于防重复加载
  List<PhotoItem> _items = []; // 已加载的数据
  Future<T>? _currentFuture;

  DateSectionState(this.timestamp);

  // -------- 公共查询接口 --------

  /// 是否已经开始加载
  bool get hasStarted => _started;

  /// 是否当前有请求在途
  bool get isLoading => _loadingDates.contains(timestamp);

  /// 获取已缓存的数据（若有）
  T? get cached => _cached;

  /// 获取已加载的项目列表
  List<PhotoItem> get items => _items;

  /// 获取当前的 Future（若在途）
  Future<T>? get currentFuture => _currentFuture;

  /// 获取项目数
  int get itemCount => _items.length;

  // -------- 公共操作接口 --------

  /// 标记为已开始加载
  void markStarted() {
    _started = true;
  }

  /// 缓存数据并记录项目列表
  void cacheItems(T data, List<PhotoItem> photoItems) {
    _cached = data;
    _items = photoItems;
  }

  /// 设置当前的 Future（用于加载过程中）
  void setCurrentFuture(Future<T> future) {
    _currentFuture = future;
  }

  /// 清空当前 Future
  void clearCurrentFuture() {
    _currentFuture = null;
  }

  /// 同步添加加载标记（防重复）
  bool tryAddLoadingDate() {
    if (_loadingDates.contains(timestamp)) {
      return false; // 已有加载在途
    }
    _loadingDates.add(timestamp);
    return true;
  }

  /// 移除加载标记
  void removeLoadingDate() {
    _loadingDates.remove(timestamp);
  }

  /// 等待其他加载完成（如果有）
  Future<void> waitForOtherLoading() async {
    while (_loadingDates.contains(timestamp)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 清空所有状态（用于切换空间时）
  void clear() {
    _cached = null;
    _started = false;
    _loadingDates.clear();
    _items = [];
    _currentFuture = null;
  }

  @override
  String toString() =>
      'DateSectionState(timestamp=$timestamp, started=$_started, '
      'loading=${_loadingDates.isNotEmpty}, items=${_items.length})';
}
