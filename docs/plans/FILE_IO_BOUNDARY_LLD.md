# 文件读写收口到 `services/` —— 详细设计（LLD）

> 范围：把 `state/`、`agent/`、`views/` 里直接读写文件的代码收进 `services/`，并加一条检查规则防止回退。
> **不改任何运行时行为**：每处替换前后的返回值、异常类型与错误文案保持一致（逐处对照见 §4.4）。
> 基线：`main` @ `2e594c6`（下文行号均指该提交）。长期约定见 [../ARCHITECTURE.md](../ARCHITECTURE.md)。

---

## 1. 背景

按 Flutter 官方架构指南（UI 层 View + ViewModel，数据层 Service 包装外部系统），本项目的目录已经能一一对应：

| 指南中的层 | 本项目 |
| --- | --- |
| Service（外部 API、本地存储、平台插件） | `services/`、`services/llm/` |
| Domain Model | `models/` |
| ViewModel（`ChangeNotifier`） | `state/` |
| View、共享组件、主题 | `views/`、`widgets/`、`theme/` |

所以**不改目录结构**（理由见 §5）。差距在于职责：指南要求 ViewModel 与 View 不直接做 I/O，而本项目有 59 处文件读写散落在 `services/` 之外。

## 2. 现状问题

| # | 问题 | 位置（`2e594c6`） |
| --- | --- | --- |
| P1 | 4 个状态类直接读写标注文件（exists → readAsString / writeAsString），同一段逻辑写了 8 遍 | `state/dataset_state.dart:359-377`（遍历目录并读标注）；`state/editor_session.dart:130-134`（读标注、取图片大小）、`:347`（保存）；`state/tag_ops.dart:378-389`、`:489-520`、`:573`；`state/batch_tag_state.dart:487-508`、`:527-559` |
| P2 | agent 工具直接读写标注与图片，共 32 处 | `agent/caption_variant_tools.dart`（188、377-402、756-841、1225-1341、1464、1571、1632）；`agent/json_caption_tools.dart`（129-137、769-819、993-1058）；`agent/caption_edit_tools.dart:400-446`；`agent/media_tools.dart:213`（读图片字节） |
| P3 | "图片路径 → 标注路径"的公式 `'${p.withoutExtension(imagePath)}$ext'` 有 4 份 | `state/dataset_state.dart:187`、`:371`；`state/editor_session.dart:124`；`agent/caption_variant_tools.dart:1619` |
| P4 | 3 个界面各自弹文件框、读写 JSON；弹框参数（`FileType.custom`、`['json']`）和异常处理重复 3 遍 | `views/panels/tag_library_panel.dart:636-676`；`views/dialogs/tag_dictionary_dialog.dart:900-938`；`views/dialogs/data_transfer_dialog.dart:32-47`、`:57-71` |
| P5 | 界面在 UI 线程上做同步文件系统调用 | `views/workbench/workbench_view.dart:137`（`Directory(directory).existsSync()`） |
| P6 | 没有任何检查阻止新代码在 `services/` 以外读写文件 | `tool/check_layers.dart` 只检查 import |

后果：

- **测试只能用真实临时目录**。写入失败、读取失败这类分支很难构造，现有测试基本没覆盖。
- **修改容易漏改**。比如以后要给标注写入加原子写（先写临时文件再改名），要改 `state/` 的 20 处与 `agent/` 的 32 处。

## 3. 目标与非目标

**目标**

1. 数据集文件（图片与标注）的所有读写只经过 `services/dataset_store.dart`。
2. JSON 导入导出的"弹框 + 读写"只经过 `services/json_file_dialogs.dart`。
3. 标注路径公式只剩一份。
4. `tool/check_layers.dart` 新增规则：除 `services/` 外，任何文件不得直接调用文件读写 API。
5. 现有 945 个测试不改一行即全部通过。

**非目标**

