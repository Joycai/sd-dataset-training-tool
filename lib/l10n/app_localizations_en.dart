// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DataSet Training Tool';

  @override
  String get editor => 'Editor';

  @override
  String get settings => 'Settings';

  @override
  String get toggleTheme => 'Toggle Theme';

  @override
  String get editorView => 'Editor View';

  @override
  String get settingsView => 'Settings View';

  @override
  String get language => 'Language';

  @override
  String get captionExtension => 'Caption Extension';

  @override
  String get resetSettings => 'Reset Settings';

  @override
  String get resetSettingsConfirmationTitle => 'Confirm Reset';

  @override
  String get resetSettingsConfirmationContent =>
      'Are you sure you want to reset all settings to their default values? This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';
}
