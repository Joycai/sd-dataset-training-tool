# CI 优化 —— 执行计划

> 依据：2026-09-26 对 `.github/workflows/dart.yml`、`release.yml` 的审查（问题编号 C1–C14 见 §0.2）。
> 基线：`main` @ `2e594c6`（v1.17.1+19）。提交分支：`ci/optimization`。
> 现状数据：Dart 工作流单次约 3.5 分钟，其中 `flutter test` 140s（970 用例 / 75 文件）；Release 约 6 分钟，关键路径 build-windows 5 分钟。
> 本地工具链 Flutter 3.47.5；CI 固定 Flutter 3.44.7。

---

## 0. 总览

### 0.1 阶段

| 阶段 | 内容 | 对应问题 | 改动类型 | 预期收益 |
| --- | --- | --- | --- | --- |
| 1 | `dart.yml` 基础加固 | C1–C5 | 纯配置 | 重复 run 自动取消；文档改动不触发；卡死 run 不再跑满 6 小时 |
| 2 | Flutter 版本单一来源 | C6 | 配置 + pubspec | 本地 / CI / Release 三处版本一致 |
| 3 | 测试尾巴与版本一致性测试 | C7、C9 | 测试代码 | `flutter test` 约 -25s；版本漂移在 PR 阶段被拦 |
| 4 | Release 门禁与复用 | C8、C10、C11 | 工作流重构 | 发布前必过 analyze/test；可在分支上 dry-run |
| 5 | 维护性 | C12–C14 | 新增文件 | 依赖升级提醒；AiApiServer 有最低限度检查 |
| 6 | PR 与验证 | — | — | — |

全局约束：**每个阶段一个提交，每个提交单独能过 CI**（§7 验收标准）。阶段 1、2、5 互不依赖；阶段 4 依赖阶段 1（工作流改名）和阶段 3（版本测试替代 release 里的 grep 校验）。

### 0.2 问题清单

| 编号 | 问题 | 位置 |
| --- | --- | --- |
| C1 | 无 `concurrency`，同一 PR 连推时旧 run 不取消 | dart.yml |
| C2 | 无 `permissions`，token 走仓库默认权限 | dart.yml |
| C3 | 无 `timeout-minutes`，卡死 job 跑满 6 小时 | dart.yml、release.yml |
| C4 | 无路径过滤，docs / wiki / AiApiServer 改动也跑 Flutter CI | dart.yml |
| C5 | l10n 校验用 `git diff --exit-code`，漏检新增未跟踪文件 | dart.yml:27 |
| C6 | Flutter 版本在 dart.yml:21 与 release.yml:18 各写一份，且与本地 3.47.5 不一致 | 两处 |
| C7 | `toolbar_overflow_test.dart` 单个用例串行 4224 次 pump，独占测试步骤最后 32s | test/views/panels/ |
| C8 | Release 可从任意分支 dispatch，不跑 analyze / test 直接出包 | release.yml |
| C9 | `AppInfo.version` 与 pubspec 一致性只在发布时用 grep 校验 | release.yml:36 |
| C10 | macOS runner 按 10 倍分钟计费，build job 无超时 | release.yml |
| C11 | Release 工作流无法在合入前验证 | release.yml |
| C12 | 无 Dependabot，actions 浮动大版本、pub 依赖无升级提醒 | .github/ |
| C13 | AiApiServer 33 个 Python 文件零 CI | .github/ |
| C14 | 工作流名 `Dart` 与内容不符 | dart.yml:1 |

---

## 1. 阶段 1：`dart.yml` 基础加固

| # | 步骤 | 改动 |
| --- | --- | --- |
| 1.1 | 改名 | `name: Dart` → `name: CI`；文件改名 `ci.yml`（`git mv`）。main 无分支保护，无 required check 需要同步 |
| 1.2 | 权限 | 顶层 `permissions: { contents: read }` |
| 1.3 | 并发 | 顶层 `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }` |
| 1.4 | 超时 | job 级 `timeout-minutes: 15`（当前 3.5 分钟，留 4 倍余量） |
| 1.5 | 路径过滤 | `push` 与 `pull_request` 各加 `paths-ignore: ['docs/**', 'wiki/**', '**.md', 'AiApiServer/**', '.claude/**']` |
| 1.6 | l10n 校验 | 步骤改为 `flutter gen-l10n && test -z "$(git status --porcelain lib/l10n)"`，失败时先 `git status lib/l10n` 打印差异 |
| 1.7 | 测试报告 | **不改**。`flutter test` 在 `GITHUB_ACTIONS` 环境下已默认使用 `github` reporter（现有日志里的 ✅ 标记即其输出），显式传参无收益 |

