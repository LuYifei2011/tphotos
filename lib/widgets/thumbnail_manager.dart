import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- ThumbnailManager: 并发限制 + 去重（in-flight dedupe）+ 内存 LRU + 磁盘缓存 ----------
class ThumbnailManager {
  ThumbnailManager._internal();
  static final ThumbnailManager instance = ThumbnailManager._internal();

  int maxConcurrent = 6; // 默认值，将从设置中加载
  int _running = 0;
  Completer<void>? _settingsCompleter;

  final Queue<_QueuedTask> _queue = Queue<_QueuedTask>();
  final Map<String, Future<Uint8List>> _inFlight = {};

  final int _memoryCapacity = 200;
  final LinkedHashMap<String, _MemoryEntry> _memoryCache = LinkedHashMap();

  static const int _diskCapacity = 400;
  Directory? _cacheDir;
  File? _indexFile;
  final Map<String, _DiskEntry> _diskIndex = {};
  Future<void>? _initFuture;
  bool _indexSaveScheduled = false;

  Future<void> _ensureInitialized() {
    return _initFuture ??= _init();
  }

  /// 确保设置只加载一次（线程安全）
  Future<void> _loadSettings() async {
    // 如果已经在加载或已加载完成，复用同一个 Future
    if (_settingsCompleter != null) {
      return _settingsCompleter!.future;
    }

    _settingsCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt('concurrent_requests') ?? 6;
      maxConcurrent = value.clamp(1, 32);
      debugPrint(
        '[ThumbCache] Loaded concurrent requests setting: $maxConcurrent',
      );
      _settingsCompleter!.complete();
    } catch (e) {
      debugPrint('[ThumbCache] Failed to load settings: $e, using default: 6');
      maxConcurrent = 6;
      _settingsCompleter!.complete();
    }
    return _settingsCompleter!.future;
  }

  /// 更新并发数（从设置页面调用，立即生效）
  void updateMaxConcurrent(int value) {
    maxConcurrent = value.clamp(1, 32);
    debugPrint('[ThumbCache] Updated concurrent requests to: $maxConcurrent');
    // 触发调度，如果有排队的任务可以立即开始执行
    _schedule();
  }

  Future<void> _init() async {
    await _loadSettings();
    try {
      Directory? baseDir;
      if (Platform.isAndroid) {
        final externalDirs = await getExternalCacheDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          baseDir = externalDirs.first;
        }
      }
      baseDir ??= await getTemporaryDirectory();
      final dir = Directory(p.join(baseDir.path, 'tphotos', 'thumb_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      _indexFile = File(p.join(dir.path, 'index.json'));
      if (await _indexFile!.exists()) {
        try {
          final content = await _indexFile!.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            final entries = decoded['entries'];
            if (entries is Map<String, dynamic>) {
              entries.forEach((key, value) {
                if (value is Map<String, dynamic>) {
                  final entry = _DiskEntry.fromJson(value);
                  if (entry != null) {
                    _diskIndex[key] = entry;
                  }
                }
              });
            }
          }
        } catch (_) {
          _diskIndex.clear();
        }
      }
      debugPrint('[ThumbCache] dir=${dir.path}, entries=${_diskIndex.length}');
    } catch (e) {
      debugPrint('[ThumbCache] init failed: $e');
      _cacheDir = null;
      _indexFile = null;
      _diskIndex.clear();
    }
  }

  Future<Uint8List> load(
    String key,
    Future<List<int>> Function() fetcher, {
    int? stamp,
    bool prioritize = true,
  }) async {
    final mem = _memoryCache.remove(key);
    if (mem != null) {
      final matches = stamp == null || mem.stamp == null || mem.stamp == stamp;
      if (matches) {
        _memoryCache[key] = mem;
        return mem.bytes;
      }
    }

    await _ensureInitialized();

    final diskEntry = _diskIndex[key];
    if (diskEntry != null) {
      final matches = stamp == null || diskEntry.stamp == stamp;
      if (matches && _cacheDir != null) {
        final file = File(p.join(_cacheDir!.path, diskEntry.fileName));
        try {
          final bytes = await file.readAsBytes();
          diskEntry.lastAccess = DateTime.now().millisecondsSinceEpoch;
          _putToMemory(key, bytes, stamp ?? diskEntry.stamp);
          _scheduleIndexSave();
          debugPrint('[ThumbCache] disk HIT $key');
          return bytes;
        } catch (e) {
          debugPrint('[ThumbCache] disk read failed for $key: $e');
          await _removeDiskEntry(key, scheduleSave: true);
        }
      } else if (diskEntry.stamp != stamp) {
        debugPrint('[ThumbCache] disk stale stamp, evict $key');
        await _removeDiskEntry(key, scheduleSave: true);
      }
    } else {
      debugPrint('[ThumbCache] disk MISS (no index) $key');
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) {
      if (prioritize) _promoteQueuedTask(key);
      return inFlight;
    }

    final completer = Completer<Uint8List>();
    _inFlight[key] = completer.future;

    final task = _QueuedTask(key, () async {
      try {
        final list = await fetcher();
        final bytes = Uint8List.fromList(list);
        _putToMemory(key, bytes, stamp);
        if (stamp != null) {
          await _putToDisk(key, bytes, stamp);
        }
        if (!completer.isCompleted) completer.complete(bytes);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });

    if (prioritize) {
      _promoteQueuedTask(key);
      _queue.addFirst(task);
    } else {
      _queue.addLast(task);
    }

    _schedule();

    return completer.future.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  void _putToMemory(String key, Uint8List bytes, int? stamp) {
    _memoryCache.remove(key);
    _memoryCache[key] = _MemoryEntry(bytes, stamp);
    if (_memoryCache.length > _memoryCapacity) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  Future<void> _putToDisk(String key, Uint8List bytes, int stamp) async {
    if (_cacheDir == null) return;
    final fileName = _fileNameForKey(key);
    final file = File(p.join(_cacheDir!.path, fileName));
    try {
      await file.writeAsBytes(bytes, flush: true);
      _diskIndex[key] = _DiskEntry(
        fileName: fileName,
        stamp: stamp,
        lastAccess: DateTime.now().millisecondsSinceEpoch,
      );
      await _evictOverflow();
      _scheduleIndexSave();
    } catch (e) {
      debugPrint('Thumbnail disk write failed for $key: $e');
    }
  }

  Future<void> _evictOverflow() async {
    if (_cacheDir == null) return;
    while (_diskIndex.length > _diskCapacity) {
      String? oldestKey;
      int? oldestAccess;
      _diskIndex.forEach((key, value) {
        if (oldestAccess == null || value.lastAccess < oldestAccess!) {
          oldestAccess = value.lastAccess;
          oldestKey = key;
        }
      });
      if (oldestKey == null) break;
      await _removeDiskEntry(oldestKey!, scheduleSave: false);
    }
  }

  Future<void> _removeDiskEntry(
    String key, {
    required bool scheduleSave,
  }) async {
    final entry = _diskIndex.remove(key);
    if (scheduleSave) {
      _scheduleIndexSave();
    }
    if (entry == null || _cacheDir == null) {
      return;
    }
    final file = File(p.join(_cacheDir!.path, entry.fileName));
    try {
      await file.delete();
    } catch (_) {}
  }

  String _fileNameForKey(String key) {
    final digest = crypto.sha1.convert(utf8.encode(key)).toString();
    return '$digest.bin';
  }

  void _scheduleIndexSave() {
    if (_indexFile == null || _indexSaveScheduled) return;
    _indexSaveScheduled = true;
    Future.microtask(() async {
      _indexSaveScheduled = false;
      if (_indexFile == null) return;
      try {
        final data = {
          'entries': _diskIndex.map(
            (key, value) => MapEntry(key, value.toJson()),
          ),
        };
        await _indexFile!.writeAsString(jsonEncode(data), flush: true);
      } catch (e) {
        debugPrint('Thumbnail index save failed: $e');
      }
    });
  }

  void _schedule() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _running++;
      task.run().whenComplete(() {
        _running--;
        _schedule();
      });
    }
  }

  // Move a queued task to the front so the most recently requested (visible)
  // thumbnails run before stale ones.
  void _promoteQueuedTask(String key) {
    for (final task in _queue.toList()) {
      if (task.key == key) {
        _queue.remove(task);
        _queue.addFirst(task);
        break;
      }
    }
  }

  void clearMemoryCache() => _memoryCache.clear();
}

class _MemoryEntry {
  final Uint8List bytes;
  final int? stamp;
  _MemoryEntry(this.bytes, this.stamp);
}

class _DiskEntry {
  _DiskEntry({
    required this.fileName,
    required this.stamp,
    required this.lastAccess,
  });

  final String fileName;
  final int stamp;
  int lastAccess;

  Map<String, dynamic> toJson() => {
    'file': fileName,
    'stamp': stamp,
    'lastAccess': lastAccess,
  };

  static _DiskEntry? fromJson(Map<String, dynamic> json) {
    final file = json['file'] as String?;
    final stampValue = json['stamp'];
    if (file == null || stampValue == null) {
      return null;
    }
    final lastAccessValue = json['lastAccess'];
    return _DiskEntry(
      fileName: file,
      stamp: stampValue is int ? stampValue : (stampValue as num).toInt(),
      lastAccess: lastAccessValue is int
          ? lastAccessValue
          : (lastAccessValue as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class _QueuedTask {
  final String key;
  final Future<void> Function() run;
  _QueuedTask(this.key, this.run);
}
