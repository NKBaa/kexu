import 'package:course_timetable/data/models/ai_ops.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/services/ai_apply_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一份可预测的测试课表。
Timetable buildTimetable() {
  return Timetable(
    semester: Semester(
      id: 'sem1',
      name: '2026 春季学期',
      startMonday: DateTime(2026, 2, 23),
      totalWeeks: 16,
    ),
    timeSlots: defaultTimeSlots(),
    courses: [
      Course(
        id: 'c1',
        semesterId: 'sem1',
        name: '高等数学',
        teacher: '张老师',
        colorIndex: 0,
        sessions: const [
          Session(
            id: 's1',
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: [1, 2, 3, 4],
            location: 'A101',
          ),
        ],
      ),
      Course(
        id: 'c2',
        semesterId: 'sem1',
        name: '大学英语',
        teacher: '李老师',
        colorIndex: 1,
        sessions: const [
          Session(
            id: 's2',
            dayOfWeek: 3,
            startPeriod: 5,
            endPeriod: 6,
            weeks: [1, 2, 3, 4],
          ),
        ],
      ),
    ],
  );
}

AiOp op(AiOpKind kind, String courseName, [Map<String, dynamic> args = const {}]) =>
    AiOp(kind: kind, courseName: courseName, args: args);

void main() {
  const service = AiApplyService();

  group('删除课程', () {
    test('按名称删除命中', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [op(AiOpKind.deleteCourse, '大学英语')]),
      );
      expect(report.appliedCount, 1);
      expect(report.timetable.courses.length, 1);
      expect(report.timetable.courses.first.name, '高等数学');
    });

    test('课程不存在时跳过并给出原因', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [op(AiOpKind.deleteCourse, '不存在的课')]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedCount, 1);
      expect(report.skippedDetails.first, contains('找不到课程'));
      expect(report.timetable.courses.length, 2);
    });
  });

  group('新增课程', () {
    test('带 sessions 数组时正常新增', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.addCourse,
            courseName: '线性代数',
            args: {
              'teacher': '王老师',
              'sessions': [
                {'dayOfWeek': 2, 'startPeriod': 3, 'endPeriod': 4, 'weeks': [1, 2, 3]},
              ],
            },
          ),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(report.timetable.courses.length, 3);
      final added = report.timetable.courses.last;
      expect(added.name, '线性代数');
      expect(added.sessions.single.dayOfWeek, 2);
      expect(added.sessions.single.startPeriod, 3);
    });

    test('用扁平 day/period 字段也能新增', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.addCourse,
            courseName: '物理',
            args: {'dayOfWeek': '周四', 'startPeriod': 7, 'endPeriod': 8},
          ),
        ]),
      );
      expect(report.appliedCount, 1);
      final added = report.timetable.courses.last;
      expect(added.sessions.single.dayOfWeek, 4);
      expect(added.sessions.single.startPeriod, 7);
    });

    test('新增时自动分配不冲突的颜色', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.addCourse,
            courseName: '新课程',
            args: {'sessions': [{'dayOfWeek': 5, 'startPeriod': 1, 'endPeriod': 2}]},
          ),
        ]),
      );
      final added = report.timetable.courses.last;
      expect(added.colorIndex, isNot(0));
      expect(added.colorIndex, isNot(1));
    });

    test('缺少课程名时拒绝', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [const AiOp(kind: AiOpKind.addCourse, courseName: '')]),
      );
      expect(report.appliedCount, 0);
    });
  });

  group('修改时段（不规律周次）', () {
    test('把整门课改成单周上课', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.updateSession,
            courseName: '高等数学',
            args: {
              'weeks': [1, 3, 5, 7],
            },
          ),
        ]),
      );
      expect(report.appliedCount, 1);
      final course = report.timetable.courses.firstWhere((c) => c.name == '高等数学');
      expect(course.sessions.single.weeks, [1, 3, 5, 7]);
    });

    test('只改地点', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.updateSession,
            courseName: '高等数学',
            args: {'location': 'B203'},
          ),
        ]),
      );
      final course = report.timetable.courses.firstWhere((c) => c.name == '高等数学');
      expect(course.sessions.single.location, 'B203');
      // 其他字段不变
      expect(course.sessions.single.dayOfWeek, 1);
      expect(course.sessions.single.weeks, [1, 2, 3, 4]);
    });

    test('调课：星期与节次一起改', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.moveSession,
            courseName: '大学英语',
            args: {'dayOfWeek': 5, 'startPeriod': 7, 'endPeriod': 8},
          ),
        ]),
      );
      final course = report.timetable.courses.firstWhere((c) => c.name == '大学英语');
      expect(course.sessions.single.dayOfWeek, 5);
      expect(course.sessions.single.startPeriod, 7);
      expect(course.sessions.single.endPeriod, 8);
      expect(course.sessions.single.weeks, [1, 2, 3, 4]);
    });

    test('没有任何可识别字段时跳过', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updateSession, '高等数学', const {'unrelated': 'x'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('可识别的修改字段'));
    });
  });

  group('时段增删', () {
    test('新增时段到已有课程', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.addSession,
            courseName: '高等数学',
            args: {'dayOfWeek': 3, 'startPeriod': 5, 'endPeriod': 6, 'weeks': [1, 2]},
          ),
        ]),
      );
      final course = report.timetable.courses.firstWhere((c) => c.name == '高等数学');
      expect(course.sessions.length, 2);
    });

    test('按星期精确删除时段', () {
      final t = buildTimetable();
      // 先加一个时段，再删掉周一那个
      final withExtra = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.addSession,
            courseName: '高等数学',
            args: {'dayOfWeek': 3, 'startPeriod': 5, 'endPeriod': 6},
          ),
        ]),
      ).timetable;

      final report = service.apply(
        withExtra,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.deleteSession,
            courseName: '高等数学',
            args: {'dayOfWeek': 1},
          ),
        ]),
      );
      final course = report.timetable.courses.firstWhere((c) => c.name == '高等数学');
      expect(course.sessions.length, 1);
      expect(course.sessions.single.dayOfWeek, 3);
    });
  });

  group('修改课程元信息', () {
    test('改教师', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.updateCourse,
            courseName: '高等数学',
            args: {'teacher': '赵老师'},
          ),
        ]),
      );
      final course = report.timetable.courses.firstWhere((c) => c.name == '高等数学');
      expect(course.teacher, '赵老师');
    });

    test('改课程名', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          AiOp(
            kind: AiOpKind.updateCourse,
            courseName: '高等数学',
            args: {'newName': '高等数学（上）'},
          ),
        ]),
      );
      expect(
        report.timetable.courses.any((c) => c.name == '高等数学（上）'),
        isTrue,
      );
    });
  });

  group('多操作与整体一致性', () {
    test('多条操作按顺序全部应用', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.deleteCourse, '大学英语'),
          AiOp(
            kind: AiOpKind.updateSession,
            courseName: '高等数学',
            args: {'weeks': [2, 4, 6]},
          ),
        ]),
      );
      expect(report.appliedCount, 2);
      expect(report.timetable.courses.length, 1);
      expect(report.timetable.courses.single.sessions.single.weeks, [2, 4, 6]);
    });

    test('单条失败不影响后续操作', () {
      final t = buildTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.deleteCourse, '不存在'),
          op(AiOpKind.deleteCourse, '大学英语'),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(report.skippedCount, 1);
      expect(report.timetable.courses.length, 1);
    });

    test('应用不会修改原始课表（纯函数）', () {
      final t = buildTimetable();
      service.apply(t, AiEditPlan(ops: [op(AiOpKind.deleteCourse, '大学英语')]));
      expect(t.courses.length, 2, reason: '输入课表应保持不变');
    });

    test('空计划返回原课表且摘要友好', () {
      final t = buildTimetable();
      final report = service.apply(t, const AiEditPlan());
      expect(report.timetable.courses.length, 2);
      expect(report.summary, contains('没有需要执行的改动'));
    });
  });

  group('AiEditPlan 解析容错', () {
    test('从模型 JSON 解析操作列表', () {
      final plan = AiEditPlan.fromAiJson({
        'summary': '已理解',
        'ops': [
          {'kind': 'deleteCourse', 'courseName': '大学英语'},
          {'type': 'updateSession', 'course': '高等数学', 'args': {'weeks': '1-8单'}},
        ],
      });
      expect(plan.ops.length, 2);
      expect(plan.ops[0].kind, AiOpKind.deleteCourse);
      expect(plan.ops[1].kind, AiOpKind.updateSession);
      expect(plan.ops[1].weeks, [1, 3, 5, 7]);
    });

    test('未知操作被丢弃并记录告警', () {
      final plan = AiEditPlan.fromAiJson({
        'ops': [
          {'kind': 'explode', 'courseName': 'x'},
          {'kind': 'deleteCourse', 'courseName': '大学英语'},
        ],
      });
      expect(plan.ops.length, 1);
      expect(plan.warnings, isNotEmpty);
    });

    test('缺少课程名的非新增操作被丢弃', () {
      final plan = AiEditPlan.fromAiJson({
        'ops': [
          {'kind': 'deleteCourse'},
        ],
      });
      expect(plan.ops, isEmpty);
      expect(plan.warnings, isNotEmpty);
    });
  });
}
