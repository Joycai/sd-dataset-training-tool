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
  String get captionTypesTitle => 'Caption Types';

  @override
  String get captionTypesDesc =>
      'Keep several caption files per image; enabled types appear in the navigator\'s and the editor\'s switcher';

  @override
  String get captionTypeName => 'Name';

  @override
  String get captionTypeNameHint => 'Untitled type';

  @override
  String get captionTypeFormat => 'Format';

  @override
  String get captionTypeExtension => 'Extension';

  @override
  String get captionTypeAdd => 'Add type';

  @override
  String get captionTypeEnabled => 'Enabled';

  @override
  String get captionTypeDefaultBadge => 'Default';

  @override
  String get captionTypeDefaultHint => 'The default type is always enabled';

  @override
  String get captionTypeRules =>
      'Extensions must be unique · the default type cannot be disabled or deleted';

  @override
  String get captionTypeFormatTooltip =>
      'Format: how this type\'s caption files are parsed — comma-separated tags, a JSON document, or natural-language sentences';

  @override
  String get captionTypeFormatTags => 'WD14 tags';

  @override
  String get captionTypeFormatTagsDesc =>
      'Comma-separated · editable tag chips';

  @override
  String get captionTypeFormatJson => 'Anima JSON';

  @override
  String get captionTypeFormatJsonDesc =>
      'Structured document · read-only tag view';

  @override
  String get captionTypeFormatNl => 'Natural language';

  @override
  String get captionTypeFormatNlDesc => 'Full text · split into sentences';

  @override
  String get captionTypeDuplicate =>
      'This extension is already used by another caption type';

  @override
  String get captionTypeInvalid => 'Not a usable caption extension';

  @override
  String get captionTypePickerTooltip =>
      'Switch caption type. The editor, batch edits and the AI assistant all read and write this type\'s caption files.';

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
  String get done => 'Done';

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
  String get searchFilenameHint => 'Search filenames';

  @override
  String get subdirAll => 'All folders';

  @override
  String get subdirRoot => 'Root folder';

  @override
  String get subdirPickerTooltip =>
      'Switch subdirectory. The selected folder also scopes the tag statistics, the batch edits and the AI assistant.';

  @override
  String subdirScopeNotice(String name) {
    return 'Scope: $name';
  }

  @override
  String get subdirScopeClearTooltip => 'Back to the whole dataset';

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
  String tagCountShort(int count) {
    return '$count tags';
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
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get openInNewWindow => 'Open in separate window';

  @override
  String get textTab => 'Text';

  @override
  String get tagsTab => 'Tags';

  @override
  String get jsonTab => 'JSON';

  @override
  String get captionJsonEmpty => 'No caption yet.';

  @override
  String captionJsonInvalid(String error) {
    return 'Invalid JSON — $error';
  }

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
  String compareModeCapsule(int count) {
    return 'Compare mode · $count with results';
  }

  @override
  String get compareModeHint => 'Accept or reject AI results one by one';

  @override
  String get compareModeExitGlobal => 'Exit compare mode';

  @override
  String compareBadgePending(int count) {
    return '$count to review';
  }

  @override
  String get compareBadgeReviewed => 'Reviewed';

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
      '✓ = on the current image. Right-click for actions';

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
  String get tagMenuOpenDictionary => 'Open in dictionary…';

  @override
  String get tagMenuRemoveFromImage => 'Remove from this image';

  @override
  String get tagMenuSetAnchor => 'Set as insertion anchor';

  @override
  String get tagMenuClearAnchor => 'Clear insertion anchor';

  @override
  String get tagMenuAddToLibrary => 'Add to library';

  @override
  String get tagMenuApplySuggestion => 'Apply suggestion';

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
  String undoFailedRetryHint(int count) {
    return '$count files could not be written — the operation is still on the stack, undo again to retry them';
  }

  @override
  String filesFailed(int count) {
    return '$count files could not be written';
  }

  @override
  String get filterPanelTitle => 'Gallery filter';

  @override
  String filterStatus(int shown, int total) {
    return 'Filtered · $shown / $total match';
  }

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
  String get shortcutHints => 'Ctrl+S save · Ctrl+E AI tag · Ctrl+Z undo';

  @override
  String get aiServiceConnected => 'AI service connected';

  @override
  String get aiServiceOffline => 'AI service offline';

  @override
  String get navBrowse => 'Browse';

  @override
  String get toggleNavigator => 'Show / hide navigator';

  @override
  String get toggleInspector => 'Show / hide inspector';

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
  String get accentTitle => 'Theme Color';

  @override
  String get accentDesc =>
      'Base color; surfaces, borders and highlights across the UI are tinted from it';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentViolet => 'Violet';

  @override
  String get accentRose => 'Rose';

  @override
  String get accentGreen => 'Green';

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

  @override
  String get close => 'Close';

  @override
  String get agentPanelTitle => 'AI Assistant';

  @override
  String get agentMinimize => 'Collapse panel';

  @override
  String get agentExpand => 'Expand panel';

  @override
  String get agentNewSession => 'New conversation';

  @override
  String get agentStop => 'Stop';

  @override
  String get agentSend => 'Send';

  @override
  String get agentInputHint => 'Ask about or edit your dataset…';

  @override
  String get agentNoProfileHint =>
      'No LLM backend configured yet. Add one in Settings to start using the assistant.';

  @override
  String get agentOpenSettings => 'Open Settings';

  @override
  String get agentRunning => 'Thinking…';

  @override
  String agentTokensUsed(int count) {
    return '$count tokens used this conversation';
  }

  @override
  String get agentExpandInput => 'Expand input';

  @override
  String get agentComposerTitle => 'Compose message';

  @override
  String get agentQuestionTitle => 'The assistant is asking';

  @override
  String get agentQuestionCustomHint => 'Type a custom answer…';

  @override
  String get agentQuestionDismiss => 'Dismiss without answering';

  @override
  String get agentStoppedNotice => 'Stopped.';

  @override
  String get agentSessionResetNotice => 'Dataset changed — conversation reset.';

  @override
  String get agentSwitchProfile => 'Switch backend';

  @override
  String agentProfileSwitchedNotice(String name) {
    return 'Switched to \"$name\" — the next message starts a new conversation, without the context above.';
  }

  @override
  String agentErrorNotice(String message) {
    return 'Error: $message';
  }

  @override
  String get agentConfirmTitle => 'The assistant wants to modify captions';

  @override
  String get agentConfirmAllow => 'Allow';

  @override
  String get agentConfirmAllowAll => 'Allow all this conversation';

  @override
  String get agentConfirmReject => 'Reject';

  @override
  String get agentTokenCapTitle => 'Conversation token budget';

  @override
  String get agentTokenCapDesc =>
      'Stops a conversation once it has spent this many tokens. Every turn re-sends the whole history, so batch work spends it fast — raise it, or start a new conversation when it runs out. Applies to the next conversation.';

  @override
  String get agentTokenCapUnlimited => 'No limit';

  @override
  String get agentTokenCapNotice =>
      'This conversation reached its token budget. Start a new conversation, or raise the budget in Settings.';

  @override
  String agentTokensUsedOfCap(int used, int cap) {
    return '$used / $cap tokens used this conversation';
  }

  @override
  String get agentConfirmWritesTitle => 'Confirm writes';

  @override
  String get agentConfirmWritesDesc =>
      'Ask before the assistant modifies caption files; every change stays undoable either way';

  @override
  String get promptPresetsTitle => 'Prompt presets';

  @override
  String get promptPresetsDesc =>
      'Save prompts you use often and drop them into the assistant\'s input with one click';

  @override
  String get promptPresetsEmpty => 'No prompt presets yet';

  @override
  String get promptPresetsManage => 'Manage presets…';

  @override
  String get promptPresetAdd => 'Add prompt';

  @override
  String get promptPresetNewName => 'New prompt';

  @override
  String get promptPresetUntitled => 'Untitled';

  @override
  String get promptPresetName => 'Name';

  @override
  String get promptPresetContent => 'Prompt text';

  @override
  String get promptPresetContentHint =>
      'The text inserted into the assistant\'s input…';

  @override
  String get promptPresetSelectHint =>
      'Select a prompt on the left, or add a new one.';

  @override
  String get promptPresetMoveUp => 'Move up';

  @override
  String get promptPresetMoveDown => 'Move down';

  @override
  String get promptPresetDeleteConfirmTitle => 'Delete prompt';

  @override
  String promptPresetDeleteConfirmContent(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get builtinPresetsSection => 'Built-in prompts';

  @override
  String get animaJsonGeneratePresetTitle => 'WD14 tags to Anima JSON';

  @override
  String get animaJsonGeneratePresetBody =>
      'Convert this dataset\'s WD14 tag captions into Anima JSON captions (the AnimaLoraToolkit simplified format).\n\nTarget fields, in order: quality (fixed value), count (people count), character, series, artist (fixed value), appearance (array: hair, eyes, body, clothing, accessories), tags (array: actions, expressions, composition, viewpoint and everything else — the catch-all), environment (array: indoors/outdoors, sky, lighting, scenery), nl (natural-language description, empty string for now).\n\nSteps:\n1. Confirm with get_dataset_overview that a JSON-format caption type is configured; if not, stop and tell me to add one in the caption type settings first.\n2. Get every tag with get_tag_stats and sort each one into the fields above to build the assign map; leave any tag you are unsure about out of assign so it falls into the tags catch-all.\n3. Run convert_captions_to_json once: source is the tag-format type carrying the WD14 tags, target is the JSON type, unassigned_field is tags, and quality, artist and nl are constants (empty strings unless I gave values below). Declare count, character and series as string normally, but as array if one image can carry several such tags at once (say 1girl plus 1boy), so no image gets skipped. Images that already have a non-empty target file are skipped unless you set overwrite.\n4. Afterwards report the tags that fell into the catch-all (unassigned_tags_seen); if any clearly belong in appearance or environment, fix them with a follow-up restructure_json_captions assign pass.\n\nDo not loop write_caption_file to write JSON image by image.';

  @override
  String get animaJsonReorderPresetTitle => 'Reorder Anima JSON fields';

  @override
  String get animaJsonReorderPresetBody =>
      'Reorder this dataset\'s Anima JSON captions into the standard field order: quality, count, character, series, artist, appearance, tags, environment, nl (the render order — nl always last).\n\nSteps:\n1. Run inspect_json_captions on the JSON caption type to see which keys actually exist, how many tags each holds and which key orders occur; plan from that result, never from memory.\n2. Run restructure_json_captions once: declare fields in the order above; same-named keys route automatically, use from to rename or merge; declare nl as preserve so it is copied verbatim; use tags as unassigned_field. Any extra keys the dataset carries either merge into a matching field via from, or keep their name placed after environment and before nl. Declare a field as string only when inspect shows at most one tag per image under it — otherwise use array.\n3. Keep drop_empty false so every image keeps the same shape; use tag_priority if some tags should come first inside a field.\n4. Afterwards report written/unchanged/failed counts plus anything in unrouted_keys_seen and unassigned_tags_seen.\n\nDo not rewrite images one by one with write_caption_file.';

  @override
  String get batchTagModeSheet => 'Sheet';

  @override
  String get batchTagModeSheetDesc =>
      'Rebuilds every caption from a saved character sheet: the trigger word and fixed traits always, outfit items only where the tagger saw them, and the tagger\'s expression / background / pose / framing kept as-is.';

  @override
  String get batchTagRulesLabel => 'Rule set';

  @override
  String get batchTagRulesHint => 'Pick a rule set';

  @override
  String get batchTagRulesUnnamed => 'Unnamed rule set';

  @override
  String get batchTagRulesEmpty =>
      'No rule sets yet. Run the character sheet skill in the assistant first — it produces the rules this mode applies.';

  @override
  String batchTagRulesSummary(int identity, int garments, int conflicts) {
    return '$identity fixed traits · $garments outfit items · $conflicts always removed';
  }

  @override
  String get batchTagEvidenceThreshold => 'Outfit evidence threshold';

  @override
  String get batchTagEvidenceThresholdDesc =>
      'Lower than the tagger\'s own threshold on purpose: the sheet already says the character wears these, so a faint sighting is more likely real than invented. Raise it to the tagger\'s threshold to disable the allowance.';

  @override
  String get batchTagSheetOverwriteWarning =>
      'Captions are rebuilt, not merged — existing tags are replaced. One undo reverts the whole run.';

  @override
  String get mergeRulesApplyHint =>
      'To apply these across the dataset, open batch tagging and pick the \"Sheet\" mode.';

  @override
  String get agentSkillsSection => 'Built-in skills';

  @override
  String get characterSheetSkill => 'Character sheet tagging…';

  @override
  String get characterSheetTitle => 'Character sheet tagging';

  @override
  String get characterSheetIntro =>
      'The assistant samples the dataset with the tagger and works out how your fixed tags combine with what the tagger sees. It produces merge rules for you to review — no caption is written in this step.';

  @override
  String get characterSheetName => 'Rule set name';

  @override
  String get characterSheetNameHint => 'e.g. the character\'s name';

  @override
  String get characterSheetTrigger => 'Trigger word';

  @override
  String get characterSheetTriggerHint =>
      'written as the first tag of every caption';

  @override
  String get characterSheetIdentity => 'Fixed traits';

  @override
  String get characterSheetIdentityHint =>
      'hair colour, hairstyle, breast size, eyes… written on every image';

  @override
  String get characterSheetGarments => 'Outfit';

  @override
  String get characterSheetGarmentsHint =>
      'dress, gloves, boots, accessories… written only where the tagger saw them';

  @override
  String get characterSheetExtra => 'Additional requirements (optional)';

  @override
  String get characterSheetExtraHint =>
      'leave empty to go entirely by the tagger\'s output';

  @override
  String get characterSheetSampleSize => 'Sample size';

  @override
  String get characterSheetSampleSizeSuffix => 'images';

  @override
  String get characterSheetStart => 'Start';

  @override
  String get characterSheetTagsHelp => 'One per line, or comma-separated.';

  @override
  String get characterSheetSummaryTitle => 'Character sheet tagging (planning)';

  @override
  String characterSheetSummarySample(int count) {
    return 'Sampling $count images';
  }

  @override
  String get mergeRulesTitle => 'Merge rules';

  @override
  String mergeRulesSampled(int count) {
    return 'from $count sampled images';
  }

  @override
  String get mergeRulesTrigger => 'Trigger word';

  @override
  String get mergeRulesIdentity => 'Always written';

  @override
  String get mergeRulesConflict => 'Always removed';

  @override
  String get mergeRulesGarments => 'Outfit, gated by the tagger';

  @override
  String get mergeRulesPassthrough => 'Kept from the tagger';

  @override
  String get mergeRulesNotes => 'Notes';

  @override
  String get mergeRulesNeverWritten =>
      'no evidence in the sample — never written';

  @override
  String mergeRulesEvidence(String tags) {
    return 'when the tagger says: $tags';
  }

  @override
  String get llmSection => 'AI Assistant (LLM)';

  @override
  String get llmActiveProfile => 'Active backend';

  @override
  String get llmActiveProfileDesc =>
      'Which configured LLM backend the assistant talks to';

  @override
  String get llmNoProfiles => 'None configured';

  @override
  String get llmManageProfiles => 'Backends';

  @override
  String get llmManageProfilesDesc =>
      'Add, edit, test and remove LLM backend configurations';

  @override
  String get llmManageAction => 'Manage';

  @override
  String get llmProfilesTitle => 'LLM Backends';

  @override
  String get llmProviderLabel => 'PROVIDER';

  @override
  String get llmAddProvider => 'Add provider';

  @override
  String get llmAddModel => 'Add model';

  @override
  String get llmDeleteModel => 'Delete model';

  @override
  String get llmEditProvider => 'Edit';

  @override
  String get llmDisplayName => 'Display name';

  @override
  String get llmVisionBadge => 'Vision';

  @override
  String llmInheritsFromProvider(String name) {
    return 'URL and key come from the provider \"$name\".';
  }

  @override
  String get llmPricingTitle => 'Pricing (per Mtoken)';

  @override
  String get llmPricingNote =>
      'Used for usage accounting only; never sent with requests.';

  @override
  String get llmPriceInput => 'Input';

  @override
  String get llmPriceOutput => 'Output';

  @override
  String get llmPriceCacheRead => 'Cache read';

  @override
  String get llmPriceCacheWrite => 'Cache write';

  @override
  String get llmNewProfileName => 'New backend';

  @override
  String get llmSelectProfileHint =>
      'Select a backend on the left, or add a new one.';

  @override
  String get llmProfileName => 'Name';

  @override
  String get llmPreset => 'Preset';

  @override
  String get llmKindOpenAi => 'OpenAI-compatible';

  @override
  String get llmKindAnthropic => 'Anthropic';

  @override
  String get llmBaseUrl => 'Base URL';

  @override
  String get llmApiKey => 'API Key';

  @override
  String get llmApiKeyPlaintextNote =>
      'Stored as plain text in local settings.';

  @override
  String get llmModel => 'Model';

  @override
  String get llmContextWindow => 'Context window';

  @override
  String get llmMaxOutput => 'Max output';

  @override
  String get llmTemperature => 'Temperature';

  @override
  String get llmSupportsVision => 'Vision (multimodal)';

  @override
  String get llmSupportsVisionDesc =>
      'Enable if the model accepts images; unlocks image tools in later phases';

  @override
  String get llmFetchModels => 'Fetch model list';

  @override
  String get llmNoModelsFound => 'The server returned no models';

  @override
  String get llmTestConnection => 'Test connection';

  @override
  String llmTestOk(int ms) {
    return 'Connection OK ($ms ms)';
  }

  @override
  String llmTestFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get llmDeleteConfirmTitle => 'Delete backend';

  @override
  String llmDeleteConfirmContent(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get tagWikiAction => 'Danbooru wiki';

  @override
  String get tagPostsAction => 'Danbooru posts';

  @override
  String get tagWikiTooltip => 'Open the danbooru wiki (F1)';

  @override
  String get tagTranslateAction => 'Add a translation';

  @override
  String get tagEditTranslation => 'Edit the translation';

  @override
  String get tagNotInDictionary => 'Not in the tag dictionary';

  @override
  String tagPostCount(int count) {
    return '$count posts on danbooru';
  }

  @override
  String tagSuggestionAlias(String alias) {
    return 'alias: $alias';
  }

  @override
  String tagSuggestionLocalUsed(int count) {
    return 'your tag · $count images in this dataset';
  }

  @override
  String get tagSuggestionLocalLibrary => 'your tag · from the tag library';

  @override
  String get tagSuggestionCustom => 'added by hand';

  @override
  String tagNotInDictionaryUsed(int count) {
    return 'Not in the tag dictionary · $count images in this dataset';
  }

  @override
  String get tagDictionaryTitle => 'Tag dictionary';

  @override
  String get tagDictionaryDesc =>
      'Suggests danbooru tags while you type in the caption editor';

  @override
  String get tagDictionaryStatusLoading => 'Loading…';

  @override
  String tagDictionaryStatusBundled(int count) {
    return 'Built-in · $count tags';
  }

  @override
  String tagDictionaryStatusFull(int count) {
    return 'Full · $count tags';
  }

  @override
  String get tagDictionaryFullTitle => 'Full danbooru dictionary';

  @override
  String get tagDictionaryFullDesc =>
      'Downloads the top 100k tags with aliases, artists and copyrights (~3.5 MB)';

  @override
  String get tagDictionaryDownloadAction => 'Download';

  @override
  String get tagDictionaryRemoveAction => 'Remove';

  @override
  String get tagDictionaryDownloading => 'Downloading…';

  @override
  String tagDictionaryDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get tagGlossTitle => 'Tag translations';

  @override
  String get tagGlossDesc =>
      'Shows a translation beside each tag, in the app\'s language. Display only — never written into a caption';

  @override
  String get tagGlossModeOff => 'Off';

  @override
  String get tagGlossModeInline => 'Beside the tag';

  @override
  String get tagGlossModeTooltip => 'On hover only';

  @override
  String get tagDictionaryManageTitle => 'Edit dictionary';

  @override
  String get tagDictionaryManageDesc =>
      'Translate tags, add tags danbooru does not have, import or export a glossary';

  @override
  String get tagDictionaryOpenAction => 'Open dictionary';

  @override
  String get dictManagerTitle => 'Tag dictionary';

  @override
  String dictManagerCounts(
    String locale,
    int builtin,
    int custom,
    int translated,
  ) {
    return '$locale · $builtin built in, $custom added, $translated translated';
  }

  @override
  String dictGlossaryError(String message) {
    return 'Glossary file could not be read: $message';
  }

  @override
  String get dictSearchHint => 'Search a tag or a translation';

  @override
  String get dictGlossaryEmpty =>
      'Nothing translated yet. Search for a tag to give it a translation.';

  @override
  String get dictNoResults => 'No matching tag or translation';

  @override
  String get dictSelectHint => 'Pick a tag on the left to translate it.';

  @override
  String get dictTranslationLabel => 'Translation';

  @override
  String get dictTranslationHint => 'Shown beside the tag in the UI';

  @override
  String get dictNoteLabel => 'Note';

  @override
  String get dictNoteHint =>
      'What the tag actually means, when the translation alone is ambiguous';

  @override
  String get dictDeleteHint =>
      'An empty field is not saved; use the button below to delete a translation.';

  @override
  String get dictDeleteTranslationAction => 'Delete translation';

  @override
  String dictDeleteTranslationConfirm(String tag) {
    return 'Delete the translation for \"$tag\"? The tag goes back to showing its own name.';
  }

  @override
  String dictRemoveCustomConfirm(String tag) {
    return 'Remove \"$tag\" from the dictionary? It will no longer be offered in autocomplete; its translation is kept.';
  }

  @override
  String get dictCustomBadge => 'added';

  @override
  String get dictOrphanBadge => 'unknown tag';

  @override
  String dictCategoryAndCount(String category, int count) {
    return '$category · $count posts';
  }

  @override
  String get dictCategoryGeneral => 'General';

  @override
  String get dictCategoryArtist => 'Artist';

  @override
  String get dictCategoryCopyright => 'Copyright';

  @override
  String get dictCategoryCharacter => 'Character';

  @override
  String get dictCategoryMeta => 'Meta';

  @override
  String get dictSourceManual => 'Written by hand';

  @override
  String get dictSourceLlm => 'From the assistant';

  @override
  String get dictSourceDanbooru => 'From the danbooru wiki';

  @override
  String get dictRemoveCustomAction => 'Remove from dictionary';

  @override
  String get dictAddTagNameLabel => 'Tag name';

  @override
  String get dictAddTagNameHint => 'danbooru spelling, e.g. my_character_(oc)';

  @override
  String get dictAddTagCategoryLabel => 'Category';

  @override
  String dictAddTagExists(String tag) {
    return '\"$tag\" is already in the dictionary';
  }

  @override
  String get dictImportAction => 'Import';

  @override
  String get dictExportAction => 'Export';

  @override
  String dictImportSummary(int written, int skipped) {
    return 'Imported $written translations, skipped $skipped';
  }

  @override
  String get dictClearAiAction => 'Clear AI translations';

  @override
  String get dictClearAiTitle => 'Clear AI translations';

  @override
  String dictClearAiConfirm(int count) {
    return 'Delete $count translations produced by the assistant? Ones you wrote by hand are kept.';
  }

  @override
  String dictClearAiDone(int count) {
    return 'Deleted $count translations';
  }

  @override
  String get dictClearAiNone => 'No assistant translations to clear';

  @override
  String get dictFooterHint =>
      'One glossary per app language · added tags and translations stay on this machine';

  @override
  String get dictOpenTooltip => 'Open the tag dictionary';

  @override
  String get dictFilterAll => 'All';

  @override
  String dictFilterCustom(int count) {
    return 'Added $count';
  }

  @override
  String get dictUntranslated => 'Untranslated';

  @override
  String get dictNewTagAction => 'New tag';

  @override
  String get dictFetchSourceName => 'danbooru';

  @override
  String get dictOrderAlpha => 'A–Z';

  @override
  String get dictOrderUsage => 'By usage';

  @override
  String get dictDatasetOnly => 'This dataset only';

  @override
  String get dictOrderRelevance => 'By relevance';

  @override
  String dictResultCount(int count) {
    return '$count results';
  }

  @override
  String get dictCustomEmpty =>
      'No tags added yet. Use \"New tag\" for characters or private tags the built-in dictionary does not have.';

  @override
  String get dictUntranslatedEmpty => 'Nothing left to translate.';

  @override
  String get dictCollectAction => 'Add';

  @override
  String dictCollectedCount(int count) {
    return 'Added $count tags to the dictionary';
  }

  @override
  String dictMissingTitle(int count) {
    return '$count tags are not in the dictionary';
  }

  @override
  String get dictMissingDesc =>
      'They render untranslated; adding them makes them translatable and completable';

  @override
  String get dictMissingIgnore => 'Ignore';

  @override
  String get dictMissingCollectAll => 'Add all as custom';

  @override
  String dictMissingUsage(int count) {
    return '$count images';
  }

  @override
  String dictMissingMore(int count) {
    return '$count more';
  }

  @override
  String get dictAliasesLabel => 'Aliases';

  @override
  String get dictAliasesHint =>
      'searching these spellings finds this entry too';

  @override
  String get dictAiTranslateAction => 'Translate with AI';

  @override
  String get dictAiTranslating => 'Translating…';

  @override
  String dictAiTranslateFailed(String error) {
    return 'AI translation failed: $error';
  }

  @override
  String get dictRevertAction => 'Revert';

  @override
  String dictSourceBecomes(String source) {
    return 'saving makes it \"$source\"';
  }

  @override
  String get dictUsageLabel => 'Used in this dataset';

  @override
  String dictUsageValue(int count, int percent) {
    return '$count images · $percent%';
  }

  @override
  String get dictUnknownTagHint => 'not in the dictionary';

  @override
  String get dictNewTagTitle => 'New custom tag';

  @override
  String get dictNewTagDesc =>
      'For characters, styles or private tags the built-in dictionary does not have';

  @override
  String get dictNewTagSpellingHint =>
      'danbooru spelling: lower case, underscores';

  @override
  String dictNewTagSpellingPreview(String name) {
    return 'stored as $name';
  }

  @override
  String get dictNewTagAliasesLabel => 'Aliases (optional, comma separated)';

  @override
  String get dictNewTagAliasesHint => 'prettysammy, sammy';

  @override
  String get dictNewTagAutocompleteTitle => 'Offer in autocomplete';

  @override
  String get dictNewTagAutocompleteDesc =>
      'Suggested alongside built-in tags in tag fields';

  @override
  String get dictNewTagExistsHint =>
      'A tag the dictionary already has is not added twice';

  @override
  String get dictNewTagSubmit => 'Add';

  @override
  String get dictFetchAction => 'Fetch from danbooru';

  @override
  String get dictFetching => 'Fetching…';

  @override
  String get dictFetchPromptLabel => 'Tag name or danbooru URL';

  @override
  String get dictFetchPromptHint =>
      'long_hair, or a link you copied from danbooru';

  @override
  String get dictFetchPromptNote =>
      'A wiki page, a post search or a tag listing URL all work. Reads danbooru\'s public API — nothing is sent anywhere.';

  @override
  String dictFetchFailed(String error) {
    return 'Lookup failed: $error';
  }

  @override
  String dictFetchUnknown(String tag) {
    return 'danbooru has no tag called \"$tag\"';
  }

  @override
  String dictFetchedHeader(String category, int count) {
    return 'danbooru: $category · $count posts';
  }

  @override
  String get dictFetchOtherNames => 'Other names on danbooru';

  @override
  String get dictFetchUseAsTranslation => 'Use as the translation';

  @override
  String get dictFetchWikiLabel => 'From the wiki';

  @override
  String get dictFetchUseAsNote => 'Use as the note';

  @override
  String get dictFetchNoWiki => 'This tag has no wiki page.';

  @override
  String get dictFetchAddAction => 'Add to the dictionary';

  @override
  String get dictFetchPrivacyNote =>
      'Reads the public API only; nothing is uploaded';

  @override
  String get dictFetchLookupAction => 'Look up';

  @override
  String get dictFetchWillWrite => 'Will write';

  @override
  String get dictFetchFieldPostCount => 'Post count';

  @override
  String get dictFetchKeepsEdits =>
      '· your own translation and note are never overwritten';

  @override
  String get dictFetchAlreadyKnown => 'The dictionary already has this tag.';

  @override
  String get dictFetchWriteAction => 'Write to dictionary';

  @override
  String get dictFetchOpenAction => 'Go to the tag';

  @override
  String dictFetchAdded(String tag) {
    return 'Added to the dictionary: $tag';
  }

  @override
  String get dataSection => 'Data';

  @override
  String get dataExportTitle => 'Export data';

  @override
  String get dataExportDesc =>
      'Save your AI backends, tag library and prompt presets to one file';

  @override
  String get dataExportAction => 'Export…';

  @override
  String get dataImportTitle => 'Import data';

  @override
  String get dataImportDesc =>
      'Restore from an export file; nothing already here is deleted';

  @override
  String get dataImportAction => 'Import…';

  @override
  String get dataExportDialogTitle => 'Export data';

  @override
  String get dataExportPick => 'Choose what to write to the file.';

  @override
  String get dataExportExcludes =>
      'The built-in and downloaded danbooru dictionaries are left out — the app can fetch those again.';

  @override
  String get dataExportApiKeys => 'Include API keys';

  @override
  String get dataExportApiKeysHint =>
      'They are written as plain text. Keep the file somewhere private.';

  @override
  String get dataExportConfirm => 'Export';

  @override
  String get dataSectionLlm => 'AI backends';

  @override
  String dataSectionLlmSummary(int providers, int models) {
    return '$providers backends · $models models';
  }

  @override
  String get dataSectionTagLibrary => 'Tag library';

  @override
  String dataSectionTagLibrarySummary(
    int tags,
    int groups,
    int custom,
    int translations,
  ) {
    return '$tags tags · $groups groups · $custom custom tags · $translations translations';
  }

  @override
  String get dataSectionPresets => 'Prompt presets';

  @override
  String dataSectionPresetsSummary(int count) {
    return '$count presets';
  }

  @override
  String get dataSectionMissing => 'Not in this file';

  @override
  String get dataImportDialogTitle => 'Import data';

  @override
  String dataImportSource(String version, String date) {
    return 'Written by version $version on $date';
  }

  @override
  String get dataImportNoKeys =>
      'This export carries no API keys — you will have to enter them again.';

  @override
  String get dataImportMode => 'When something already exists';

  @override
  String get dataImportModeMerge => 'Keep what is here';

  @override
  String get dataImportModeOverwrite => 'Use the file\'s version';

  @override
  String get dataImportModeHint =>
      'Neither choice deletes anything: an import only adds or updates.';

  @override
  String get dataImportConfirm => 'Import';

  @override
  String get dataImportDoneTitle => 'Import finished';

  @override
  String get dataImportNothingChanged =>
      'Everything in the file was already here.';

  @override
  String dataImportReportLlm(int added, int updated, int models) {
    return 'AI backends: $added added, $updated updated, $models models added';
  }

  @override
  String dataImportReportLibrary(
    int tags,
    int groups,
    int custom,
    int translations,
  ) {
    return 'Tag library: $tags tags, $groups groups, $custom custom tags, $translations translations';
  }

  @override
  String dataImportReportPresets(int added, int updated) {
    return 'Prompt presets: $added added, $updated updated';
  }
}
