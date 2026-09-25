# 代码结构规范化 —— 执行计划

> 设计依据见 [CODE_STRUCTURE_REFACTOR_LLD.md](CODE_STRUCTURE_REFACTOR_LLD.md)（问题编号 P1–P7 / S1–S4 / C1–C3 与之对应）。
> 基线：`main` @ `e68c352`（v1.17.1+19）。提交分支：`refactor/code-structure`（阶段 1–4 最初在 `claude/reload-skills-291676` 工作区完成，按阶段 5 重放）。
> 本地工具链 Flutter 3.47.5；CI 固定 Flutter 3.44.7。

---

## 0. 总览

| 阶段 | 内容 | 对应问题 | 状态 |
| --- | --- | --- | --- |
| 1 | 静态检查与格式 | S1–S4 | ✅ 已完成（C1） |
| 2 | `lib/` 分包与依赖方向 | P1–P6 | ✅ 已完成（C2、C3） |
| 3 | `test/` 镜像 `lib/` | P7 | ✅ 已完成（C4） |
| 4 | 工程配置与文档 | C1–C3 | ✅ 已完成（C5、C6） |
| 5 | 拆分提交 | — | ✅ 已完成 |
| 6 | PR 与 CI 验证 | — | ⏳ 进行中 |
| 7 | 后续任务 | 范围外 | ⏳ 另立任务 |

全局约束：**每个阶段结束都必须满足第 8 节的验收标准**，不满足不进入下一阶段。

---

## 1. 阶段 1：静态检查与格式

| # | 步骤 | 命令 / 改动 |
| --- | --- | --- |
| 1.1 | 评估候选 lint 的违例数 | 对每条规则单独启用后 `flutter analyze`，结果见 LLD §6.1 |
| 1.2 | 写入 `analysis_options.yaml` | 12 条新增规则 + 排除 gen-l10n 生成物 |
| 1.3 | 自动修复 | `dart fix --apply --code=directives_ordering,prefer_final_locals`（73 处，71 个文件。LLD §6.1 的 71 + 4 = 75 是 analyzer 违例数；`dart fix` 对同一文件的多条 `directives_ordering` 只做一次排序，计 69 处，加 `prefer_final_locals` 4 处共 73） |
| 1.4 | 手动修复 | `agent_chat_panel.dart` 包 `unawaited`；`tag_library_panel.dart` `void async` → `Future<void>`；`glass_backdrop_group_test.dart` 包 `unawaited`；两个文件补 `import 'dart:async'` |
| 1.5 | 消除 analyzer 误报 | `test/tag_ai_group_test.dart`（现 `test/services/`）`_FakeLlm` 命名构造改初始化列表 |
| 1.6 | 格式化 | `dart format lib test tool` |
| 1.7 | 修复格式化引出的 lint | `danbooru_api.dart` 单行 `if` 补花括号 |

**验收**：`flutter analyze` → `No issues found!`；`dart format --set-exit-if-changed` 退出码 0。

---

## 2. 阶段 2：`lib/` 分包与依赖方向

| # | 步骤 | 说明 |
| --- | --- | --- |
| 2.1 | 生成映射表 `map-lib.txt` | 31 行，内容见 LLD §4.2–4.5 |
| 2.2 | 执行移动脚本（附录 A） | `python3 move.py map-lib.txt`：改写 import 后 `git mv` |
| 2.3 | 修排序、格式化 | `dart fix --apply --code=directives_ordering && dart format lib test tool` |
| 2.4 | 删除空目录 | `lib/services/agent/` |
| 2.5 | 常量下沉（P1） | 新建 `models/image_formats.dart`；改 `caption_type.dart`、`dataset_state.dart`（LLD §4.1） |
| 2.6 | 同步非代码引用 | `models/data_bundle.dart` 注释路径；`.claude/skills/update-models/SKILL.md` 中 dialog 路径 |
| 2.7 | 分层校验 | 运行附录 B 脚本，要求 0 violation |