**说明**：
- 1.5 的 `.claude/**` 是 skills 与本地配置，不影响构建；若后续把 `bump-version` 等 skill 的校验脚本纳入 CI，再从列表移除。
- 1.5 在以后启用分支保护 required check 时会出现 "expected" 挂起。届时改为 `dorny/paths-filter` 在 job 内跳过步骤，而不是在触发层过滤。

**验收**：PR 上连续推两次，第一次 run 状态为 `cancelled`；只改 `README.md` 的提交不触发 CI；Actions 列表中工作流名为 `CI`。

---

## 2. 阶段 2：Flutter 版本单一来源

| # | 步骤 | 改动 |
| --- | --- | --- |
| 2.1 | 决定目标版本 | **升到 3.47.5**（与本地一致）。理由：格式校验与 lint 结果由开发机上的 SDK 产生，CI 落后于本地才是漂移的来源；本地已在 3.47.5 下通过全部检查 |
| 2.2 | pubspec | `environment:` 下加 `flutter: 3.47.5`（精确版本，非范围；`flutter pub get` 在版本不符时会报错，这是想要的效果） |
| 2.3 | ci.yml | `flutter-version: 3.44.7` → `flutter-version-file: pubspec.yaml` |
| 2.4 | release.yml | 删除 `env.FLUTTER_VERSION`，三个 build job 同样改用 `flutter-version-file: pubspec.yaml` |
| 2.5 | 本地复核 | `flutter pub get && flutter analyze && dart format --output=none --set-exit-if-changed lib test tool && flutter test` |
| 2.6 | 文档 | `docs/plans/CODE_STRUCTURE_REFACTOR_PLAN.md` §7 表中"统一本地与 CI 的 Flutter 版本"一项标记为已完成并指向本文 |

**说明**：
- `subosito/flutter-action@v2`（当前最新 v2.23.0）支持 `flutter-version-file`，读取 `environment.flutter`，要求写精确版本而非范围。Windows runner 缺少 `yq`，action 会自动安装，无需额外步骤。
- 版本变更后 flutter-action 与 pub 缓存 key 都会变，首次 run 冷启动约多 2 分钟，之后恢复。
- 若 2.5 在 3.47.5 下出现新的 analyzer 提示，先修代码再提交，不回退版本。

**验收**：`grep -rn "3.44.7\|FLUTTER_VERSION" .github pubspec.yaml` 无输出；CI 日志中 flutter-action 报告 `3.47.5`；第二次 run 缓存命中。

---

## 3. 阶段 3：测试尾巴与版本一致性测试

### 3.1 拆分 `toolbar_overflow_test.dart`（C7）

现状：2 语言 × 3 保存态 × 2 对比 × 2 格式 = 24 组合，每组按 4px 步长扫 200–900px 共 176 个宽度，全部在一个 `testWidgets` 里串行，独占测试步骤末尾 32s。

| # | 步骤 | 改动 |
| --- | --- | --- |
| 3.1.1 | 抽公共部分 | 新建 `test/views/panels/toolbar_overflow_harness.dart`（无 `_test` 后缀，不会被当作测试文件）：搬入 `_pngBytes`、`setUp` 逻辑、`harness()` 和扫描函数 `sweepToolbar({required Locale locale, required CaptionFormat format})` |
| 3.1.2 | 按 locale × format 拆 4 个文件 | `toolbar_overflow_en_tags_test.dart`、`toolbar_overflow_en_prose_test.dart`、`toolbar_overflow_zh_tags_test.dart`、`toolbar_overflow_zh_prose_test.dart`，每个只调一次 `sweepToolbar` |
| 3.1.3 | 删除原文件 | `git rm test/views/panels/toolbar_overflow_test.dart` |
| 3.1.4 | 计时对比 | 改前：`time flutter test test/views/panels/toolbar_overflow_test.dart`；改后：`time flutter test test/views/panels/toolbar_overflow_*_test.dart`。`flutter test` 默认并发数为 CPU 核数，ubuntu-latest 为 4 核，4 个文件恰好并行 |

