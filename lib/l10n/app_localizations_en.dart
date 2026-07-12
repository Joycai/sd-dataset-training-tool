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

  @override
  String get commonTags => 'Common Tags';

  @override
  String get import => 'Import/Replace';

  @override
  String get newTags => 'New Tags (Click to add)';

  @override
  String get importTagsTitle => 'Import/Replace Common Tags';

  @override
  String get importTagsContent =>
      'Paste comma-separated tags here. This will replace all existing common tags.';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get addTagsTitle => 'Add Common Tags';

  @override
  String get addTagsContent =>
      'Paste comma-separated tags to add to the existing list.';

  @override
  String get imageTags => 'Image Tags';

  @override
  String get assetsPanelTitle => 'Assets';

  @override
  String get searchFilenameHint => 'Search filenames';

  @override
  String get filterAll => 'All';

  @override
  String get filterUntagged => 'Untagged';

  @override
  String get filterTagged => 'Tagged';

  @override
  String columnsCount(int count) {
    return '$count col';
  }

  @override
  String get openFolder => 'Open Folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get noImagesFound => 'No images yet. Open a folder to start.';

  @override
  String get noMatches => 'No images match the current filter.';

  @override
  String scanError(String error) {
    return 'Failed to scan directory: $error';
  }

  @override
  String get noDatasetOpen => 'No folder open';

  @override
  String imageCountShort(int count) {
    return '$count images';
  }

  @override
  String get selectImageHint => 'Select an image from the assets panel.';

  @override
  String get previousImage => 'Previous image';

  @override
  String get nextImage => 'Next image';

  @override
  String get fitToWindow => 'Fit to window';

  @override
  String get openInNewWindow => 'Open in separate window';

  @override
  String get textTab => 'Text';

  @override
  String get tagsTab => 'Tags';

  @override
  String tagCount(int count) {
    return '$count tags';
  }

  @override
  String savedAt(String time) {
    return 'Saved $time';
  }

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get savingNow => 'Saving';

  @override
  String get saveFailed => 'Save failed';

  @override
  String get captionHint => 'Write the caption here, tags separated by commas';

  @override
  String get addTagHint => 'Type a tag and press Enter';

  @override
  String get noTagsYet => 'No tags yet.';

  @override
  String get editTagTitle => 'Edit Tag';

  @override
  String get tagLibraryTitle => 'Tag Library';

  @override
  String get filterTagsHint => 'Filter tags';

  @override
  String get clickToApplyHint => 'Click to apply, click again to remove';

  @override
  String get newTagsSection => 'New in this image';

  @override
  String get addAllToLibrary => 'Add all';

  @override
  String get legendApplied => 'Applied';

  @override
  String get legendNotApplied => 'Not applied';

  @override
  String get legendNew => 'New';

  @override
  String get removeFromLibrary => 'Remove from library';

  @override
  String get libraryEmpty =>
      'The library is empty. Use the plus button to add tags.';

  @override
  String taggedProgress(int tagged, int total) {
    return 'Tagged $tagged / $total';
  }

  @override
  String get autoSaveOnStatus => 'Auto-save on';

  @override
  String get autoSaveOffStatus => 'Auto-save off';

  @override
  String get saveShortcutHint => 'Ctrl+S to save now';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get datasetSection => 'Dataset';

  @override
  String get dangerZone => 'Danger Zone';

  @override
  String get languageDesc => 'Interface display language';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeDesc => 'Dark is easier on the eyes for long sessions';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get captionExtensionDesc =>
      'Suffix of the caption file that shares the image\'s name, e.g. .txt or .caption';

  @override
  String get includeSubdirsTitle => 'Include subdirectories';

  @override
  String get includeSubdirsDesc =>
      'Recursively scan all folders inside the opened directory';

  @override
  String get autoSaveTitle => 'Auto-save';

  @override
  String get autoSaveDesc =>
      'Write the caption file 0.8 s after you stop editing';

  @override
  String get resetDesc =>
      'Restore defaults and clear the tag library. Images and caption files are not touched.';

  @override
  String get resetAction => 'Reset';
}
