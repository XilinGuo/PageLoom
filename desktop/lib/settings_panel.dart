part of 'main.dart';

extension _SettingsPanel on _DesktopState {
  File get settingsFile => File('${historyFile.parent.path}\\settings.dat');
  String get backend =>
      '${File(Platform.resolvedExecutable).parent.path}\\engine';
  bool get settingsLocked => busy || savingSettings || settingsLoading;

  Future<Settings> bridgeCommand(List<String> args, {Settings? input}) async {
    final process = await Process.start('$backend\\runtime\\pythonw.exe', [
      '$backend\\bridge.py',
      ...args,
    ], workingDirectory: backend);
    process.stdin.done.ignore();
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr.drain<void>();
    if (input != null) process.stdin.writeln(jsonEncode(input));
    await process.stdin.close();
    final output = await stdout;
    await stderr;
    final exitCode = await process.exitCode;
    for (final line in const LineSplitter().convert(output).reversed) {
      if (!line.startsWith('PDFMATH ')) continue;
      final event = jsonDecode(line.substring(8)) as Settings;
      if (exitCode == 0) return event;
      throw FormatException(
        redactLog(event['message'].toString(), settings.credentials()),
      );
    }
    throw StateError('翻译引擎未返回数据（退出码 $exitCode）');
  }

  Future<void> loadSettings() async {
    if (!settingsLoading) update(() => settingsLoading = true);
    try {
      final schemaFile = File('$backend\\settings-schema.json');
      final schema = jsonDecode(await schemaFile.readAsString()) as Settings;
      if (!mounted) return;
      settings.readSchema(schema);
      settingsReady = true;
      if (await settingsFile.exists()) {
        final encrypted = await settingsFile.readAsBytes();
        final plain = await windows.invokeMethod<Uint8List>(
          'unprotectSettings',
          encrypted,
        );
        if (plain == null) throw const FormatException('无法解密本地设置');
        final saved = jsonDecode(utf8.decode(plain)) as Settings;
        if (!mounted) return;
        settings.restore(saved);
        if (saved['engine'] case final String id
            when settings.engines.any((entry) => entry['id'] == id)) {
          engine = id;
        }
        if (settings.languages.containsKey(saved['from'])) {
          from = saved['from'] as String;
        }
        if (settings.languages.containsKey(saved['to'])) {
          to = saved['to'] as String;
        }
        if (outputFormats.containsKey(saved['format'])) {
          format = saved['format'] as String;
        }
        pages.text = saved['pages'] as String? ?? '';
        outputRoot = saved['outputRoot'] as String?;
      }
      appendLog('INFO', '已载入翻译引擎设置');
    } on Object catch (error) {
      appendLog('ERROR', '无法载入设置：$error');
      if (mounted) message('无法载入设置，请在运行日志中查看详情');
    } finally {
      if (mounted) update(() => settingsLoading = false);
    }
  }

