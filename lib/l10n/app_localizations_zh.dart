// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '数据集训练工具';

  @override
  String get editor => '编辑器';

  @override
  String get settings => '设置';

  @override
  String get toggleTheme => '切换主题';

  @override
  String get editorView => '编辑器视图';

  @override
  String get settingsView => '设置视图';

  @override
  String get language => '语言';

  @override
  String get captionExtension => 'Caption 文件扩展名';

  @override
  String get resetSettings => '重置所有设置';

  @override
  String get resetSettingsConfirmationTitle => '确认重置';

  @override
  String get resetSettingsConfirmationContent => '您确定要将所有设置重置为默认值吗？此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get save => '保存';

  @override
  String get commonTags => '常用标签';

  @override
  String get import => '导入/替换';

  @override
  String get newTags => '新标签 (点击添加)';

  @override
  String get importTagsTitle => '导入/替换常用标签';

  @override
  String get importTagsContent => '在此处粘贴以逗号分隔的标签。这将会替换所有现有的常用标签。';

  @override
  String get add => '添加';

  @override
  String get delete => '删除';

  @override
  String get addTagsTitle => '添加常用标签';

  @override
  String get addTagsContent => '在此处粘贴以逗号分隔的标签，以添加到现有列表。';

  @override
  String get imageTags => '图片标签';

  @override
  String get assetsPanelTitle => '素材';

  @override
  String get searchFilenameHint => '搜索文件名';

  @override
  String get filterAll => '全部';

  @override
  String get filterUntagged => '未打标';

  @override
  String get filterTagged => '已打标';

  @override
  String columnsCount(int count) {
    return '$count 列';
  }

  @override
  String get openFolder => '打开文件夹';

  @override
  String get refresh => '刷新';

  @override
  String get noImagesFound => '还没有图片，打开一个文件夹开始。';

  @override
  String get noMatches => '没有符合当前筛选条件的图片。';

  @override
  String scanError(String error) {
    return '扫描目录失败：$error';
  }

  @override
  String get noDatasetOpen => '未打开文件夹';

  @override
  String imageCountShort(int count) {
    return '$count 张';
  }

  @override
  String get selectImageHint => '在左侧素材面板选择一张图片。';

  @override
  String get previousImage => '上一张';

  @override
  String get nextImage => '下一张';

  @override
  String get fitToWindow => '适应窗口';

  @override
  String get openInNewWindow => '在独立窗口打开';

  @override
  String get textTab => '文本';

  @override
  String get tagsTab => '标签';

  @override
  String tagCount(int count) {
    return '$count 个标签';
  }

  @override
  String savedAt(String time) {
    return '已保存 $time';
  }

  @override
  String get unsavedChanges => '未保存的更改';

  @override
  String get savingNow => '保存中';

  @override
  String get saveFailed => '保存失败';

  @override
  String get captionHint => '在这里编写 caption，标签之间用逗号分隔';

  @override
  String get addTagHint => '输入标签后按回车添加';

  @override
  String get noTagsYet => '还没有标签。';

  @override
  String get editTagTitle => '编辑标签';

  @override
  String get tagSortModeTooltip => '排序模式：直接拖动标签排序';

  @override
  String get aiInterrogateButton => 'AI 识别';

  @override
  String get aiInterrogating => '识别中…';

  @override
  String get aiParamsTitle => 'AI 识别参数';

  @override
  String get aiServerUrl => '服务地址';

  @override
  String get aiModelLabel => '模型';

  @override
  String get aiNoModels => '暂无模型，点击刷新获取';

  @override
  String get aiRefreshModels => '刷新模型列表';

  @override
  String get aiThresholdLabel => '阈值';

  @override
  String get aiUseModelDefault => '模型默认';

  @override
  String get aiThresholdDesc => '阈值越低，识别出的标签越多。';

  @override
  String get aiIgnoreTagsLabel => '忽略标签';

  @override
  String get aiIgnoreTagsDesc => '逗号分隔，这些标签不会出现在识别结果中。';

  @override
  String get aiUnderscoreToSpaces => '下划线转空格';

  @override
  String get aiEscapeParentheses => '转义括号 \\( \\)';

  @override
  String get aiConnecting => '连接中';

  @override
  String get aiConnectionOk => '服务已连接';

  @override
  String get aiConnectionFail => '无法连接';

  @override
  String get aiConnectionUnknown => '未知';

  @override
  String get aiCurrentTagsHeader => '当前标签';

  @override
  String get aiResultHeader => 'AI 识别结果';

  @override
  String aiMissingCount(int count) {
    return '$count 个 AI 未识别';
  }

  @override
  String aiNewCount(int count) {
    return '新建议 $count';
  }

  @override
  String get aiShowNewOnly => '仅新建议';

  @override
  String get aiLegendNew => '新建议（点击添加）';

  @override
  String get aiLegendMissing => 'AI 未识别';

  @override
  String get aiLegendMatched => '已匹配';

  @override
  String aiAddAllNew(int count) {
    return '添加全部新建议 ($count)';
  }

  @override
  String get aiRerun => '重新识别';

  @override
  String get aiDoneCompare => '完成';

  @override
  String get aiNoResultYet => '本图还没有识别结果。';

  @override
  String get aiFirstRunHint => '首次使用某个模型需要下载，可能较慢。';

  @override
  String get aiNoModelSelected => '未选择模型，请检查 AI 识别参数。';

  @override
  String aiFailed(String error) {
    return '识别失败：$error';
  }

  @override
  String get rightTabLibrary => '标签库';

  @override
  String get rightTabDataset => '数据集';

  @override
  String get datasetTagsTitle => '数据集标签';

  @override
  String get datasetTagsEmpty => '数据集里还没有标签。';

  @override
  String get datasetTagsHint => '绿色 = 当前图片包含，右键打开操作菜单';

  @override
  String get clearTagFilter => '清除标签过滤';

  @override
  String get menuFilterInclude => '仅显示包含此标签的图片';

  @override
  String get menuFilterExclude => '仅显示不包含此标签的图片';

  @override
  String get menuReplaceAppend => '替换 / 追加…';

  @override
  String get menuDeleteGlobal => '从所有图片中删除';

  @override
  String get deleteTagConfirmTitle => '全局删除标签';

  @override
  String deleteTagConfirmContent(int count, String tag) {
    return '从 $count 张图片中移除“$tag”？此操作可从顶栏撤销。';
  }

  @override
  String get replaceDialogTitle => '替换 / 追加';

  @override
  String get replaceModeReplace => '替换为';

  @override
  String get replaceModeBefore => '在其前插入';

  @override
  String get replaceModeAfter => '在其后插入';

  @override
  String get replaceInputHint => '逗号分隔的标签';

  @override
  String get apply => '应用';

  @override
  String filesUpdated(int count) {
    return '已更新 $count 个文件';
  }

  @override
  String get noFilesChanged => '没有需要修改的文件。';

  @override
  String filterActiveInclude(String tag) {
    return '仅含：$tag';
  }

  @override
  String filterActiveExclude(String tag) {
    return '不含：$tag';
  }

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String undoTooltip(String action) {
    return '撤销：$action';
  }

  @override
  String redoTooltip(String action) {
    return '重做：$action';
  }

  @override
  String opDeleteLabel(String tag) {
    return '删除“$tag”';
  }

  @override
  String opReplaceLabel(String tag) {
    return '替换“$tag”';
  }

  @override
  String opInsertLabel(String tag) {
    return '在“$tag”旁追加';
  }

  @override
  String get tagLibraryTitle => '常用标签库';

  @override
  String get filterTagsHint => '筛选标签';

  @override
  String get clickToApplyHint => '单击应用，再次单击移除';

  @override
  String get newTagsSection => '本图新标签';

  @override
  String get addAllToLibrary => '全部入库';

  @override
  String get legendApplied => '已应用';

  @override
  String get legendNotApplied => '未应用';

  @override
  String get legendNew => '新标签';

  @override
  String get removeFromLibrary => '从库中移除';

  @override
  String get libraryEmpty => '标签库是空的，点击加号添加标签。';

  @override
  String get newGroupTitle => '新建分组';

  @override
  String get editGroupTitle => '编辑分组';

  @override
  String get groupNameHint => '分组名称';

  @override
  String get groupColorLabel => '颜色';

  @override
  String get customColorLabel => '自定义';

  @override
  String get ungroupedSection => '未分组';

  @override
  String get groupEditModeTooltip => '分组编辑模式';

  @override
  String get groupEditHint => '单击选中，右键发送到分组';

  @override
  String groupEditSelectedHint(int count) {
    return '已选 $count · 右键发送到分组';
  }

  @override
  String sendToGroup(String name) {
    return '发送到 $name';
  }

  @override
  String get sendToNewGroup => '新建分组并发送…';

  @override
  String get removeFromGroup => '移出分组';

  @override
  String get editGroupMenu => '编辑分组…';

  @override
  String get deleteGroupMenu => '删除分组';

  @override
  String deleteGroupConfirmContent(String name) {
    return '删除分组“$name”？组内标签将回到未分组。';
  }

  @override
  String taggedProgress(int tagged, int total) {
    return '已打标 $tagged / $total';
  }

  @override
  String get autoSaveOnStatus => '自动保存已开启';

  @override
  String get autoSaveOffStatus => '自动保存已关闭';

  @override
  String get saveShortcutHint => 'Ctrl+S 立即保存';

  @override
  String get appearanceSection => '外观';

  @override
  String get datasetSection => '数据集';

  @override
  String get dangerZone => '危险区';

  @override
  String get languageDesc => '界面显示语言';

  @override
  String get themeTitle => '主题';

  @override
  String get themeDesc => '暗色更适合长时间看图';

  @override
  String get themeLight => '亮色';

  @override
  String get themeDark => '暗色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get captionExtensionDesc => '与图片同名的标注文件后缀，常见 .txt / .caption';

  @override
  String get includeSubdirsTitle => '默认包含子目录';

  @override
  String get includeSubdirsDesc => '打开目录时递归扫描其下所有子文件夹';

  @override
  String get autoSaveTitle => '自动保存';

  @override
  String get autoSaveDesc => '停止编辑 0.8 秒后自动写入 caption 文件';

  @override
  String get resetDesc => '恢复默认值并清空常用标签库，不影响任何图片与 caption 文件';

  @override
  String get resetAction => '重置';
}
