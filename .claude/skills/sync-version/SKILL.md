---
name: sync-version
description: 升级/同步 app 版本号的完整流程:版本号写在哪几处、semver 怎么定、如何校验两处一致。用户说"升版本"、"发新版本"、"改版本号"、"同步版本"、"bump version"时使用。
---

# App 版本号同步流程

版本号一共只有 **两处** 需要手改,其余全部由构建自动派生:

| 位置 | 内容 | 说明 |
|---|---|---|
| `pubspec.yaml` 的 `version:` | `X.Y.Z+B` | 唯一权威来源。`B` 是 build number,每次发版 +1 |
| `lib/app_info.dart` 的 `AppInfo.version` | `'X.Y.Z'` | 设置页「关于」卡片显示用,**不含** build number |

**不需要动的地方**:`windows/runner/Runner.rc`、macOS/Linux runner 里的版本
均在 `flutter build` 时通过 `FLUTTER_VERSION` 宏从 pubspec 自动注入;
`AppInfo.copyright` / `license` / `repositoryUrl` 与版本无关,除非仓库迁移
或跨年才需要更新。

## 步骤

1. **定新版本号**(semver,以本次发版包含的改动为准):
   - 破坏性变更 / 数据格式不兼容 → major +1,minor/patch 归零
   - 新功能(feat) → minor +1,patch 归零
   - 仅修复(fix)/ 文档 / 重构 → patch +1
   - build number `B` 无条件 +1,只增不减
2. **改 `pubspec.yaml`**:`version: X.Y.Z+B`
3. **改 `lib/app_info.dart`**:`static const String version = 'X.Y.Z';`
4. **校验**(两处 semver 必须逐字一致):

   ```bash
   grep "^version:" pubspec.yaml && grep "version = " lib/app_info.dart
   ```

   然后跑 `flutter analyze --no-pub` 确认无告警。

## 发版(版本号合入后)

`.github/workflows/release.yml` 负责出包:在 GitHub Actions 页对目标分支
手动触发 **Release** workflow 即可,它会:

1. 从 `pubspec.yaml` 读版本号,并校验与 `AppInfo.version` 一致(不一致直接失败);
2. 校验 release `vX.Y.Z` 尚不存在;
3. 并行构建 Windows/macOS/Linux 桌面包 + AiApiServer 源码包;
4. 自动打 tag `vX.Y.Z` 并创建 GitHub Release 挂上四个产物。

因此本 skill 只管改两处文件;tag 与 release 由 workflow 生成,**不要手动打
版本 tag**。

## 约束

- 版本号只在发版分支/PR 里改,不要混进无关的功能 PR。
- 若未来新增 CHANGELOG、README 版本徽章或安装包命名脚本等含版本号的
  文件,必须把它加进上表并同步更新本 skill。