**不做**：步长 4 → 8。覆盖密度是原测试注释里明确的设计，拆文件已经足够把尾巴压到 8s 左右，不需要降覆盖。

**验收**：4 个文件用例总数与原文件一致（24 组合全覆盖）；本地计时 4 文件并行后总时长 ≤ 原时长的 40%；CI 测试步骤末尾不再出现单文件独占 30s 的间隔。

### 3.2 版本一致性测试（C9）

| # | 步骤 | 改动 |
| --- | --- | --- |
| 3.2.1 | 新建 `test/app_info_test.dart` | 读 `pubspec.yaml`（测试运行时 cwd 为项目根），解析 `version: X.Y.Z+N`，断言 `AppInfo.version == 'X.Y.Z'`，断言 `msix_config.msix_version == 'X.Y.Z.N'` |
| 3.2.2 | 解析方式 | 不引入 `yaml` 包，用正则逐行匹配 `^version:` 与 `^\s+msix_version:`，与 release.yml 现有 grep 逻辑等价 |
| 3.2.3 | 更新 skill | `.claude/skills/bump-version/SKILL.md` 的校验一节加一句：`flutter test test/app_info_test.dart` 可一次验证三处一致 |

**验收**：手改 `AppInfo.version` 为错误值时该测试失败，改回后通过。

---

## 4. 阶段 4：Release 门禁与复用

| # | 步骤 | 改动 |
| --- | --- | --- |
| 4.1 | ci.yml 可复用 | `on:` 增加 `workflow_call: {}`。`paths-ignore` 只对 push / pull_request 生效，被调用时始终全跑 |
| 4.2 | release.yml 加门禁 | 新增 job `check: { needs: version, uses: ./.github/workflows/ci.yml }`；`build-windows` / `build-macos` / `build-linux` / `package-server` 的 `needs` 改为 `[version, check]` |
| 4.3 | 删除 grep 校验 | 删除 version job 中 "Verify AppInfo.version matches pubspec.yaml" 步骤（已由 §3.2 的测试在 `check` 中覆盖） |
| 4.4 | 超时 | `version` / `package-server` / `release`：10 分钟；`build-linux`：20 分钟；`build-windows` / `build-macos`：30 分钟 |
| 4.5 | dry-run 输入 | `workflow_dispatch.inputs.dry_run: { type: boolean, default: false }`。为 true 时：跳过 "Ensure release does not already exist"，`release` job 加 `if: ${{ !inputs.dry_run }}`。四个包仍作为 artifact 上传，可下载验证 |
| 4.6 | 顶层 `permissions` | 现为 `contents: write` 全局生效。收窄为顶层 `contents: read`，仅 `release` job 声明 `permissions: { contents: write }` |

**说明**：
- 复用后 `concurrency` 分组键中的 `github.workflow` 取调用方名称，Release 触发的 check 落在 `Release-<ref>` 组，不会与同分支上的 `CI-<ref>` 互相取消。首次 dry-run 时在 Actions 页面确认这一点。
- 发布总时长约 +3.5 分钟（check 与 build 串行）。可接受：发布频率约每月一次。
- 4.5 让阶段 4 可以在 `ci/optimization` 分支上验证：`gh workflow run release.yml --ref ci/optimization -f dry_run=true`。

**验收**：dry-run 成功，`release` job 显示 skipped，四个 artifact 可下载；在分支上故意让一个测试失败再 dry-run，build job 不启动。

---

## 5. 阶段 5：维护性

### 5.1 Dependabot（C12）

新建 `.github/dependabot.yml`：

| 生态 | 目录 | 频率 | 说明 |
| --- | --- | --- | --- |
| `github-actions` | `/` | 每周一 | 覆盖 `actions/*`、`subosito/flutter-action`、`softprops/action-gh-release` |
| `pub` | `/` | 每周一 | `groups` 把 minor / patch 合成一个 PR；`desktop_multi_window` 为 git 依赖，Dependabot 会忽略 |
| `pip` | `/AiApiServer` | **不开** | torch / transformers 的升级需要在 GPU 环境下人工验证，自动 PR 只会积压 |

### 5.2 AiApiServer 最低限度检查（C13）

