import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../l10n/app_localizations.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

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
            // 当前选中的语言
            value: appState.currentLocale,
            // 下拉菜单的选项
            items: const [
              DropdownMenuItem(
                value: Locale('en'),
                child: Text('English'),
              ),
              DropdownMenuItem(
                value: Locale('zh'),
                child: Text('中文'),
              ),
            ],
            // 当用户选择一个新语言时
            onChanged: (Locale? newLocale) {
              if (newLocale != null) {
                context.read<AppState>().updateLocale(newLocale);
              }
            },
          ),
        ),
        const Divider(),
        // 未来可以继续在这里添加其他设置项...
      ],
    );
  }
}