**试过但放弃**：删掉 `settings_service.dart` 对 `theme/` 的 import。它实际使用 `AppMetrics` 作默认面板宽度，删后编译失败；按 LLD §3 判定为合法依赖，已还原。

**验收**：第 8 节全部通过；附录 B 输出 `violations: 0`；全仓 grep 无 `services/agent`、`lib/app_state.dart`、`views/workbench_view.dart` 等旧路径残留（`docs/plans/` 下的历史方案除外）。

---

## 3. 阶段 3：`test/` 镜像 `lib/`

| # | 步骤 | 说明 |
| --- | --- | --- |
| 3.1 | 生成候选映射 | 脚本对每个测试取其 `package:` import 中与文件名最相近的 lib 文件，放入同目录 |
| 3.2 | 人工复核 | 修正 5 例（LLD §4.6 表）；`widget_test.dart` 不动 |
| 3.3 | 检查路径依赖 | `grep -rn "'test/\|Platform.script" test` 无结果，移动不影响夹具定位 |
| 3.4 | 执行移动 | 同一脚本，`map-test.txt` 72 行 |
| 3.5 | 全量测试 | `flutter test` |

**验收**：第 8 节全部通过；`test/` 根目录只剩 `widget_test.dart`。

---

## 4. 阶段 4：工程配置与文档

| # | 改动 |
| --- | --- |
| 4.1 | `pubspec.yaml`：`description`；`msix` → `dev_dependencies`；`flutter pub get` |
| 4.2 | `MyApp` → `DatasetToolkitApp`（`lib/main.dart`、`test/widget_test.dart`） |
| 4.3 | `l10n.yaml` 删残留注释 |
| 4.4 | `.github/workflows/dart.yml` 新增 “Verify formatting” 步骤 |
| 4.5 | `git mv` 两份根目录方案文档到 `docs/plans/` |
| 4.6 | 新增 `docs/ARCHITECTURE.md`（分层规则与约定）、本计划与 LLD |

**验收**：第 8 节全部通过；`dart run msix:create` 能解析并启动 msix 的可执行入口（证明移到 dev 依赖后仍可用；msix 不支持 `--help`，实际打包只在 Windows 打包机上做）。

---

## 5. 阶段 5：拆分提交（已完成）

阶段 1–4 目前混在同一个工作区里：被移动的文件同时带有格式化改动，事后按 hunk 拆分容易出错。因为每一步都是脚本化、确定性的，所以**从基线重放**：

```bash
git switch -c refactor/code-structure e68c352
```

然后按下表逐步执行、逐步提交，每次提交前跑第 8 节验收：

| 提交 | 执行 | 提交信息 |
| --- | --- | --- |
| C1 | 阶段 1 全部步骤 | `style: 收紧 lint 规则并统一格式化` |
| C2 | 阶段 2（2.1–2.4、2.6） | `refactor: 按分层规则重组 lib 目录` |
| C3 | 阶段 2.5 | `refactor(models): 图片扩展名常量下沉到 models，解除 models→state 依赖` |
| C4 | 阶段 3 | `test: 测试目录镜像 lib 结构` |
| C5 | 阶段 4.1–4.4 | `chore: 清理模板残留，CI 增加格式校验` |
| C6 | 阶段 4.5–4.6 | `docs: 架构约定、结构规范化方案与执行计划` |

重放完成后，用 `git diff refactor/code-structure claude/reload-skills-291676` 与当前工作区比对，要求**零差异**（证明重放忠实于已验证的结果），再丢弃旧工作区分支。

C1 的 commit hash 写入 `.git-blame-ignore-revs`（随 C6 一起提交），让 `git blame` 跳过纯格式化提交。

**执行结果**：

