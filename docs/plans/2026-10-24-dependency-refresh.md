# 依赖更新与 file_picker 迁移

范围：修复 PR #124 在新解析依赖下的 CI 失败；保持 Flutter 3.47.6，不升级 SDK。

- 更新所有可解析依赖；直接依赖更新为 file_picker 13.2.0、file_saver 0.7.0、image 4.12.0、archive 4.5.2、shared_preferences 2.5.6。
- 移除 saveFile 的无效弃用参数 type / allowedExtensions；保留 UTF-8 字节、文件名、JSON MIME 类型与取消返回值。pickFiles 的 JSON 过滤继续保留，目录选择 API 无需变化。
- 应用纳入 pubspec.lock，保证本地、CI 与发布依赖一致。保留 SDK/上游约束下不可升级的传递依赖，不使用 dependency_overrides。
- 上游依据：https://pub.dev/documentation/file_picker/latest/file_picker/FilePicker/saveFile.html 和 https://pub.dev/packages/file_saver/changelog 。file_saver 0.7.0 对现有 saveFile 调用无需迁移。

验证：pub get、gen-l10n（无生成差异）、格式、分析、分层全部通过；完整测试 1042 通过、4 跳过。pub outdated 确认所有直接/开发依赖为最新，4 项传递依赖受上游或 SDK 约束。插件注册文件无新增内容变更，保留原有 macOS 本地修改。PR CI 待推送后验证；未实际操作各平台原生文件对话框。
