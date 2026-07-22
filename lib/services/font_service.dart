import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 界面字体选项。持久化用 [AppFontChoiceX.id]（稳定字符串），不要存枚举序号。
enum AppFontChoice { system, harmony, misans }

extension AppFontChoiceX on AppFontChoice {
  String get id => switch (this) {
        AppFontChoice.system => 'system',
        AppFontChoice.harmony => 'harmony',
        AppFontChoice.misans => 'misans',
      };

  static AppFontChoice fromId(String? id) => switch (id) {
        'harmony' => AppFontChoice.harmony,
        'misans' => AppFontChoice.misans,
        _ => AppFontChoice.system,
      };
}

class _FontSpec {
  const _FontSpec({
    required this.family,
    required this.urls,
    required this.entryPattern,
  });

  /// 注册到 FontLoader / ThemeData 的家族名（以此为准，与字体内部名无关）。
  final String family;

  /// 按顺序尝试的下载地址：官方 CDN → GitHub raw → gh-proxy 镜像。
  final List<String> urls;

  /// 从 zip 中挑选 TTF 的正则（大小写不敏感，匹配完整条目路径）。
  final String entryPattern;
}

/// 下载 / 解压 / 注册可选界面字体（鸿蒙、小米）。
///
/// 字体包只在首次使用时下载到应用数据目录
/// `<app-support>/fonts/<id>/`，之后每次启动直接注册本地 TTF。
class FontService extends ChangeNotifier {
  static const Map<AppFontChoice, _FontSpec> _specs = {
    AppFontChoice.harmony: _FontSpec(
      family: 'HarmonyOS Sans SC',
      urls: [
        'https://github.com/huawei-fonts/HarmonyOS-Sans/raw/main/HarmonyOS%20Sans.zip',
        'https://ghfast.top/https://github.com/huawei-fonts/HarmonyOS-Sans/raw/main/HarmonyOS%20Sans.zip',
      ],
      entryPattern:
          r'HarmonyOS[ _]?Sans[ _]?SC[ _-](Regular|Medium|Bold)\.ttf$',
    ),
    AppFontChoice.misans: _FontSpec(
      family: 'MiSans',
      urls: [
        'https://cdn.cnbj1.fds.api.mi-img.com/vipmlmodel/font/MiSans/MiSans.zip',
        'https://hyperos.mi.com/font-download/MiSans.zip',
      ],
      entryPattern: r'MiSans-(Regular|Medium|Bold)\.ttf$',
    ),
  };

  double? _progress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  AppFontChoice? _downloading;
  final Set<AppFontChoice> _loaded = {}; // 已注册到引擎
  final Set<AppFontChoice> _downloadedOnDisk = {}; // TTF 已存在本地

  /// 下载进度 0-1；未在下载或总大小未知时为 null。
  double? get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  AppFontChoice? get downloading => _downloading;

  /// [c] 对应的主题字体家族名；系统字体或尚未注册时为 null。
  String? familyFor(AppFontChoice c) => c == AppFontChoice.system
      ? null
      : (_loaded.contains(c) ? _specs[c]!.family : null);

  bool isLoaded(AppFontChoice c) => _loaded.contains(c);

  bool isDownloadedSync(AppFontChoice c) =>
      c == AppFontChoice.system || _downloadedOnDisk.contains(c);

  Future<Directory> _fontDir(AppFontChoice c) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'fonts', c.id));
  }

  Future<List<File>> _localFontFiles(AppFontChoice c) async {
    final dir = await _fontDir(c);
    if (!await dir.exists()) return const [];
    return dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.ttf'))
        .cast<File>()
        .toList();
  }

  /// 启动时调用一次，扫描磁盘上已下载的字体，让设置页能同步显示状态。
  Future<void> init() async {
    for (final c in const [AppFontChoice.harmony, AppFontChoice.misans]) {
      if ((await _localFontFiles(c)).isNotEmpty) _downloadedOnDisk.add(c);
    }
  }

  /// 注册之前已下载的 TTF；磁盘上没有时安静返回。
  Future<void> loadIfDownloaded(AppFontChoice c) async {
    if (c == AppFontChoice.system || _loaded.contains(c)) return;
    final files = await _localFontFiles(c);
    if (files.isEmpty) return;
    await _register(_specs[c]!.family, files);
    _loaded.add(c);
    _downloadedOnDisk.add(c);
    notifyListeners();
  }

  /// 下载官方字体包、解压 TTF 并注册。失败时抛出异常。
  Future<void> downloadAndLoad(AppFontChoice choice) async {
    final spec = _specs[choice]!;
    if (_downloading != null) return;
    _downloading = choice;
    _progress = null;
    _receivedBytes = 0;
    _totalBytes = 0;
    notifyListeners();

    final dir = await _fontDir(choice);
    await dir.create(recursive: true);
    final zipFile = File(p.join(dir.path, '_download.zip'));
    try {
      Object? lastError;
      var ok = false;
      for (final url in spec.urls) {
        try {
          await _downloadTo(url, zipFile);
          ok = true;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (!ok) throw lastError ?? Exception('download failed');

      // 解压放到 isolate 里做——字体包几十 MB，主线程解压会卡死界面。
      final extracted = await compute(
        _extractFonts,
        <String>[zipFile.path, dir.path, spec.entryPattern],
      );
      if (extracted.isEmpty) {
        throw Exception('No matching font files in the package');
      }

      await _register(spec.family, extracted.map(File.new).toList());
      _loaded.add(choice);
      _downloadedOnDisk.add(choice);
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      _downloading = null;
      _progress = null;
      notifyListeners();
    }
  }

  Future<void> _downloadTo(String url, File target) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      _totalBytes = response.contentLength ?? 0;
      _receivedBytes = 0;
      final sink = target.openWrite();
      var lastNotified = 0; // 每 256 KB 通知一次，避免逐 chunk 重建进度条
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          _receivedBytes += chunk.length;
          if (_totalBytes > 0) {
            _progress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
          }
          if (_receivedBytes - lastNotified >= 256 * 1024) {
            lastNotified = _receivedBytes;
            notifyListeners();
          }
        }
        notifyListeners();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<void> _register(String family, List<File> files) async {
    final loader = FontLoader(family); // 这里的家族名即主题里要用的名字
    for (final f in files) {
      loader.addFont(f.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

/// Isolate 入口：args = [zipPath, outDir, entryPattern]。
/// 按文件名去重——字体包常在多个目录里放同一份 TTF。
List<String> _extractFonts(List<String> args) {
  final re = RegExp(args[2], caseSensitive: false);
  final archive = ZipDecoder().decodeBytes(File(args[0]).readAsBytesSync());
  final seen = <String>{};
  final out = <String>[];
  for (final entry in archive) {
    if (!entry.isFile || !re.hasMatch(entry.name)) continue;
    final name = p.basename(entry.name);
    if (!seen.add(name.toLowerCase())) continue;
    final file = File(p.join(args[1], name));
    file.writeAsBytesSync(entry.content as List<int>);
    out.add(file.path);
  }
  return out;
}
