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
  String get tagSortModeTooltip => 'Sort mode: drag tags to reorder';

  @override
  String get aiInterrogateButton => 'AI tag';

  @override
  String get aiInterrogating => 'Tagging…';

  @override
  String get aiParamsTitle => 'AI tagging parameters';

  @override
  String get aiServerUrl => 'Server URL';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiNoModels => 'No models yet — refresh to fetch';

  @override
  String get aiRefreshModels => 'Refresh model list';

  @override
  String get aiThresholdLabel => 'Threshold';

  @override
  String get aiUseModelDefault => 'Model default';

  @override
  String get aiThresholdDesc => 'Lower values produce more tags.';

  @override
  String get aiIgnoreTagsLabel => 'Ignored tags';

  @override
  String get aiIgnoreTagsDesc =>
      'Comma-separated. These tags never appear in AI results.';

  @override
  String get aiUnderscoreToSpaces => 'Underscores to spaces';

  @override
  String get aiEscapeParentheses => 'Escape parentheses \\( \\)';

  @override
  String get aiConnecting => 'Connecting';

  @override
  String get aiConnectionOk => 'Connected';

  @override
  String get aiConnectionFail => 'Unreachable';

  @override
  String get aiConnectionUnknown => 'Unknown';

  @override
  String get aiCurrentTagsHeader => 'Current tags';

  @override
  String get aiResultHeader => 'AI results';

  @override
  String aiMissingCount(int count) {
    return '$count not in AI results';
  }

  @override
  String aiNewCount(int count) {
    return '$count new';
  }

  @override
  String get aiShowNewOnly => 'New only';

  @override
  String get aiLegendNew => 'New (click to add)';

  @override
  String get aiLegendMissing => 'Not in AI results';

  @override
  String get aiLegendMatched => 'Matched';

  @override
  String aiAddAllNew(int count) {
    return 'Add all new ($count)';
  }

  @override
  String get aiRerun => 'Re-run';

  @override
  String get aiDoneCompare => 'Done';

  @override
  String get aiNoResultYet => 'No result for this image yet.';

  @override
  String get aiFirstRunHint =>
      'First use of a model downloads it — this can take a while.';

  @override
  String get aiNoModelSelected => 'No model selected. Check the AI parameters.';

  @override
  String aiFailed(String error) {
    return 'AI tagging failed: $error';
  }

  @override
  String get rightTabLibrary => 'Library';

  @override
  String get rightTabDataset => 'Dataset';

  @override
  String get datasetTagsTitle => 'Dataset Tags';

  @override
  String get datasetTagsEmpty => 'No tags in this dataset yet.';

  @override
  String get datasetTagsHint =>
      'Green = on the current image. Right-click for actions';

  @override
  String get clearTagFilter => 'Clear tag filter';

  @override
  String get menuFilterInclude => 'Only images with this tag';

  @override
  String get menuFilterExclude => 'Only images without this tag';

  @override
  String get menuReplaceAppend => 'Replace / append…';

  @override
  String get menuDeleteGlobal => 'Delete from all images';

  @override
  String get deleteTagConfirmTitle => 'Delete tag everywhere';

  @override
  String deleteTagConfirmContent(int count, String tag) {
    return 'Remove \"$tag\" from $count images? This can be undone from the toolbar.';
  }

  @override
  String get replaceDialogTitle => 'Replace / append';

  @override
  String get replaceModeReplace => 'Replace with';

  @override
  String get replaceModeBefore => 'Insert before';

  @override
  String get replaceModeAfter => 'Insert after';

  @override
  String get replaceInputHint => 'Comma-separated tags';

  @override
  String get apply => 'Apply';

  @override
  String filesUpdated(int count) {
    return '$count files updated';
  }

  @override
  String get noFilesChanged => 'No files needed changes.';

  @override
  String filterActiveInclude(String tag) {
    return 'Only with: $tag';
  }

  @override
  String filterActiveExclude(String tag) {
    return 'Only without: $tag';
  }

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String undoTooltip(String action) {
    return 'Undo: $action';
  }

  @override
  String redoTooltip(String action) {
    return 'Redo: $action';
  }

  @override
  String opDeleteLabel(String tag) {
    return 'delete \"$tag\"';
  }

  @override
  String opReplaceLabel(String tag) {
    return 'replace \"$tag\"';
  }

  @override
  String opInsertLabel(String tag) {
    return 'append next to \"$tag\"';
  }

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
