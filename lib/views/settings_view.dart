import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../services/font_service.dart';
import '../theme/app_theme.dart';

/// Settings, grouped into cards: appearance, dataset behavior, and the
/// danger zone. Each row pairs the control with a one-line description.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _captionController.text = context.read<AppState>().captionExtension;
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  void _commitCaptionExtension() {
    final appState = context.read<AppState>();
    var value = _captionController.text.trim();
    if (value.isEmpty) {
      value = appState.captionExtension;
    } else if (!value.startsWith('.')) {
      value = '.$value';
    }
    _captionController.text = value;
    appState.updateCaptionExtension(value);
  }

  String _fontLabel(AppLocalizations l10n, AppFontChoice choice) =>
      switch (choice) {
        AppFontChoice.system => l10n.fontSystem,
        AppFontChoice.harmony => l10n.fontHarmony,
        AppFontChoice.misans => l10n.fontMiSans,
      };

  Future<void> _selectFont(AppFontChoice choice) async {
    final appState = context.read<AppState>();
    final fonts = appState.fontService;
    final l10n = AppLocalizations.of(context)!;

    // 系统字体或本次会话已注册的字体：直接切换。
    if (choice == AppFontChoice.system || fonts.isLoaded(choice)) {
      await appState.updateFontChoice(choice);
      return;
    }
    // 磁盘上已有（此前下载过但本次启动未激活）：注册即可，绝不重复提示下载。
    if (fonts.isDownloadedSync(choice)) {
      await fonts.loadIfDownloaded(choice);
      await appState.updateFontChoice(choice);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.fontDownloadConfirmTitle),
        content: Text(
          l10n.fontDownloadConfirmContent(_fontLabel(l10n, choice)),
        ),
        actions: [
          TextButton(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text(l10n.fontDownloadAction),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FontDownloadDialog(
        choice: choice,
        title: l10n.fontDownloadingTitle(_fontLabel(l10n, choice)),
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().updateFontChoice(choice);
    }
  }

  Future<void> _showResetConfirmationDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetSettingsConfirmationTitle),
        content: Text(l10n.resetSettingsConfirmationContent),
        actions: [
          TextButton(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.confirm),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AppState>().resetSettings();
      if (mounted) {
        _captionController.text = context.read<AppState>().captionExtension;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final appState = context.watch<AppState>();

    return Column(
      children: [
        // Header bar with back navigation, mirroring the workbench top bar.
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: semantic.panel,
            border: Border(bottom: BorderSide(color: semantic.line)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: l10n.editor,
                color: semantic.muted,
                onPressed: () =>
                    context.read<AppState>().updateView(MainView.editor),
              ),
              const SizedBox(width: 4),
              Text(
                l10n.settings,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    _SettingsCard(
                      title: l10n.appearanceSection,
                      children: [
                        _SettingsRow(
                          title: l10n.language,
                          description: l10n.languageDesc,
                          control: DropdownButton<Locale>(
                            value: appState.currentLocale,
                            underline: const SizedBox.shrink(),
                            borderRadius: BorderRadius.circular(7),
                            items: const [
                              DropdownMenuItem(
                                value: Locale('en'),
                                child: Text('English',
                                    style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: Locale('zh'),
                                child: Text('中文（简体）',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ],
                            onChanged: (locale) {
                              if (locale != null) {
                                appState.updateLocale(locale);
                              }
                            },
                          ),
                        ),
                        _SettingsRow(
                          title: l10n.fontTitle,
                          description: l10n.fontDesc,
                          control: DropdownButton<AppFontChoice>(
                            value: appState.fontChoice,
                            underline: const SizedBox.shrink(),
                            borderRadius: BorderRadius.circular(7),
                            items: [
                              for (final choice in AppFontChoice.values)
                                DropdownMenuItem(
                                  value: choice,
                                  child: Text(
                                    _fontLabel(l10n, choice),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                            onChanged: (choice) {
                              if (choice != null) _selectFont(choice);
                            },
                          ),
                        ),
                        _SettingsRow(
                          title: l10n.themeTitle,
                          description: l10n.themeDesc,
                          control: SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStateProperty.all(
                                  const TextStyle(fontSize: 12.5)),
                            ),
                            segments: [
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text(l10n.themeLight),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text(l10n.themeDark),
                              ),
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text(l10n.themeSystem),
                              ),
                            ],
                            selected: {appState.currentThemeMode},
                            onSelectionChanged: (selection) =>
                                appState.updateThemeMode(selection.first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsCard(
                      title: l10n.datasetSection,
                      children: [
                        _SettingsRow(
                          title: l10n.captionExtension,
                          description: l10n.captionExtensionDesc,
                          control: SizedBox(
                            width: 110,
                            child: Focus(
                              focusNode: _captionFocusNode,
                              onFocusChange: (hasFocus) {
                                if (!hasFocus) _commitCaptionExtension();
                              },
                              child: TextFormField(
                                controller: _captionController,
                                textAlign: TextAlign.center,
                                style: monoStyle(context, size: 12.5),
                                onFieldSubmitted: (_) =>
                                    _commitCaptionExtension(),
                              ),
                            ),
                          ),
                        ),
                        _SettingsRow(
                          title: l10n.includeSubdirsTitle,
                          description: l10n.includeSubdirsDesc,
                          control: Switch(
                            value: appState.includeSubdirectories,
                            onChanged: appState.updateIncludeSubdirectories,
                          ),
                        ),
                        _SettingsRow(
                          title: l10n.autoSaveTitle,
                          description: l10n.autoSaveDesc,
                          control: Switch(
                            value: appState.autoSave,
                            onChanged: appState.updateAutoSave,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsCard(
                      title: l10n.dangerZone,
                      danger: true,
                      children: [
                        _SettingsRow(
                          title: l10n.resetSettings,
                          description: l10n.resetDesc,
                          control: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withAlpha(150),
                              ),
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: _showResetConfirmationDialog,
                            child: Text(l10n.resetAction),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 模态下载进度对话框：打开即开始下载，成功 pop(true)，失败提示后 pop(false)。
class _FontDownloadDialog extends StatefulWidget {
  const _FontDownloadDialog({required this.choice, required this.title});

  final AppFontChoice choice;
  final String title;

  @override
  State<_FontDownloadDialog> createState() => _FontDownloadDialogState();
}

class _FontDownloadDialogState extends State<_FontDownloadDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final fonts = context.read<AppState>().fontService;
    try {
      await fonts.downloadAndLoad(widget.choice);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fontDownloadFailed('$e'))),
      );
      Navigator.of(context).pop(false);
    }
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final fonts = context.read<AppState>().fontService;
    final semantic = context.semantic;
    return AlertDialog(
      title: Text(widget.title),
      content: ListenableBuilder(
        listenable: fonts,
        builder: (context, _) {
          final received = fonts.receivedBytes;
          final total = fonts.totalBytes;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 首个进度包到达前显示不定长进度条。
              LinearProgressIndicator(value: fonts.progress),
              const SizedBox(height: 10),
              Text(
                total > 0
                    ? '${_mb(received)} MB / ${_mb(total)} MB'
                    : '${_mb(received)} MB',
                style: monoStyle(context, size: 12, color: semantic.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.children,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = danger
        ? Color.alphaBlend(scheme.error.withAlpha(115), semantic.line)
        : semantic.line;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: semantic.raised,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: semantic.line)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: danger ? scheme.error : semantic.muted,
              ),
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: semantic.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          control,
        ],
      ),
    );
  }
}