- 不引入 Repository 层、Use Case 层、`data/`/`domain/`/`ui/` 目录（§5）。
- 不改 `DatasetState` 对外暴露的 `List<File>`。`File` 在本项目里主要当路径句柄用（`Image.file`、`FileSaver`），只持有 `File` 对象不算 I/O。
- 不处理以下两类问题，见 §9：界面里临时 `new` 出来的 `SettingsService()`；`image_preview_window.dart` 里的 `FileSaver` 调用。
- 不改变任何读写的时机、顺序与并发语义（包括 exists 与 read 之间原有的竞态窗口）。

## 4. 设计

### 4.1 `models/caption_type.dart`：标注路径公式（P3）

```dart
/// The caption file that sits beside [imagePath] for a caption type whose
/// file extension is [captionExtension] (with its leading dot).
String captionPathOf(String imagePath, String captionExtension) =>
    '${p.withoutExtension(imagePath)}$captionExtension';
```

放在 `models/` 而不是 `services/`：这是纯字符串计算，`state/`、`agent/`、`services/` 都要用，而 `models/` 是它们共同允许依赖的最低层。`models/caption_type.dart` 需要新增 `package:path` 的 import，`path` 是纯函数包，不违反 `models/` "无 I/O、无 Flutter" 的约定。

原来的 4 处改为调用它：

- `DatasetState.captionPathFor(imagePath)` 保留，改为 `captionPathOf(imagePath, _captionExtension)`。
- `agent/caption_variant_tools.dart` 的公开函数 `captionVariantPath(imagePath, type)` 保留（agent 内有 20 多处调用），改为 `captionPathOf(imagePath, type.extension)`。
- `DatasetState.scan`、`EditorSession.load` 内联的两处直接改用 `captionPathOf`。

### 4.2 `services/dataset_store.dart`（新增，P1、P2、P5）

```dart
/// One image found by [DatasetStore.scan], with the raw text of its caption
/// file: '' when the caption is missing or cannot be read.
typedef ScannedImage = ({File image, String caption});

/// The dataset on disk: image files and the caption files beside them.
///
/// Every read and write of a dataset file goes through here, so state
/// classes and agent tools hold no file I/O of their own, and a test can
/// swap in a fake with `implements DatasetStore`. Stateless: one const
/// instance can be shared freely.
class DatasetStore {
  const DatasetStore();

  /// Supported images under [root] (symlinks are not followed), unordered,
  /// each with its caption text. A caption that exists but cannot be read
  /// counts as '' — an unreadable caption must not abort a scan. A listing
  /// failure surfaces as a stream error after the images found so far.
  Stream<ScannedImage> scan(
    String root, {
    required bool recursive,
    required String captionExtension,
  });

  /// The caption file's text, or null when the file does not exist.
  /// Throws [FileSystemException] when it exists but cannot be read
  /// (including invalid UTF-8).
  Future<String?> readCaption(String captionPath);

  /// Creates or overwrites the caption file. Throws [FileSystemException].
  Future<void> writeCaption(String captionPath, String text);

  /// Whether [path] exists and is larger than zero bytes.
  Future<bool> isNonEmptyFile(String path);

  /// Size of the image in bytes. Throws [FileSystemException].
  Future<int> imageLength(String imagePath);

  /// The image's raw bytes. Throws [FileSystemException].
  Future<Uint8List> readImageBytes(String imagePath);

  /// Whether [path] is an existing directory.
  Future<bool> directoryExists(String path);
}
```

设计要点：