新建 `.github/workflows/server.yml`：

| # | 步骤 | 改动 |
| --- | --- | --- |
| 5.2.1 | 触发 | `push` / `pull_request` 到 main，`paths: ['AiApiServer/**', '.github/workflows/server.yml']` |
| 5.2.2 | 环境 | `actions/setup-python@v5`，`python-version: '3.11'`。**不装 requirements.txt** |
| 5.2.3 | 检查 | `python -m compileall -q AiApiServer`；`pipx run ruff check AiApiServer` |
| 5.2.4 | ruff 起始规则 | 新建 `AiApiServer/ruff.toml`：`select = ["E9", "F63", "F7", "F82"]`（语法错误、未定义名、非法比较）。先本地跑一次，若有违例先修再提交；更多规则留待后续 |
| 5.2.5 | 同样加上 | `permissions: contents: read`、`concurrency`、`timeout-minutes: 5` |

**验收**：只改 `AiApiServer/main.py` 的提交触发 server.yml 而不触发 ci.yml；反之亦然。

---

## 6. 阶段 6：PR 与验证

| # | 步骤 | 说明 |
| --- | --- | --- |
| 6.1 | 提交顺序 | 6 个提交，每阶段一个：`ci: 加固 CI 工作流触发与权限`（阶段 1）→ `ci: Flutter 版本以 pubspec 为准`（阶段 2）→ `test: 拆分工具栏溢出扫描，增加版本一致性测试`（阶段 3）→ `ci: release 前跑 CI 检查，支持 dry-run`（阶段 4）→ `ci: 增加 Dependabot 与 AiApiServer 检查`（阶段 5） |
| 6.2 | 分两个 PR | PR-1 含阶段 1、2、3、5：全部由 PR 自身的 CI 验证。PR-2 含阶段 4：合入 PR-1 后 rebase，用 §4.5 的 dry-run 验证 |
| 6.3 | PR-1 验证清单 | §1、§2、§3、§5 各自的验收项；另外在 PR 上连推两次确认 C1 生效 |
| 6.4 | PR-2 验证清单 | §4 验收项；dry-run 的 run 链接贴进 PR 描述 |
| 6.5 | 合入后 | 在 main 上观察一次 push 触发的 CI：冷缓存后第二次 run 总时长应 ≤ 3 分钟 |

---

## 7. 每阶段验收标准

1. `flutter analyze` → `No issues found!`
2. `dart format --output=none --set-exit-if-changed lib test tool` 退出码 0
3. `dart run tool/check_layers.dart` → 0 violation
4. `flutter test` 全部通过
5. 该阶段 §1–§5 中列出的专项验收项
6. 工作流文件改动后，用 `actionlint`（`brew install actionlint`）本地校验一次，避免推上去才发现语法错

---

## 8. 风险与回退

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 3.47.5 下 analyzer 出新提示 | 阶段 2 CI 失败 | 本地已在 3.47.5 下通过，概率低；出现则修代码，不回退版本 |
| `flutter-version-file` 读不到 `environment.flutter` | flutter-action 报错 | 该参数自 v2.13 支持；失败时临时回退为显式 `flutter-version`，并在 pubspec 保留 `flutter:` 约束 |
| 拆分后 4 个溢出测试并行争抢 CPU，单文件变慢 | 收益低于预期 | 以 CI 实测为准；若总时长未降到 40% 以下，再考虑步长 4 → 8 |
| 复用 workflow 后 `concurrency` 分组与预期不符 | Release 的 check 取消同分支 CI | 首次 dry-run 时核对分组键；不符则给 `check` job 单独指定 `concurrency` |
| ruff 起始规则在现有代码上有违例 | server.yml 首次即红 | 5.2.4 要求先本地跑通再提交 |
| `paths-ignore` 与未来的 required check 冲突 | PR 卡在 expected | §1 说明中已给出改用 `dorny/paths-filter` 的路径 |

---

## 9. 不在本次范围

- Windows msix 打包进 Release：需要签名证书与 secrets 管理，另立任务。
- macOS 签名与公证：同上。
- 把 `flutter test` 拆成多 job 分片：当前 140s 尚不值得引入分片的复杂度，等测试规模翻倍再评估。
- AiApiServer 单元测试：先有语法级检查，测试框架的引入另议。
