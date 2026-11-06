part of 'main.dart';

enum InterfaceFont {
  miSans('MiSans', 'MiSans'),
  harmony('HarmonyOS Sans', 'HarmonyOS Sans'),
  yaHei('微软雅黑 UI', 'Microsoft YaHei UI');

  const InterfaceFont(this.label, this.family);

  final String label;
  final String family;
}

class PageLoomMark extends StatelessWidget {
  const PageLoomMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _PageLoomMarkPainter()),
  );
}

class _PageLoomMarkPainter extends CustomPainter {
  const _PageLoomMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    const bounds = Rect.fromLTWH(1, 1, 62, 62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(18)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [Color(0xff705fff), Color(0xff2356fa), Color(0xff0056ff)],
          stops: [0, .53, 1],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(14, 20, 29, 30),
        const Radius.circular(4.5),
      ),
      Paint()..color = const Color(0xff75b7ff),
    );
    const front = Rect.fromLTWH(21, 14, 28, 30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(front, const Radius.circular(4.5)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffeef7ff), Color(0xffc6defa)],
        ).createShader(front),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PageLoomMarkPainter oldDelegate) => false;
}

class Appearance {
  const Appearance({
    this.mode = ThemeMode.system,
    this.font = InterfaceFont.miSans,
  });

  factory Appearance.fromJson(Object? data) {
    final values = data is Map<String, dynamic>
        ? data
        : const <String, dynamic>{};
    return Appearance(
      mode: ThemeMode.values.firstWhere(
        (mode) => mode.name == values['theme'],
        orElse: () => ThemeMode.system,
      ),
      font: InterfaceFont.values.firstWhere(
        (font) => font.name == values['font'],
        orElse: () => InterfaceFont.miSans,
      ),
    );
  }

  final ThemeMode mode;
  final InterfaceFont font;

  String encode() => jsonEncode({'theme': mode.name, 'font': font.name});
}

class PageLoomApp extends StatefulWidget {
  const PageLoomApp({super.key, this.appearanceStorage, this.historyStorage});

  final File? appearanceStorage;
  final File? historyStorage;

  @override
  State<PageLoomApp> createState() => _PageLoomAppState();
}

class _PageLoomAppState extends State<PageLoomApp> {
  Appearance _appearance = const Appearance();
  Future<void> _pendingWrite = Future.value();
  bool _userChangedAppearance = false;

  File get _file =>
      widget.appearanceStorage ??
      File.fromUri(appDataDirectory.uri.resolve('appearance.json'));

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
  }

  Future<void> _loadAppearance() async {
    Appearance saved;
    try {
      saved = Appearance.fromJson(jsonDecode(await _file.readAsString()));
    } on Exception {
      return;
    }
    if (mounted && !_userChangedAppearance) {
      setState(() => _appearance = saved);
      if (saved.mode != ThemeMode.system) unawaited(_syncTitleBar(saved.mode));
    }
  }

  Future<void> _changeAppearance(Appearance next) {
    _userChangedAppearance = true;
    if (_appearance.mode != next.mode) unawaited(_syncTitleBar(next.mode));
    setState(() => _appearance = next);
    final file = _file;
    final write = _pendingWrite.then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.$pid.tmp');
      await temp.writeAsString(next.encode(), flush: true);
      await temp.rename(file.path);
    });
    _pendingWrite = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _syncTitleBar(ThemeMode mode) async {
    try {
      await windows.invokeMethod<void>('setThemeMode', mode.name);
    } on PlatformException {
      // The client area still uses the selected Flutter theme.
    } on MissingPluginException {
      // Non-Windows builds have no native title-bar bridge.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PageLoom',
    debugShowCheckedModeBanner: false,
    themeMode: _appearance.mode,
    themeAnimationDuration: Duration.zero,
    theme: _interfaceTheme(
      _lightColors,
      const Color(0xffefedf0),
      _appearance.font,
    ),
    darkTheme: _interfaceTheme(
      _darkColors,
      const Color(0xff181a20),
      _appearance.font,
    ),
    home: Desktop(
      historyStorage: widget.historyStorage,
      appearance: _appearance,
      onAppearanceChanged: _changeAppearance,
    ),
  );
}

const _lightColors = ColorScheme.light(
  primary: Color(0xff145bc6),
  primaryContainer: Color(0xffdfe9fa),
  onPrimaryContainer: Color(0xff153f80),
  secondary: Color(0xff145bc6),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xffdfe9fa),
  onSecondaryContainer: Color(0xff153f80),
  surface: Color(0xfffaf8fa),
  surfaceContainerHighest: Color(0xffeeedf0),
  onSurface: Color(0xff171d28),
  onSurfaceVariant: Color(0xff515969),
  outline: Color(0xff787f8e),
  outlineVariant: Color(0xffd3d1d6),
  error: Color(0xffaa2433),
);

const _darkColors = ColorScheme.dark(
  primary: Color(0xffa9c7ff),
  onPrimary: Color(0xff0c2c59),
  primaryContainer: Color(0xff28436a),
  onPrimaryContainer: Color(0xffd9e6ff),
  secondary: Color(0xffa9c7ff),
  onSecondary: Color(0xff0c2c59),
  secondaryContainer: Color(0xff28436a),
  onSecondaryContainer: Color(0xffd9e6ff),
  surface: Color(0xff23262e),
  surfaceContainerLow: Color(0xff262a33),
  surfaceContainerHigh: Color(0xff2c303a),
  surfaceContainerHighest: Color(0xff303540),
  onSurface: Color(0xffedf0f7),
  onSurfaceVariant: Color(0xffb9c1d1),
  outline: Color(0xff929bad),
  outlineVariant: Color(0xff414756),
  error: Color(0xffffb3bd),
);