- **只做 I/O，不做解析**。`scan` 返回标注原文，按 `CaptionFormat` 解析仍留在 `DatasetState`。这样 service 不需要知道任何标注语法，依赖只有 `models/image_formats.dart`，用于筛选支持的图片扩展名。
- **`readCaption` 用 `null` 表示"不存在"**。调用方在"缺失时跳过"和"缺失按空串处理"两种语义之间选，原来的 `exists()` 分支就能原样保留，比如 `tag_ops` 的 `createMissing`、`json_caption_tools` 的 `missingFile++`。
- **异常类型不变**：底层仍是 `File.readAsString()`/`writeAsString()`，抛出的 `FileSystemException` 及其 `toString()` 与原来一致，所以各处拼进错误文案的 `$e` 不变。编码错误同样是 `FileSystemException`（已验证：`Failed to decode data using encoding 'utf-8'`）。
- **用具体类，不定义抽象接口**。项目里只有一种实现。Dart 的每个类本身就能当接口用，测试用 `implements DatasetStore` 即可替换，写法与现有的 `_FakeLlm implements LlmClient` 相同。

### 4.3 注入方式

`DatasetState` 持有 store，并把它作为只读字段公开。其他需要读写的一方都已经持有 `DatasetState`，直接从它取：

| 类 / 模块 | 如何拿到 store |
| --- | --- |
| `DatasetState` | 构造参数 `DatasetState({DatasetStore store = const DatasetStore()})`，公开为 `final DatasetStore store` |
| `EditorSession` | 构造参数 `EditorSession({DatasetStore store = const DatasetStore()})`，它不持有 `DatasetState` |
| `TagOps`、`BatchTagState` | `dataset.store`，构造函数不变 |
| `agent/` 各工具 | `dataset.store`（工具依赖里已有 `DatasetState`） |
| `WorkbenchView` | 创建时把 `_dataset.store` 传给 `EditorSession`；启动时的目录存在检查改为 `_dataset.store.directoryExists` |

这样选的理由：

- **参数都带默认值**，测试里 81 处 `DatasetState()`、`EditorSession()`、`TagOps(dataset: …)` 一处都不用改（目标 5）。
- **注入点只有两个**。每个数据集只有一个 store，`TagOps`、`BatchTagState` 和 agent 工具读写的一定是同一个数据集，不会出现"状态读 A、工具写 B"的组合。
- 项目已有同样写法：`AiTaggerState(settings, {AiTaggerService? service})`、`BatchTagState({…, AiTaggerService? service})`。

### 4.4 逐处替换与语义对照

`s` 指 `dataset.store`，在 `EditorSession` 内指 `_store`。

| 位置 | 原代码 | 替换为 | 需保持的语义 |
| --- | --- | --- | --- |
| `dataset_state.dart:359-387` | `Directory.list` + 逐个读标注 | `await for (final img in s.scan(…))`，外层 `try` 不变 | 标注不可读按 `''` 处理；列目录出错时保留已找到的文件，并把 `e.toString()` 记到 `error`；排序、`followLinks: false`、扩展名过滤不变 |
| `editor_session.dart:128-136` | `exists` → `readAsString`；`imageFile.length()` | `content = await _store.readCaption(p) ?? ''`；`bytes = await _store.imageLength(imageFile.path)` | 两者仍在同一个 `try` 里，任一失败都记为 `error`，`SaveState.error` 不变 |
| `editor_session.dart:347` | `File(path).writeAsString(text)` | `_store.writeCaption(path, text)` | 失败时进入 `SaveState.error`，`_lastError` 仍是 `e.toString()` |
| `tag_ops.dart:378-389` | exists / read / write | `readCaption(..) ?? ''` / `writeCaption` | 失败文案 `cannot read "$captionPath": $e`、`cannot write …` 不变 |
| `tag_ops.dart:489-520` | 同上，缺失且 `!createMissing` 时跳过 | `final text = await s.readCaption(..); if (text == null && !createMissing) continue;` | 跳过条件与失败文案不变 |
| `tag_ops.dart:573` | undo/redo 回写 | `s.writeCaption(edit.captionPath, text)` | 部分失败的处理不变 |
| `batch_tag_state.dart:487-508`、`:527-559` | 无 `try`，异常交给运行循环 | `readCaption(..) ?? ''`、`writeCaption`，同样不加 `try` | 仍由外层循环按文件记失败 |
| `caption_edit_tools.dart:400-446` | `exists ? read : ''`；write | `readCaption(..) ?? ''`；`writeCaption` | `cannot read: $e` / `cannot write: $e` 不变 |
| `caption_variant_tools.dart` 各处读写 | 同上各种写法 | 同上 | `exists: false` 分支由 `== null` 判断；`_maxCaptionRead` 截断、`runExclusive` 包裹写入不变 |
| `caption_variant_tools.dart:1632-1638` | `exists && length > 0`，外包 `catch → false` | `s.isNonEmptyFile(path)`，外层 `catch` 保留 | 按字节数判断，不读取内容 |
| `json_caption_tools.dart` 3 处 | exists / read / write | `readCaption` 为 `null` 时走 `missingFile++` 或 `skippedNoCaption++` | 计数与失败文案不变 |
| `media_tools.dart:213` | `File(key).readAsBytes()` | `s.readImageBytes(key)` | `cannot read image: $e` 不变 |
| `media_tools.dart:108-110` | `interrogateImageFile(File(key), …)` | **不改** | 只把 `File` 作为句柄传给 service，本身没有读写 |
| `workbench_view.dart:137` | `Directory(d).existsSync()` | `if (d != null && await _dataset.store.directoryExists(d) && mounted) _scan(d);` | 由同步改为异步，扫描推迟到这次存在检查（一次磁盘 I/O）返回后才启动；await 后补 `mounted` 检查 |

