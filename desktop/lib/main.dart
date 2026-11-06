import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'workspace.dart';
part 'settings.dart';
part 'settings_panel.dart';

const windows = MethodChannel('pdfmath/desktop');

const blue = Color(0xff145bc6);
const blueInk = Color(0xff153f80);
const ink = Color(0xff171d28);
const muted = Color(0xff515969);
const background = Color(0xffefedf0);
const paper = Color(0xfffaf8fa);
const inset = Color(0xffeeedf0);
const tint = Color(0xffdfe9fa);
const green = Color(0xffa4f89d);

void main() => runApp(buildDesktopApp());

Widget buildDesktopApp() => MaterialApp(
  title: 'PDFMathTranslate',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: blue,
      onPrimary: Colors.white,
      primaryContainer: tint,
      onPrimaryContainer: blueInk,
      secondary: blue,
      onSecondary: Colors.white,
      secondaryContainer: tint,
      onSecondaryContainer: blueInk,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
    ),
    fontFamily: 'Microsoft YaHei UI',
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inset,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide.none,
      ),
    ),
  ),
  home: const Desktop(),
);

class Desktop extends StatefulWidget {
  const Desktop({super.key, this.historyStorage});

  final File? historyStorage;
  @override
  State<Desktop> createState() => _DesktopState();
}

class _DesktopState extends State<Desktop> {
  final pages = TextEditingController();
  final settings = DesktopSettings();
  final logs = ListQueue<(String, String)>();
  final history = <Map<String, dynamic>>[];
  final selectedHistory = <String>{};
  final openSettingGroups = {'翻译服务与速率限制'};
  int page = 0;
  String? source;
  String? outputRoot;
  String from = 'en';
  String to = 'zh-CN';
  String format = 'both';
  String engine = 'Bing';
  String stage = '等待导入 PDF';
  String? error;
  double? progress;
  bool busy = false;
  bool cancelling = false;
  bool historyLoaded = false;
  bool historyError = false;
  bool historyCleaning = false;
  bool settingsLoading = true;
  bool settingsReady = false;
  bool savingSettings = false;
  bool loadingGlossary = false;
  String logLevel = 'all';
  Process? worker;
  Timer? logRefresh;
  Map<String, dynamic>? latest;