  Future<void> saveSettings() async {
    if (settingsLocked) return;
    final saved = {
      ...settings.snapshot(),
      'engine': engine,
      'from': from,
      'to': to,
      'format': format,
      'pages': pages.text,
      'outputRoot': outputRoot,
    };
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(saved)));
    update(() => savingSettings = true);
    try {
      await bridgeCommand(['--validate'], input: translationSettings());
      final encrypted = await windows.invokeMethod<Uint8List>(
        'protectSettings',
        plain,
      );
      if (encrypted == null) throw StateError('无法加密本地设置');
      await settingsFile.parent.create(recursive: true);
      final temp = File('${settingsFile.path}.$pid.tmp');
      await temp.writeAsBytes(encrypted, flush: true);
      await temp.rename(settingsFile.path);
      if (mounted) message('设置已保存');
      appendLog('INFO', '已保存翻译设置');
    } on Object catch (error) {
      final detail = error is FormatException
          ? error.message
          : error.toString();
      if (mounted) message('保存失败：$detail');
      appendLog('ERROR', '设置保存失败：$detail');
    } finally {
      if (mounted) update(() => savingSettings = false);
    }
  }

  Settings translationSettings() => {
    'engine': settings.engineRequest(engine, term: false),
    'termEngine': settings.termEngine.isEmpty
        ? null
        : settings.engineRequest(settings.termEngine, term: true),
    'from': from,
    'to': to,
    'format': format,
    'pages': switch (settings.pageRange) {
      'first' => '1',
      'first5' => '1-5',
      'range' => pages.text.trim(),
      _ => '',
    },
    'rate': settings.rate,
    'termRate': settings.termRate,
    'translation': settings.translation,
    'pdf': settings.pdf,
    'glossaries': settings.supportsLlm(engine) ? settings.glossaries : [],
  };

  void appendLog(String level, String message) {
    if (!mounted || message.trim().isEmpty) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    logs.addFirst((level, '[$time] $level $message'));
    if (logs.length > 1500) logs.removeLast();
    if (page == 3) scheduleLogRefresh();
  }

  Future<void> glossaryPreview({String? existing}) async {
    if (loadingGlossary || settingsLocked) return;
    update(() => loadingGlossary = true);
    try {
      final path =
          existing ?? await windows.invokeMethod<String>('chooseGlossary');
      if (path == null || !mounted) return;
      final event = await bridgeCommand(['--glossary', path, to]);
      if (!mounted) return;
      if (!settings.glossaries.contains(path)) {
        update(() => settings.glossaries.add(path));
      }
      final rows = (event['rows'] as List).cast<List<dynamic>>();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(basename(path)),
          content: SizedBox(
            width: 520,
            height: 340,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('适用于当前目标语言的条目：${event['count']}（最多预览 100 条）'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) => ListTile(
                      dense: true,
                      title: Text(rows[index][0].toString()),
                      subtitle: Text(rows[index][1].toString()),
                    ),
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
        ),
      );
    } on Exception catch (error) {
      if (mounted) message('术语表读取失败：$error');
      appendLog('ERROR', '术语表读取失败：$error');
    } finally {
      if (mounted) update(() => loadingGlossary = false);
    }
  }

  Widget settingsPanel() {
    if (settingsLoading) return panel(child: const LinearProgressIndicator());
    if (!settingsReady) {
      return panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('无法读取翻译服务配置，请检查便携目录是否完整。'),
            TextButton(onPressed: loadSettings, child: const Text('重新加载')),
          ],
        ),
      );
    }
    final extraction = !(translationValue('no_auto_extract_glossary') as bool);
    final canExtract =
        settings.termEngine.isNotEmpty || settings.supportsLlm(engine);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: PanelTitle(Icons.tune_rounded, '翻译设置')),
                  FilledButton.icon(
                    onPressed: settingsLocked ? null : saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(savingSettings ? '正在保存…' : '保存设置'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '修改立即用于新任务。保存后，设置由当前 Windows 用户加密保留。',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        settingGroup(
          '翻译服务与速率限制',
          Icons.cloud_outlined,
          () => [
            settingsChoice('主翻译服务', engine, {
              for (final item in settings.engines)
                item['id'] as String: serviceLabel(item['id'] as String),
            }, (id) => update(() => engine = id)),
            ...engineInputs(engine, term: false),
            if (engine == 'SiliconFlowFree')
              const Text('硅基流动免费服务提供，固定速率为 20 QPS。')
            else
              ...rateInputs(settings.rate, term: false),
          ],
        ),
        const SizedBox(height: 13),
        settingGroup(
          '自动术语提取与术语表',
          Icons.menu_book_outlined,
          () => [
            toggle(
              '启用自动术语提取',
              extraction,
              (value) => update(
                () => settings.translation['no_auto_extract_glossary'] = !value,
              ),
            ),
            if (extraction) ...[
              settingsChoice(
                '术语提取服务',
                settings.termEngine,
                {
                  '': '跟随主翻译服务',
                  for (final item in settings.engines.where(
                    (item) => item['llm'] == true,
                  ))
                    item['id'] as String: serviceLabel(item['id'] as String),
                },
                (id) => update(() => settings.termEngine = id),
              ),
              if (!canExtract)
                const Text(
                  '当前主服务不支持自动术语提取。可在此单独选择一个支持的服务。',
                  style: TextStyle(color: muted),
                ),
              if (settings.termEngine.isNotEmpty)
                ...engineInputs(settings.termEngine, term: true),
              if (canExtract) ...rateInputs(settings.termRate, term: true),
              if (canExtract)
                translationToggle('save_auto_extracted_glossary', '输出自动提取的术语表'),
            ],
            if (settings.supportsLlm(engine)) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: settingsLocked || loadingGlossary
                      ? null
                      : () => glossaryPreview(),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('添加 CSV 术语表'),
                ),
              ),
              const Text('CSV 须包含 source 和 target 列，可用 tgt_lng 列限定目标语言。'),
              for (final path in settings.glossaries)
                ListTile(
                  title: Text(basename(path)),
                  onTap: settingsLocked || loadingGlossary
                      ? null
                      : () => glossaryPreview(existing: path),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '移除术语表',
                    onPressed: settingsLocked || loadingGlossary
                        ? null
                        : () => update(() => settings.glossaries.remove(path)),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 13),
        settingGroup(
          '页码与 PDF 输出',
          Icons.picture_as_pdf_outlined,
          () => [
            ...pageControls(),
            settingsChoice(
              '输出模式',
              format,
              outputFormats,
              (value) => update(() => format = value),
            ),
            pdfToggle('dual_translate_first', '双语模式下译文在前'),
            pdfToggle('use_alternating_pages_dual', '双语 PDF 使用交替页面'),
            settingsChoice(
              '水印模式',
              pdfValue('watermark_output_mode') as String,
              const {'watermarked': '带水印', 'no_watermark': '无水印'},
              (value) =>
                  update(() => settings.pdf['watermark_output_mode'] = value),
            ),
          ],
        ),
        const SizedBox(height: 13),
        settingGroup(
          '高级翻译',
          Icons.translate_rounded,
          () => [
            input(
              '自定义系统提示词',
              'custom_system_prompt',
              translationValue('custom_system_prompt'),
              (value) => settings.translation['custom_system_prompt'] = value,
              multiline: true,
            ),
            input(
              '最小翻译文本长度',
              'min_text_length',
              translationValue('min_text_length'),
              (value) => settings.translation['min_text_length'] = value,
              kind: 'int',
            ),
            settingsChoice(
              '译文主字体族',
              (translationValue('primary_font_family') as String?) ?? '',
              const {
                '': '自动',
                'serif': '衬线',
                'sans-serif': '无衬线',
                'script': '手写／斜体',
              },
              (value) => update(
                () => settings.translation['primary_font_family'] =
                    value.isEmpty ? null : value,
              ),
            ),
            translationToggle('ignore_cache', '忽略翻译缓存'),
          ],
        ),
        const SizedBox(height: 13),
        settingGroup(
          '排版与扫描件',
          Icons.document_scanner_outlined,
          () => [
            pdfToggle('skip_clean', '跳过 PDF 清理'),
            pdfToggle('disable_rich_text_translate', '禁用富文本翻译'),
            pdfToggle('enhance_compatibility', '启用兼容性增强'),
            pdfToggle('split_short_lines', '强制拆分短行'),
            if (pdfValue('split_short_lines') == true)
              pdfSlider(
                'short_line_split_factor',
                '短行拆分阈值',
                minimum: .1,
                divisions: 9,
              ),
            pdfToggle('translate_table_text', '翻译表格文字（实验）'),
            pdfToggle('skip_scanned_detection', '跳过扫描件检测'),
            pdfToggle('ocr_workaround', 'OCR 变通模式（实验）'),
            pdfToggle('auto_enable_ocr_workaround', '自动为重度扫描件启用 OCR 变通模式'),
            input(
              '每部分最大页数（0 为不限）',
              'max_pages_per_part',
              pdfValue('max_pages_per_part'),
              (value) => settings.pdf['max_pages_per_part'] = value == 0
                  ? null
                  : value,
              kind: 'int',
            ),
            input(
              '公式字体匹配（正则）',
              'formular_font_pattern',
              pdfValue('formular_font_pattern'),
              (value) => settings.pdf['formular_font_pattern'] = value,
            ),
            input(
              '公式字符匹配（正则）',
              'formular_char_pattern',
              pdfValue('formular_char_pattern'),
              (value) => settings.pdf['formular_char_pattern'] = value,
            ),
          ],
        ),
        const SizedBox(height: 13),
        settingGroup(
          'BabelDOC 高级选项',
          Icons.integration_instructions_outlined,
          () => [
            pdfToggle(
              'no_merge_alternating_line_numbers',
              '合并交替行号',
              invert: true,
            ),
            pdfToggle('no_remove_non_formula_lines', '移除非公式线条', invert: true),
            pdfSlider('non_formula_line_iou_threshold', '非公式线条 IoU 阈值'),
            pdfSlider('figure_table_protection_threshold', '图表保护阈值'),
            pdfToggle('skip_formula_offset_calculation', '跳过公式偏移计算'),
          ],
        ),
      ],
    );
  }

  List<Widget> pageControls() => [
    settingsChoice(
      '翻译页码',
      settings.pageRange,
      pageRanges,
      (value) => update(() => settings.pageRange = value),
    ),
    if (settings.pageRange == 'range')
      TextField(
        controller: pages,
        enabled: !settingsLocked,
        decoration: const InputDecoration(
          labelText: '自定义页码',
          hintText: '例如 1,3,5-10,-5',
        ),
      ),
    pdfToggle('only_include_translated_page', '输出仅包含已翻译的页面'),
  ];

  Widget settingGroup(
    String label,
    IconData icon,
    List<Widget> Function() buildControls,
  ) {
    final expanded = openSettingGroups.contains(label);
    return panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 5,
            ),
            title: PanelTitle(icon, label),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => update(() {
              if (expanded) {
                openSettingGroups.remove(label);
              } else {
                openSettingGroups.add(label);
              }
            }),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in buildControls())
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: child,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> engineInputs(String id, {required bool term}) {
    final fields = settings.fields(id);
    final values = settings.values(id, term: term);
    return [
      for (final field in fields)
        if (settings.visible(field, fields, values))
          engineInput(id, field, values, term: term),
    ];
  }

  Widget engineInput(
    String id,
    Settings field,
    Settings values, {
    required bool term,
  }) {
    final name = field['name'] as String;
    final label = field['label'] as String;
    final value = settings.fieldValue(field, values);
    if (field['choices'] case final List choices) {
      return settingsChoice(
        label,
        value?.toString() ?? '',
        {
          for (final choice in choices)
            if (choice is List)
              choice[1]?.toString() ?? '': choice[1] == null
                  ? '未设置'
                  : choice[0].toString()
            else
              choice.toString(): choice.toString(),
        },
        (value) => update(() => values[name] = value.isEmpty ? null : value),
      );
    }
    if (field['type'] == 'bool') {
      return toggle(
        label,
        value == true,
        (value) => update(() => values[name] = value),
      );
    }
    return input(
      label,
      '$term:$id:$name',
      value,
      (value) => values[name] = value,
      kind: field['type'] as String,
      secret: field['secret'] == true,
    );
  }

  List<Widget> rateInputs(Settings rate, {required bool term}) => [
    settingsChoice(
      term ? '术语提取速率模式' : '翻译速率模式',
      rate['mode'] as String,
      {
        if (term) 'inherit': '跟随主翻译速率',
        'RPM': '每分钟请求数（RPM）',
        'Concurrent Threads': '并发线程',
        'Custom': '自定义 QPS / 线程池',
      },
      (value) => update(() => rate['mode'] = value),
    ),
    for (final (mode, name, label) in const [
      ('RPM', 'rpm_input', '每分钟请求数'),
      ('Concurrent Threads', 'concurrent_threads', '并发线程数'),
      ('Custom', 'custom_qps', '每秒请求数（QPS）'),
      ('Custom', 'custom_pool_workers', '线程池上限（留空或 0 为默认）'),
    ])
      if (rate['mode'] == mode)
        input(
          label,
          '$term:$name',
          rate[name],
          (value) => rate[name] = value,
          kind: 'int',
        ),
  ];

  Object? pdfValue(String key) => settings.pdf.containsKey(key)
      ? settings.pdf[key]
      : settings.pdfDefaults[key];
  Object? translationValue(String key) => settings.translation.containsKey(key)
      ? settings.translation[key]
      : settings.translationDefaults[key];

  Widget toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: settingsLocked ? null : onChanged,
      );

  Widget pdfToggle(String name, String label, {bool invert = false}) => toggle(
    label,
    (pdfValue(name) == true) != invert,
    (value) => update(() => settings.pdf[name] = value != invert),
  );

  Widget translationToggle(String name, String label) => toggle(
    label,
    translationValue(name) == true,
    (value) => update(() => settings.translation[name] = value),
  );

  Widget pdfSlider(
    String name,
    String label, {
    double minimum = 0,
    int divisions = 20,
  }) {
    final value = (pdfValue(name) as num).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · ${value.toStringAsFixed(2)}'),
        Slider(
          value: value,
          min: minimum,
          max: 1,
          divisions: divisions,
          onChanged: settingsLocked
              ? null
              : (value) => update(() => settings.pdf[name] = value),
        ),
      ],
    );
  }

  Widget settingsChoice(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> onChanged,
  ) {
    if (choices.length > 4) {
      return choicePicker(label, value, choices, onChanged);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted)),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in choices.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: entry.key == value,
                onSelected: settingsLocked ? null : (_) => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }

  Widget input(
    String label,
    String id,
    Object? value,
    ValueChanged<dynamic> onChanged, {
    String kind = 'str',
    bool secret = false,
    bool multiline = false,
  }) {
    return TextFormField(
      key: ValueKey(id),
      initialValue: value?.toString(),
      enabled: !settingsLocked,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      maxLines: multiline ? 4 : 1,
      keyboardType: kind == 'int' ? TextInputType.number : TextInputType.text,
      inputFormatters: kind == 'int'
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => onChanged(
        kind == 'int'
            ? int.tryParse(text)
            : text.trim().isEmpty
            ? null
            : text,
      ),
    );
  }

  Widget logsPanel() {
    final visible = logs
        .where(
          (line) => switch (logLevel) {
            'error' => line.$1 == 'ERROR' || line.$1 == 'CRITICAL',
            'warning' => const {
              'WARNING',
              'ERROR',
              'CRITICAL',
            }.contains(line.$1),
            _ => true,
          },
        )
        .toList();
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelTitle(Icons.terminal_rounded, '后台运行日志'),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in const {
                'all': '全部',
                'warning': '警告及错误',
                'error': '仅错误',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: logLevel == entry.key,
                  onSelected: (_) => update(() => logLevel = entry.key),
                ),
              TextButton.icon(
                onPressed: visible.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: visible.reversed
                                .map((line) => line.$2)
                                .join('\n'),
                          ),
                        );
                        if (mounted) message('已复制当前筛选结果');
                      },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制'),
              ),
              TextButton.icon(
                onPressed: logs.isEmpty ? null : () => update(logs.clear),
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '本次会话最多保留 1500 条日志，最新消息在上方。',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            emptyState(Icons.terminal_rounded, '暂无日志', '翻译进度和后台消息会显示在这里。')
          else
            Container(
              height: 430,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: inset,
                borderRadius: BorderRadius.circular(17),
              ),
              child: ListView.builder(
                primary: false,
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final (level, text) = visible[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        color: switch (level) {
                          'ERROR' || 'CRITICAL' => const Color(0xffaa2433),
                          'WARNING' => const Color(0xff805700),
                          _ => ink,
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
