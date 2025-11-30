// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '数据集训练工具';

  @override
  String get editor => '编辑器';

  @override
  String get settings => '设置';

  @override
  String get toggleTheme => '切换主题';

  @override
  String get editorView => '编辑器视图';

  @override
  String get settingsView => '设置视图';

  @override
  String get language => '语言';

  @override
  String get captionExtension => '描述文件扩展名';

  @override
  String get resetSettings => '重置设置';

  @override
  String get resetSettingsConfirmationTitle => '确认重置';

  @override
  String get resetSettingsConfirmationContent => '您确定要将所有设置重置为默认值吗？此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get save => '保存';
}