  File get historyFile {
    if (widget.historyStorage case final File file) return file;
    final local =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File('$local\\PDFMathTranslateDesktop\\history.json');
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadHistory());
    unawaited(loadSettings());
  }

  @override
  void dispose() {
    logRefresh?.cancel();
    unawaited(worker?.stdin.close().catchError((Object _) {}));
    pages.dispose();
    super.dispose();
  }

  void scheduleLogRefresh() {
    if (logRefresh?.isActive ?? false) return;
    logRefresh = Timer(const Duration(milliseconds: 100), () {
      if (mounted && page == 3) setState(() {});
    });
  }

  String basename(String path) => path.split(RegExp(r'[/\\]')).last;

  void update(VoidCallback change) => setState(change);

  void swapLanguages() {
    setState(() {
      final previousSource = from;
      from = to;
      to = previousSource;
    });
  }

  Future<void> loadHistory() async {
    try {
      history.addAll(await readHistory());
    } on Exception {
      historyError = true;
    } finally {
      if (mounted) setState(() => historyLoaded = true);
    }
  }

  Future<List<Settings>> readHistory() async {
    if (!await historyFile.exists()) return [];
    final entries = jsonDecode(await historyFile.readAsString());
    if (entries is! List<dynamic>) {
      throw const FormatException('Expected a list of translation jobs.');
    }
    return entries.whereType<Settings>().where((entry) {
      return entry['name'] is String &&
          entry['at'] is String &&
          entry['status'] is String &&
          entry['output'] is String &&
          entry['files'] is List<dynamic>;
    }).toList();
  }

  Future<void> changeHistory(
    List<Settings> Function(List<Settings>) change,
  ) async {
    final file = historyFile;
    await file.parent.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      final entries = change(await readHistory()).take(100).toList();
      final temp = File('${file.path}.$pid.tmp');
      await temp.writeAsString(jsonEncode(entries), flush: true);
      await temp.rename(file.path);
      if (!mounted) return;
      setState(() {
        history
          ..clear()
          ..addAll(entries);
        selectedHistory.retainAll(
          entries.map((entry) => entry['output'] as String),
        );
        historyError = false;
      });
    } finally {
      await lock.close();
    }
  }

  Future<void> clearHistory({bool all = false}) async {
    if (!historyLoaded || historyCleaning || busy || history.isEmpty) return;
    if (all) {
      final confirmed = await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) => AlertDialog(
          title: const Text('清理全部任务记录？'),
          content: const Text('历史记录将被清空，已生成的 PDF 和其他输出文件会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('全部清理'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || busy || historyCleaning) return;
    }
    if (!all && selectedHistory.isEmpty) return;
    setState(() => historyCleaning = true);
    try {
      var removed = 0;
      await changeHistory((entries) {
        final remaining = all
            ? <Settings>[]
            : entries
                  .where((entry) => !selectedHistory.contains(entry['output']))
                  .toList();
        removed = entries.length - remaining.length;
        return remaining;
      });
      if (mounted) message('已清理 $removed 条任务记录');
    } on Exception {
      if (mounted) {
        setState(() => historyError = true);
        message('清理失败，任务记录仍保留');
      }
    } finally {
      if (mounted) setState(() => historyCleaning = false);
    }
  }

  Future<void> saveHistory(Settings entry) async {
    try {
      await changeHistory((entries) => [entry, ...entries]);
    } on Exception {
      if (mounted) {
        setState(() {
          history.insert(0, entry);
          historyError = true;
        });
      }
    }
  }

  Future<void> chooseSource() async {
    try {
      final file = await windows.invokeMethod<String>('choosePdf');
      if (file == null || !mounted || busy) return;
      setState(() {
        source = file;
        latest = null;
        error = null;
        progress = null;
        stage = '等待开始';
      });
    } on Exception {
      if (mounted) message('无法打开文件选择器');
    }
  }

  Future<void> chooseOutput() async {
    try {
      final directory = await windows.invokeMethod<String>('chooseDirectory');
      if (directory != null && mounted && !busy) {
        setState(() => outputRoot = directory);
      }
    } on Exception {
      if (mounted) message('无法打开目录选择器');
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> openPath(String path) async {
    try {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound &&
          await windows.invokeMethod<bool>('openPath', path) == true) {
        return;
      }
    } on Exception {
      // A moved file or missing PDF association can prevent launch.
    }
    if (mounted) message('无法打开，文件或目录可能已移动。');
  }

  Future<void> cancel() async {
    if (cancelling || !busy) return;
    setState(() {
      cancelling = true;
      stage = '正在取消任务';
    });
    appendLog('INFO', '已请求取消任务');
    await worker?.stdin.close().catchError((Object _) {});
  }

  Future<void> start() async {
    final input = source;
    if (settingsLocked ||
        historyCleaning ||
        !historyLoaded ||
        !settingsReady ||
        input == null) {
      return;
    }
    if (from == to) {
      message('请选择不同的源语言和目标语言');
      return;
    }
    if (settings.pageRange == 'range' && pages.text.trim().isEmpty) {
      message('请输入自定义页码');
      return;
    }
    final now = DateTime.now();
    final folder = outputRoot ?? File(input).parent.path;
    final output = '$folder\\PDFMath-${now.microsecondsSinceEpoch}';
    final request = jsonEncode({
      'source': input,
      'output': output,
      ...translationSettings(),
    });
    setState(() {
      busy = true;
      cancelling = false;
      error = null;
      latest = null;
      progress = null;
      stage = '正在启动翻译引擎';
    });

    final secrets = settings.credentials();
    appendLog('INFO', '开始翻译 ${basename(input)} · ${serviceLabel(engine)}');
    void record(String line) {
      final level = RegExp(
        r'^(DEBUG|INFO|WARNING|ERROR|CRITICAL)\b',
      ).firstMatch(line);
      appendLog(
        level?.group(1) ?? 'INFO',
        redactLog(
          level == null ? line : line.substring(level.end).trimLeft(),
          secrets,
        ),
      );
    }

    List<dynamic>? files;
    String? failure;
    bool cancelled = false;
    try {
      final process = await Process.start('$backend\\runtime\\pythonw.exe', [
        '$backend\\bridge.py',
      ], workingDirectory: backend);
      worker = process;
      process.stdin.done.ignore();
      final stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(record);
      final stdout = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((line) {
            if (!line.startsWith('PDFMATH ')) {
              record(line);
              return;
            }
            final event = jsonDecode(line.substring(8)) as Map<String, dynamic>;
            switch (event['type']) {
              case 'stage':
              case 'progress':
                if (!mounted || cancelling) break;
                final name = event['stage'] as String? ?? '';
                final label = stageNames[name] ?? name;
                final nextStage = label.isEmpty ? stage : label;
                final value = event['progress'];
                final nextProgress = value is num
                    ? math.max(progress ?? 0.0, (value / 100).clamp(0.0, 1.0))
                    : progress;
                if (nextStage == stage && nextProgress == progress) break;
                if (nextStage != stage) appendLog('INFO', nextStage);
                setState(() {
                  stage = nextStage;
                  progress = nextProgress;
                });
              case 'finish':
                files = event['files'] as List<dynamic>;
              case 'error':
                failure = redactLog(event['message'].toString(), secrets);
              case 'cancelled':
                cancelled = true;
            }
          });
      process.stdin.writeln(request);
      if (cancelling || !mounted) {
        unawaited(process.stdin.close().catchError((Object _) {}));
      }
      await Future.wait([stdout, stderr]);
      final code = await process.exitCode;
      unawaited(process.stdin.close().catchError((Object _) {}));
      if (!cancelled && (code != 0 || files == null)) {
        failure ??= '翻译引擎异常退出（退出码 $code）';
      }
    } on Exception catch (exception) {
      failure = exception is ProcessException
          ? '无法启动翻译引擎，请检查便携版目录是否完整。'
          : '无法读取翻译引擎的结果。';
      unawaited(worker?.stdin.close().catchError((Object _) {}));
    } finally {
      worker = null;
    }

    if (!mounted) return;
    final success = failure == null && files != null;
    if (failure case final String detail) {
      appendLog('ERROR', detail);
    } else {
      appendLog('INFO', success ? '翻译完成，已生成 ${files!.length} 个文件' : '翻译已取消');
    }
    final entry = <String, dynamic>{
      'name': basename(input),
      'at': now.toIso8601String(),
      'status': success
          ? '已完成'
          : cancelled
          ? '已取消'
          : '失败',
      'files': success ? files : [],
      'output': output,
    };
    setState(() {
      latest = entry;
      progress = success ? 1 : null;
      stage = entry['status'] as String;
      error = failure;
    });
    await saveHistory(entry);
    if (mounted) {
      setState(() {
        busy = false;
        cancelling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => workspaceFrame();
}