| 提交 | hash | 验收 |
| --- | --- | --- |
| C1 | `df1881d` | analyze 0、format 0、test `+920 -2` |
| C2 | `43a1421` | 同上；分层 1（见下） |
| C3 | `c6c6024` | 同上；分层 0 |
| C4 | `24d2973` | 同上；72 个纯 rename，0 行改动 |
| C5 | `8738826` | 同上 |
| C6 | `da89230` | 文档 |
| review 修复 | `917cc82` 及之后 | 文档（单片 review 与整体 review 的修复） |
| 合入 main | `2481f31` | 带入 PR #106（chip_dim 阈值修复），无冲突；format 0、analyze 0、分层 0、test `+923` |

- 重放到 C6 暂存文档后，与原工作区快照 `git diff` 为**零差异**；之后 C6 只在文档上追加了本节、状态更新和 LLD §6.1 的 exclude 说明。
- 偏离：C2 单独提交时分层校验为 1（`models/caption_type.dart → state/`，即 P1），因为 2.5 拆到了 C3；分层 0 的验收相应移到 C3。
- 每个提交都做了单独 review。成立的问题：LLD 未说明平台目录的 analyzer exclude（C6 补充）；`update-models` skill 里的测试命令仍是旧路径、合入策略 rebase merge 会使 blame-ignore 失效、ARCHITECTURE 允许依赖列表窄于 LLD 矩阵（C6 之后的 review 修复提交）。

---

## 6. 阶段 6：PR 与 CI 验证（进行中）

1. 推送分支，开 PR 到 `main`，描述引用本计划与 LLD。
2. 重点关注 CI 的三个步骤：
   - **Verify localizations**：本次未改 arb，应无差异。
   - **Verify formatting**：新增步骤，CI 用 Flutter 3.44.7 的 formatter。若与本地 3.47.5 结果不一致 → 在 3.44.7 下重跑 `dart format` 追加提交，并在 PR 中注明。
   - **Run tests**：合入 main（含 PR #106 对 `chip_dim_test` 的修复）后本地 `+923` 全绿，CI 应一致。
3. 合入策略：**Create a merge commit**（与仓库现有的 “Merge pull request #…” 一致）。不要 squash，也不要 rebase merge：GitHub 的 rebase merge 总会重写 commit hash，squash 会把 C1 并入别的改动，两者都会使 `.git-blame-ignore-revs` 里记录的 C1 hash 失效。
4. 合入后通知进行中的分支 rebase；被移动文件上的冲突按新路径解决。

**回滚**：C2–C4 以文件重命名为主，`git revert` 可干净回退；C1 独立，可单独回退而不影响结构调整。

---

## 7. 后续任务（不在本次范围）

| 任务 | 说明 | 优先级 |
| --- | --- | --- |
| `settings_view.dart` 移入 `views/dialogs/` | 它只作为设置对话框使用，按 ARCHITECTURE 规则应在 `dialogs/`；见 LLD §9 | 低 |
| 修复 `test/views/dialogs/tag_dictionary_dialog_test.dart` 偶发失败 | danbooru 查询用例在全量并行运行时约 1/7 概率失败、单跑稳定通过；`fetch()` 用固定 80 ms 真实时间等待含文件 I/O 的往返，基线即如此。改为等待实际完成；已开独立任务 | 中 |
| 统一本地与 CI 的 Flutter 版本 | CI 3.44.7 vs 本地 3.47.5 是像素测试与格式校验不一致的根源；考虑 `.fvmrc` 或升级 CI | 中 |
| 拆分超大 UI 文件 | `tag_dictionary_dialog.dart` 等，切分点见 LLD §9 | 低 |
| ~~分层规则进 CI~~ | 已完成：`tool/check_layers.dart`（见附录 B）在 CI analyze 之后执行，并已写入 ARCHITECTURE 的提交前检查 | — |
| 评估剩余 lint | `avoid_dynamic_calls`（20 处，JSON 解析）可配合类型化解析逐步启用 | 低 |

---

## 8. 每阶段验收标准

