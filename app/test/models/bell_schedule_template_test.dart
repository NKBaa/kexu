import 'dart:convert';

import 'package:course_timetable/data/models/bell_schedule_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('作息模板解析', () {
    test('按学校分组，解析多套模板与节次', () {
      final catalog = BellScheduleTemplateCatalog.fromJson({
        'version': 1,
        'updatedAt': '2026-11-02',
        'schools': [
          {
            'school': 'A 大学',
            'note': '示例说明',
            'templates': [
              {
                'id': 'a-12',
                'name': '标准 12 节',
                'description': '上午四节',
                'slots': [
                  {'period': 2, 'start': '08:55', 'end': '09:40'},
                  {'period': 1, 'start': '08:00', 'end': '08:45'},
                ],
              },
            ],
          },
          {
            'school': 'B 大学',
            'templates': [
              {
                'id': 'b-10',
                'name': '标准 10 节',
                'slots': [
                  {'period': 1, 'start': '08:00', 'end': '08:45'},
                ],
              },
            ],
          },
        ],
      });

      expect(catalog.schools, hasLength(2));
      expect(catalog.schools.first.school, 'A 大学');
      expect(catalog.schools.first.note, '示例说明');
      expect(catalog.allTemplates.length, 2);
      final t = catalog.schools.first.templates.single;
      expect(t.name, '标准 12 节');
      expect(t.slots.map((s) => s.period), [1, 2]);
      expect(t.firstStart, '08:00');
      expect(t.lastEnd, '09:40');
    });

    test('缺少 slots 的模板会报格式错误', () {
      expect(
        () => BellScheduleTemplateCatalog.fromJson({
          'schools': [
            {
              'school': 'A',
              'templates': [
                {'id': 'x', 'name': '空模板'},
              ],
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('JSON 字符串可直接反序列化', () {
      const raw = '''
      {"schools":[{"school":"通用","templates":[
        {"id":"g","name":"标准","slots":[{"period":1,"start":"08:00","end":"08:45"}]}
      ]}]}
      ''';
      final catalog = BellScheduleTemplateCatalog.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      expect(catalog.allTemplates.single.school, '通用');
    });

    test('解析学校的分时间段作息日期范围', () {
      final catalog = BellScheduleTemplateCatalog.fromJson({
        'schools': [
          {
            'school': '分季大学',
            'templates': [
              {
                'id': 'spring',
                'name': '春季作息',
                'dateRange': {'start': '05-01', 'end': '10-01'},
                'slots': [
                  {'period': 1, 'start': '08:00', 'end': '08:45'},
                ],
              },
            ],
          },
        ],
      });
      final t = catalog.allTemplates.single;
      expect(t.hasDateRange, isTrue);
      expect(t.rangeLabel, '05-01 ~ 10-01');
    });
  });
}
