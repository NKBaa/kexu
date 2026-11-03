import 'package:course_timetable/data/models/bell_schedule.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/ai_message.dart';
import 'package:course_timetable/features/ai/now_context.dart';
import 'package:course_timetable/features/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

Semester semester({int totalWeeks = 16}) => Semester(
      id: 's1',
      name: '2025 秋季学期',
      startMonday: DateTime(2025, 9, 1),
      totalWeeks: totalWeeks,
    );

Timetable twoCourseTimetable() => Timetable(
      semester: semester(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          teacher: '张三',
          credit: 4,
          courseCode: 'MATH101',
          note: '带计算器',
          sessions: [
            Session(
              id: 'ss1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: List.generate(16, (i) => i + 1),
              location: 'A101',
            ),
            Session(
              id: 'ss2',
              dayOfWeek: 3,
              startPeriod: 3,
              endPeriod: 4,
              weeks: [1, 3, 5, 7, 9, 11, 13, 15],
              location: 'B202',
            ),
          ],
          adjustments: [
            Adjustment(
              id: 'a1',
              type: AdjustmentType.cancel,
              fromDate: DateTime(2025, 10, 6),
              note: '国庆放假',
            ),
          ],
        ),
        Course(
          id: 'c2',
          semesterId: 's1',
          name: '大学英语',
          teacher: '李四',
          sessions: [
            Session(
              id: 'ss3',
              dayOfWeek: 5,
              startPeriod: 5,
              endPeriod: 6,
              weeks: [2, 4, 6, 8],
            ),
          ],
        ),
      ],
      timeSlots: defaultTimeSlots(),
    );

