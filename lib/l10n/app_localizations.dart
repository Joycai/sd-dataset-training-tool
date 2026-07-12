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