```bash
flutter pub get                                                 # 先解析依赖，否则 formatter 按错误的语言版本格式化
dart format --output=none --set-exit-if-changed lib test tool   # 退出码 0
flutter analyze                                                 # No issues found!
flutter test                                                    # 全部通过（合入 main 前：除 chip_dim_test 2 例外）
dart run tool/check_layers.dart                                 # violations: 0（附录 B，在仓库根目录运行）
```

当前结果（合入 main @ `472a689` 后）：格式 0 变更；analyzer 0 issue；测试 `+923` 全部通过；分层 0 violation。各提交单独验收时为 `+920 -2`，失败的 2 例是基线即存在的 `chip_dim_test`，已由 main 上的 PR #106 修复。

---

## 附录 A：移动脚本 `move.py`

输入为每行 `旧路径 新路径` 的映射表（仓库相对路径，`#` 开头为注释）。在仓库根目录运行。算法说明见 LLD §5。

```python
import os, re, subprocess, sys

PKG = 'dataset_training_tool'
mapping = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    a, b = line.split()
    mapping[os.path.normpath(a)] = os.path.normpath(b)

files = []
for root in ('lib', 'test', 'tool'):
    for dp, _, fs in os.walk(root):
        files += [os.path.normpath(os.path.join(dp, f)) for f in fs if f.endswith('.dart')]

IMPORT = re.compile(r"""^((?:import|export|part)\s+')([^']+)(')""", re.M)

plans = {}
for f in files:
    src = open(f, encoding='utf-8').read()
    new_f = mapping.get(f, f)

    def repl(m):
        uri = m.group(2)
        if uri.startswith('dart:'):
            return m.group(0)
        if uri.startswith('package:'):
            if not uri.startswith(f'package:{PKG}/'):
                return m.group(0)
            target, style = os.path.normpath('lib/' + uri[len(f'package:{PKG}/'):]), 'package'
        else:
            target, style = os.path.normpath(os.path.join(os.path.dirname(f), uri)), 'relative'
        new_target = mapping.get(target, target)
        if new_target == target and new_f == f:
            return m.group(0)
        if style == 'package':
            uri2 = f'package:{PKG}/' + new_target[len('lib/'):]
        else:
            uri2 = os.path.relpath(new_target, os.path.dirname(new_f))
        return m.group(1) + uri2 + m.group(3)

    plans[f] = IMPORT.sub(repl, src)

for f, text in plans.items():
    open(f, 'w', encoding='utf-8').write(text)
for a, b in mapping.items():
    os.makedirs(os.path.dirname(b), exist_ok=True)
    subprocess.check_call(['git', 'mv', a, b])
print(f'moved {len(mapping)} files')
```

## 附录 B：分层校验 `tool/check_layers.dart`

重构期间用的是手工运行的 Python 脚本 `check_layers.py`（见本文件 git 历史）。它只匹配 `^import '...'`，漏掉 `export` 与 `package:dataset_training_tool/...` 自引用。现已由 `tool/check_layers.dart` 取代，规则与 LLD §3 矩阵一致，`views/`、`l10n/` 及 `lib/` 根下文件不受限。在仓库根目录运行：

```bash
dart run tool/check_layers.dart   # 打印每条 VIOLATION，末行 violations: N；N > 0 时退出码 1
```

与旧脚本相比：

- 检查 `import`、`export`、`part`，含条件导入的各备选 URI（`if (dart.library.io) '...'`）；
- 相对路径与 `package:dataset_training_tool/` 都解析到 `lib/` 下的顶层目录或文件，指向 `lib/` 之外也算违规；
- `lib/` 下出现矩阵里没有的新顶层目录时报错，避免新目录绕开检查；
- CI（`.github/workflows/dart.yml`）在 `flutter analyze` 之后运行；测试见 `test/tool/check_layers_test.dart`。

矩阵改动时同步改 `docs/ARCHITECTURE.md` 表格、LLD §3 与脚本里的 `allowedImports`。