ThemeData _interfaceTheme(
  ColorScheme colors,
  Color background,
  InterfaceFont font,
) {
  return ThemeData(
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    fontFamily: font.family,
    fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

extension _AppearanceLayout on _DesktopState {
  ColorScheme get colors => Theme.of(context).colorScheme;
  bool get dark => colors.brightness == Brightness.dark;
  Color get muted => colors.onSurfaceVariant;
  Color get inset => colors.surfaceContainerHighest;
  Color get success => dark ? const Color(0xff214734) : const Color(0xffa4f89d);
  Color get onSuccess =>
      dark ? const Color(0xffadf2c7) : const Color(0xff164623);

  Future<void> changeAppearance(Appearance next) async {
    try {
      await widget.onAppearanceChanged?.call(next);
    } on FileSystemException {
      if (mounted) message('外观已应用，保存设置失败');
    }
  }

  Widget appearancePanel() {
    final appearance = widget.appearance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PanelTitle(Icons.contrast_rounded, '界面主题'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (mode, label, icon) in const [
                    (ThemeMode.system, '跟随系统', Icons.desktop_windows_outlined),
                    (ThemeMode.light, '亮色', Icons.light_mode_outlined),
                    (ThemeMode.dark, '暗色', Icons.dark_mode_outlined),
                  ])
                    ChoiceChip(
                      avatar: Icon(
                        icon,
                        size: 18,
                        color: appearance.mode == mode
                            ? colors.onSecondaryContainer
                            : muted,
                      ),
                      label: Text(label),
                      selected: appearance.mode == mode,
                      showCheckmark: false,
                      onSelected: (_) => changeAppearance(
                        Appearance(mode: mode, font: appearance.font),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PanelTitle(Icons.font_download_outlined, '界面字体'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final font in InterfaceFont.values)
                    ChoiceChip(
                      label: Text(
                        font.label,
                        style: TextStyle(fontFamily: font.family),
                      ),
                      selected: appearance.font == font,
                      onSelected: (_) => changeAppearance(
                        Appearance(mode: appearance.mode, font: font),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          padding: const EdgeInsets.all(8),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于'),
            subtitle: const Text('版本、项目链接与字体许可'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => update(() => page = _aboutPage),
          ),
        ),
      ],
    );
  }
}

class _AboutPage extends StatefulWidget {
  const _AboutPage();

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  static const _project = 'https://github.com/XilinGuo/PageLoom';
  static const _links = [
    (Icons.code_rounded, '项目', _project),
    (
      Icons.memory_rounded,
      '翻译引擎',
      'https://github.com/PDFMathTranslate-next/PDFMathTranslate-next',
    ),
    (
      Icons.auto_stories_outlined,
      '文档排版',
      'https://github.com/funstory-ai/BabelDOC',
    ),
  ];

  late final Future<String?> _version = _readVersion();

  Future<String?> _readVersion() async {
    try {
      return (await windows.invokeMethod<String>(
        'appVersion',
      ))?.split('+').first;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _openLink(String url) async {
    try {
      if (await windows.invokeMethod<bool>('openUrl', url) == true) return;
    } on PlatformException {
      // Report the failure in the page below.
    } on MissingPluginException {
      // Report the failure in the page below.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 26),
        Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Padding(
                padding: EdgeInsets.all(21),
                child: PageLoomMark(size: 70),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PageLoom',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FutureBuilder<String?>(
                  future: _version,
                  builder: (context, snapshot) => snapshot.hasData
                      ? _tag(
                          'v${snapshot.data}',
                          colors.primary,
                          colors.onPrimary,
                        )
                      : const SizedBox.shrink(),
                ),
                _tag('AGPL-3.0', colors.surface, colors.onSurface),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '基于 Flutter 的 Windows PDF 翻译工具，保留文档排版、公式和图表。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _openLink('$_project/releases'),
              icon: const Icon(Icons.system_update_alt_rounded, size: 19),
              label: const Text('查看更新'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 10),
          child: Text(
            '更多',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, (icon, title, url)) in _links.indexed) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 66, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.surfaceContainerHighest,
                    foregroundColor: colors.onSurfaceVariant,
                    child: Icon(icon),
                  ),
                  title: Text(title),
                  subtitle: Text(
                    Uri.parse(url).authority + Uri.parse(url).path,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _openLink(url),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '界面使用 MiSans 和 HarmonyOS Sans 字体。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            TextButton(
              onPressed: () =>
                  _openLink('https://hyperos.mi.com/font/zh/download/'),
              child: const Text('MiSans 许可'),
            ),
            TextButton(
              onPressed: () async {
                final license = await rootBundle.loadString(
                  'assets/fonts/HarmonyOS-Sans-LICENSE.txt',
                );
                if (!context.mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('HarmonyOS Sans 许可'),
                    content: SingleChildScrollView(
                      child: SelectableText(license.replaceAll('\u0000', '')),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('HarmonyOS Sans 许可'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tag(String label, Color background, Color foreground) => DecoratedBox(
    decoration: ShapeDecoration(
      color: background,
      shape: const StadiumBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
