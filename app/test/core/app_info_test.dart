import 'dart:io';

import 'package:course_timetable/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app_info', () {
    test('版本常量与 pubspec.yaml 的 version 一致（防止版本号漂移）', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml 里缺少 version 行');

      // 发版时 app_info.dart 与 pubspec.yaml 必须同时改，否则这里会失败
      expect(
        match!.group(1),
        '$appVersion+$appBuildNumber',
        reason: 'app_info.dart 的版本号与 pubspec.yaml 不一致',
      );
    });

    test('展示用版本号与完整版本号格式正确', () {
      expect(appName, isNotEmpty);
      expect(versionLabel, appVersion);
      expect(fullVersion, '$appVersion+$appBuildNumber');
      expect(versionLabel, matches(RegExp(r'^\d+\.\d+\.\d+')));
      expect(appBuildNumber, greaterThan(0));
    });
  });
}