### 4.5 `services/json_file_dialogs.dart`（新增，P4）

```dart
/// Asks the user for a `.json` file and returns its text, or null when the
/// dialog is cancelled. Throws [FileSystemException] when the file cannot be
/// read (invalid UTF-8 included).
Future<String?> pickAndReadJson();

/// Asks where to save a `.json` file (suggesting [fileName]) and writes
/// [contents] there. Returns the chosen path, or null when cancelled.
/// Throws [FileSystemException] when the write fails.
Future<String?> saveJson({required String fileName, required String contents});
```

三个界面改为调用它们：

- 导入仍在界面里 catch `FormatException`（内容解析失败）和 `FileSystemException`（读失败），提示文案不变。
- `data_transfer_dialog` 的 `runDataImport(context, text)` 已单独拆出来供测试用，不受影响。

**有一处调用顺序变化**：`tag_library_panel` 和 `tag_dictionary_dialog` 原来先弹保存框、拿到路径再生成 JSON，改后要先生成 JSON 再弹框。

- 两个生成函数 `exportLibraryJson`、`exportJson` 都是同步的纯计算，所以这一变化看不出来。唯一的区别是：保存框打开期间，如果助手在后台改了标签库或词典，原来导出的是关闭保存框时的内容，现在导出的是打开保存框时的内容。两者都是用户发起导出那一刻的合理快照。
- 唯一的代价是用户取消保存时白算了一次，而这里只是一次小规模的 JSON 序列化。
- 为了这一点把参数改成回调（`String Function()`）不值得。

`FilePicker` 属于平台插件，按指南应归入 Service 层。放在 `services/` 符合 ARCHITECTURE 中 `services/` 那一行的描述（"I/O and external systems"）。

### 4.6 检查规则：禁止在 `services/` 外直接读写文件（P6）

在 `tool/check_layers.dart` 新增 `checkDirectIo(Directory lib)`，`run` 把它的违规与分层违规合并输出、合并计算退出码。CI 调用方式不变。

- **范围**：`lib/` 下除 `services/` 以外的所有 `.dart` 文件，`main.dart` 也在内。
- **判定**：去掉行注释后，匹配对 `dart:io` 读写方法的调用：
  ```
  \.(readAsString|readAsBytes|readAsLines|writeAsString|writeAsBytes|openRead|openWrite|
     exists|existsSync|length|list|listSync|delete|deleteSync|rename|renameSync|
     createSync|stat|statSync)\(
  ```