void main() {
  group('buildTimetableContext', () {
    test('包含学期信息与课程/时段摘要', () {
      final ctx = buildTimetableContext(twoCourseTimetable());
      expect(ctx, contains('2025 秋季学期'));
      expect(ctx, contains('共 16 周'));
      expect(ctx, contains('2025-09-01'));
      expect(ctx, contains('课程数：2'));
      expect(ctx, contains('时段总数：3'));
      expect(ctx, contains('高等数学'));
      expect(ctx, contains('张三'));
      expect(ctx, contains('4 学分'));
      expect(ctx, contains('编号 MATH101'));
      expect(ctx, contains('周一'));
      expect(ctx, contains('第1-2节'));
      expect(ctx, contains('1-16周'));
      expect(ctx, contains('@A101'));
      expect(ctx, contains('1-15周(单)'));
      expect(ctx, contains('@B202'));
      expect(ctx, contains('大学英语'));
      expect(ctx, contains('2-8周(双)'));
      expect(ctx, contains('备注：带计算器'));
      expect(ctx, contains('调整：停课'));
      expect(ctx, contains('国庆放假'));
    });

    test('空课表给出明确说明', () {
      final ctx = buildTimetableContext(Timetable(semester: semester()));
      expect(ctx, contains('2025 秋季学期'));
      expect(ctx, contains('当前课表为空'));
      expect(ctx, isNot(contains('课程数')));
    });

    test('课程过多时截断并注明省略数量', () {
      final courses = List.generate(
        90,
        (i) => Course(
          id: 'c$i',
          semesterId: 's1',
          name: '课程$i',
          sessions: [
            Session(
              id: 's$i',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1],
            ),
          ],
        ),
      );
      final ctx = buildTimetableContext(
        Timetable(semester: semester(), courses: courses),
      );
      expect(ctx, contains('课程数：90'));
      expect(ctx, contains('课程79'));
      expect(ctx, isNot(contains('课程80')));
      expect(ctx, contains('其余 10 门课程已省略'));
    });

    test('课程没有时段时明确说明', () {
      final t = Timetable(
        semester: semester(),
        courses: const [
          Course(id: 'c1', semesterId: 's1', name: '待排课'),
        ],
      );
      expect(buildTimetableContext(t), contains('暂无上课时段'));
    });

    test('多行备注被压成一行，避免破坏提示词结构', () {
      final t = Timetable(
        semester: semester(),
        courses: [
          Course(
            id: 'c1',
            semesterId: 's1',
            name: '课程A',
            note: '第一行\n第二行',
            sessions: const [
              Session(id: 's', dayOfWeek: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
            ],
          ),
        ],
      );
      final ctx = buildTimetableContext(t);
      expect(ctx, contains('备注：第一行 第二行'));
      expect(ctx, isNot(contains('第一行\n第二行')));
    });

    test('包含作息方案与各节起止时间', () {
      final ctx = buildTimetableContext(twoCourseTimetable());
      expect(ctx, contains('作息方案'));
      expect(ctx, contains('默认作息'));
      expect(ctx, contains('当前生效'));
      expect(ctx, contains('第1节 08:00-08:45'));
      expect(ctx, contains('第12节 21:45-22:30'));
    });

    test('多套作息都列出，并标注生效区间', () {
      final t = Timetable(
        semester: semester(),
        schedules: [
          BellSchedule(id: 'default', name: '默认作息', slots: defaultTimeSlots()),
          BellSchedule(
            id: 'summer',
            name: '夏季作息',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 9, 30),
            slots: const [TimeSlot(period: 1, start: '08:00', end: '08:45')],
          ),
        ],
      );
      final ctx = buildTimetableContext(t);
      expect(ctx, contains('共 2 套'));
      expect(ctx, contains('夏季作息'));
      expect(ctx, contains('05-01 ~ 09-30'));
      expect(ctx, contains('不限日期'));
    });
  });

  group('buildImageToTimetablePrompt', () {
    test('包含输出契约、总周数与关键约束', () {
      final p = buildImageToTimetablePrompt(totalWeeks: 18);
      expect(p, contains('JSON'));
      expect(p, contains('courses'));
      expect(p, contains('sessions'));
      expect(p, contains('dayOfWeek'));
      expect(p, contains('startPeriod'));
      expect(p, contains('endPeriod'));
      expect(p, contains('weeks'));
      expect(p, contains('1~18'));
      expect(p, contains('单周'));
      expect(p, contains('双周'));
      expect(p, contains('不要编造'));
      expect(p, contains('note'));
    });

    test('补充说明被带入提示词', () {
      final p = buildImageToTimetablePrompt(
        totalWeeks: 16,
        extraHint: '第 1 周从 9 月 1 日开始',
      );
      expect(p, contains('第 1 周从 9 月 1 日开始'));
    });

    test('空补充说明不会产生空段落', () {
      final p = buildImageToTimetablePrompt(totalWeeks: 16, extraHint: '   ');
      expect(p, isNot(contains('用户补充说明')));
    });

    test('总周数非法时回退为 16', () {
      final p = buildImageToTimetablePrompt(totalWeeks: 0);
      expect(p, contains('1~16'));
    });
  });

  group('buildNlEditPrompt', () {
    test('包含课表上下文、用户指令与操作类型说明', () {
      final p = buildNlEditPrompt(
        instruction: '把高数改成单周',
        current: twoCourseTimetable(),
      );
      expect(p, contains('把高数改成单周'));
      expect(p, contains('高等数学'));
      expect(p, contains('当前课表'));
      for (final kind in [
        'addCourse',
        'updateCourse',
        'deleteCourse',
        'addSession',
        'updateSession',
        'deleteSession',
        'moveSession',
      ]) {
        expect(p, contains(kind), reason: '提示词缺少操作类型 $kind');
      }
      expect(p, contains('match'));
      expect(p, contains('patch'));
      expect(p, contains('ops'));
      expect(p, contains('1~16'));
      // 新契约：优先使用课表里的规范全名，允许用户用简称/错别字。
      expect(p, contains('规范全名'));
      expect(p, isNot(contains('必须与这里完全一致')));
    });

    test('注入「现在」的时间上下文', () {
      final now = NowContext.fromTimetable(
        twoCourseTimetable(),
        now: DateTime(2025, 9, 17, 14, 30),
      );
      final p = buildNlEditPrompt(
        instruction: '把明天的课挪到下周',
        current: twoCourseTimetable(),
        now: now,
      );
      expect(p, contains('现在的时间上下文'));
      expect(p, contains('2025-09-17 14:30（周三）'));
      expect(p, contains('当前教学周：第 3 周'));
      expect(p, contains('下一教学周：第 4 周'));
      expect(p, contains('今天各节次时间'));
    });

    test('相对时间换算规则写入提示词', () {
      final p = buildNlEditPrompt(
        instruction: '把明天的课挪到下周',
        current: twoCourseTimetable(),
      );
      for (final keyword in [
        '今天/明天/后天/大后天',
        '本周X',
        '下周X',
        '周日一律用 7',
        '跨周',
        '上午',
        '下午',
        '晚上',
        '超出学期范围',
      ]) {
        expect(p, contains(keyword), reason: '提示词缺少时间规则：$keyword');
      }
    });

    test('白话容错与反问契约写入提示词', () {
      final p = buildNlEditPrompt(
        instruction: '高数改成单双周都上',
        current: twoCourseTimetable(),
      );
      expect(p, contains('白话'));
      expect(p, contains('简称'));
      expect(p, contains('错别字'));
      expect(p, contains('不要为了反问而反问'));
      expect(p, contains('"ask"'));
      expect(p, contains('"options"'));
      expect(p, contains('模糊指令 → 合理操作或反问'));
    });

    test('多轮对话时提示结合历史，但不重复历史正文', () {
      final p = buildNlEditPrompt(
        instruction: '就改高等数学',
        current: twoCourseTimetable(),
        history: const [
          AiChatMessage.user('把高数改成单周'),
          AiChatMessage.assistant('{"ask":"HISTORY-ONLY-TOKEN","options":[],"ops":[]}'),
        ],
      );
      expect(p, contains('多轮对话'));
      expect(p, contains('结合历史'));
      // 历史正文只作为独立 message 发送，不重复拼进 prompt 文本。
      expect(p, isNot(contains('HISTORY-ONLY-TOKEN')));
    });

    test('未传 now 时也能正常生成提示词', () {
      final p = buildNlEditPrompt(
        instruction: '删除大学英语',
        current: twoCourseTimetable(),
      );
      expect(p, contains('删除大学英语'));
      expect(p, isNot(contains('现在的时间上下文')));
    });

    test('包含作息类操作（updatePeriod / shiftSchedule）说明', () {
      final p = buildNlEditPrompt(
        instruction: '第3节改成10:05上课',
        current: twoCourseTimetable(),
      );
      for (final kind in ['updatePeriod', 'shiftSchedule']) {
        expect(p, contains(kind), reason: '提示词缺少操作类型 $kind');
      }
      expect(p, contains('scheduleName'));
      expect(p, contains('不需要 courseName'));
      expect(p, contains('作息时间 vs 课程时间的区分'));
      expect(p, contains('第 3 节改成 10:05 上课'));
      expect(p, contains('整体推迟 10 分钟'));
    });
  });
}
