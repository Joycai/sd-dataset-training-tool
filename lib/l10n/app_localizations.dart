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

  /// No description provided for @captionTypesTitle.
  ///
  /// In en, this message translates to:
  /// **'Caption Types'**
  String get captionTypesTitle;

  /// No description provided for @captionTypesDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep several caption files per image; enabled types appear in the navigator\'s and the editor\'s switcher'**
  String get captionTypesDesc;

  /// No description provided for @captionTypeName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get captionTypeName;

  /// No description provided for @captionTypeNameHint.
  ///
  /// In en, this message translates to:
  /// **'Untitled type'**
  String get captionTypeNameHint;

  /// No description provided for @captionTypeFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get captionTypeFormat;

  /// No description provided for @captionTypeExtension.
  ///
  /// In en, this message translates to:
  /// **'Extension'**
  String get captionTypeExtension;

  /// No description provided for @captionTypeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add type'**
  String get captionTypeAdd;

  /// No description provided for @captionTypeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get captionTypeEnabled;

  /// No description provided for @captionTypeDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get captionTypeDefaultBadge;

  /// No description provided for @captionTypeDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'The default type is always enabled'**
  String get captionTypeDefaultHint;

  /// No description provided for @captionTypeRules.
  ///
  /// In en, this message translates to:
  /// **'Extensions must be unique · the default type cannot be disabled or deleted'**
  String get captionTypeRules;

  /// No description provided for @captionTypeFormatTooltip.
  ///
  /// In en, this message translates to:
  /// **'Format: how this type\'s caption files are parsed — comma-separated tags, a JSON document, or natural-language sentences'**
  String get captionTypeFormatTooltip;

  /// No description provided for @captionTypeFormatTags.
  ///
  /// In en, this message translates to:
  /// **'WD14 tags'**
  String get captionTypeFormatTags;

  /// No description provided for @captionTypeFormatTagsDesc.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated · editable tag chips'**
  String get captionTypeFormatTagsDesc;

  /// No description provided for @captionTypeFormatJson.
  ///
  /// In en, this message translates to:
  /// **'Anima JSON'**
  String get captionTypeFormatJson;

  /// No description provided for @captionTypeFormatJsonDesc.
  ///
  /// In en, this message translates to:
  /// **'Structured document · read-only tag view'**
  String get captionTypeFormatJsonDesc;

  /// No description provided for @captionTypeFormatNl.
  ///
  /// In en, this message translates to:
  /// **'Natural language'**
  String get captionTypeFormatNl;

  /// No description provided for @captionTypeFormatNlDesc.
  ///
  /// In en, this message translates to:
  /// **'Full text · split into sentences'**
  String get captionTypeFormatNlDesc;

  /// No description provided for @captionTypeDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This extension is already used by another caption type'**
  String get captionTypeDuplicate;

  /// No description provided for @captionTypeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a usable caption extension'**
  String get captionTypeInvalid;

  /// No description provided for @captionTypePickerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch caption type. The editor, batch edits and the AI assistant all read and write this type\'s caption files.'**
  String get captionTypePickerTooltip;

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

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

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

  /// No description provided for @searchFilenameHint.
  ///
  /// In en, this message translates to:
  /// **'Search filenames'**
  String get searchFilenameHint;

  /// No description provided for @subdirAll.
  ///
  /// In en, this message translates to:
  /// **'All folders'**
  String get subdirAll;

  /// No description provided for @subdirRoot.
  ///
  /// In en, this message translates to:
  /// **'Root folder'**
  String get subdirRoot;

  /// No description provided for @subdirPickerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch subdirectory. The selected folder also scopes the tag statistics, the batch edits and the AI assistant.'**
  String get subdirPickerTooltip;

  /// No description provided for @subdirScopeNotice.
  ///
  /// In en, this message translates to:
  /// **'Scope: {name}'**
  String subdirScopeNotice(String name);

  /// No description provided for @subdirScopeClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back to the whole dataset'**
  String get subdirScopeClearTooltip;

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

  /// No description provided for @thumbFitTooltip.
  ///
  /// In en, this message translates to:
  /// **'Fit thumbnails: show the whole image'**
  String get thumbFitTooltip;

  /// No description provided for @thumbFillTooltip.
  ///
  /// In en, this message translates to:
  /// **'Fill thumbnails: crop to fill the cell'**
  String get thumbFillTooltip;

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

  /// No description provided for @tagCountShort.
  ///
  /// In en, this message translates to:
  /// **'{count} tags'**
  String tagCountShort(int count);

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

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

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

  /// No description provided for @jsonTab.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get jsonTab;

  /// No description provided for @captionJsonEmpty.
  ///
  /// In en, this message translates to:
  /// **'No caption yet.'**
  String get captionJsonEmpty;

  /// No description provided for @captionJsonInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON — {error}'**
  String captionJsonInvalid(String error);

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

  /// No description provided for @compareModeCapsule.
  ///
  /// In en, this message translates to:
  /// **'Compare mode · {count} with results'**
  String compareModeCapsule(int count);

  /// No description provided for @compareModeHint.
  ///
  /// In en, this message translates to:
  /// **'Accept or reject AI results one by one'**
  String get compareModeHint;

  /// No description provided for @compareModeExitGlobal.
  ///
  /// In en, this message translates to:
  /// **'Exit compare mode'**
  String get compareModeExitGlobal;

  /// No description provided for @compareBadgePending.
  ///
  /// In en, this message translates to:
  /// **'{count} to review'**
  String compareBadgePending(int count);

  /// No description provided for @compareBadgeReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get compareBadgeReviewed;

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
  /// **'✓ = on the current image. Right-click for actions'**
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

  /// No description provided for @tagMenuOpenDictionary.
  ///
  /// In en, this message translates to:
  /// **'Open in dictionary…'**
  String get tagMenuOpenDictionary;

  /// No description provided for @tagMenuRemoveFromImage.
  ///
  /// In en, this message translates to:
  /// **'Remove from this image'**
  String get tagMenuRemoveFromImage;

  /// No description provided for @tagMenuSetAnchor.
  ///
  /// In en, this message translates to:
  /// **'Set as insertion anchor'**
  String get tagMenuSetAnchor;

  /// No description provided for @tagMenuClearAnchor.
  ///
  /// In en, this message translates to:
  /// **'Clear insertion anchor'**
  String get tagMenuClearAnchor;

  /// No description provided for @tagMenuAddToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get tagMenuAddToLibrary;

  /// No description provided for @tagMenuApplySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Apply suggestion'**
  String get tagMenuApplySuggestion;

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

  /// No description provided for @deleteTagConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete ({count})'**
  String deleteTagConfirmButton(int count);

  /// No description provided for @datasetTagSortAlphaTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort tags alphabetically'**
  String get datasetTagSortAlphaTooltip;

  /// No description provided for @datasetReorderMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort all images\' tags…'**
  String get datasetReorderMenuLabel;

  /// No description provided for @datasetReorderDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort tags everywhere'**
  String get datasetReorderDialogTitle;

  /// No description provided for @datasetReorderDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Reorders every image\'s tags to match the order shown in this list. Applies to {count} images.'**
  String datasetReorderDialogContent(int count);

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

  /// No description provided for @replaceAffectedCount.
  ///
  /// In en, this message translates to:
  /// **'Applies to {count} images'**
  String replaceAffectedCount(int count);

  /// No description provided for @applyCountButton.
  ///
  /// In en, this message translates to:
  /// **'Apply ({count})'**
  String applyCountButton(int count);

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

  /// No description provided for @undoFailedRetryHint.
  ///
  /// In en, this message translates to:
  /// **'{count} files could not be written — the operation is still on the stack, undo again to retry them'**
  String undoFailedRetryHint(int count);

  /// No description provided for @filesFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} files could not be written'**
  String filesFailed(int count);

  /// No description provided for @filterPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Gallery filter'**
  String get filterPanelTitle;

  /// No description provided for @filterStatus.
  ///
  /// In en, this message translates to:
  /// **'Filtered · {shown} / {total} match'**
  String filterStatus(int shown, int total);

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

  /// No description provided for @opReorderLabel.
  ///
  /// In en, this message translates to:
  /// **'sort tags everywhere'**
  String get opReorderLabel;

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

  /// No description provided for @groupEditSelectAction.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get groupEditSelectAction;

  /// No description provided for @groupEditDeselectAction.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get groupEditDeselectAction;

  /// No description provided for @groupEditSelectAllInGroupAction.
  ///
  /// In en, this message translates to:
  /// **'Select all in group'**
  String get groupEditSelectAllInGroupAction;

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

  /// No description provided for @shortcutHints.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+S save · Ctrl+E AI tag · Ctrl+Z undo'**
  String get shortcutHints;

  /// No description provided for @aiServiceConnected.
  ///
  /// In en, this message translates to:
  /// **'AI service connected'**
  String get aiServiceConnected;

  /// No description provided for @aiServiceOffline.
  ///
  /// In en, this message translates to:
  /// **'AI service offline'**
  String get aiServiceOffline;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @toggleNavigator.
  ///
  /// In en, this message translates to:
  /// **'Show / hide navigator'**
  String get toggleNavigator;

  /// No description provided for @toggleInspector.
  ///
  /// In en, this message translates to:
  /// **'Show / hide inspector'**
  String get toggleInspector;

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

  /// No description provided for @accentTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get accentTitle;

  /// No description provided for @accentDesc.
  ///
  /// In en, this message translates to:
  /// **'Base color; surfaces, borders and highlights across the UI are tinted from it'**
  String get accentDesc;

  /// No description provided for @accentTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get accentTeal;

  /// No description provided for @accentBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentBlue;

  /// No description provided for @accentIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get accentIndigo;

  /// No description provided for @accentViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get accentViolet;

  /// No description provided for @accentRose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get accentRose;

  /// No description provided for @accentGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @versionTitle.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionTitle;

  /// No description provided for @versionDesc.
  ///
  /// In en, this message translates to:
  /// **'Current application version'**
  String get versionDesc;

  /// No description provided for @licenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get licenseTitle;

  /// No description provided for @sourceCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCodeTitle;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @agentPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get agentPanelTitle;

  /// No description provided for @agentMinimize.
  ///
  /// In en, this message translates to:
  /// **'Collapse panel'**
  String get agentMinimize;

  /// No description provided for @agentExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand panel'**
  String get agentExpand;

  /// No description provided for @agentNewSession.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get agentNewSession;

  /// No description provided for @agentStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get agentStop;

  /// No description provided for @agentSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get agentSend;

  /// No description provided for @agentInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about or edit your dataset…'**
  String get agentInputHint;

  /// No description provided for @agentNoProfileHint.
  ///
  /// In en, this message translates to:
  /// **'No LLM backend configured yet. Add one in Settings to start using the assistant.'**
  String get agentNoProfileHint;

  /// No description provided for @agentOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get agentOpenSettings;

  /// No description provided for @agentRunning.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get agentRunning;

  /// No description provided for @agentTokensUsed.
  ///
  /// In en, this message translates to:
  /// **'{count} tokens used this conversation'**
  String agentTokensUsed(int count);

  /// No description provided for @agentExpandInput.
  ///
  /// In en, this message translates to:
  /// **'Expand input'**
  String get agentExpandInput;

  /// No description provided for @agentComposerTitle.
  ///
  /// In en, this message translates to:
  /// **'Compose message'**
  String get agentComposerTitle;

  /// No description provided for @agentQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'The assistant is asking'**
  String get agentQuestionTitle;

  /// No description provided for @agentQuestionCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Type a custom answer…'**
  String get agentQuestionCustomHint;

  /// No description provided for @agentQuestionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss without answering'**
  String get agentQuestionDismiss;

  /// No description provided for @agentStoppedNotice.
  ///
  /// In en, this message translates to:
  /// **'Stopped.'**
  String get agentStoppedNotice;

  /// No description provided for @agentSessionResetNotice.
  ///
  /// In en, this message translates to:
  /// **'Dataset changed — conversation reset.'**
  String get agentSessionResetNotice;

  /// No description provided for @agentSwitchProfile.
  ///
  /// In en, this message translates to:
  /// **'Switch backend'**
  String get agentSwitchProfile;

  /// No description provided for @agentProfileSwitchedNotice.
  ///
  /// In en, this message translates to:
  /// **'Switched to \"{name}\" — the next message starts a new conversation, without the context above.'**
  String agentProfileSwitchedNotice(String name);

  /// No description provided for @agentErrorNotice.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String agentErrorNotice(String message);

  /// No description provided for @agentConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'The assistant wants to modify captions'**
  String get agentConfirmTitle;

  /// No description provided for @agentConfirmAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get agentConfirmAllow;

  /// No description provided for @agentConfirmAllowAll.
  ///
  /// In en, this message translates to:
  /// **'Allow all this conversation'**
  String get agentConfirmAllowAll;

  /// No description provided for @agentConfirmReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get agentConfirmReject;

  /// No description provided for @agentTokenCapTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation token budget'**
  String get agentTokenCapTitle;

  /// No description provided for @agentTokenCapDesc.
  ///
  /// In en, this message translates to:
  /// **'Stops a conversation once it has spent this many tokens. Every turn re-sends the whole history, so batch work spends it fast — raise it, or start a new conversation when it runs out. Applies to the next conversation.'**
  String get agentTokenCapDesc;

  /// No description provided for @agentTokenCapUnlimited.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get agentTokenCapUnlimited;

  /// No description provided for @agentTokenCapNotice.
  ///
  /// In en, this message translates to:
  /// **'This conversation reached its token budget. Start a new conversation, or raise the budget in Settings.'**
  String get agentTokenCapNotice;

  /// No description provided for @agentTokensUsedOfCap.
  ///
  /// In en, this message translates to:
  /// **'{used} / {cap} tokens used this conversation'**
  String agentTokensUsedOfCap(int used, int cap);

  /// No description provided for @agentConfirmWritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm writes'**
  String get agentConfirmWritesTitle;

  /// No description provided for @agentConfirmWritesDesc.
  ///
  /// In en, this message translates to:
  /// **'Ask before the assistant modifies caption files; every change stays undoable either way'**
  String get agentConfirmWritesDesc;

  /// No description provided for @promptPresetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Prompt presets'**
  String get promptPresetsTitle;

  /// No description provided for @promptPresetsDesc.
  ///
  /// In en, this message translates to:
  /// **'Save prompts you use often and drop them into the assistant\'s input with one click'**
  String get promptPresetsDesc;

  /// No description provided for @promptPresetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No prompt presets yet'**
  String get promptPresetsEmpty;

  /// No description provided for @promptPresetsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage presets…'**
  String get promptPresetsManage;

  /// No description provided for @promptPresetAdd.
  ///
  /// In en, this message translates to:
  /// **'Add prompt'**
  String get promptPresetAdd;

  /// No description provided for @promptPresetNewName.
  ///
  /// In en, this message translates to:
  /// **'New prompt'**
  String get promptPresetNewName;

  /// No description provided for @promptPresetUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get promptPresetUntitled;

  /// No description provided for @promptPresetName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get promptPresetName;

  /// No description provided for @promptPresetContent.
  ///
  /// In en, this message translates to:
  /// **'Prompt text'**
  String get promptPresetContent;

  /// No description provided for @promptPresetContentHint.
  ///
  /// In en, this message translates to:
  /// **'The text inserted into the assistant\'s input…'**
  String get promptPresetContentHint;

  /// No description provided for @promptPresetSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select a prompt on the left, or add a new one.'**
  String get promptPresetSelectHint;

  /// No description provided for @promptPresetMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get promptPresetMoveUp;

  /// No description provided for @promptPresetMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get promptPresetMoveDown;

  /// No description provided for @promptPresetDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete prompt'**
  String get promptPresetDeleteConfirmTitle;

  /// No description provided for @promptPresetDeleteConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String promptPresetDeleteConfirmContent(String name);

  /// No description provided for @builtinPresetsSection.
  ///
  /// In en, this message translates to:
  /// **'Built-in prompts'**
  String get builtinPresetsSection;

  /// No description provided for @animaJsonGeneratePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'WD14 tags to Anima JSON'**
  String get animaJsonGeneratePresetTitle;

  /// No description provided for @animaJsonGeneratePresetBody.
  ///
  /// In en, this message translates to:
  /// **'Convert this dataset\'s WD14 tag captions into Anima JSON captions (the AnimaLoraToolkit simplified format).\n\nTarget fields, in order: quality (fixed value), count (people count), character, series, artist (fixed value), appearance (array: hair, eyes, body, clothing, accessories), tags (array: actions, expressions, composition, viewpoint and everything else — the catch-all), environment (array: indoors/outdoors, sky, lighting, scenery), nl (natural-language description, empty string for now).\n\nSteps:\n1. Confirm with get_dataset_overview that a JSON-format caption type is configured; if not, stop and tell me to add one in the caption type settings first.\n2. Get every tag with get_tag_stats and sort each one into the fields above to build the assign map; leave any tag you are unsure about out of assign so it falls into the tags catch-all.\n3. Run convert_captions_to_json once: source is the tag-format type carrying the WD14 tags, target is the JSON type, unassigned_field is tags, and quality, artist and nl are constants (empty strings unless I gave values below). Declare count, character and series as string normally, but as array if one image can carry several such tags at once (say 1girl plus 1boy), so no image gets skipped. Images that already have a non-empty target file are skipped unless you set overwrite.\n4. Afterwards report the tags that fell into the catch-all (unassigned_tags_seen); if any clearly belong in appearance or environment, fix them with a follow-up restructure_json_captions assign pass.\n\nDo not loop write_caption_file to write JSON image by image.'**
  String get animaJsonGeneratePresetBody;

  /// No description provided for @animaJsonReorderPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder Anima JSON fields'**
  String get animaJsonReorderPresetTitle;

  /// No description provided for @animaJsonReorderPresetBody.
  ///
  /// In en, this message translates to:
  /// **'Reorder this dataset\'s Anima JSON captions into the standard field order: quality, count, character, series, artist, appearance, tags, environment, nl (the render order — nl always last).\n\nSteps:\n1. Run inspect_json_captions on the JSON caption type to see which keys actually exist, how many tags each holds and which key orders occur; plan from that result, never from memory.\n2. Run restructure_json_captions once: declare fields in the order above; same-named keys route automatically, use from to rename or merge; declare nl as preserve so it is copied verbatim; use tags as unassigned_field. Any extra keys the dataset carries either merge into a matching field via from, or keep their name placed after environment and before nl. Declare a field as string only when inspect shows at most one tag per image under it — otherwise use array.\n3. Keep drop_empty false so every image keeps the same shape; use tag_priority if some tags should come first inside a field.\n4. Afterwards report written/unchanged/failed counts plus anything in unrouted_keys_seen and unassigned_tags_seen.\n\nDo not rewrite images one by one with write_caption_file.'**
  String get animaJsonReorderPresetBody;

  /// No description provided for @batchTagModeSheet.
  ///
  /// In en, this message translates to:
  /// **'Sheet'**
  String get batchTagModeSheet;

  /// No description provided for @batchTagModeSheetDesc.
  ///
  /// In en, this message translates to:
  /// **'Rebuilds every caption from a saved character sheet: the trigger word and fixed traits always, outfit items only where the tagger saw them, and the tagger\'s expression / background / pose / framing kept as-is.'**
  String get batchTagModeSheetDesc;

  /// No description provided for @batchTagRulesLabel.
  ///
  /// In en, this message translates to:
  /// **'Rule set'**
  String get batchTagRulesLabel;

  /// No description provided for @batchTagRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a rule set'**
  String get batchTagRulesHint;

  /// No description provided for @batchTagRulesUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed rule set'**
  String get batchTagRulesUnnamed;

  /// No description provided for @batchTagRulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rule sets yet. Run the character sheet skill in the assistant first — it produces the rules this mode applies.'**
  String get batchTagRulesEmpty;

  /// No description provided for @batchTagRulesSummary.
  ///
  /// In en, this message translates to:
  /// **'{identity} fixed traits · {garments} outfit items · {conflicts} always removed'**
  String batchTagRulesSummary(int identity, int garments, int conflicts);

  /// No description provided for @batchTagEvidenceThreshold.
  ///
  /// In en, this message translates to:
  /// **'Outfit evidence threshold'**
  String get batchTagEvidenceThreshold;

  /// No description provided for @batchTagEvidenceThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Lower than the tagger\'s own threshold on purpose: the sheet already says the character wears these, so a faint sighting is more likely real than invented. Raise it to the tagger\'s threshold to disable the allowance.'**
  String get batchTagEvidenceThresholdDesc;

  /// No description provided for @batchTagSheetOverwriteWarning.
  ///
  /// In en, this message translates to:
  /// **'Captions are rebuilt, not merged — existing tags are replaced. One undo reverts the whole run.'**
  String get batchTagSheetOverwriteWarning;

  /// No description provided for @mergeRulesApplyHint.
  ///
  /// In en, this message translates to:
  /// **'To apply these across the dataset, open batch tagging and pick the \"Sheet\" mode.'**
  String get mergeRulesApplyHint;

  /// No description provided for @agentSkillsSection.
  ///
  /// In en, this message translates to:
  /// **'Built-in skills'**
  String get agentSkillsSection;

  /// No description provided for @characterSheetSkill.
  ///
  /// In en, this message translates to:
  /// **'Character sheet tagging…'**
  String get characterSheetSkill;

  /// No description provided for @characterSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Character sheet tagging'**
  String get characterSheetTitle;

  /// No description provided for @characterSheetIntro.
  ///
  /// In en, this message translates to:
  /// **'The assistant samples the dataset with the tagger and works out how your fixed tags combine with what the tagger sees. It produces merge rules for you to review — no caption is written in this step.'**
  String get characterSheetIntro;

  /// No description provided for @characterSheetName.
  ///
  /// In en, this message translates to:
  /// **'Rule set name'**
  String get characterSheetName;

  /// No description provided for @characterSheetNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. the character\'s name'**
  String get characterSheetNameHint;

  /// No description provided for @characterSheetTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger word'**
  String get characterSheetTrigger;

  /// No description provided for @characterSheetTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'written as the first tag of every caption'**
  String get characterSheetTriggerHint;

  /// No description provided for @characterSheetIdentity.
  ///
  /// In en, this message translates to:
  /// **'Fixed traits'**
  String get characterSheetIdentity;

  /// No description provided for @characterSheetIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'hair colour, hairstyle, breast size, eyes… written on every image'**
  String get characterSheetIdentityHint;

  /// No description provided for @characterSheetGarments.
  ///
  /// In en, this message translates to:
  /// **'Outfit'**
  String get characterSheetGarments;

  /// No description provided for @characterSheetGarmentsHint.
  ///
  /// In en, this message translates to:
  /// **'dress, gloves, boots, accessories… written only where the tagger saw them'**
  String get characterSheetGarmentsHint;

  /// No description provided for @characterSheetExtra.
  ///
  /// In en, this message translates to:
  /// **'Additional requirements (optional)'**
  String get characterSheetExtra;

  /// No description provided for @characterSheetExtraHint.
  ///
  /// In en, this message translates to:
  /// **'leave empty to go entirely by the tagger\'s output'**
  String get characterSheetExtraHint;

  /// No description provided for @characterSheetSampleSize.
  ///
  /// In en, this message translates to:
  /// **'Sample size'**
  String get characterSheetSampleSize;

  /// No description provided for @characterSheetSampleSizeSuffix.
  ///
  /// In en, this message translates to:
  /// **'images'**
  String get characterSheetSampleSizeSuffix;

  /// No description provided for @characterSheetStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get characterSheetStart;

  /// No description provided for @characterSheetTagsHelp.
  ///
  /// In en, this message translates to:
  /// **'One per line, or comma-separated.'**
  String get characterSheetTagsHelp;

  /// No description provided for @characterSheetSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Character sheet tagging (planning)'**
  String get characterSheetSummaryTitle;

  /// No description provided for @characterSheetSummarySample.
  ///
  /// In en, this message translates to:
  /// **'Sampling {count} images'**
  String characterSheetSummarySample(int count);

  /// No description provided for @mergeRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge rules'**
  String get mergeRulesTitle;

  /// No description provided for @mergeRulesSampled.
  ///
  /// In en, this message translates to:
  /// **'from {count} sampled images'**
  String mergeRulesSampled(int count);

  /// No description provided for @mergeRulesTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger word'**
  String get mergeRulesTrigger;

  /// No description provided for @mergeRulesIdentity.
  ///
  /// In en, this message translates to:
  /// **'Always written'**
  String get mergeRulesIdentity;

  /// No description provided for @mergeRulesConflict.
  ///
  /// In en, this message translates to:
  /// **'Always removed'**
  String get mergeRulesConflict;

  /// No description provided for @mergeRulesGarments.
  ///
  /// In en, this message translates to:
  /// **'Outfit, gated by the tagger'**
  String get mergeRulesGarments;

  /// No description provided for @mergeRulesPassthrough.
  ///
  /// In en, this message translates to:
  /// **'Kept from the tagger'**
  String get mergeRulesPassthrough;

  /// No description provided for @mergeRulesNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get mergeRulesNotes;

  /// No description provided for @mergeRulesNeverWritten.
  ///
  /// In en, this message translates to:
  /// **'no evidence in the sample — never written'**
  String get mergeRulesNeverWritten;

  /// No description provided for @mergeRulesEvidence.
  ///
  /// In en, this message translates to:
  /// **'when the tagger says: {tags}'**
  String mergeRulesEvidence(String tags);

  /// No description provided for @llmSection.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant (LLM)'**
  String get llmSection;

  /// No description provided for @llmActiveProfile.
  ///
  /// In en, this message translates to:
  /// **'Active backend'**
  String get llmActiveProfile;

  /// No description provided for @llmActiveProfileDesc.
  ///
  /// In en, this message translates to:
  /// **'Which configured LLM backend the assistant talks to'**
  String get llmActiveProfileDesc;

  /// No description provided for @llmNoProfiles.
  ///
  /// In en, this message translates to:
  /// **'None configured'**
  String get llmNoProfiles;

  /// No description provided for @llmManageProfiles.
  ///
  /// In en, this message translates to:
  /// **'Backends'**
  String get llmManageProfiles;

  /// No description provided for @llmManageProfilesDesc.
  ///
  /// In en, this message translates to:
  /// **'Add, edit, test and remove LLM backend configurations'**
  String get llmManageProfilesDesc;

  /// No description provided for @llmManageAction.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get llmManageAction;

  /// No description provided for @llmProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'LLM Backends'**
  String get llmProfilesTitle;

  /// No description provided for @llmProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'PROVIDER'**
  String get llmProviderLabel;

  /// No description provided for @llmAddProvider.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get llmAddProvider;

  /// No description provided for @llmAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get llmAddModel;

  /// No description provided for @llmDeleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get llmDeleteModel;

  /// No description provided for @llmEditProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get llmEditProvider;

  /// No description provided for @llmDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get llmDisplayName;

  /// No description provided for @llmVisionBadge.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get llmVisionBadge;

  /// No description provided for @llmInheritsFromProvider.
  ///
  /// In en, this message translates to:
  /// **'URL and key come from the provider \"{name}\".'**
  String llmInheritsFromProvider(String name);

  /// No description provided for @llmPricingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pricing (per Mtoken)'**
  String get llmPricingTitle;

  /// No description provided for @llmPricingNote.
  ///
  /// In en, this message translates to:
  /// **'Used for usage accounting only; never sent with requests.'**
  String get llmPricingNote;

  /// No description provided for @llmPriceInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get llmPriceInput;

  /// No description provided for @llmPriceOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get llmPriceOutput;

  /// No description provided for @llmPriceCacheRead.
  ///
  /// In en, this message translates to:
  /// **'Cache read'**
  String get llmPriceCacheRead;

  /// No description provided for @llmPriceCacheWrite.
  ///
  /// In en, this message translates to:
  /// **'Cache write'**
  String get llmPriceCacheWrite;

  /// No description provided for @llmNewProfileName.
  ///
  /// In en, this message translates to:
  /// **'New backend'**
  String get llmNewProfileName;

  /// No description provided for @llmSelectProfileHint.
  ///
  /// In en, this message translates to:
  /// **'Select a backend on the left, or add a new one.'**
  String get llmSelectProfileHint;

  /// No description provided for @llmProfileName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get llmProfileName;

  /// No description provided for @llmPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get llmPreset;

  /// No description provided for @llmKindOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible'**
  String get llmKindOpenAi;

  /// No description provided for @llmKindAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic'**
  String get llmKindAnthropic;

  /// No description provided for @llmBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get llmBaseUrl;

  /// No description provided for @llmApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get llmApiKey;

  /// No description provided for @llmApiKeyPlaintextNote.
  ///
  /// In en, this message translates to:
  /// **'Stored as plain text in local settings.'**
  String get llmApiKeyPlaintextNote;

  /// No description provided for @llmModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get llmModel;

  /// No description provided for @llmContextWindow.
  ///
  /// In en, this message translates to:
  /// **'Context window'**
  String get llmContextWindow;

  /// No description provided for @llmMaxOutput.
  ///
  /// In en, this message translates to:
  /// **'Max output'**
  String get llmMaxOutput;

  /// No description provided for @llmTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get llmTemperature;

  /// No description provided for @llmSupportsVision.
  ///
  /// In en, this message translates to:
  /// **'Vision (multimodal)'**
  String get llmSupportsVision;

  /// No description provided for @llmSupportsVisionDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable if the model accepts images; unlocks image tools in later phases'**
  String get llmSupportsVisionDesc;

  /// No description provided for @llmFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch model list'**
  String get llmFetchModels;

  /// No description provided for @llmNoModelsFound.
  ///
  /// In en, this message translates to:
  /// **'The server returned no models'**
  String get llmNoModelsFound;

  /// No description provided for @llmTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get llmTestConnection;

  /// No description provided for @llmTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connection OK ({ms} ms)'**
  String llmTestOk(int ms);

  /// No description provided for @llmTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String llmTestFailed(String error);

  /// No description provided for @llmDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete backend'**
  String get llmDeleteConfirmTitle;

  /// No description provided for @llmDeleteConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String llmDeleteConfirmContent(String name);

  /// No description provided for @tagWikiAction.
  ///
  /// In en, this message translates to:
  /// **'Danbooru wiki'**
  String get tagWikiAction;

  /// No description provided for @tagPostsAction.
  ///
  /// In en, this message translates to:
  /// **'Danbooru posts'**
  String get tagPostsAction;

  /// No description provided for @tagWikiTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open the danbooru wiki (F1)'**
  String get tagWikiTooltip;

  /// No description provided for @tagTranslateAction.
  ///
  /// In en, this message translates to:
  /// **'Add a translation'**
  String get tagTranslateAction;

  /// No description provided for @tagEditTranslation.
  ///
  /// In en, this message translates to:
  /// **'Edit the translation'**
  String get tagEditTranslation;

  /// No description provided for @tagNotInDictionary.
  ///
  /// In en, this message translates to:
  /// **'Not in the tag dictionary'**
  String get tagNotInDictionary;

  /// No description provided for @tagPostCount.
  ///
  /// In en, this message translates to:
  /// **'{count} posts on danbooru'**
  String tagPostCount(int count);

  /// No description provided for @tagSuggestionAlias.
  ///
  /// In en, this message translates to:
  /// **'alias: {alias}'**
  String tagSuggestionAlias(String alias);

  /// No description provided for @tagSuggestionLocalUsed.
  ///
  /// In en, this message translates to:
  /// **'your tag · {count} images in this dataset'**
  String tagSuggestionLocalUsed(int count);

  /// No description provided for @tagSuggestionLocalLibrary.
  ///
  /// In en, this message translates to:
  /// **'your tag · from the tag library'**
  String get tagSuggestionLocalLibrary;

  /// No description provided for @tagSuggestionCustom.
  ///
  /// In en, this message translates to:
  /// **'added by hand'**
  String get tagSuggestionCustom;

  /// No description provided for @tagNotInDictionaryUsed.
  ///
  /// In en, this message translates to:
  /// **'Not in the tag dictionary · {count} images in this dataset'**
  String tagNotInDictionaryUsed(int count);

  /// No description provided for @tagDictionaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag dictionary'**
  String get tagDictionaryTitle;

  /// No description provided for @tagDictionaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Suggests danbooru tags while you type in the caption editor'**
  String get tagDictionaryDesc;

  /// No description provided for @tagDictionaryStatusLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get tagDictionaryStatusLoading;

  /// No description provided for @tagDictionaryStatusBundled.
  ///
  /// In en, this message translates to:
  /// **'Built-in · {count} tags'**
  String tagDictionaryStatusBundled(int count);

  /// No description provided for @tagDictionaryStatusFull.
  ///
  /// In en, this message translates to:
  /// **'Full · {count} tags'**
  String tagDictionaryStatusFull(int count);

  /// No description provided for @tagDictionaryFullTitle.
  ///
  /// In en, this message translates to:
  /// **'Full danbooru dictionary'**
  String get tagDictionaryFullTitle;

  /// No description provided for @tagDictionaryFullDesc.
  ///
  /// In en, this message translates to:
  /// **'Downloads the top 100k tags with aliases, artists and copyrights (~3.5 MB)'**
  String get tagDictionaryFullDesc;

  /// No description provided for @tagDictionaryDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get tagDictionaryDownloadAction;

  /// No description provided for @tagDictionaryRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get tagDictionaryRemoveAction;

  /// No description provided for @tagDictionaryDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get tagDictionaryDownloading;

  /// No description provided for @tagDictionaryDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String tagDictionaryDownloadFailed(String error);

  /// No description provided for @tagGlossTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag translations'**
  String get tagGlossTitle;

  /// No description provided for @tagGlossDesc.
  ///
  /// In en, this message translates to:
  /// **'Shows a translation beside each tag, in the app\'s language. Display only — never written into a caption'**
  String get tagGlossDesc;

  /// No description provided for @tagGlossModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get tagGlossModeOff;

  /// No description provided for @tagGlossModeInline.
  ///
  /// In en, this message translates to:
  /// **'Beside the tag'**
  String get tagGlossModeInline;

  /// No description provided for @tagGlossModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'On hover only'**
  String get tagGlossModeTooltip;

  /// No description provided for @tagDictionaryManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit dictionary'**
  String get tagDictionaryManageTitle;

  /// No description provided for @tagDictionaryManageDesc.
  ///
  /// In en, this message translates to:
  /// **'Translate tags, add tags danbooru does not have, import or export a glossary'**
  String get tagDictionaryManageDesc;

  /// No description provided for @tagDictionaryOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open dictionary'**
  String get tagDictionaryOpenAction;

  /// No description provided for @dictManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag dictionary'**
  String get dictManagerTitle;

  /// No description provided for @dictManagerCounts.
  ///
  /// In en, this message translates to:
  /// **'{locale} · {builtin} built in, {custom} added, {translated} translated'**
  String dictManagerCounts(
    String locale,
    int builtin,
    int custom,
    int translated,
  );

  /// No description provided for @dictGlossaryError.
  ///
  /// In en, this message translates to:
  /// **'Glossary file could not be read: {message}'**
  String dictGlossaryError(String message);

  /// No description provided for @dictSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search a tag or a translation'**
  String get dictSearchHint;

  /// No description provided for @dictGlossaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing translated yet. Search for a tag to give it a translation.'**
  String get dictGlossaryEmpty;

  /// No description provided for @dictNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching tag or translation'**
  String get dictNoResults;

  /// No description provided for @dictSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a tag on the left to translate it.'**
  String get dictSelectHint;

  /// No description provided for @dictTranslationLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get dictTranslationLabel;

  /// No description provided for @dictTranslationHint.
  ///
  /// In en, this message translates to:
  /// **'Shown beside the tag in the UI'**
  String get dictTranslationHint;

  /// No description provided for @dictNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get dictNoteLabel;

  /// No description provided for @dictNoteHint.
  ///
  /// In en, this message translates to:
  /// **'What the tag actually means, when the translation alone is ambiguous'**
  String get dictNoteHint;

  /// No description provided for @dictDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'An empty field is not saved; use the button below to delete a translation.'**
  String get dictDeleteHint;

  /// No description provided for @dictDeleteTranslationAction.
  ///
  /// In en, this message translates to:
  /// **'Delete translation'**
  String get dictDeleteTranslationAction;

  /// No description provided for @dictDeleteTranslationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the translation for \"{tag}\"? The tag goes back to showing its own name.'**
  String dictDeleteTranslationConfirm(String tag);

  /// No description provided for @dictRemoveCustomConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{tag}\" from the dictionary? It will no longer be offered in autocomplete; its translation is kept.'**
  String dictRemoveCustomConfirm(String tag);

  /// No description provided for @dictCustomBadge.
  ///
  /// In en, this message translates to:
  /// **'added'**
  String get dictCustomBadge;

  /// No description provided for @dictOrphanBadge.
  ///
  /// In en, this message translates to:
  /// **'unknown tag'**
  String get dictOrphanBadge;

  /// No description provided for @dictCategoryAndCount.
  ///
  /// In en, this message translates to:
  /// **'{category} · {count} posts'**
  String dictCategoryAndCount(String category, int count);

  /// No description provided for @dictCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get dictCategoryGeneral;

  /// No description provided for @dictCategoryArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get dictCategoryArtist;

  /// No description provided for @dictCategoryCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get dictCategoryCopyright;

  /// No description provided for @dictCategoryCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get dictCategoryCharacter;

  /// No description provided for @dictCategoryMeta.
  ///
  /// In en, this message translates to:
  /// **'Meta'**
  String get dictCategoryMeta;

  /// No description provided for @dictSourceManual.
  ///
  /// In en, this message translates to:
  /// **'Written by hand'**
  String get dictSourceManual;

  /// No description provided for @dictSourceLlm.
  ///
  /// In en, this message translates to:
  /// **'From the assistant'**
  String get dictSourceLlm;

  /// No description provided for @dictSourceDanbooru.
  ///
  /// In en, this message translates to:
  /// **'From the danbooru wiki'**
  String get dictSourceDanbooru;

  /// No description provided for @dictRemoveCustomAction.
  ///
  /// In en, this message translates to:
  /// **'Remove from dictionary'**
  String get dictRemoveCustomAction;

  /// No description provided for @dictAddTagNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get dictAddTagNameLabel;

  /// No description provided for @dictAddTagNameHint.
  ///
  /// In en, this message translates to:
  /// **'danbooru spelling, e.g. my_character_(oc)'**
  String get dictAddTagNameHint;

  /// No description provided for @dictAddTagCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get dictAddTagCategoryLabel;

  /// No description provided for @dictAddTagExists.
  ///
  /// In en, this message translates to:
  /// **'\"{tag}\" is already in the dictionary'**
  String dictAddTagExists(String tag);

  /// No description provided for @dictImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dictImportAction;

  /// No description provided for @dictExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get dictExportAction;

  /// No description provided for @dictImportSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported {written} translations, skipped {skipped}'**
  String dictImportSummary(int written, int skipped);

  /// No description provided for @dictClearAiAction.
  ///
  /// In en, this message translates to:
  /// **'Clear AI translations'**
  String get dictClearAiAction;

  /// No description provided for @dictClearAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear AI translations'**
  String get dictClearAiTitle;

  /// No description provided for @dictClearAiConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} translations produced by the assistant? Ones you wrote by hand are kept.'**
  String dictClearAiConfirm(int count);

  /// No description provided for @dictClearAiDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} translations'**
  String dictClearAiDone(int count);

  /// No description provided for @dictClearAiNone.
  ///
  /// In en, this message translates to:
  /// **'No assistant translations to clear'**
  String get dictClearAiNone;

  /// No description provided for @dictFooterHint.
  ///
  /// In en, this message translates to:
  /// **'One glossary per app language · added tags and translations stay on this machine'**
  String get dictFooterHint;

  /// No description provided for @dictOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open the tag dictionary'**
  String get dictOpenTooltip;

  /// No description provided for @dictFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dictFilterAll;

  /// No description provided for @dictFilterCustom.
  ///
  /// In en, this message translates to:
  /// **'Added {count}'**
  String dictFilterCustom(int count);

  /// No description provided for @dictUntranslated.
  ///
  /// In en, this message translates to:
  /// **'Untranslated'**
  String get dictUntranslated;

  /// No description provided for @dictNewTagAction.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get dictNewTagAction;

  /// No description provided for @dictFetchSourceName.
  ///
  /// In en, this message translates to:
  /// **'danbooru'**
  String get dictFetchSourceName;

  /// No description provided for @dictOrderAlpha.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get dictOrderAlpha;

  /// No description provided for @dictOrderUsage.
  ///
  /// In en, this message translates to:
  /// **'By usage'**
  String get dictOrderUsage;

  /// No description provided for @dictDatasetOnly.
  ///
  /// In en, this message translates to:
  /// **'This dataset only'**
  String get dictDatasetOnly;

  /// No description provided for @dictOrderRelevance.
  ///
  /// In en, this message translates to:
  /// **'By relevance'**
  String get dictOrderRelevance;

  /// No description provided for @dictResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count} results'**
  String dictResultCount(int count);

  /// No description provided for @dictCustomEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags added yet. Use \"New tag\" for characters or private tags the built-in dictionary does not have.'**
  String get dictCustomEmpty;

  /// No description provided for @dictUntranslatedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing left to translate.'**
  String get dictUntranslatedEmpty;

  /// No description provided for @dictCollectAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get dictCollectAction;

  /// No description provided for @dictCollectedCount.
  ///
  /// In en, this message translates to:
  /// **'Added {count} tags to the dictionary'**
  String dictCollectedCount(int count);

  /// No description provided for @dictMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} tags are not in the dictionary'**
  String dictMissingTitle(int count);

  /// No description provided for @dictMissingDesc.
  ///
  /// In en, this message translates to:
  /// **'They render untranslated; adding them makes them translatable and completable'**
  String get dictMissingDesc;

  /// No description provided for @dictMissingIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get dictMissingIgnore;

  /// No description provided for @dictMissingCollectAll.
  ///
  /// In en, this message translates to:
  /// **'Add all as custom'**
  String get dictMissingCollectAll;

  /// No description provided for @dictMissingUsage.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String dictMissingUsage(int count);

  /// No description provided for @dictMissingMore.
  ///
  /// In en, this message translates to:
  /// **'{count} more'**
  String dictMissingMore(int count);

  /// No description provided for @dictAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get dictAliasesLabel;

  /// No description provided for @dictAliasesHint.
  ///
  /// In en, this message translates to:
  /// **'searching these spellings finds this entry too'**
  String get dictAliasesHint;

  /// No description provided for @dictAiTranslateAction.
  ///
  /// In en, this message translates to:
  /// **'Translate with AI'**
  String get dictAiTranslateAction;

  /// No description provided for @dictAiTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get dictAiTranslating;

  /// No description provided for @dictAiTranslateFailed.
  ///
  /// In en, this message translates to:
  /// **'AI translation failed: {error}'**
  String dictAiTranslateFailed(String error);

  /// No description provided for @dictRevertAction.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get dictRevertAction;

  /// No description provided for @dictSourceBecomes.
  ///
  /// In en, this message translates to:
  /// **'saving makes it \"{source}\"'**
  String dictSourceBecomes(String source);

  /// No description provided for @dictUsageLabel.
  ///
  /// In en, this message translates to:
  /// **'Used in this dataset'**
  String get dictUsageLabel;

  /// No description provided for @dictUsageValue.
  ///
  /// In en, this message translates to:
  /// **'{count} images · {percent}%'**
  String dictUsageValue(int count, int percent);

  /// No description provided for @dictUnknownTagHint.
  ///
  /// In en, this message translates to:
  /// **'not in the dictionary'**
  String get dictUnknownTagHint;

  /// No description provided for @dictNewTagTitle.
  ///
  /// In en, this message translates to:
  /// **'New custom tag'**
  String get dictNewTagTitle;

  /// No description provided for @dictNewTagDesc.
  ///
  /// In en, this message translates to:
  /// **'For characters, styles or private tags the built-in dictionary does not have'**
  String get dictNewTagDesc;

  /// No description provided for @dictNewTagSpellingHint.
  ///
  /// In en, this message translates to:
  /// **'danbooru spelling: lower case, underscores'**
  String get dictNewTagSpellingHint;

  /// No description provided for @dictNewTagSpellingPreview.
  ///
  /// In en, this message translates to:
  /// **'stored as {name}'**
  String dictNewTagSpellingPreview(String name);

  /// No description provided for @dictNewTagAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases (optional, comma separated)'**
  String get dictNewTagAliasesLabel;

  /// No description provided for @dictNewTagAliasesHint.
  ///
  /// In en, this message translates to:
  /// **'prettysammy, sammy'**
  String get dictNewTagAliasesHint;

  /// No description provided for @dictNewTagAutocompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Offer in autocomplete'**
  String get dictNewTagAutocompleteTitle;

  /// No description provided for @dictNewTagAutocompleteDesc.
  ///
  /// In en, this message translates to:
  /// **'Suggested alongside built-in tags in tag fields'**
  String get dictNewTagAutocompleteDesc;

  /// No description provided for @dictNewTagExistsHint.
  ///
  /// In en, this message translates to:
  /// **'A tag the dictionary already has is not added twice'**
  String get dictNewTagExistsHint;

  /// No description provided for @dictNewTagSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get dictNewTagSubmit;

  /// No description provided for @dictFetchAction.
  ///
  /// In en, this message translates to:
  /// **'Fetch from danbooru'**
  String get dictFetchAction;

  /// No description provided for @dictFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching…'**
  String get dictFetching;

  /// No description provided for @dictFetchPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Tag name or danbooru URL'**
  String get dictFetchPromptLabel;

  /// No description provided for @dictFetchPromptHint.
  ///
  /// In en, this message translates to:
  /// **'long_hair, or a link you copied from danbooru'**
  String get dictFetchPromptHint;

  /// No description provided for @dictFetchPromptNote.
  ///
  /// In en, this message translates to:
  /// **'A wiki page, a post search or a tag listing URL all work. Reads danbooru\'s public API — nothing is sent anywhere.'**
  String get dictFetchPromptNote;

  /// No description provided for @dictFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Lookup failed: {error}'**
  String dictFetchFailed(String error);

  /// No description provided for @dictFetchUnknown.
  ///
  /// In en, this message translates to:
  /// **'danbooru has no tag called \"{tag}\"'**
  String dictFetchUnknown(String tag);

  /// No description provided for @dictFetchedHeader.
  ///
  /// In en, this message translates to:
  /// **'danbooru: {category} · {count} posts'**
  String dictFetchedHeader(String category, int count);

  /// No description provided for @dictFetchOtherNames.
  ///
  /// In en, this message translates to:
  /// **'Other names on danbooru'**
  String get dictFetchOtherNames;

  /// No description provided for @dictFetchUseAsTranslation.
  ///
  /// In en, this message translates to:
  /// **'Use as the translation'**
  String get dictFetchUseAsTranslation;

  /// No description provided for @dictFetchWikiLabel.
  ///
  /// In en, this message translates to:
  /// **'From the wiki'**
  String get dictFetchWikiLabel;

  /// No description provided for @dictFetchUseAsNote.
  ///
  /// In en, this message translates to:
  /// **'Use as the note'**
  String get dictFetchUseAsNote;

  /// No description provided for @dictFetchNoWiki.
  ///
  /// In en, this message translates to:
  /// **'This tag has no wiki page.'**
  String get dictFetchNoWiki;

  /// No description provided for @dictFetchAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add to the dictionary'**
  String get dictFetchAddAction;

  /// No description provided for @dictFetchPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Reads the public API only; nothing is uploaded'**
  String get dictFetchPrivacyNote;

  /// No description provided for @dictFetchLookupAction.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get dictFetchLookupAction;

  /// No description provided for @dictFetchWillWrite.
  ///
  /// In en, this message translates to:
  /// **'Will write'**
  String get dictFetchWillWrite;

  /// No description provided for @dictFetchFieldPostCount.
  ///
  /// In en, this message translates to:
  /// **'Post count'**
  String get dictFetchFieldPostCount;

  /// No description provided for @dictFetchKeepsEdits.
  ///
  /// In en, this message translates to:
  /// **'· your own translation and note are never overwritten'**
  String get dictFetchKeepsEdits;

  /// No description provided for @dictFetchAlreadyKnown.
  ///
  /// In en, this message translates to:
  /// **'The dictionary already has this tag.'**
  String get dictFetchAlreadyKnown;

  /// No description provided for @dictFetchWriteAction.
  ///
  /// In en, this message translates to:
  /// **'Write to dictionary'**
  String get dictFetchWriteAction;

  /// No description provided for @dictFetchOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Go to the tag'**
  String get dictFetchOpenAction;

  /// No description provided for @dictFetchAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to the dictionary: {tag}'**
  String dictFetchAdded(String tag);

  /// No description provided for @dictDanbooruUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update from danbooru'**
  String get dictDanbooruUpdateAction;

  /// No description provided for @dictDanbooruUpdateDone.
  ///
  /// In en, this message translates to:
  /// **'Updated {tag} from danbooru'**
  String dictDanbooruUpdateDone(String tag);

  /// No description provided for @dictDanbooruMarkedMissing.
  ///
  /// In en, this message translates to:
  /// **'danbooru has no tag called \"{tag}\" — marked, so batch updates skip it'**
  String dictDanbooruMarkedMissing(String tag);

  /// No description provided for @dictBatchAction.
  ///
  /// In en, this message translates to:
  /// **'Danbooru batch update'**
  String get dictBatchAction;

  /// No description provided for @dictBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch update from danbooru'**
  String get dictBatchTitle;

  /// No description provided for @dictBatchDesc.
  ///
  /// In en, this message translates to:
  /// **'Fetches other names and the wiki excerpt for every listed tag danbooru has not been asked about yet. Other names join the tag\'s aliases and the wiki excerpt fills an empty note — existing text is never overwritten.'**
  String get dictBatchDesc;

  /// No description provided for @dictBatchScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Covers the tags the list on the left is currently showing.'**
  String get dictBatchScopeNote;

  /// No description provided for @dictBatchPending.
  ///
  /// In en, this message translates to:
  /// **'{count} tags to fetch'**
  String dictBatchPending(int count);

  /// No description provided for @dictBatchCached.
  ///
  /// In en, this message translates to:
  /// **'{count} already have danbooru info'**
  String dictBatchCached(int count);

  /// No description provided for @dictBatchMissing.
  ///
  /// In en, this message translates to:
  /// **'{count} marked as not on danbooru — skipped'**
  String dictBatchMissing(int count);

  /// No description provided for @dictBatchNothing.
  ///
  /// In en, this message translates to:
  /// **'Every listed tag already has danbooru info.'**
  String get dictBatchNothing;

  /// No description provided for @dictBatchRateNote.
  ///
  /// In en, this message translates to:
  /// **'Tags are fetched one at a time with a short pause between requests; a long list takes a while.'**
  String get dictBatchRateNote;

  /// No description provided for @dictBatchStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get dictBatchStart;

  /// No description provided for @dictBatchStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get dictBatchStop;

  /// No description provided for @dictBatchRunning.
  ///
  /// In en, this message translates to:
  /// **'Updating {done}/{total}: {tag}'**
  String dictBatchRunning(int done, int total, String tag);

  /// No description provided for @dictBatchSummary.
  ///
  /// In en, this message translates to:
  /// **'Done: {updated} updated, {missing} not on danbooru, {failed} failed'**
  String dictBatchSummary(int updated, int missing, int failed);

  /// No description provided for @dictBatchStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped: {error}'**
  String dictBatchStopped(String error);

  /// No description provided for @dataSection.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get dataSection;

  /// No description provided for @dataExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get dataExportTitle;

  /// No description provided for @dataExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Save your AI backends, tag library and prompt presets to one file'**
  String get dataExportDesc;

  /// No description provided for @dataExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get dataExportAction;

  /// No description provided for @dataImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get dataImportTitle;

  /// No description provided for @dataImportDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore from an export file; nothing already here is deleted'**
  String get dataImportDesc;

  /// No description provided for @dataImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get dataImportAction;

  /// No description provided for @dataExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get dataExportDialogTitle;

  /// No description provided for @dataExportPick.
  ///
  /// In en, this message translates to:
  /// **'Choose what to write to the file.'**
  String get dataExportPick;

  /// No description provided for @dataExportExcludes.
  ///
  /// In en, this message translates to:
  /// **'The built-in and downloaded danbooru dictionaries are left out — the app can fetch those again.'**
  String get dataExportExcludes;

  /// No description provided for @dataExportApiKeys.
  ///
  /// In en, this message translates to:
  /// **'Include API keys'**
  String get dataExportApiKeys;

  /// No description provided for @dataExportApiKeysHint.
  ///
  /// In en, this message translates to:
  /// **'They are written as plain text. Keep the file somewhere private.'**
  String get dataExportApiKeysHint;

  /// No description provided for @dataExportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get dataExportConfirm;

  /// No description provided for @dataSectionLlm.
  ///
  /// In en, this message translates to:
  /// **'AI backends'**
  String get dataSectionLlm;

  /// No description provided for @dataSectionLlmSummary.
  ///
  /// In en, this message translates to:
  /// **'{providers} backends · {models} models'**
  String dataSectionLlmSummary(int providers, int models);

  /// No description provided for @dataSectionTagLibrary.
  ///
  /// In en, this message translates to:
  /// **'Tag library'**
  String get dataSectionTagLibrary;

  /// No description provided for @dataSectionTagLibrarySummary.
  ///
  /// In en, this message translates to:
  /// **'{tags} tags · {groups} groups · {custom} custom tags · {translations} translations · {records} danbooru records'**
  String dataSectionTagLibrarySummary(
    int tags,
    int groups,
    int custom,
    int translations,
    int records,
  );

  /// No description provided for @dataSectionPresets.
  ///
  /// In en, this message translates to:
  /// **'Prompt presets'**
  String get dataSectionPresets;

  /// No description provided for @dataSectionPresetsSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} presets'**
  String dataSectionPresetsSummary(int count);

  /// No description provided for @dataSectionMissing.
  ///
  /// In en, this message translates to:
  /// **'Not in this file'**
  String get dataSectionMissing;

  /// No description provided for @dataImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get dataImportDialogTitle;

  /// No description provided for @dataImportSource.
  ///
  /// In en, this message translates to:
  /// **'Written by version {version} on {date}'**
  String dataImportSource(String version, String date);

  /// No description provided for @dataImportNoKeys.
  ///
  /// In en, this message translates to:
  /// **'This export carries no API keys — you will have to enter them again.'**
  String get dataImportNoKeys;

  /// No description provided for @dataImportMode.
  ///
  /// In en, this message translates to:
  /// **'When something already exists'**
  String get dataImportMode;

  /// No description provided for @dataImportModeMerge.
  ///
  /// In en, this message translates to:
  /// **'Keep what is here'**
  String get dataImportModeMerge;

  /// No description provided for @dataImportModeOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Use the file\'s version'**
  String get dataImportModeOverwrite;

  /// No description provided for @dataImportModeHint.
  ///
  /// In en, this message translates to:
  /// **'Neither choice deletes anything: an import only adds or updates.'**
  String get dataImportModeHint;

  /// No description provided for @dataImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataImportConfirm;

  /// No description provided for @dataImportDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Import finished'**
  String get dataImportDoneTitle;

  /// No description provided for @dataImportNothingChanged.
  ///
  /// In en, this message translates to:
  /// **'Everything in the file was already here.'**
  String get dataImportNothingChanged;

  /// No description provided for @dataImportReportLlm.
  ///
  /// In en, this message translates to:
  /// **'AI backends: {added} added, {updated} updated, {models} models added'**
  String dataImportReportLlm(int added, int updated, int models);

  /// No description provided for @dataImportReportLibrary.
  ///
  /// In en, this message translates to:
  /// **'Tag library: {tags} tags, {groups} groups, {custom} custom tags, {translations} translations, {records} danbooru records'**
  String dataImportReportLibrary(
    int tags,
    int groups,
    int custom,
    int translations,
    int records,
  );

  /// No description provided for @dataImportReportPresets.
  ///
  /// In en, this message translates to:
  /// **'Prompt presets: {added} added, {updated} updated'**
  String dataImportReportPresets(int added, int updated);
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
