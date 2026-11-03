import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/draft.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiConfig', () {
    test('isConfigured 判定', () {
      expect(const AiModelConfig().isConfigured, isFalse);
      expect(const AiModelConfig(baseUrl: 'https://x/v1').isConfigured, isFalse);
      expect(
        const AiModelConfig(baseUrl: 'https://x/v1', model: 'm').isConfigured,
        isTrue,
      );
    });

    test('chatCompletionsUrl 处理末尾斜杠', () {
      expect(
        const AiModelConfig(baseUrl: 'https://api.deepseek.com/v1/', model: 'm')
            .chatCompletionsUrl,
        'https://api.deepseek.com/v1/chat/completions',
      );
    });

    test('baseUrl 已含 /chat/completions 时不重复拼接', () {
      expect(
        const AiModelConfig(
          baseUrl: 'https://x/v1/chat/completions',
          model: 'm',
        ).chatCompletionsUrl,
        'https://x/v1/chat/completions',
      );
    });

    test('JSON 往返', () {
      const c = AiModelConfig(
        baseUrl: 'https://api.x.com/v1',
        apiKey: 'sk-abc',
        model: 'glm-4v',
        temperature: 0.1,
        timeoutSeconds: 90,
      );
      final back = AiModelConfig.fromJson(c.toJson());
      expect(back.baseUrl, c.baseUrl);
      expect(back.apiKey, c.apiKey);
      expect(back.model, c.model);
      expect(back.temperature, c.temperature);
      expect(back.timeoutSeconds, c.timeoutSeconds);
    });

    test('预设存在且基础字段完整', () {
      expect(aiProviderPresets, isNotEmpty);
      for (final p in aiProviderPresets) {
        expect(p.id, isNotEmpty);
        expect(p.label, isNotEmpty);
      }
      // 必须有一个支持视觉的预设（图片转课表依赖）
      expect(aiProviderPresets.any((p) => p.supportsVision), isTrue);
    });
  });

  group('DraftCourse 解析模型输出', () {
    test('标准 sessions 结构', () {
      final d = DraftCourse.fromAiJson({
        'name': '高等数学',
        'teacher': '张老师',
        'sessions': [
          {'dayOfWeek': 1, 'startPeriod': 1, 'endPeriod': 2, 'weeks': [1, 2, 3]},
        ],
      }, defaultWeeks: [1, 2, 3]);
      expect(d.name, '高等数学');
      expect(d.teacher, '张老师');
      expect(d.sessions.length, 1);
      expect(d.sessions.single.dayOfWeek, 1);
      expect(d.isValid, isTrue);
    });

    test('中文星期写法', () {
      final d = DraftCourse.fromAiJson({
        'name': '英语',
        'sessions': [
          {'dayOfWeek': '周三', 'startPeriod': 5, 'endPeriod': 6},
        ],
      }, defaultWeeks: [1, 2]);
      expect(d.sessions.single.dayOfWeek, 3);
    });

    test('缺省周次时回退到 defaultWeeks 并保留告警机制', () {
      final d = DraftCourse.fromAiJson({
        'name': '物理',
        'sessions': [
          {'dayOfWeek': 2, 'startPeriod': 3, 'endPeriod': 4},
        ],
      }, defaultWeeks: [1, 2, 3, 4, 5]);
      expect(d.sessions.single.weeks, [1, 2, 3, 4, 5]);
    });

    test('weekRange 字符串被解析成显式周次', () {
      final d = DraftCourse.fromAiJson({
        'name': '化学',
        'sessions': [
          {
            'dayOfWeek': 4,
            'startPeriod': 1,
            'endPeriod': 2,
            'weekRange': '1-8周(单)',
          },
        ],
      });
      expect(d.sessions.single.weeks, [1, 3, 5, 7]);
    });

    test('无效时段被丢弃并记录告警', () {
      final d = DraftCourse.fromAiJson({
        'name': '体育',
        'sessions': [
          {'dayOfWeek': 9, 'startPeriod': 1, 'endPeriod': 2},
        ],
      });
      expect(d.sessions, isEmpty);
      expect(d.warnings, isNotEmpty);
    });

    test('缺课程名时告警', () {
      final d = DraftCourse.fromAiJson({
        'sessions': [
          {'dayOfWeek': 1, 'startPeriod': 1, 'endPeriod': 2, 'weeks': [1]},
        ],
      });
      expect(d.name, isEmpty);
      expect(d.warnings.any((w) => w.contains('课程名')), isTrue);
      expect(d.isValid, isFalse);
    });
  });

  group('draftToCourse 转换', () {
    test('草稿转真实课程', () {
      const draft = DraftCourse(
        name: '高等数学',
        teacher: '张老师',
        sessions: [
          DraftSession(
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: [1, 2, 3],
            location: 'A101',
          ),
        ],
      );
      final course = draftToCourse(draft, 'sem1', colorIndex: 3);
      expect(course.name, '高等数学');
      expect(course.semesterId, 'sem1');
      expect(course.colorIndex, 3);
      expect(course.sessions.length, 1);
      expect(course.sessions.single.location, 'A101');
      expect(course.id, isNotEmpty);
    });
  });

  group('模型 JSON 往返', () {
    test('Timetable 序列化后可还原', () {
      final t = Timetable(
        semester: Semester(
          id: 's1',
          name: '测试学期',
          startMonday: DateTime(2026, 2, 23),
          totalWeeks: 16,
        ),
        timeSlots: defaultTimeSlots(),
        courses: [
          Course(
            id: 'c1',
            semesterId: 's1',
            name: '高等数学',
            teacher: '张老师',
            colorIndex: 2,
            sessions: const [
              Session(
                id: 'ss1',
                dayOfWeek: 1,
                startPeriod: 1,
                endPeriod: 2,
                weeks: [1, 3, 5],
                location: 'A101',
              ),
            ],
          ),
        ],
      );

      final back = Timetable.fromJson(t.toJson());
      expect(back.semester.name, '测试学期');
      expect(back.semester.totalWeeks, 16);
      expect(back.courses.length, 1);
      expect(back.courses.single.name, '高等数学');
      expect(back.courses.single.colorIndex, 2);
      expect(back.courses.single.sessions.single.weeks, [1, 3, 5]);
      expect(back.courses.single.sessions.single.location, 'A101');
    });

    test('Course 序列化往返', () {
      const c = Course(
        id: 'c1',
        semesterId: 's1',
        name: '英语',
        teacher: '李老师',
        credit: 3.5,
        colorIndex: 1,
        sessions: [
          Session(
            id: 'ss1',
            dayOfWeek: 3,
            startPeriod: 5,
            endPeriod: 6,
            weeks: [1, 2, 3],
          ),
        ],
      );
      final back = Course.fromJson(c.toJson());
      expect(back.credit, 3.5);
      expect(back.teacher, '李老师');
      expect(back.sessions.single.endPeriod, 6);
    });
  });

  group('Session 语义', () {
    test('span 计算跨节数', () {
      const s = Session(
        id: 'x',
        dayOfWeek: 1,
        startPeriod: 3,
        endPeriod: 6,
        weeks: [1],
      );
      expect(s.span, 4);
    });

    test('describe 输出可读文本', () {
      const s = Session(
        id: 'x',
        dayOfWeek: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: [1, 3, 5],
        location: 'A101',
      );
      expect(s.describe(), contains('周一'));
      expect(s.describe(), contains('1-2'));
      expect(s.describe(), contains('A101'));
    });
  });
}

