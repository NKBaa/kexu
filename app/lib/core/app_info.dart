/// 应用元信息：名称与版本号的**唯一来源**。
///
/// 版本号以前散落在设置页、关于页的硬编码字符串里，升级时容易漏改，
/// 导致「关于页显示旧版本、GitHub Release 却是新版本」。
/// 现在统一从这里读取，并由 `test/core/app_info_test.dart` 校验
/// 与 `pubspec.yaml` 的 `version` 保持一致。
///
/// 发版时**只需要改这两个常量 + pubspec.yaml 的 version**：
/// - [appVersion] 对应 pubspec 中 `+` 之前的部分（如 `1.1.0`）；
/// - [appBuildNumber] 对应 pubspec 中 `+` 之后的构建号（如 `2`）。
library;

/// 应用中文名（展示用）。
const String appName = '课序';

/// 语义化版本号，如 `1.1.0`。
const String appVersion = '1.2.28';

/// 构建号（Android versionCode），如 `2`。
const int appBuildNumber = 84;

/// 展示用版本号，如 `1.1.0`。
const String versionLabel = appVersion;

/// 完整版本号（含构建号），如 `1.1.0+2`。
const String fullVersion = '$appVersion+$appBuildNumber';
