part of 'main.dart';

const stageNames = {
  'Parse PDF and Create Intermediate Representation': '解析 PDF',
  'DetectScannedFile': '检测扫描页',
  'Detect Scanned File': '检测扫描页',
  'Parse Page Layout': '分析页面排版',
  'Parse Paragraphs': '识别段落',
  'Parse Formulas and Styles': '识别公式和样式',
  'Translate': '翻译内容',
  'Translate Paragraphs': '翻译段落',
  'Typesetting': '重新排版',
  'Add Fonts': '嵌入字体',
  'Generate drawing instructions': '生成绘制指令',
  'Subset font': '精简字体',
  'Save PDF': '保存 PDF',
};

extension _WorkspaceLayout on _DesktopState {
  Widget workspaceFrame() {
    final compact = MediaQuery.sizeOf(context).width < 870;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: compact ? 70 : 216, child: sidebar(compact)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 27,
                25,
                compact ? 18 : 27,
                0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header(),
                      const SizedBox(height: 26),
                      Expanded(
                        child: page == 1
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: historyPanel(),
                              )
                            : SingleChildScrollView(
                                key: PageStorageKey(page),
                                padding: const EdgeInsets.only(bottom: 36),
                                child: switch (page) {
                                  0 => Column(
                                    children: [
                                      responsivePair(
                                        importPanel(),
                                        progressPanel(),
                                      ),
                                      const SizedBox(height: 17),
                                      responsivePair(
                                        optionsPanel(),
                                        resultsPanel(),
                                      ),
                                    ],
                                  ),
                                  2 => settingsPanel(),
                                  _ => logsPanel(),
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget sidebar(bool compact) {
    const destinations = [
      (Icons.dashboard_rounded, '翻译工作台'),
      (Icons.history_rounded, '任务记录'),
      (Icons.tune_rounded, '翻译设置'),
      (Icons.terminal_rounded, '运行日志'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xffe4e2e5),
        border: Border(right: BorderSide(color: Color(0xffd3d1d6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 25, 11, 27),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: blue,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PDFMath',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'TRANSLATE NEXT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.1,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 12, 9),
              child: Text('工作区', style: TextStyle(color: muted, fontSize: 12)),
            ),
          for (var index = 0; index < destinations.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Tooltip(
                message: compact ? destinations[index].$2 : '',
                child: Material(
                  color: page == index
                      ? const Color(0xffd3d1d6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    onTap: () => update(() => page = index),
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              color: page == index ? blue : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(destinations[index].$1, size: 23, color: ink),
                          if (!compact) ...[
                            const SizedBox(width: 12),
                            Text(
                              destinations[index].$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget header() {
    const titles = ['翻译工作台', '任务记录', '翻译设置', '运行日志'];
    const subtitles = [
      '保留排版、公式和图表的 PDF 翻译',
      '查看翻译结果和历史任务',
      '配置翻译服务、术语提取和 PDF 排版',
      '查看翻译引擎的进度、警告和错误',
    ];
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titles[page],
                style: const TextStyle(
                  fontSize: 33,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitles[page],
                style: const TextStyle(color: muted, fontSize: 14),
              ),
            ],
          ),
        ),
        statusBadge(
          busy ? '任务运行中' : '工作区就绪',
          busy ? tint : green,
          busy ? Icons.sync_rounded : Icons.check_rounded,
        ),
      ],
    );
  }

  Widget responsivePair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 690) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 17), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 17),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }

  Widget importPanel() => panel(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(29),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: WavePainter())),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PanelTitle(Icons.description_outlined, '源文档'),
                      const SizedBox(height: 17),
                      Text(
                        source == null ? '导入 PDF' : basename(source!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        source ?? '选择本机的 PDF 文件开始翻译',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : chooseSource,
                        icon: const Icon(Icons.folder_open_rounded, size: 19),
                        label: Text(source == null ? '选择 PDF' : '更换文件'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: busy
                      ? '取消翻译'
                      : source == null
                      ? '选择 PDF'
                      : '开始翻译',
                  child: Semantics(
                    button: true,
                    child: InkResponse(
                      onTap: busy
                          ? (cancelling ? null : cancel)
                          : (source == null
                                ? chooseSource
                                : historyLoaded &&
                                      settingsReady &&
                                      !settingsLocked
                                ? start
                                : null),
                      radius: 47,
                      child: CustomPaint(
                        painter: FlowerPainter(cancelling ? muted : blue),
                        child: SizedBox.square(
                          dimension: 83,
                          child: Icon(
                            busy
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 37,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget progressPanel() {
    final percent = progress == null ? '—' : '${(progress! * 100).round()}%';
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(Icons.monitor_heart_outlined, '翻译进度'),
          const SizedBox(height: 13),
          Text(
            percent,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 13),
          LinearProgressIndicator(
            value: busy ? progress : progress ?? 0,
            borderRadius: BorderRadius.circular(10),
            minHeight: 8,
            backgroundColor: inset,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: statusBadge(
                  serviceLabel(engine),
                  inset,
                  Icons.cloud_outlined,
                ),
              ),
              const Spacer(),
              if (busy)
                TextButton(
                  onPressed: cancelling ? null : cancel,
                  child: const Text('取消任务'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget optionsPanel() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelTitle(Icons.tune_rounded, '翻译选项'),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: languagePicker(
                '源语言',
                from,
                (value) => update(() => from = value),
              ),
            ),
            IconButton(
              onPressed: settingsLocked ? null : swapLanguages,
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: '交换语言',
            ),
            Expanded(
              child: languagePicker(
                '目标语言',
                to,
                (value) => update(() => to = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        const Text(
          '输出模式',
          style: TextStyle(color: muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in outputFormats.entries)
              ChoiceChip(
                label: Text(item.value),
                selected: format == item.key,
                onSelected: settingsLocked
                    ? null
                    : (_) => update(() => format = item.key),
                showCheckmark: false,
                backgroundColor: inset,
                selectedColor: blue,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: format == item.key ? Colors.white : ink,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (settingsReady)
          for (final control in pageControls())
            Padding(padding: const EdgeInsets.only(bottom: 8), child: control),
        const SizedBox(height: 12),
        Material(
          color: inset,
          borderRadius: BorderRadius.circular(17),
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text(
              '输出位置',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              outputRoot ?? '在源文件所在位置创建任务文件夹',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: busy ? null : chooseOutput,
          ),
        ),
      ],
    ),
  );

  Widget resultsPanel() {
    final entry = latest;
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(Icons.inventory_2_outlined, '输出文件'),
          const SizedBox(height: 16),
          if (error case final String message)
            SelectableText(
              message,
              style: const TextStyle(color: Color(0xffaa2433)),
            )
          else if (entry != null && entry['status'] == '已完成')
            ...resultButtons(entry)
          else
            emptyState(
              Icons.picture_as_pdf_outlined,
              entry?['status'] == '已取消' ? '任务已取消' : '暂无输出',
              '翻译完成后可在此打开 PDF。',
            ),
        ],
      ),
    );
  }

  List<Widget> resultButtons(Map<String, dynamic> entry) => [
    for (final item in (entry['files'] as List<dynamic>? ?? []))
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: OutlinedButton.icon(
          onPressed: () => openPath(item['path'] as String),
          icon: Icon(
            item['kind'] == 'glossary'
                ? Icons.menu_book_outlined
                : Icons.picture_as_pdf_outlined,
            size: 17,
          ),
          label: Text(switch (item['kind']) {
            'mono' => '打开单语 PDF',
            'glossary' => '打开自动提取的术语表',
            _ => '打开双语 PDF',
          }),
        ),
      ),
    TextButton.icon(
      onPressed: () => openPath(entry['output'] as String),
      icon: const Icon(Icons.folder_open_outlined, size: 17),
      label: const Text('打开输出目录'),
    ),
  ];

  Widget historyPanel() {
    final canClean = historyLoaded && !busy && !historyCleaning;
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelTitle(Icons.history_rounded, '最近的翻译任务'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: canClean && selectedHistory.isNotEmpty
                    ? () => clearHistory()
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('清理所选'),
              ),
              TextButton(
                onPressed: canClean && history.isNotEmpty
                    ? () => clearHistory(all: true)
                    : null,
                child: const Text('全部清理'),
              ),
              if (selectedHistory.isNotEmpty)
                Text(
                  '已选 ${selectedHistory.length} 条',
                  style: const TextStyle(color: muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (historyError)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('本地记录读取或保存失败。', style: TextStyle(color: muted)),
            ),
          if (!historyLoaded || historyCleaning)
            const LinearProgressIndicator(),
          if (historyLoaded && history.isEmpty)
            emptyState(Icons.history_rounded, '暂无任务', '翻译记录将在这里显示。')
          else if (historyLoaded)
            Expanded(
              child: ListView.separated(
                key: const PageStorageKey('history-list'),
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    historyRow(history[index], canClean),
              ),
            ),
        ],
      ),
    );
  }

  Widget historyRow(Map<String, dynamic> entry, bool canSelect) {
    final completed = entry['status'] == '已完成';
    final id = entry['output'] as String;
    return Material(
      color: inset,
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        key: ObjectKey(entry),
        leading: Checkbox(
          value: selectedHistory.contains(id),
          semanticLabel: '选择 ${entry['name']}',
          onChanged: canSelect
              ? (checked) => update(() {
                  if (checked == true) {
                    selectedHistory.add(id);
                  } else {
                    selectedHistory.remove(id);
                  }
                })
              : null,
        ),
        title: Text(entry['name'] as String, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          (entry['at'] as String).replaceFirst('T', ' ').split('.').first,
        ),
        trailing: statusBadge(
          entry['status'] as String,
          completed ? green : paper,
          completed ? Icons.check_rounded : Icons.info_outline_rounded,
        ),
        onTap: completed
            ? () => showDialog<void>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (context) => AlertDialog(
                  title: Text(entry['name'] as String),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: resultButtons(entry),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  Widget languagePicker(
    String label,
    String value,
    ValueChanged<String> onSelected,
  ) => choicePicker(
    label,
    value,
    settings.languages,
    onSelected,
    showCodes: true,
  );

  Widget choicePicker(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onSelected, {
    bool showCodes = false,
  }) {
    return OutlinedButton(
      onPressed: settingsLocked
          ? null
          : () async {
              final selected = await showDialog<String>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (_) => ChoiceDialog(
                  label: label,
                  current: value,
                  options: options,
                  showCodes: showCodes,
                ),
              );
              if (mounted && selected != null && !settingsLocked) {
                onSelected(selected);
              }
            },
      style: OutlinedButton.styleFrom(
        backgroundColor: inset,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        side: BorderSide.none,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: muted)),
                Text(
                  options[value] ?? value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 20),
        ],
      ),
    );
  }
}

class ChoiceDialog extends StatefulWidget {
  const ChoiceDialog({
    super.key,
    required this.label,
    required this.current,
    required this.options,
    required this.showCodes,
  });

  final String label;
  final String current;
  final Map<String, String> options;
  final bool showCodes;

  @override
  State<ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<ChoiceDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.options.entries
        .where(
          (entry) =>
              entry.key.toLowerCase().contains(query) ||
              entry.value.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.showCodes ? '搜索语言或代码' : '搜索选项',
              ),
              onChanged: (value) =>
                  setState(() => query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('没有匹配的选项'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final entry = matches[index];
                        return ListTile(
                          dense: true,
                          selected: entry.key == widget.current,
                          title: Text(entry.value),
                          trailing: widget.showCodes ? Text(entry.key) : null,
                          onTap: () => Navigator.pop(context, entry.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

Widget panel({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(22),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(29),
      boxShadow: const [
        BoxShadow(
          color: Color(0x110d182b),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

Widget statusBadge(String text, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: ink),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    ),
  );
}

Widget emptyState(IconData icon, String title, String body) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: inset,
      borderRadius: BorderRadius.circular(19),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: muted, size: 23),
        const SizedBox(height: 9),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: muted, size: 20),
      const SizedBox(width: 8),
      Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class WavePainter extends CustomPainter {
  const WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * .65;
    final h = size.height;
    final path = Path()
      ..moveTo(x, 0)
      ..cubicTo(x + 24, h * .23, x - 34, h * .24, x - 10, h * .46)
      ..cubicTo(x + 13, h * .63, x - 16, h * .79, x + 42, h * .85)
      ..quadraticBezierTo(x + 74, h * .89, x + 83, h)
      ..lineTo(size.width, h)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = tint);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) => false;
}

class FlowerPainter extends CustomPainter {
  const FlowerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final path = Path();
    for (var step = 0; step < 180; step++) {
      final angle = step * 2 * math.pi / 180;
      final radius = size.shortestSide * (.455 + .036 * math.cos(8 * angle));
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (step == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawShadow(path, color.withValues(alpha: .5), 11, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(FlowerPainter oldDelegate) => oldDelegate.color != color;
}
