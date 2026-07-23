import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DataSet Training Tool'**
  String get appTitle;

  /// No description provided for @datasetLocation.
  ///
  /// In en, this message translates to:
  /// **'Dataset Location'**
  String get datasetLocation;

  /// No description provided for @editor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editor;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @toggleTheme.
  ///
  /// In en, this message translates to:
  /// **'Toggle Theme'**
  String get toggleTheme;

  /// No description provided for @editorView.
  ///
  /// In en, this message translates to:
  /// **'Editor View'**
  String get editorView;

  /// No description provided for @settingsView.
  ///
  /// In en, this message translates to:
  /// **'Settings View'**
  String get settingsView;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @captionExtension.
  ///
  /// In en, this message translates to:
  /// **'Caption Extension'**
  String get captionExtension;

  /// No description provided for @resetSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset Settings'**
  String get resetSettings;

  /// No description provided for @resetSettingsConfirmationTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Reset'**
  String get resetSettingsConfirmationTitle;

  /// No description provided for @resetSettingsConfirmationContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset all settings to their default values? This action cannot be undone.'**
  String get resetSettingsConfirmationContent;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @commonTags.
  ///
  /// In en, this message translates to:
  /// **'Common Tags'**
  String get commonTags;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import/Replace'**
  String get import;

  /// No description provided for @newTags.
  ///
  /// In en, this message translates to:
  /// **'New Tags (Click to add)'**
  String get newTags;

  /// No description provided for @importTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import/Replace Common Tags'**
  String get importTagsTitle;

  /// No description provided for @importTagsContent.
  ///
  /// In en, this message translates to:
  /// **'Paste comma-separated tags here. This will replace all existing common tags.'**
  String get importTagsContent;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @addTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Common Tags'**
  String get addTagsTitle;

  /// No description provided for @addTagsContent.
  ///
  /// In en, this message translates to:
  /// **'Paste comma-separated tags to add to the existing list.'**
  String get addTagsContent;

  /// No description provided for @imageTags.
  ///
  /// In en, this message translates to:
  /// **'Image Tags'**
  String get imageTags;

  /// No description provided for @assetsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assetsPanelTitle;

  /// No description provided for @searchFilenameHint.
  ///
  /// In en, this message translates to:
  /// **'Search filenames'**
  String get searchFilenameHint;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterUntagged.
  ///
  /// In en, this message translates to:
  /// **'Untagged'**
  String get filterUntagged;

  /// No description provided for @filterTagged.
  ///
  /// In en, this message translates to:
  /// **'Tagged'**
  String get filterTagged;

  /// No description provided for @columnsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} col'**
  String columnsCount(int count);

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noImagesFound.
  ///
  /// In en, this message translates to:
  /// **'No images yet. Open a folder to start.'**
  String get noImagesFound;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No images match the current filter.'**
  String get noMatches;

  /// No description provided for @scanError.
  ///
  /// In en, this message translates to:
  /// **'Failed to scan directory: {error}'**
  String scanError(String error);

  /// No description provided for @noDatasetOpen.
  ///
  /// In en, this message translates to:
  /// **'No folder open'**
  String get noDatasetOpen;

  /// No description provided for @imageCountShort.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String imageCountShort(int count);

  /// No description provided for @selectImageHint.
  ///
  /// In en, this message translates to:
  /// **'Select an image from the assets panel.'**
  String get selectImageHint;

  /// No description provided for @previousImage.
  ///
  /// In en, this message translates to:
  /// **'Previous image'**
  String get previousImage;

  /// No description provided for @nextImage.
  ///
  /// In en, this message translates to:
  /// **'Next image'**
  String get nextImage;

  /// No description provided for @fitToWindow.
  ///
  /// In en, this message translates to:
  /// **'Fit to window'**
  String get fitToWindow;

  /// No description provided for @openInNewWindow.
  ///
  /// In en, this message translates to:
  /// **'Open in separate window'**
  String get openInNewWindow;

  /// No description provided for @textTab.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textTab;

  /// No description provided for @tagsTab.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsTab;

  /// No description provided for @tagCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tags'**
  String tagCount(int count);

  /// No description provided for @savedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {time}'**
  String savedAt(String time);

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @savingNow.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get savingNow;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveFailed;

  /// No description provided for @captionHint.
  ///
  /// In en, this message translates to:
  /// **'Write the caption here, tags separated by commas'**
  String get captionHint;

  /// No description provided for @addTagHint.
  ///
  /// In en, this message translates to:
  /// **'Type a tag and press Enter'**
  String get addTagHint;

  /// No description provided for @noTagsYet.
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get noTagsYet;

  /// No description provided for @editTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Tag'**
  String get editTagTitle;

  /// No description provided for @tagSortModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort mode: drag tags to reorder'**
  String get tagSortModeTooltip;

  /// No description provided for @tagAnchorHolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set insert anchor: new tags are added after this tag ([ / ] to move, click again to clear)'**
  String get tagAnchorHolderTooltip;

  /// No description provided for @anchorStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Insert anchor: {tag}'**
  String anchorStatusLabel(String tag);

  /// No description provided for @anchorClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'New tags are inserted after this tag; click to clear (back to append at end)'**
  String get anchorClearTooltip;

  /// No description provided for @aiInterrogateButton.
  ///
  /// In en, this message translates to:
  /// **'AI tag'**
  String get aiInterrogateButton;

  /// No description provided for @aiInterrogating.
  ///
  /// In en, this message translates to:
  /// **'Tagging…'**
  String get aiInterrogating;

  /// No description provided for @aiParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI tagging parameters'**
  String get aiParamsTitle;

  /// No description provided for @aiServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get aiServerUrl;

  /// No description provided for @aiModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModelLabel;

  /// No description provided for @aiNoModels.
  ///
  /// In en, this message translates to:
  /// **'No models yet — refresh to fetch'**
  String get aiNoModels;

  /// No description provided for @aiRefreshModels.
  ///
  /// In en, this message translates to:
  /// **'Refresh model list'**
  String get aiRefreshModels;

  /// No description provided for @aiModelGroupTag.
  ///
  /// In en, this message translates to:
  /// **'Tag models · booru style'**
  String get aiModelGroupTag;

  /// No description provided for @aiModelGroupCaption.
  ///
  /// In en, this message translates to:
  /// **'Natural language captions'**
  String get aiModelGroupCaption;

  /// No description provided for @aiModelLegacyGroup.
  ///
  /// In en, this message translates to:
  /// **'Legacy models ({count})'**
  String aiModelLegacyGroup(Object count);

  /// No description provided for @aiModelFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter models…'**
  String get aiModelFilterHint;

  /// No description provided for @aiModelFilterNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching models'**
  String get aiModelFilterNoMatch;

  /// No description provided for @aiBadgeRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get aiBadgeRecommended;

  /// No description provided for @aiBadgeUncensored.
  ///
  /// In en, this message translates to:
  /// **'Uncensored'**
  String get aiBadgeUncensored;

  /// No description provided for @aiVramFootnote.
  ///
  /// In en, this message translates to:
  /// **'VRAM figures are estimates; amber means demanding.'**
  String get aiVramFootnote;

  /// No description provided for @aiThresholdCaptionNote.
  ///
  /// In en, this message translates to:
  /// **'The selected model outputs captions; the threshold has no effect.'**
  String get aiThresholdCaptionNote;

  /// No description provided for @aiThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get aiThresholdLabel;

  /// No description provided for @aiUseModelDefault.
  ///
  /// In en, this message translates to:
  /// **'Model default'**
  String get aiUseModelDefault;

  /// No description provided for @aiThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Lower values produce more tags.'**
  String get aiThresholdDesc;

  /// No description provided for @aiIgnoreTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Ignored tags'**
  String get aiIgnoreTagsLabel;

  /// No description provided for @aiIgnoreTagsDesc.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated. These tags never appear in AI results.'**
  String get aiIgnoreTagsDesc;

  /// No description provided for @aiUnderscoreToSpaces.
  ///
  /// In en, this message translates to:
  /// **'Underscores to spaces'**
  String get aiUnderscoreToSpaces;

  /// No description provided for @aiEscapeParentheses.
  ///
  /// In en, this message translates to:
  /// **'Escape parentheses \\( \\)'**
  String get aiEscapeParentheses;

  /// No description provided for @aiConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get aiConnecting;

  /// No description provided for @aiConnectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get aiConnectionOk;

  /// No description provided for @aiConnectionFail.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get aiConnectionFail;

  /// No description provided for @aiConnectionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get aiConnectionUnknown;

  /// No description provided for @aiCurrentTagsHeader.
  ///
  /// In en, this message translates to:
  /// **'Current tags'**
  String get aiCurrentTagsHeader;

  /// No description provided for @aiResultHeader.
  ///
  /// In en, this message translates to:
  /// **'AI results'**
  String get aiResultHeader;

  /// No description provided for @aiMissingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} not in AI results'**
  String aiMissingCount(int count);

  /// No description provided for @aiNewCount.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String aiNewCount(int count);

  /// No description provided for @aiShowNewOnly.
  ///
  /// In en, this message translates to:
  /// **'New only'**
  String get aiShowNewOnly;

  /// No description provided for @aiLegendNew.
  ///
  /// In en, this message translates to:
  /// **'New (click to add)'**
  String get aiLegendNew;

  /// No description provided for @aiLegendMissing.
  ///
  /// In en, this message translates to:
  /// **'Not in AI results'**
  String get aiLegendMissing;

  /// No description provided for @aiLegendMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get aiLegendMatched;

  /// No description provided for @aiAddAllNew.
  ///
  /// In en, this message translates to:
  /// **'Add all new ({count})'**
  String aiAddAllNew(int count);

  /// No description provided for @aiRerun.
  ///
  /// In en, this message translates to:
  /// **'Re-run'**
  String get aiRerun;

  /// No description provided for @aiExitCompare.
  ///
  /// In en, this message translates to:
  /// **'Exit compare'**
  String get aiExitCompare;

  /// No description provided for @aiExitCompareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Exit compare mode (applies to all images)'**
  String get aiExitCompareTooltip;

  /// No description provided for @aiNoResultYet.
  ///
  /// In en, this message translates to:
  /// **'No result for this image yet.'**
  String get aiNoResultYet;

  /// No description provided for @aiFirstRunHint.
  ///
  /// In en, this message translates to:
  /// **'First use of a model downloads it — this can take a while.'**
  String get aiFirstRunHint;

  /// No description provided for @aiNoModelSelected.
  ///
  /// In en, this message translates to:
  /// **'No model selected. Check the AI parameters.'**
  String get aiNoModelSelected;

  /// No description provided for @aiFailed.
  ///
  /// In en, this message translates to:
  /// **'AI tagging failed: {error}'**
  String aiFailed(String error);

  /// No description provided for @batchTagButton.
  ///
  /// In en, this message translates to:
  /// **'Batch tagging'**
  String get batchTagButton;

  /// No description provided for @batchTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch AI tagging'**
  String get batchTagTitle;

  /// No description provided for @batchTagParamsHint.
  ///
  /// In en, this message translates to:
  /// **'Threshold, ignored tags and normalization follow the AI parameters.'**
  String get batchTagParamsHint;

  /// No description provided for @batchTagOpenParams.
  ///
  /// In en, this message translates to:
  /// **'AI parameters…'**
  String get batchTagOpenParams;

  /// No description provided for @batchTagModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get batchTagModeLabel;

  /// No description provided for @batchTagModeAppend.
  ///
  /// In en, this message translates to:
  /// **'Append'**
  String get batchTagModeAppend;

  /// No description provided for @batchTagModeOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get batchTagModeOverwrite;

  /// No description provided for @batchTagModeRecognize.
  ///
  /// In en, this message translates to:
  /// **'Recognize'**
  String get batchTagModeRecognize;

  /// No description provided for @batchTagModeRecognizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Interrogates and caches results without touching caption files; when finished, compare mode opens for per-image review.'**
  String get batchTagModeRecognizeDesc;

  /// No description provided for @batchTagModeAppendDesc.
  ///
  /// In en, this message translates to:
  /// **'New AI tags are appended after each image\'s existing tags; duplicates are never added.'**
  String get batchTagModeAppendDesc;

  /// No description provided for @batchTagModeOverwriteDesc.
  ///
  /// In en, this message translates to:
  /// **'AI results replace each image\'s existing tags; configure below which existing tags survive.'**
  String get batchTagModeOverwriteDesc;

  /// No description provided for @batchTagPreservedLabel.
  ///
  /// In en, this message translates to:
  /// **'Preserved tags'**
  String get batchTagPreservedLabel;

  /// No description provided for @batchTagPreservedDesc.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated. These existing tags survive the overwrite.'**
  String get batchTagPreservedDesc;

  /// No description provided for @batchTagKeepFirstN.
  ///
  /// In en, this message translates to:
  /// **'Keep first N existing tags'**
  String get batchTagKeepFirstN;

  /// No description provided for @batchTagBlacklistLabel.
  ///
  /// In en, this message translates to:
  /// **'Blacklist'**
  String get batchTagBlacklistLabel;

  /// No description provided for @batchTagBlacklistDesc.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated. These tags are never appended.'**
  String get batchTagBlacklistDesc;

  /// No description provided for @batchTagScopeFiltered.
  ///
  /// In en, this message translates to:
  /// **'Only the {count} filtered images'**
  String batchTagScopeFiltered(Object count);

  /// No description provided for @batchTagTargetCount.
  ///
  /// In en, this message translates to:
  /// **'{count} images will be processed, one at a time.'**
  String batchTagTargetCount(Object count);

  /// No description provided for @batchTagStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get batchTagStart;

  /// No description provided for @batchTagRunning.
  ///
  /// In en, this message translates to:
  /// **'Batch tagging {completed}/{total}'**
  String batchTagRunning(Object completed, Object total);

  /// No description provided for @batchTagProgressCounts.
  ///
  /// In en, this message translates to:
  /// **'Changed {changed} · Failed {failed}'**
  String batchTagProgressCounts(Object changed, Object failed);

  /// No description provided for @batchTagHide.
  ///
  /// In en, this message translates to:
  /// **'Run in background'**
  String get batchTagHide;

  /// No description provided for @batchTagCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel run'**
  String get batchTagCancel;

  /// No description provided for @batchTagCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get batchTagCancelling;

  /// No description provided for @batchTagDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch tagging finished'**
  String get batchTagDoneTitle;

  /// No description provided for @batchTagDoneSummary.
  ///
  /// In en, this message translates to:
  /// **'{completed} images processed: {changed} changed, {failed} failed.'**
  String batchTagDoneSummary(Object completed, Object changed, Object failed);

  /// No description provided for @batchTagRecognizeDoneSummary.
  ///
  /// In en, this message translates to:
  /// **'{completed} images processed: {changed} recognized, {failed} failed.'**
  String batchTagRecognizeDoneSummary(
    Object completed,
    Object changed,
    Object failed,
  );

  /// No description provided for @batchTagRecognizeDoneHint.
  ///
  /// In en, this message translates to:
  /// **'Compare mode is on: switch images to review the AI suggestions.'**
  String get batchTagRecognizeDoneHint;

  /// No description provided for @batchTagUndoHint.
  ///
  /// In en, this message translates to:
  /// **'Use undo in the top bar to revert this run.'**
  String get batchTagUndoHint;

  /// No description provided for @batchTagOperationLabel.
  ///
  /// In en, this message translates to:
  /// **'batch AI tagging'**
  String get batchTagOperationLabel;

  /// No description provided for @rightTabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get rightTabLibrary;

  /// No description provided for @rightTabDataset.
  ///
  /// In en, this message translates to:
  /// **'Dataset'**
  String get rightTabDataset;

  /// No description provided for @datasetTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Dataset Tags'**
  String get datasetTagsTitle;

  /// No description provided for @datasetTagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags in this dataset yet.'**
  String get datasetTagsEmpty;

  /// No description provided for @datasetTagsHint.
  ///
  /// In en, this message translates to:
  /// **'Green = on the current image. Right-click for actions'**
  String get datasetTagsHint;

  /// No description provided for @clearTagFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear tag filter'**
  String get clearTagFilter;

  /// No description provided for @menuFilterInclude.
  ///
  /// In en, this message translates to:
  /// **'Only images with this tag'**
  String get menuFilterInclude;

  /// No description provided for @menuFilterExclude.
  ///
  /// In en, this message translates to:
  /// **'Only images without this tag'**
  String get menuFilterExclude;

  /// No description provided for @menuReplaceAppend.
  ///
  /// In en, this message translates to:
  /// **'Replace / append…'**
  String get menuReplaceAppend;

  /// No description provided for @menuDeleteGlobal.
  ///
  /// In en, this message translates to:
  /// **'Delete from all images'**
  String get menuDeleteGlobal;

  /// No description provided for @deleteTagConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete tag everywhere'**
  String get deleteTagConfirmTitle;

  /// No description provided for @deleteTagConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{tag}\" from {count} images? This can be undone from the toolbar.'**
  String deleteTagConfirmContent(int count, String tag);

  /// No description provided for @addTagsGlobalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add tags to all images…'**
  String get addTagsGlobalTooltip;

  /// No description provided for @addTagsGlobalTitle.
  ///
  /// In en, this message translates to:
  /// **'Add tags to all images'**
  String get addTagsGlobalTitle;

  /// No description provided for @addTagsPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Insert position'**
  String get addTagsPositionLabel;

  /// No description provided for @addTagsPosHead.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get addTagsPosHead;

  /// No description provided for @addTagsPosTail.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get addTagsPosTail;

  /// No description provided for @addTagsPosIndex.
  ///
  /// In en, this message translates to:
  /// **'At position'**
  String get addTagsPosIndex;

  /// No description provided for @addTagsIndexHint.
  ///
  /// In en, this message translates to:
  /// **'1 = first'**
  String get addTagsIndexHint;

  /// No description provided for @addTagsGlobalTargetCount.
  ///
  /// In en, this message translates to:
  /// **'Tags will be added to {count} images; tags an image already has are skipped.'**
  String addTagsGlobalTargetCount(int count);

  /// No description provided for @opAddGlobalLabel.
  ///
  /// In en, this message translates to:
  /// **'add \"{tags}\"'**
  String opAddGlobalLabel(String tags);

  /// No description provided for @replaceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace / append'**
  String get replaceDialogTitle;

  /// No description provided for @replaceModeReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get replaceModeReplace;

  /// No description provided for @replaceModeBefore.
  ///
  /// In en, this message translates to:
  /// **'Insert before'**
  String get replaceModeBefore;

  /// No description provided for @replaceModeAfter.
  ///
  /// In en, this message translates to:
  /// **'Insert after'**
  String get replaceModeAfter;

  /// No description provided for @replaceInputHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated tags'**
  String get replaceInputHint;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @filesUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count} files updated'**
  String filesUpdated(int count);

  /// No description provided for @noFilesChanged.
  ///
  /// In en, this message translates to:
  /// **'No files needed changes.'**
  String get noFilesChanged;

  /// No description provided for @filterPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Gallery filter'**
  String get filterPanelTitle;

  /// No description provided for @filterMatches.
  ///
  /// In en, this message translates to:
  /// **'{shown} / {total} match'**
  String filterMatches(int shown, int total);

  /// No description provided for @filterOpAnd.
  ///
  /// In en, this message translates to:
  /// **'AND'**
  String get filterOpAnd;

  /// No description provided for @filterOpOr.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get filterOpOr;

  /// No description provided for @filterToggleOpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Toggle this group\'s AND/OR'**
  String get filterToggleOpTooltip;

  /// No description provided for @filterToggleRoleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Toggle include/exclude'**
  String get filterToggleRoleTooltip;

  /// No description provided for @filterRemoveConditionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove condition'**
  String get filterRemoveConditionTooltip;

  /// No description provided for @filterAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add condition / sub-group'**
  String get filterAddTooltip;

  /// No description provided for @filterAddCondition.
  ///
  /// In en, this message translates to:
  /// **'Add condition…'**
  String get filterAddCondition;

  /// No description provided for @filterAddSubgroup.
  ///
  /// In en, this message translates to:
  /// **'Add sub-group'**
  String get filterAddSubgroup;

  /// No description provided for @filterDissolveGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dissolve group (children move up)'**
  String get filterDissolveGroupTooltip;

  /// No description provided for @filterPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add filter condition'**
  String get filterPickerTitle;

  /// No description provided for @filterRoleInclude.
  ///
  /// In en, this message translates to:
  /// **'Include'**
  String get filterRoleInclude;

  /// No description provided for @filterRoleExclude.
  ///
  /// In en, this message translates to:
  /// **'Exclude'**
  String get filterRoleExclude;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @undoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo: {action}'**
  String undoTooltip(String action);

  /// No description provided for @redoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Redo: {action}'**
  String redoTooltip(String action);

  /// No description provided for @opDeleteLabel.
  ///
  /// In en, this message translates to:
  /// **'delete \"{tag}\"'**
  String opDeleteLabel(String tag);

  /// No description provided for @opReplaceLabel.
  ///
  /// In en, this message translates to:
  /// **'replace \"{tag}\"'**
  String opReplaceLabel(String tag);

  /// No description provided for @opInsertLabel.
  ///
  /// In en, this message translates to:
  /// **'append next to \"{tag}\"'**
  String opInsertLabel(String tag);

  /// No description provided for @tagLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag Library'**
  String get tagLibraryTitle;

  /// No description provided for @filterTagsHint.
  ///
  /// In en, this message translates to:
  /// **'Filter tags'**
  String get filterTagsHint;

  /// No description provided for @clickToApplyHint.
  ///
  /// In en, this message translates to:
  /// **'Click to apply, click again to remove'**
  String get clickToApplyHint;

  /// No description provided for @newTagsSection.
  ///
  /// In en, this message translates to:
  /// **'New in this image'**
  String get newTagsSection;

  /// No description provided for @addAllToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add all'**
  String get addAllToLibrary;

  /// No description provided for @legendApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get legendApplied;

  /// No description provided for @legendNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Not applied'**
  String get legendNotApplied;

  /// No description provided for @legendNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get legendNew;

  /// No description provided for @removeFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get removeFromLibrary;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'The library is empty. Use the plus button to add tags.'**
  String get libraryEmpty;

  /// No description provided for @moreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsTooltip;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from file…'**
  String get importFromFile;

  /// No description provided for @exportLibraryMenu.
  ///
  /// In en, this message translates to:
  /// **'Export tags (with groups)…'**
  String get exportLibraryMenu;

  /// No description provided for @exportGroupsMenu.
  ///
  /// In en, this message translates to:
  /// **'Export groups only…'**
  String get exportGroupsMenu;

  /// No description provided for @clearLibrary.
  ///
  /// In en, this message translates to:
  /// **'Clear library'**
  String get clearLibrary;

  /// No description provided for @clearLibraryConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Remove all {count} tags? Groups are kept.'**
  String clearLibraryConfirmContent(int count);

  /// No description provided for @importSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported {tags} tags, created {groups} groups'**
  String importSummary(int tags, int groups);

  /// No description provided for @importFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailedMsg(String error);

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported: {path}'**
  String exportedTo(String path);

  /// No description provided for @exportFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailedMsg(String error);

  /// No description provided for @newGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroupTitle;

  /// No description provided for @editGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get editGroupTitle;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameHint;

  /// No description provided for @groupColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get groupColorLabel;

  /// No description provided for @customColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customColorLabel;

  /// No description provided for @ungroupedSection.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get ungroupedSection;

  /// No description provided for @groupEditModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Group edit mode'**
  String get groupEditModeTooltip;

  /// No description provided for @changeGroupColorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change group color'**
  String get changeGroupColorTooltip;

  /// No description provided for @moveGroupUpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move group up'**
  String get moveGroupUpTooltip;

  /// No description provided for @moveGroupDownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move group down'**
  String get moveGroupDownTooltip;

  /// No description provided for @groupEditHint.
  ///
  /// In en, this message translates to:
  /// **'Click to select, right-click to send to a group'**
  String get groupEditHint;

  /// No description provided for @groupEditSelectedHint.
  ///
  /// In en, this message translates to:
  /// **'{count} selected · right-click to send to a group'**
  String groupEditSelectedHint(int count);

  /// No description provided for @sendToGroup.
  ///
  /// In en, this message translates to:
  /// **'Send to {name}'**
  String sendToGroup(String name);

  /// No description provided for @sendToNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group and send…'**
  String get sendToNewGroup;

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @editGroupMenu.
  ///
  /// In en, this message translates to:
  /// **'Edit group…'**
  String get editGroupMenu;

  /// No description provided for @deleteGroupMenu.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroupMenu;

  /// No description provided for @deleteGroupConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{name}\"? Its tags return to Ungrouped.'**
  String deleteGroupConfirmContent(String name);

  /// No description provided for @taggedProgress.
  ///
  /// In en, this message translates to:
  /// **'Tagged {tagged} / {total}'**
  String taggedProgress(int tagged, int total);

  /// No description provided for @autoSaveOnStatus.
  ///
  /// In en, this message translates to:
  /// **'Auto-save on'**
  String get autoSaveOnStatus;

  /// No description provided for @autoSaveOffStatus.
  ///
  /// In en, this message translates to:
  /// **'Auto-save off'**
  String get autoSaveOffStatus;

  /// No description provided for @saveShortcutHint.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+S to save now'**
  String get saveShortcutHint;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @datasetSection.
  ///
  /// In en, this message translates to:
  /// **'Dataset'**
  String get datasetSection;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get dangerZone;

  /// No description provided for @languageDesc.
  ///
  /// In en, this message translates to:
  /// **'Interface display language'**
  String get languageDesc;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// No description provided for @themeDesc.
  ///
  /// In en, this message translates to:
  /// **'Dark is easier on the eyes for long sessions'**
  String get themeDesc;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @fontTitle.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontTitle;

  /// No description provided for @fontDesc.
  ///
  /// In en, this message translates to:
  /// **'UI font. HarmonyOS Sans and MiSans are downloaded on first use'**
  String get fontDesc;

  /// No description provided for @fontSystem.
  ///
  /// In en, this message translates to:
  /// **'System font'**
  String get fontSystem;

  /// No description provided for @fontHarmony.
  ///
  /// In en, this message translates to:
  /// **'HarmonyOS Sans'**
  String get fontHarmony;

  /// No description provided for @fontMiSans.
  ///
  /// In en, this message translates to:
  /// **'MiSans'**
  String get fontMiSans;

  /// No description provided for @fontDownloadConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Download font'**
  String get fontDownloadConfirmTitle;

  /// No description provided for @fontDownloadConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Using {font} for the first time requires downloading the official font package into the app data directory. This only happens once. Download now?'**
  String fontDownloadConfirmContent(String font);

  /// No description provided for @fontDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get fontDownloadAction;

  /// No description provided for @fontDownloadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading {font}…'**
  String fontDownloadingTitle(String font);

  /// No description provided for @fontDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Font download failed: {error}'**
  String fontDownloadFailed(String error);

  /// No description provided for @captionExtensionDesc.
  ///
  /// In en, this message translates to:
  /// **'Suffix of the caption file that shares the image\'s name, e.g. .txt or .caption'**
  String get captionExtensionDesc;

  /// No description provided for @includeSubdirsTitle.
  ///
  /// In en, this message translates to:
  /// **'Include subdirectories'**
  String get includeSubdirsTitle;

  /// No description provided for @includeSubdirsDesc.
  ///
  /// In en, this message translates to:
  /// **'Recursively scan all folders inside the opened directory'**
  String get includeSubdirsDesc;

  /// No description provided for @autoSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-save'**
  String get autoSaveTitle;

  /// No description provided for @autoSaveDesc.
  ///
  /// In en, this message translates to:
  /// **'Write the caption file 0.8 s after you stop editing'**
  String get autoSaveDesc;

  /// No description provided for @resetDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults and clear the tag library. Images and caption files are not touched.'**
  String get resetDesc;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
