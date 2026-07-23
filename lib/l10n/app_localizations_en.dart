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
  String get datasetLocation => 'Dataset Location';

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
  String get thumbFitTooltip => 'Fit thumbnails: show the whole image';

  @override
  String get thumbFillTooltip => 'Fill thumbnails: crop to fill the cell';

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
  String get tagAnchorHolderTooltip =>
      'Set insert anchor: new tags are added after this tag ([ / ] to move, click again to clear)';

  @override
  String anchorStatusLabel(String tag) {
    return 'Insert anchor: $tag';
  }

  @override
  String get anchorClearTooltip =>
      'New tags are inserted after this tag; click to clear (back to append at end)';

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
  String get aiModelGroupTag => 'Tag models · booru style';

  @override
  String get aiModelGroupCaption => 'Natural language captions';

  @override
  String aiModelLegacyGroup(Object count) {
    return 'Legacy models ($count)';
  }

  @override
  String get aiModelFilterHint => 'Filter models…';

  @override
  String get aiModelFilterNoMatch => 'No matching models';

  @override
  String get aiBadgeRecommended => 'Recommended';

  @override
  String get aiBadgeUncensored => 'Uncensored';

  @override
  String get aiVramFootnote =>
      'VRAM figures are estimates; amber means demanding.';

  @override
  String get aiThresholdCaptionNote =>
      'The selected model outputs captions; the threshold has no effect.';

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
  String get aiExitCompare => 'Exit compare';

  @override
  String get aiExitCompareTooltip =>
      'Exit compare mode (applies to all images)';

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
  String get batchTagButton => 'Batch tagging';

  @override
  String get batchTagTitle => 'Batch AI tagging';

  @override
  String get batchTagParamsHint =>
      'Threshold, ignored tags and normalization follow the AI parameters.';

  @override
  String get batchTagOpenParams => 'AI parameters…';

  @override
  String get batchTagModeLabel => 'Mode';

  @override
  String get batchTagModeAppend => 'Append';

  @override
  String get batchTagModeOverwrite => 'Overwrite';

  @override
  String get batchTagModeRecognize => 'Recognize';

  @override
  String get batchTagModeRecognizeDesc =>
      'Interrogates and caches results without touching caption files; when finished, compare mode opens for per-image review.';

  @override
  String get batchTagModeAppendDesc =>
      'New AI tags are appended after each image\'s existing tags; duplicates are never added.';

  @override
  String get batchTagModeOverwriteDesc =>
      'AI results replace each image\'s existing tags; configure below which existing tags survive.';

  @override
  String get batchTagPreservedLabel => 'Preserved tags';

  @override
  String get batchTagPreservedDesc =>
      'Comma-separated. These existing tags survive the overwrite.';

  @override
  String get batchTagKeepFirstN => 'Keep first N existing tags';

  @override
  String get batchTagBlacklistLabel => 'Blacklist';

  @override
  String get batchTagBlacklistDesc =>
      'Comma-separated. These tags are never appended.';

  @override
  String batchTagScopeFiltered(Object count) {
    return 'Only the $count filtered images';
  }

  @override
  String batchTagTargetCount(Object count) {
    return '$count images will be processed, one at a time.';
  }

  @override
  String get batchTagStart => 'Start';

  @override
  String batchTagRunning(Object completed, Object total) {
    return 'Batch tagging $completed/$total';
  }

  @override
  String batchTagProgressCounts(Object changed, Object failed) {
    return 'Changed $changed · Failed $failed';
  }

  @override
  String get batchTagHide => 'Run in background';

  @override
  String get batchTagCancel => 'Cancel run';

  @override
  String get batchTagCancelling => 'Cancelling…';

  @override
  String get batchTagDoneTitle => 'Batch tagging finished';

  @override
  String batchTagDoneSummary(Object completed, Object changed, Object failed) {
    return '$completed images processed: $changed changed, $failed failed.';
  }

  @override
  String batchTagRecognizeDoneSummary(
    Object completed,
    Object changed,
    Object failed,
  ) {
    return '$completed images processed: $changed recognized, $failed failed.';
  }

  @override
  String get batchTagRecognizeDoneHint =>
      'Compare mode is on: switch images to review the AI suggestions.';

  @override
  String get batchTagUndoHint => 'Use undo in the top bar to revert this run.';

  @override
  String get batchTagOperationLabel => 'batch AI tagging';

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
  String get addTagsGlobalTooltip => 'Add tags to all images…';

  @override
  String get addTagsGlobalTitle => 'Add tags to all images';

  @override
  String get addTagsPositionLabel => 'Insert position';

  @override
  String get addTagsPosHead => 'Start';

  @override
  String get addTagsPosTail => 'End';

  @override
  String get addTagsPosIndex => 'At position';

  @override
  String get addTagsIndexHint => '1 = first';

  @override
  String addTagsGlobalTargetCount(int count) {
    return 'Tags will be added to $count images; tags an image already has are skipped.';
  }

  @override
  String opAddGlobalLabel(String tags) {
    return 'add \"$tags\"';
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
  String get filterPanelTitle => 'Gallery filter';

  @override
  String filterMatches(int shown, int total) {
    return '$shown / $total match';
  }

  @override
  String get filterOpAnd => 'AND';

  @override
  String get filterOpOr => 'OR';

  @override
  String get filterToggleOpTooltip => 'Toggle this group\'s AND/OR';

  @override
  String get filterToggleRoleTooltip => 'Toggle include/exclude';

  @override
  String get filterRemoveConditionTooltip => 'Remove condition';

  @override
  String get filterAddTooltip => 'Add condition / sub-group';

  @override
  String get filterAddCondition => 'Add condition…';

  @override
  String get filterAddSubgroup => 'Add sub-group';

  @override
  String get filterDissolveGroupTooltip => 'Dissolve group (children move up)';

  @override
  String get filterPickerTitle => 'Add filter condition';

  @override
  String get filterRoleInclude => 'Include';

  @override
  String get filterRoleExclude => 'Exclude';

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
  String get moreActionsTooltip => 'More actions';

  @override
  String get importFromFile => 'Import from file…';

  @override
  String get exportLibraryMenu => 'Export tags (with groups)…';

  @override
  String get exportGroupsMenu => 'Export groups only…';

  @override
  String get clearLibrary => 'Clear library';

  @override
  String clearLibraryConfirmContent(int count) {
    return 'Remove all $count tags? Groups are kept.';
  }

  @override
  String importSummary(int tags, int groups) {
    return 'Imported $tags tags, created $groups groups';
  }

  @override
  String importFailedMsg(String error) {
    return 'Import failed: $error';
  }

  @override
  String exportedTo(String path) {
    return 'Exported: $path';
  }

  @override
  String exportFailedMsg(String error) {
    return 'Export failed: $error';
  }

  @override
  String get newGroupTitle => 'New group';

  @override
  String get editGroupTitle => 'Edit group';

  @override
  String get groupNameHint => 'Group name';

  @override
  String get groupColorLabel => 'Color';

  @override
  String get customColorLabel => 'Custom';

  @override
  String get ungroupedSection => 'Ungrouped';

  @override
  String get groupEditModeTooltip => 'Group edit mode';

  @override
  String get changeGroupColorTooltip => 'Change group color';

  @override
  String get moveGroupUpTooltip => 'Move group up';

  @override
  String get moveGroupDownTooltip => 'Move group down';

  @override
  String get groupEditHint => 'Click to select, right-click to send to a group';

  @override
  String groupEditSelectedHint(int count) {
    return '$count selected · right-click to send to a group';
  }

  @override
  String sendToGroup(String name) {
    return 'Send to $name';
  }

  @override
  String get sendToNewGroup => 'New group and send…';

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String get editGroupMenu => 'Edit group…';

  @override
  String get deleteGroupMenu => 'Delete group';

  @override
  String deleteGroupConfirmContent(String name) {
    return 'Delete group \"$name\"? Its tags return to Ungrouped.';
  }

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
  String get fontTitle => 'Font';

  @override
  String get fontDesc =>
      'UI font. HarmonyOS Sans and MiSans are downloaded on first use';

  @override
  String get fontSystem => 'System font';

  @override
  String get fontHarmony => 'HarmonyOS Sans';

  @override
  String get fontMiSans => 'MiSans';

  @override
  String get fontDownloadConfirmTitle => 'Download font';

  @override
  String fontDownloadConfirmContent(String font) {
    return 'Using $font for the first time requires downloading the official font package into the app data directory. This only happens once. Download now?';
  }

  @override
  String get fontDownloadAction => 'Download';

  @override
  String fontDownloadingTitle(String font) {
    return 'Downloading $font…';
  }

  @override
  String fontDownloadFailed(String error) {
    return 'Font download failed: $error';
  }

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

  @override
  String get aboutSection => 'About';

  @override
  String get versionTitle => 'Version';

  @override
  String get versionDesc => 'Current application version';

  @override
  String get licenseTitle => 'License';

  @override
  String get sourceCodeTitle => 'Source Code';
}
