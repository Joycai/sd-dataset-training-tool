import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../l10n/app_localizations.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _captionController;
  final FocusNode _captionFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 初始化 controller，并监听 AppState 的变化
    final appState = context.read<AppState>();
    _captionController = TextEditingController(text: appState.captionExtension);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当 AppState 的 captionExtension 发生变化时（例如重置后），更新文本框内容。
    // 正在输入时（有焦点）不同步，避免覆盖用户未提交的输入。
    final appState = context.watch<AppState>();
    if (!_captionFocusNode.hasFocus &&
        _captionController.text != appState.captionExtension) {
      _captionController.text = appState.captionExtension;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  // 校验并提交扩展名：失焦或回车时才生效，避免输入中间态（如 "." 或 "txt"）
  // 被立即保存导致查找错误的 caption 文件。
  void _commitCaptionExtension() {
    final appState = context.read<AppState>();
    var value = _captionController.text.trim();
    if (value.isEmpty || value == '.') {
      // 非法输入：还原为当前设置
      _captionController.text = appState.captionExtension;
      return;
    }
    if (!value.startsWith('.')) {
      value = '.$value';
    }
    _captionController.text = value;
    appState.updateCaptionExtension(value);
  }

  // 显示重置确认对话框
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.confirm),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AppState>().resetSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // --- 语言设置项 ---
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.language),
          trailing: DropdownButton<Locale>(
            value: appState.currentLocale,
            items: const [
              DropdownMenuItem(value: Locale('en'), child: Text('English')),
              DropdownMenuItem(value: Locale('zh'), child: Text('中文')),
            ],
            onChanged: (Locale? newLocale) {
              if (newLocale != null) {
                context.read<AppState>().updateLocale(newLocale);
              }
            },
          ),
        ),
        const Divider(),

        // --- Caption Extension 设置项 ---
        ListTile(
          leading: const Icon(Icons.description),
          title: Text(l10n.captionExtension),
          trailing: SizedBox(
            width: 100,
            child: Focus(
              focusNode: _captionFocusNode,
              onFocusChange: (hasFocus) {
                if (!hasFocus) _commitCaptionExtension();
              },
              child: TextFormField(
                controller: _captionController,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onFieldSubmitted: (_) => _commitCaptionExtension(),
              ),
            ),
          ),
        ),
        const Divider(),

        // --- 重置设置按钮 ---
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.resetSettings),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
              onPressed: _showResetConfirmationDialog,
            ),
          ),
        ),
      ],
    );
  }
}
