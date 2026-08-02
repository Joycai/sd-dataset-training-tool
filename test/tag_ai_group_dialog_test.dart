import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/tag_ai_group.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_ai_group_dialog.dart';

/// Pumps a column of proposal rows at a fixed width.
Widget _harness(List<(String tag, String? gloss, String group)> rows) =>
    MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (tag, gloss, group) in rows)
                  AiGroupSuggestionRow(
                    key: ValueKey(tag),
                    suggestion: TagGroupSuggestion(tag: tag, group: group),
                    gloss: gloss,
                    isNewGroup: false,
                    newBadge: 'new',
                    acceptTooltip: 'ok',
                    rejectTooltip: 'no',
                    enabled: true,
                    onAccept: () {},
                    onReject: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the accept/reject pair is right-aligned across rows', (
    tester,
  ) async {
    // The regression: the buttons used to follow a `Spacer()` that shared the
    // free space with three sibling `Flexible`s, so they landed at a position
    // that moved with the tag's length — visibly ragged down the list.
    await tester.pumpWidget(
      _harness([
        ('a', null, 'G'),
        ('shirai_hinako', '白井日菜子', '角色'),
        ('blue_sailor_collar', '蓝色水手领', '服装'),
        ('sketch', '草图', '画面构成'),
      ]),
    );
    await tester.pumpAndSettle();

    final rights = tester
        .widgetList<Icon>(find.byIcon(Icons.check))
        .map((icon) => tester.getTopRight(find.byWidget(icon)).dx)
        .toList();

    expect(rights, hasLength(4));
    for (final right in rights) {
      expect(right, closeTo(rights.first, 0.5));
    }
  });

  testWidgets('a very long tag does not push the buttons off the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        ('short', null, 'G'),
        (
          'a_very_long_tag_name_that_would_otherwise_overflow_the_row' * 2,
          '同样很长的一段译文用来占满整行宽度',
          '一个名字也很长的分组',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final rights = tester
        .widgetList<Icon>(find.byIcon(Icons.close))
        .map((icon) => tester.getTopRight(find.byWidget(icon)).dx)
        .toList();
    expect(rights.last, closeTo(rights.first, 0.5));
  });
}