- **违规信息**：`file I/O belongs in services/: .readAsString(`，行号精确到调用处。
- **误报与漏报**：
  - 这是按方法名的启发式检查，不是类型分析，属于"绊线"：挡住常见写法，剩下的靠 review。
  - 在基线上试跑，命中 59 行（62 个调用，有 3 行各含两个）正好是 §2 列出的全部目标，其他层没有误报。
  - 以后若误报（比如某个非 I/O 类型恰好有 `.list(` 方法），把该方法名从正则里删掉，或者改写调用。不设白名单注释，以免有人拿注释绕过检查。
  - `File(...)` 本身不算违规，只持有句柄是允许的。
- **为什么放在 `check_layers` 而不是单独的测试**：这条规则本质上是分层约束（I/O 只属于 `services/`），放在一起能共用同一条 CI 命令和同一套退出码，`docs/ARCHITECTURE.md` 也只需要写一处。

### 4.7 文档

`docs/ARCHITECTURE.md`：

- `services/` 行的 Holds 列补上 "dataset files (`DatasetStore`: images and the caption files beside them), JSON import/export dialogs"。
- Conventions 加一条："Only `services/` reads or writes files. Other layers hold `File` objects as paths and call a service; `tool/check_layers.dart` flags direct calls."
- 顶部说明里 `tool/check_layers.dart` 的职责补一句 "and direct file I/O outside `services/`"。

## 5. 备选方案与取舍

| 方案 | 结论 | 理由 |
| --- | --- | --- |
| 改成指南示例的 `data/`、`domain/`、`ui/features/` 目录 | 不采用 | 要移动约 90 个文件并重写 ARCHITECTURE 与检查工具，但代码职责没有任何改善。本应用是单窗口工作台，面板共享 `AppState`，按功能拆不出清晰的边界。 |
| 在 `DatasetStore` 之上再加 `CaptionRepository` | 不采用 | 数据源只有本地文件，没有缓存、离线同步或多源合并要处理，加一层只是原样转发。等哪天真需要缓存了，再在 store 之上加。 |
| 定义 `abstract interface class DatasetStore` + `IoDatasetStore` | 不采用 | 只有一种实现。Dart 的隐式接口已足够测试替换，多一个类名只增加阅读成本。 |
| 通过 Provider 注入 store | 不采用 | 读写发生在状态类和 agent 工具里，这些地方拿不到 `BuildContext`。 |
| 每个状态类、每个工具都单独接收 store 参数 | 不采用 | 要改 81 处测试构造，还可能出现同一数据集用了两个不同 store 的组合。 |
| 禁止非 `services/` 层 import `dart:io` | 不采用 | `File` 作为路径句柄遍布状态类和界面（`List<File>`、`Image.file`），要全部改成 `String` 路径，改动面太大。 |

## 6. 兼容性与风险

| 风险 | 缓解 |
| --- | --- |
| 替换时改变了错误文案或跳过条件，agent 的工具结果随之改变 | §4.4 逐处列出了需保持的语义。`test/agent/` 的 14 个测试文件断言了失败文案和计数。单片 review 时要按表逐行核对。 |
| `workbench_view` 改为异步后，启动时的首次扫描要等存在检查的磁盘 I/O 返回 | 扫描本身就是异步的，这段窗口里用户来不及触发别的扫描。`widget_test.dart` 新增用例覆盖"上次的目录存在时重开、不存在时不扫描"。 |
| 守卫正则将来出现误报 | 方法名表可以直接调整；工具有单元测试锁定当前行为。 |
| 与进行中的其他分支冲突（大量 agent 文件） | 按 §8 拆成小提交，合入前把 main 同步进来（merge，不 rebase）。 |

## 7. 测试策略

