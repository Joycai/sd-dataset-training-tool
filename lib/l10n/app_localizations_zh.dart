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
  String get datasetLocation => '数据集位置';

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
  String get captionTypesTitle => 'Caption 类型';

  @override
  String get captionTypesDesc =>
      '同一张图可维护多套标注文件（如 .txt 放 WD14 标签、.ntxt 放自然语言描述），在左侧图库中切换';

  @override
  String get captionTypeName => '名称';

  @override
  String get captionTypeAdd => '添加类型';

  @override
  String get captionTypeEnabled => '启用';

  @override
  String get captionTypeDefaultHint => '默认类型始终启用';

  @override
  String get captionTypeDuplicate => '该扩展名已被其他 Caption 类型使用';

  @override
  String get captionTypeInvalid => '不是可用的标注文件扩展名';

  @override
  String get captionTypePickerTooltip =>
      '切换 Caption 类型。编辑器、批量改标与 AI 助手都将读写该类型的标注文件。';

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
  String get searchFilenameHint => '搜索文件名';

  @override
  String get subdirAll => '全部子目录';

  @override
  String get subdirRoot => '根目录';

  @override
  String get subdirPickerTooltip => '切换子目录。所选目录同时决定标签统计、批量改标与 AI 助手的作用范围。';

  @override
  String subdirScopeNotice(String name) {
    return '作用范围：$name';
  }

  @override
  String get subdirScopeClearTooltip => '恢复为整个数据集';

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
  String get thumbFitTooltip => '缩略图完整显示整张图';

  @override
  String get thumbFillTooltip => '缩略图裁切填满格子';

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
  String tagCountShort(int count) {
    return '$count 标签';
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
  String get zoomIn => '放大';

  @override
  String get zoomOut => '缩小';

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
  String get tagAnchorHolderTooltip => '设为插入锚点：新标签将插入到该标签之后（[ / ] 移动，再次点击取消）';

  @override
  String anchorStatusLabel(String tag) {
    return '插入锚：$tag';
  }

  @override
  String get anchorClearTooltip => '新标签插入到该标签之后；点击清除锚点（恢复末尾追加）';

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
  String get aiModelGroupTag => '标签模型 · Danbooru 标签风';

  @override
  String get aiModelGroupCaption => '自然语言描述';

  @override
  String aiModelLegacyGroup(Object count) {
    return '旧版模型 ($count)';
  }

  @override
  String get aiModelFilterHint => '筛选模型…';

  @override
  String get aiModelFilterNoMatch => '没有匹配的模型';

  @override
  String get aiBadgeRecommended => '推荐';

  @override
  String get aiBadgeUncensored => '无审查';

  @override
  String get aiVramFootnote => '显存为估算值，黄色表示需求较高。';

  @override
  String get aiThresholdCaptionNote => '当前模型输出自然语言描述，阈值不生效。';

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
  String get aiExitCompare => '退出对比';

  @override
  String compareModeCapsule(int count) {
    return '对比模式 · $count 张有结果';
  }

  @override
  String get compareModeHint => '逐个接受 / 拒绝 AI 结果';

  @override
  String get compareModeExitGlobal => '全局退出对比';

  @override
  String compareBadgePending(int count) {
    return '待审 $count';
  }

  @override
  String get compareBadgeReviewed => '已审';

  @override
  String get aiExitCompareTooltip => '退出对比模式（对所有图片生效）';

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
  String get batchTagButton => '批量打标';

  @override
  String get batchTagTitle => '批量 AI 打标';

  @override
  String get batchTagParamsHint => '阈值、忽略标签与格式化沿用 AI 打标参数。';

  @override
  String get batchTagOpenParams => 'AI 参数…';

  @override
  String get batchTagModeLabel => '模式';

  @override
  String get batchTagModeAppend => '追加模式';

  @override
  String get batchTagModeOverwrite => '覆盖模式';

  @override
  String get batchTagModeRecognize => '仅识别';

  @override
  String get batchTagModeRecognizeDesc =>
      '只识别并缓存结果，不修改 caption 文件；完成后进入对比模式，可逐张审阅采纳建议。';

  @override
  String get batchTagModeAppendDesc => '把新识别出的标签追加到每张图已有标签之后，不会重复添加。';

  @override
  String get batchTagModeOverwriteDesc => '用 AI 识别结果覆盖每张图的已有标签，可在下方配置要保留的标签。';

  @override
  String get batchTagPreservedLabel => '保留标签';

  @override
  String get batchTagPreservedDesc => '逗号分隔。覆盖时这些已有标签会被保留。';

  @override
  String get batchTagKeepFirstN => '保留前 N 个已有标签';

  @override
  String get batchTagBlacklistLabel => '黑名单';

  @override
  String get batchTagBlacklistDesc => '逗号分隔。这些标签不会被追加。';

  @override
  String batchTagScopeFiltered(Object count) {
    return '仅处理当前筛选的 $count 张';
  }

  @override
  String batchTagTargetCount(Object count) {
    return '将逐张处理 $count 张图片。';
  }

  @override
  String get batchTagStart => '开始';

  @override
  String batchTagRunning(Object completed, Object total) {
    return '批量打标中 $completed/$total';
  }

  @override
  String batchTagProgressCounts(Object changed, Object failed) {
    return '已修改 $changed · 失败 $failed';
  }

  @override
  String get batchTagHide => '后台运行';

  @override
  String get batchTagCancel => '取消任务';

  @override
  String get batchTagCancelling => '正在取消…';

  @override
  String get batchTagDoneTitle => '批量打标完成';

  @override
  String batchTagDoneSummary(Object completed, Object changed, Object failed) {
    return '共处理 $completed 张：修改 $changed 张，失败 $failed 张。';
  }

  @override
  String batchTagRecognizeDoneSummary(
    Object completed,
    Object changed,
    Object failed,
  ) {
    return '共处理 $completed 张：识别 $changed 张，失败 $failed 张。';
  }

  @override
  String get batchTagRecognizeDoneHint => '已进入对比模式：切换图片即可逐张审阅 AI 建议。';

  @override
  String get batchTagUndoHint => '可通过顶栏的撤销按钮回退本次修改。';

  @override
  String get batchTagOperationLabel => '批量 AI 打标';

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
  String get addTagsGlobalTooltip => '为所有图片添加标签…';

  @override
  String get addTagsGlobalTitle => '为所有图片添加标签';

  @override
  String get addTagsPositionLabel => '插入位置';

  @override
  String get addTagsPosHead => '最前';

  @override
  String get addTagsPosTail => '最后';

  @override
  String get addTagsPosIndex => '指定位置';

  @override
  String get addTagsIndexHint => '1 为最前';

  @override
  String addTagsGlobalTargetCount(int count) {
    return '将为 $count 张图片添加标签；图片已有的标签会自动跳过。';
  }

  @override
  String opAddGlobalLabel(String tags) {
    return '添加“$tags”';
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
  String undoFailedRetryHint(int count) {
    return '$count 个文件写入失败——该操作仍留在栈中，再撤销一次可重试这些文件';
  }

  @override
  String filesFailed(int count) {
    return '$count 个文件写入失败';
  }

  @override
  String get filterPanelTitle => '画廊过滤';

  @override
  String filterStatus(int shown, int total) {
    return '过滤中 · 匹配 $shown / $total';
  }

  @override
  String filterMatches(int shown, int total) {
    return '匹配 $shown / $total';
  }

  @override
  String get filterOpAnd => '且';

  @override
  String get filterOpOr => '或';

  @override
  String get filterToggleOpTooltip => '切换整组 且/或';

  @override
  String get filterToggleRoleTooltip => '切换 包含/不含';

  @override
  String get filterRemoveConditionTooltip => '移除条件';

  @override
  String get filterAddTooltip => '添加条件 / 子分组';

  @override
  String get filterAddCondition => '添加条件…';

  @override
  String get filterAddSubgroup => '添加子分组';

  @override
  String get filterDissolveGroupTooltip => '解散分组（子节点上提）';

  @override
  String get filterPickerTitle => '添加过滤条件';

  @override
  String get filterRoleInclude => '包含';

  @override
  String get filterRoleExclude => '不含';

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
  String get moreActionsTooltip => '更多操作';

  @override
  String get importFromFile => '从文件导入…';

  @override
  String get exportLibraryMenu => '导出标签（含分组）…';

  @override
  String get exportGroupsMenu => '仅导出分组…';

  @override
  String get clearLibrary => '清空标签库';

  @override
  String clearLibraryConfirmContent(int count) {
    return '移除全部 $count 个标签？分组将保留。';
  }

  @override
  String importSummary(int tags, int groups) {
    return '已导入 $tags 个标签，新建 $groups 个分组';
  }

  @override
  String importFailedMsg(String error) {
    return '导入失败：$error';
  }

  @override
  String exportedTo(String path) {
    return '已导出：$path';
  }

  @override
  String exportFailedMsg(String error) {
    return '导出失败：$error';
  }

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
  String get changeGroupColorTooltip => '修改分组颜色';

  @override
  String get moveGroupUpTooltip => '上移分组';

  @override
  String get moveGroupDownTooltip => '下移分组';

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
  String get shortcutHints => 'Ctrl+S 保存 · Ctrl+E AI 识别 · Ctrl+Z 撤销';

  @override
  String get aiServiceConnected => 'AI 服务已连接';

  @override
  String get aiServiceOffline => 'AI 服务未连接';

  @override
  String get navBrowse => '浏览';

  @override
  String get toggleNavigator => '显示 / 隐藏文件导航器';

  @override
  String get toggleInspector => '显示 / 隐藏检查器';

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
  String get fontTitle => '界面字体';

  @override
  String get fontDesc => '界面显示字体，鸿蒙与小米字体首次使用需下载';

  @override
  String get fontSystem => '系统字体';

  @override
  String get fontHarmony => '鸿蒙字体';

  @override
  String get fontMiSans => '小米字体';

  @override
  String get fontDownloadConfirmTitle => '下载字体';

  @override
  String fontDownloadConfirmContent(String font) {
    return '首次使用$font需要下载官方字体包到应用数据目录，仅需一次。现在下载？';
  }

  @override
  String get fontDownloadAction => '下载';

  @override
  String fontDownloadingTitle(String font) {
    return '正在下载$font…';
  }

  @override
  String fontDownloadFailed(String error) {
    return '字体下载失败：$error';
  }

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

  @override
  String get accentTitle => '主题颜色';

  @override
  String get accentDesc => '主题基色，界面各处的底色、描线与高亮均由它派生';

  @override
  String get accentTeal => '青色';

  @override
  String get accentBlue => '蓝色';

  @override
  String get accentIndigo => '靛蓝';

  @override
  String get accentViolet => '紫色';

  @override
  String get accentRose => '玫红';

  @override
  String get accentGreen => '绿色';

  @override
  String get aboutSection => '关于';

  @override
  String get versionTitle => '版本';

  @override
  String get versionDesc => '当前应用版本';

  @override
  String get licenseTitle => '开源许可';

  @override
  String get sourceCodeTitle => '源代码';

  @override
  String get close => '关闭';

  @override
  String get agentPanelTitle => 'AI 助手';

  @override
  String get agentMinimize => '收起面板';

  @override
  String get agentExpand => '展开面板';

  @override
  String get agentNewSession => '新会话';

  @override
  String get agentStop => '停止';

  @override
  String get agentSend => '发送';

  @override
  String get agentInputHint => '向助手提问，或下达整理数据集的指令…';

  @override
  String get agentNoProfileHint => '尚未配置 LLM 后端。请先到设置中添加一个后端，再使用助手。';

  @override
  String get agentOpenSettings => '打开设置';

  @override
  String get agentRunning => '思考中…';

  @override
  String agentTokensUsed(int count) {
    return '本会话已用 $count tokens';
  }

  @override
  String get agentExpandInput => '放大输入框';

  @override
  String get agentComposerTitle => '编辑消息';

  @override
  String get agentQuestionTitle => '助手向你提问';

  @override
  String get agentQuestionCustomHint => '输入自定义回答…';

  @override
  String get agentQuestionDismiss => '不回答';

  @override
  String get agentStoppedNotice => '已停止。';

  @override
  String get agentSessionResetNotice => '数据集已切换，会话已重置。';

  @override
  String get agentSwitchProfile => '切换后端';

  @override
  String agentProfileSwitchedNotice(String name) {
    return '已切换到「$name」，下一条消息将开启新会话，不带上面的上下文。';
  }

  @override
  String agentErrorNotice(String message) {
    return '出错：$message';
  }

  @override
  String get agentConfirmTitle => '助手请求修改 caption';

  @override
  String get agentConfirmAllow => '允许';

  @override
  String get agentConfirmAllowAll => '本会话全部允许';

  @override
  String get agentConfirmReject => '拒绝';

  @override
  String get agentTokenCapTitle => '会话用量上限';

  @override
  String get agentTokenCapDesc =>
      '单个会话累计用掉这么多 token 后停止。每轮都会重发整段历史，批量任务消耗很快——可以调高，或用完后新开会话。对下一个会话生效。';

  @override
  String get agentTokenCapUnlimited => '不限';

  @override
  String get agentTokenCapNotice => '本会话已用完 token 额度。新开一个会话继续，或到设置里调高上限。';

  @override
  String agentTokensUsedOfCap(int used, int cap) {
    return '本会话已用 $used / $cap tokens';
  }

  @override
  String get agentConfirmWritesTitle => '写操作需确认';

  @override
  String get agentConfirmWritesDesc => '助手修改 caption 文件前先征求确认；无论开关与否，所有改动都可撤销';

  @override
  String get promptPresetsTitle => '预置提示词';

  @override
  String get promptPresetsDesc => '保存常用的提示词，在助手输入框一键插入';

  @override
  String get promptPresetsEmpty => '还没有预置提示词';

  @override
  String get promptPresetsManage => '管理预置提示词…';

  @override
  String get promptPresetAdd => '添加提示词';

  @override
  String get promptPresetNewName => '新提示词';

  @override
  String get promptPresetUntitled => '未命名';

  @override
  String get promptPresetName => '名称';

  @override
  String get promptPresetContent => '提示词内容';

  @override
  String get promptPresetContentHint => '会被插入到助手输入框的文本…';

  @override
  String get promptPresetSelectHint => '在左侧选择一个提示词，或新增一个。';

  @override
  String get promptPresetMoveUp => '上移';

  @override
  String get promptPresetMoveDown => '下移';

  @override
  String get promptPresetDeleteConfirmTitle => '删除提示词';

  @override
  String promptPresetDeleteConfirmContent(String name) {
    return '确定删除“$name”吗？此操作无法撤销。';
  }

  @override
  String get batchTagModeSheet => '标准样本';

  @override
  String get batchTagModeSheetDesc =>
      '按保存的标准样本规则重建每张图的 caption：触发词和固定特征恒定写入，服装只在打标器看见时才写，表情/背景/姿势/景别沿用打标器结果。';

  @override
  String get batchTagRulesLabel => '规则集';

  @override
  String get batchTagRulesHint => '选择一个规则集';

  @override
  String get batchTagRulesUnnamed => '未命名规则集';

  @override
  String get batchTagRulesEmpty => '还没有规则集。先在助手里跑「按标准样本打标」技能，本模式应用的就是它产出的规则。';

  @override
  String batchTagRulesSummary(int identity, int garments, int conflicts) {
    return '$identity 项固定特征 · $garments 件服装 · $conflicts 个恒定删除';
  }

  @override
  String get batchTagEvidenceThreshold => '服装证据阈值';

  @override
  String get batchTagEvidenceThresholdDesc =>
      '刻意低于打标器主阈值：标准样本已经说了角色穿着这些，所以一次微弱的识别更可能是真看见了而不是幻觉。调到主阈值即可关闭这项宽容。';

  @override
  String get batchTagSheetOverwriteWarning =>
      'caption 是重建而非合并，原有标签会被替换。一次撤销可回退整批。';

  @override
  String get mergeRulesApplyHint => '要把规则应用到整个数据集，打开批量打标并选择「标准样本」模式。';

  @override
  String get agentSkillsSection => '内置技能';

  @override
  String get characterSheetSkill => '按标准样本打标…';

  @override
  String get characterSheetTitle => '按标准样本打标';

  @override
  String get characterSheetIntro =>
      '助手会用打标器抽样跑一遍数据集，算出你给的固定标签该怎么和打标器的结果合并，产出一份合并规则供你审阅。这一步不会写入任何 caption。';

  @override
  String get characterSheetName => '规则集名称';

  @override
  String get characterSheetNameHint => '比如角色名';

  @override
  String get characterSheetTrigger => '触发词';

  @override
  String get characterSheetTriggerHint => '会作为每张图 caption 的第一个标签';

  @override
  String get characterSheetIdentity => '固定特征';

  @override
  String get characterSheetIdentityHint => '发色、发型、胸部、瞳色…… 每张图都写';

  @override
  String get characterSheetGarments => '服装';

  @override
  String get characterSheetGarmentsHint => '裙子、手套、鞋靴、配饰…… 只在打标器看见时才写';

  @override
  String get characterSheetExtra => '额外要求（可选）';

  @override
  String get characterSheetExtraHint => '留空则完全按打标器的结果来';

  @override
  String get characterSheetSampleSize => '采样张数';

  @override
  String get characterSheetSampleSizeSuffix => '张';

  @override
  String get characterSheetStart => '开始';

  @override
  String get characterSheetTagsHelp => '一行一个，或用逗号分隔。';

  @override
  String get characterSheetSummaryTitle => '按标准样本打标（规划阶段）';

  @override
  String characterSheetSummarySample(int count) {
    return '采样 $count 张';
  }

  @override
  String get mergeRulesTitle => '合并规则';

  @override
  String mergeRulesSampled(int count) {
    return '基于 $count 张采样';
  }

  @override
  String get mergeRulesTrigger => '触发词';

  @override
  String get mergeRulesIdentity => '恒定写入';

  @override
  String get mergeRulesConflict => '恒定删除';

  @override
  String get mergeRulesGarments => '服装（由打标器结果决定是否写入）';

  @override
  String get mergeRulesPassthrough => '沿用打标器结果';

  @override
  String get mergeRulesNotes => '备注';

  @override
  String get mergeRulesNeverWritten => '采样中没有依据，不会写入';

  @override
  String mergeRulesEvidence(String tags) {
    return '当打标器给出：$tags';
  }

  @override
  String get llmSection => 'AI 助手（LLM）';

  @override
  String get llmActiveProfile => '使用的后端';

  @override
  String get llmActiveProfileDesc => '助手当前对话所使用的 LLM 后端';

  @override
  String get llmNoProfiles => '未配置';

  @override
  String get llmManageProfiles => '后端配置';

  @override
  String get llmManageProfilesDesc => '添加、编辑、测试和删除 LLM 后端配置';

  @override
  String get llmManageAction => '管理';

  @override
  String get llmProfilesTitle => 'LLM 后端';

  @override
  String get llmProviderLabel => 'PROVIDER';

  @override
  String get llmAddProvider => '添加 Provider';

  @override
  String get llmAddModel => '添加模型';

  @override
  String get llmDeleteModel => '删除模型';

  @override
  String get llmEditProvider => '编辑';

  @override
  String get llmDisplayName => '显示名称';

  @override
  String get llmVisionBadge => '视觉';

  @override
  String llmInheritsFromProvider(String name) {
    return '地址与 Key 由 Provider「$name」提供。';
  }

  @override
  String get llmPricingTitle => '价格（每 Mtoken）';

  @override
  String get llmPricingNote => '仅用于用量统计，不影响请求。';

  @override
  String get llmPriceInput => '输入';

  @override
  String get llmPriceOutput => '输出';

  @override
  String get llmPriceCacheRead => '缓存读';

  @override
  String get llmPriceCacheWrite => '缓存写';

  @override
  String get llmNewProfileName => '新后端';

  @override
  String get llmSelectProfileHint => '在左侧选择一个后端，或新增一个。';

  @override
  String get llmProfileName => '名称';

  @override
  String get llmPreset => '预设';

  @override
  String get llmKindOpenAi => 'OpenAI 兼容';

  @override
  String get llmKindAnthropic => 'Anthropic';

  @override
  String get llmBaseUrl => 'Base URL';

  @override
  String get llmApiKey => 'API Key';

  @override
  String get llmApiKeyPlaintextNote => '以明文保存在本地设置中。';

  @override
  String get llmModel => '模型';

  @override
  String get llmContextWindow => '上下文窗口';

  @override
  String get llmMaxOutput => '最大输出';

  @override
  String get llmTemperature => '温度';

  @override
  String get llmSupportsVision => '视觉（多模态）';

  @override
  String get llmSupportsVisionDesc => '模型支持读图时开启；后续版本将解锁看图工具';

  @override
  String get llmFetchModels => '获取模型列表';

  @override
  String get llmNoModelsFound => '服务器未返回任何模型';

  @override
  String get llmTestConnection => '测试连接';

  @override
  String llmTestOk(int ms) {
    return '连接成功（$ms ms）';
  }

  @override
  String llmTestFailed(String error) {
    return '失败：$error';
  }

  @override
  String get llmDeleteConfirmTitle => '删除后端';

  @override
  String llmDeleteConfirmContent(String name) {
    return '确定删除“$name”吗？此操作无法撤销。';
  }

  @override
  String get tagWikiAction => 'Danbooru Wiki';

  @override
  String get tagPostsAction => 'Danbooru 示例图';

  @override
  String get tagWikiTooltip => '打开 Danbooru wiki（F1）';

  @override
  String get tagNotInDictionary => '词典中未收录';

  @override
  String tagPostCount(int count) {
    return 'Danbooru 上有 $count 张图';
  }

  @override
  String tagSuggestionAlias(String alias) {
    return '别名：$alias';
  }

  @override
  String tagSuggestionLocalUsed(int count) {
    return '本地标签 · 数据集中 $count 张图在用';
  }

  @override
  String get tagSuggestionLocalLibrary => '本地标签 · 来自标签库';

  @override
  String tagNotInDictionaryUsed(int count) {
    return '词典中未收录 · 数据集中 $count 张图在用';
  }

  @override
  String get tagDictionaryTitle => '标签词典';

  @override
  String get tagDictionaryDesc => '在标注编辑器里输入标签时提供 Danbooru 标签建议';

  @override
  String get tagDictionaryStatusLoading => '加载中…';

  @override
  String tagDictionaryStatusBundled(int count) {
    return '内置 · $count 条';
  }

  @override
  String tagDictionaryStatusFull(int count) {
    return '完整 · $count 条';
  }

  @override
  String get tagDictionaryFullTitle => '完整 Danbooru 词典';

  @override
  String get tagDictionaryFullDesc => '下载按热度排序的前 10 万条标签，含别名、画师与作品分类（约 3.5 MB）';

  @override
  String get tagDictionaryDownloadAction => '下载';

  @override
  String get tagDictionaryRemoveAction => '删除';

  @override
  String get tagDictionaryDownloading => '下载中…';

  @override
  String tagDictionaryDownloadFailed(String error) {
    return '下载失败：$error';
  }
}
