part of 'main.dart';

typedef Settings = Map<String, dynamic>;

class DesktopSettings {
  List<Settings> engines = [];
  Map<String, String> languages = const {'en': '英语', 'zh-CN': '简体中文'};
  Settings pdfDefaults = {};
  Settings translationDefaults = {};
  final pdf = <String, dynamic>{};
  final translation = <String, dynamic>{};
  final mainFields = <String, Settings>{};
  final termFields = <String, Settings>{};
  final rate = <String, dynamic>{
    'mode': 'Custom',
    'rpm_input': 240,
    'concurrent_threads': 40,
    'custom_qps': 4,
    'custom_pool_workers': null,
  };
  final termRate = <String, dynamic>{
    'mode': 'inherit',
    'rpm_input': 240,
    'concurrent_threads': 40,
    'custom_qps': 4,
    'custom_pool_workers': null,
  };
  final glossaries = <String>[];
  String termEngine = '';
  String pageRange = 'all';

  void readSchema(Settings event) {
    engines = (event['engines'] as List).cast<Settings>();
    final names = (event['languages'] as Map<String, dynamic>)
        .cast<String, String>();
    languages = {
      for (final entry in names.entries) entry.value: entry.key,
      'en': '英语',
      'zh-CN': '简体中文',
      'zh-TW': '繁體中文（台湾）',
    };
    pdfDefaults = event['pdf'] as Settings;
    translationDefaults = event['translation'] as Settings;
  }

  Settings engineInfo(String id) =>
      engines.firstWhere((entry) => entry['id'] == id);
  bool supportsLlm(String id) => engineInfo(id)['llm'] == true;
  List<Settings> fields(String id) =>
      (engineInfo(id)['fields'] as List).cast<Settings>();

  Settings values(String id, {required bool term}) {
    return (term ? termFields : mainFields).putIfAbsent(id, () => {});
  }

  Object? fieldValue(Settings field, Settings values) {
    final name = field['name'] as String;
    return values.containsKey(name) ? values[name] : field['default'];
  }

  bool visible(Settings field, List<Settings> siblings, Settings values) {
    final condition = field['visibleWhen'] as Settings?;
    if (condition == null) return true;
    final dependency = siblings.firstWhere(
      (item) => item['name'] == condition['field'],
    );
    return fieldValue(dependency, values) == condition['equals'];
  }

  Settings engineRequest(String id, {required bool term}) {
    final inputs = values(id, term: term);
    final options = fields(id);
    return {
      'translate_engine_type': id,
      for (final field in options)
        if (visible(field, options, inputs))
          field['name'] as String: fieldValue(field, inputs),
    };
  }

  List<String> credentials() {
    final secrets = <String>{};
    for (final engine in engines) {
      final id = engine['id'] as String;
      for (final field in fields(
        id,
      ).where((field) => field['sensitive'] == true)) {
        for (final values in [mainFields[id], termFields[id]]) {
          final value = values?[field['name']];
          if (value is String && value.trim().isNotEmpty) {
            secrets.add(value.trim());
          }
        }
      }
    }
    return secrets.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
  }

  Settings snapshot() => {
    'pdf': pdf,
    'translation': translation,
    'mainFields': mainFields,
    'termFields': termFields,
    'termEngine': termEngine,
    'rate': rate,
    'termRate': termRate,
    'glossaries': glossaries,
    'pageRange': pageRange,
  };

  void restore(Settings saved) {
    for (final (name, target) in [
      ('pdf', pdf),
      ('translation', translation),
      ('rate', rate),
      ('termRate', termRate),
    ]) {
      if (saved[name] case final Settings values) target.addAll(values);
    }
    for (final (name, target) in [
      ('mainFields', mainFields),
      ('termFields', termFields),
    ]) {
      if (saved[name] case final Settings values) {
        target.addAll(
          values.map((key, value) => MapEntry(key, value as Settings)),
        );
      }
    }
    if (saved['termEngine'] case final String id
        when engines.any(
          (entry) => entry['id'] == id && entry['llm'] == true,
        )) {
      termEngine = id;
    }
    if (saved['glossaries'] case final List paths) {
      glossaries.addAll(paths.whereType<String>());
    }
    if (saved['pageRange'] case 'first' || 'first5' || 'range') {
      pageRange = saved['pageRange'] as String;
    }
  }
}

const pageRanges = {
  'all': '全部页面',
  'first': '第一页',
  'first5': '前 5 页',
  'range': '自定义页码',
};
const outputFormats = {'both': '单语 + 双语', 'mono': '仅单语', 'dual': '仅双语'};
const serviceLabels = {
  'Google': 'Google 翻译',
  'Bing': 'Bing 翻译',
  'SiliconFlowFree': '硅基流动（免费）',
  'SiliconFlow': '硅基流动',
  'OpenAICompatible': 'OpenAI 兼容接口',
  'DeepSeek': 'DeepSeek',
  'TencentMechineTranslation': '腾讯云机器翻译',
  'Zhipu': '智谱 AI',
  'AliyunDashScope': '阿里云百炼',
  'QwenMt': '通义千问翻译',
  'ModelScope': '魔搭 ModelScope',
  'CLITranslator': '自定义命令行',
};

String serviceLabel(String id) => serviceLabels[id] ?? id;

String redactLog(String line, List<String> secrets) {
  for (final secret in secrets) {
    line = line.replaceAll(secret, '[已隐藏]');
  }
  // Provider errors can include API tokens or source text in query strings.
  return line.replaceAllMapped(
    RegExp(r'(https?://[^\s?]+)\?[^\s]+', caseSensitive: false),
    (match) => '${match.group(1)}?[已隐藏]',
  );
}