- **回归**：现有 945 个测试不做任何修改，全部通过。它们都走默认的真实 store，所以能证明替换后行为不变。
- **新增 `test/services/dataset_store_test.dart`**，覆盖以下内容：
  - `scan` 的扩展名过滤、递归与非递归、不跟随符号链接；
  - 标注缺失和不可读都得到 `''`。"不可读"用非法 UTF-8 构造；与标注同名的目录让 `File.exists()` 返回 false，属于"缺失"，与原代码一致；
  - 列目录失败时，先交付已找到的图片，再抛出流错误；
  - `readCaption` 缺失（含同名目录）时返回 `null`，不可读时抛出异常；`writeCaption` 遇到同名目录时抛出异常；
  - `writeCaption` 能新建和覆盖文件；
  - `isNonEmptyFile` 对 0 字节、非 0 字节、不存在三种情况的判断；
  - `imageLength`、`readImageBytes`、`directoryExists`。
- **新增 `models/caption_type_test.dart` 用例**：覆盖 `captionPathOf` 的多段扩展名、无扩展名、目录名带点。公式用平台默认的 `path` 上下文，与原代码一致，所以不在 macOS/Linux 上断言 Windows 路径。
- **新增用假 store 的失败分支测试**，这些是原来难以构造、现在可以直接覆盖的：
  - `TagOps.rewriteOne` 写入失败时，返回 `RewriteResult.failed`，`dataset` 的标注和撤销栈都不变；
  - `TagOps` 批量操作中部分文件写失败时，只把成功的文件记入撤销；
  - `EditorSession.save` 失败时进入 `SaveState.error`；
  - `BatchTagState` 单个文件读失败时，记为失败文件，运行继续。
- **`test/tool/check_layers_test.dart` 新增用例**：
  - 各种读写调用都能报出，并带正确的行号；
  - `services/` 下不报；
  - 行注释里的调用不报；
  - `File(path)` 本身不报；
  - `run` 在只有 I/O 违规时返回退出码 1。
- **`json_file_dialogs` 不写单测**：它就是插件调用加一行读写，界面测试里也没法弹出系统文件框。导入逻辑的测试入口仍是已有的 `runDataImport`。

## 8. 提交拆分

每个提交独立通过格式检查、`analyze`、`check_layers` 和全量测试。

| # | 提交 | 内容 |
| --- | --- | --- |
| C1 | `refactor(state): 标注与图片读写收口到 DatasetStore` | 新增 `captionPathOf`、`services/dataset_store.dart` 及其测试。`DatasetState`、`EditorSession`、`TagOps`、`BatchTagState`、`workbench_view` 改为调用 store。补充假 store 的失败分支测试。 |
| C2 | `refactor(agent): agent 工具经 DatasetStore 读写标注与图片` | 改 `agent/` 下 4 个文件；`captionVariantPath` 改为调用 `captionPathOf`。 |
| C3 | `refactor(views): JSON 导入导出改用 json_file_dialogs` | 新增 service，改 3 个界面。 |
| C4 | `feat(tool): 分层检查禁止在 services/ 之外直接读写文件` | 新增 `checkDirectIo` 及测试，更新 ARCHITECTURE。必须放在 C1–C3 之后，否则 CI 会失败。 |

## 9. 不在本次范围

- `views/workbench/workbench_view.dart:54`、`:65`、`:129`、`:330` 与 `views/panels/agent_dock.dart:38` 直接 `new SettingsService()`，而不是用 `AppState` 持有的实例。这是依赖注入问题，不是 I/O 位置问题，另开任务。
- `views/image_preview_window.dart:63` 调用 `FileSaver.instance.saveFile`。它运行在独立的 engine 里，是只有一行的插件调用，搬进 service 的收益很小。守卫正则不会匹配它。
- 标注写入改为原子写（先写临时文件再改名）。本次完成后只需改 `DatasetStore.writeCaption` 一处，可以单独评估。
- `views/settings_view.dart` 移到 `views/dialogs/`，这是上一轮遗留的问题，与本次无关。
