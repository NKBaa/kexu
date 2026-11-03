import 'dart:convert';

import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/services/schedule_template_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _catalogJson = '''
{
  "version": 1,
  "schools": [
    {
      "school": "测试大学",
      "templates": [
        {
          "id": "t1",
          "name": "测试作息",
          "slots": [
            {"period": 1, "start": "08:00", "end": "08:45"}
          ]
        }
      ]
    }
  ]
}
''';

void main() {
  test('模板固定走内置加速镜像', () async {
    final requested = <String>[];
    final service = ScheduleTemplateService(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(utf8.encode(_catalogJson), 200);
      }),
    );

    final catalog = await service.fetch(
      config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
    );

    expect(catalog.schools.single.school, '测试大学');
    expect(catalog.allTemplates.single.name, '测试作息');
    expect(requested.single, startsWith('https://ghfast.top/'));
    expect(
      requested.single,
      contains('raw.githubusercontent.com/owner/repo/main/templates/bell_schedules.json'),
    );
  });

  test('加速镜像失败时回退到 GitHub 直连', () async {
    final requested = <String>[];
    final service = ScheduleTemplateService(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        if (!request.url.toString().startsWith('https://raw.githubusercontent.com/')) {
          return http.Response('mirror unavailable', 502);
        }
        return http.Response.bytes(utf8.encode(_catalogJson), 200);
      }),
    );

    final catalog = await service.fetch(
      config: const UpdateConfig(
        repo: 'owner/repo',
        mirrorMode: 'preset',
        mirrorPresetId: 'ghfast',
      ),
    );

    expect(catalog.schools, hasLength(1));
    expect(requested, hasLength(4));
    expect(requested.first, startsWith('https://ghfast.top/'));
    expect(requested.last, startsWith('https://raw.githubusercontent.com/'));
  });

  test('仓库未配置时给出可读异常', () async {
    final service = ScheduleTemplateService(
      client: MockClient((_) async => http.Response('', 200)),
    );

    await expectLater(
      service.fetch(config: const UpdateConfig(repo: '')),
      throwsA(isA<ScheduleTemplateException>()),
    );
  });

  test('所有地址都返回无效 JSON 时给出可读异常', () async {
    final service = ScheduleTemplateService(
      client: MockClient((_) async => http.Response('not json', 200)),
    );

    await expectLater(
      service.fetch(
        config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
      ),
      throwsA(isA<ScheduleTemplateException>()),
    );
  });
}
