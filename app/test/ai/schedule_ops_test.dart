import 'package:course_timetable/data/models/ai_ops.dart';
import 'package:course_timetable/data/models/bell_schedule.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/services/ai_apply_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 作息类操作（updatePeriod / shiftSchedule）的应用测试。
///
/// 这些用例集中放这里，避免 ai_apply_service_test.dart（课程操作）过长。
Semester _semester() => Semester(
      id: 'sem1',
      name: '2026 春季学期',
      startMonday: DateTime(2026, 2, 23),
      totalWeeks: 16,
    );

/// 只有一套作息（默认 12 节）。
Timetable singleScheduleTimetable() => Timetable(
      semester: _semester(),
      schedules: [
        BellSchedule(
          id: 'default',
          name: '默认作息',
          slots: defaultTimeSlots(),
        ),
      ],
    );

/// 两套作息：常驻「默认作息」+ 限定日期的「夏季作息」。
Timetable multiScheduleTimetable() => Timetable(
      semester: _semester(),
      schedules: [
        BellSchedule(
          id: 'default',
          name: '默认作息',
          slots: defaultTimeSlots(),
        ),
        BellSchedule(
          id: 'summer',
          name: '夏季作息',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 9, 30),
          slots: const [
            TimeSlot(period: 1, start: '08:00', end: '08:45'),
            TimeSlot(period: 5, start: '14:30', end: '15:15'),
          ],
        ),
      ],
    );

/// 晚课作息：平移会跨过 00:00。
Timetable lateScheduleTimetable() => Timetable(
      semester: _semester(),
      schedules: [
        BellSchedule(
          id: 'night',
          name: '晚课作息',
          slots: const [
            TimeSlot(period: 1, start: '23:30', end: '23:50'),
            TimeSlot(period: 2, start: '23:55', end: '23:59'),
          ],
        ),
      ],
    );

AiOp op(AiOpKind kind, [Map<String, dynamic> args = const {}]) =>
    AiOp(kind: kind, courseName: '', args: args);

TimeSlot slotOf(Timetable t, int period, {String scheduleId = 'default'}) {
  final schedule = t.schedules.firstWhere((s) => s.id == scheduleId);
  return schedule.slots.firstWhere((s) => s.period == period);
}

void main() {
  const service = AiApplyService();

  group('normalizeTime 时间规范化', () {
    test('常见写法都能规范成 HH:mm', () {
      expect(AiApplyService.normalizeTime('8:10'), '08:10');
      expect(AiApplyService.normalizeTime('08:10'), '08:10');
      expect(AiApplyService.normalizeTime('8：10'), '08:10'); // 全角冒号
      expect(AiApplyService.normalizeTime('8点10分'), '08:10');
      expect(AiApplyService.normalizeTime('8点'), '08:00');
      expect(AiApplyService.normalizeTime(' 9:05 '), '09:05');
      expect(AiApplyService.normalizeTime('08:10:00'), '08:10'); // 忽略秒
      expect(AiApplyService.normalizeTime('14'), '14:00'); // 只给整点
      expect(AiApplyService.normalizeTime('０８：１０'), '08:10'); // 全角数字
    });

    test('非法写法返回 null', () {
      expect(AiApplyService.normalizeTime(null), isNull);
      expect(AiApplyService.normalizeTime(''), isNull);
      expect(AiApplyService.normalizeTime('   '), isNull);
      expect(AiApplyService.normalizeTime('abc'), isNull);
      expect(AiApplyService.normalizeTime('25:00'), isNull);
      expect(AiApplyService.normalizeTime('8:70'), isNull);
      expect(AiApplyService.normalizeTime('第3节'), isNull);
    });
  });

  group('updatePeriod 修改某一节作息时间', () {
    test('同时改开始与结束时间，且不影响其他节', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '10:05', 'endTime': '10:50'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 3).label, '10:05-10:50');
      // 其他节原样保留
      expect(slotOf(report.timetable, 1).label, '08:00-08:45');
      expect(slotOf(report.timetable, 2).label, '08:55-09:40');
      expect(slotOf(report.timetable, 4).label, '10:55-11:40');
      expect(report.timetable.schedules.single.slots.length, 12);
    });

    test('只改开始时间时保留原结束时间', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '10:05'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 3).label, '10:05-10:45');
    });

    test('只改结束时间时保留原开始时间', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'endTime': '10:50'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 3).label, '10:00-10:50');
    });

    test('支持口语时间写法（8点10分）', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 1, 'startTime': '8点10分', 'endTime': '8点55分'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 1).label, '08:10-08:55');
    });

    test('指定方案名时只改该方案', () {
      final t = multiScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {
            'period': 5,
            'startTime': '14:40',
            'scheduleName': '夏季作息',
          }),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 5, scheduleId: 'summer').label, '14:40-15:15');
      // 默认作息的第 5 节不受影响
      expect(slotOf(report.timetable, 5).label, '14:00-14:45');
      expect(report.timetable.schedules.length, 2);
    });

    test('方案名支持包含匹配（「夏季」→「夏季作息」）', () {
      final t = multiScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 5, 'startTime': '14:40', 'scheduleName': '夏季'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 5, scheduleId: 'summer').label, '14:40-15:15');
    });

    test('未指定方案名且有多套时，改当前生效的那套', () {
      final t = multiScheduleTimetable();
      final active = t.activeSchedule;
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 1, 'startTime': '08:10'}),
        ]),
      );
      expect(report.appliedCount, 1);
      final changed = report.timetable.schedules.firstWhere((s) => s.id == active.id);
      expect(changed.slots.first.label, '08:10-08:45');
    });

    test('未知节次跳过并说明', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 99, 'startTime': '10:05'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('没有第99节'));
      expect(report.timetable.schedules.single.slots.length, 12);
    });

    test('非法时间跳过并说明', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '十点零五'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('无法识别的时间'));
    });

    test('开始时间不早于结束时间时跳过', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '11:00', 'endTime': '10:00'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('开始时间必须早于结束时间'));
      expect(slotOf(report.timetable, 3).label, '10:00-10:45');
    });

    test('缺少节次时跳过', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'startTime': '10:05'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('缺少要修改的节次'));
    });

    test('既没给开始也没给结束时间时跳过', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('没有说明第3节要改成什么时间'));
    });

    test('指定了不存在的方案名时跳过并说明', () {
      final t = multiScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 1, 'startTime': '08:10', 'scheduleName': '秋季作息'}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('找不到作息方案「秋季作息」'));
    });

    test('detail 文案可读', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '10:05', 'endTime': '10:50'}),
        ]),
      );
      expect(report.appliedDetails.single, '已把「默认作息」第3节改为 10:05-10:50');
    });

    test('纯函数：不修改传入的课表', () {
      final t = singleScheduleTimetable();
      service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.updatePeriod, {'period': 3, 'startTime': '10:05'}),
        ]),
      );
      expect(slotOf(t, 3).label, '10:00-10:45');
    });
  });

  group('shiftSchedule 整体平移作息', () {
    test('推迟 10 分钟：所有节次平移且节次顺序不变', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10}),
        ]),
      );
      expect(report.appliedCount, 1);
      final slots = report.timetable.schedules.single.slots;
      expect(slots.map((s) => s.period).toList(), List.generate(12, (i) => i + 1));
      expect(slots.first.label, '08:10-08:55');
      expect(slots[1].label, '09:05-09:50');
      expect(slots.last.label, '21:55-22:40');
    });

    test('提前 10 分钟', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': -10}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 1).label, '07:50-08:35');
    });

    test('「提前10分钟」这种口语写法也识别为负数', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': '提前10分钟'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 1).label, '07:50-08:35');
    });

    test('指定方案名时只平移该方案', () {
      final t = multiScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10, 'scheduleName': '夏季作息'}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 5, scheduleId: 'summer').label, '14:40-15:25');
      expect(slotOf(report.timetable, 5).label, '14:00-14:45');
    });

    test('平移跨过 00:00 时跳过整套调整并说明', () {
      final t = lateScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10}),
        ]),
      );
      expect(report.appliedCount, 0);
      expect(report.skippedDetails.first, contains('跨过 00:00'));
      // 课表保持原样
      expect(slotOf(report.timetable, 1, scheduleId: 'night').label, '23:30-23:50');
      expect(slotOf(report.timetable, 2, scheduleId: 'night').label, '23:55-23:59');
    });

    test('缺少分钟数或为 0 时跳过', () {
      final t = singleScheduleTimetable();
      for (final args in <Map<String, dynamic>>[{}, {'minutes': 0}]) {
        final report = service.apply(t, AiEditPlan(ops: [op(AiOpKind.shiftSchedule, args)]));
        expect(report.appliedCount, 0);
        expect(report.skippedDetails.first, contains('缺少要平移的分钟数'));
      }
    });

    test('detail 文案区分推迟与提前', () {
      final t = singleScheduleTimetable();
      final later = service.apply(
        t,
        AiEditPlan(ops: [op(AiOpKind.shiftSchedule, {'minutes': 10})]),
      );
      expect(later.appliedDetails.single, '已把「默认作息」整体推迟 10 分钟');

      final earlier = service.apply(
        t,
        AiEditPlan(ops: [op(AiOpKind.shiftSchedule, {'minutes': -5})]),
      );
      expect(earlier.appliedDetails.single, '已把「默认作息」整体提前 5 分钟');
    });

    test('指定节次范围时只平移范围内的节次（下午的课推迟）', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10, 'fromPeriod': 5, 'toPeriod': 8}),
        ]),
      );
      expect(report.appliedCount, 1);
      // 上午不动
      expect(slotOf(report.timetable, 1).label, '08:00-08:45');
      expect(slotOf(report.timetable, 4).label, '10:55-11:40');
      // 第 5-8 节整体推迟 10 分钟
      expect(slotOf(report.timetable, 5).label, '14:10-14:55');
      expect(slotOf(report.timetable, 8).label, '17:05-17:50');
      // 晚上不动
      expect(slotOf(report.timetable, 9).label, '19:00-19:45');
      expect(report.appliedDetails.single, '已把「默认作息」第5-8节推迟 10 分钟');
    });

    test('只给起始节次时平移该节及以后', () {
      final t = singleScheduleTimetable();
      final report = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 5, 'fromPeriod': 9}),
        ]),
      );
      expect(report.appliedCount, 1);
      expect(slotOf(report.timetable, 8).label, '16:55-17:40');
      expect(slotOf(report.timetable, 9).label, '19:05-19:50');
      expect(report.appliedDetails.single, '已把「默认作息」第9节及以后推迟 5 分钟');
    });

    test('节次范围不合法或范围内没有节次时跳过', () {
      final t = singleScheduleTimetable();
      final invalid = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10, 'fromPeriod': 8, 'toPeriod': 5}),
        ]),
      );
      expect(invalid.appliedCount, 0);
      expect(invalid.skippedDetails.first, contains('节次范围不合法'));

      final empty = service.apply(
        t,
        AiEditPlan(ops: [
          op(AiOpKind.shiftSchedule, {'minutes': 10, 'fromPeriod': 20, 'toPeriod': 22}),
        ]),
      );
      expect(empty.appliedCount, 0);
      expect(empty.skippedDetails.first, contains('没有第20-22节'));
    });
  });

  group('AiOpKind 别名与标签', () {
    test('updatePeriod 的别名', () {
      for (final s in ['updatePeriod', 'update_period', '修改作息', '修改节次时间']) {
        expect(aiOpKindFromString(s), AiOpKind.updatePeriod, reason: s);
      }
    });

    test('shiftSchedule 的别名', () {
      for (final s in ['shiftSchedule', 'shift_schedule', '调整作息', '整体平移']) {
        expect(aiOpKindFromString(s), AiOpKind.shiftSchedule, reason: s);
      }
    });

    test('中文标签', () {
      expect(aiOpKindLabel(AiOpKind.updatePeriod), '修改作息时间');
      expect(aiOpKindLabel(AiOpKind.shiftSchedule), '整体调整作息');
    });
  });

  group('AiOp 作息参数 getter', () {
    test('period 兼容 period / section / 节次', () {
      expect(op(AiOpKind.updatePeriod, {'period': 3}).period, 3);
      expect(op(AiOpKind.updatePeriod, {'section': '5'}).period, 5);
      expect(op(AiOpKind.updatePeriod, {'节次': 7}).period, 7);
      expect(op(AiOpKind.updatePeriod, const {}).period, isNull);
    });

    test('scheduleName 兼容中英文别名', () {
      expect(op(AiOpKind.updatePeriod, {'scheduleName': '夏季作息'}).scheduleName, '夏季作息');
      expect(op(AiOpKind.updatePeriod, {'schedule': '冬季作息'}).scheduleName, '冬季作息');
      expect(op(AiOpKind.updatePeriod, {'作息': '夏季作息'}).scheduleName, '夏季作息');
      expect(op(AiOpKind.updatePeriod, {'方案': '默认作息'}).scheduleName, '默认作息');
      expect(op(AiOpKind.updatePeriod, const {}).scheduleName, isNull);
    });

    test('startTime 只采纳明显是时间的写法', () {
      expect(op(AiOpKind.updatePeriod, {'startTime': '10:05'}).startTime, '10:05');
      expect(op(AiOpKind.updatePeriod, {'start': '8:10'}).startTime, '8:10');
      expect(op(AiOpKind.updatePeriod, {'开始时间': '8点10分'}).startTime, '8点10分');
      // start 是数字节次，不能当时间
      expect(op(AiOpKind.updatePeriod, {'start': 3}).startTime, isNull);
    });

    test('endTime 同样区分节次与时间', () {
      expect(op(AiOpKind.updatePeriod, {'endTime': '10:50'}).endTime, '10:50');
      expect(op(AiOpKind.updatePeriod, {'结束时间': '10点50分'}).endTime, '10点50分');
      expect(op(AiOpKind.updatePeriod, {'end': 4}).endTime, isNull);
    });

    test('shiftMinutes 兼容正负号与口语', () {
      expect(op(AiOpKind.shiftSchedule, {'minutes': 10}).shiftMinutes, 10);
      expect(op(AiOpKind.shiftSchedule, {'minutes': -10}).shiftMinutes, -10);
      expect(op(AiOpKind.shiftSchedule, {'minutes': '-10'}).shiftMinutes, -10);
      expect(op(AiOpKind.shiftSchedule, {'minutes': '提前10分钟'}).shiftMinutes, -10);
      expect(op(AiOpKind.shiftSchedule, {'shiftMinutes': 15}).shiftMinutes, 15);
      expect(op(AiOpKind.shiftSchedule, {'分钟': 20}).shiftMinutes, 20);
      expect(op(AiOpKind.shiftSchedule, {'偏移分钟': 25}).shiftMinutes, 25);
      expect(op(AiOpKind.shiftSchedule, {'minutes': 10, 'direction': 'earlier'}).shiftMinutes, -10);
      expect(op(AiOpKind.shiftSchedule, const {}).shiftMinutes, isNull);
    });

    test('fromPeriod / toPeriod 兼容别名', () {
      expect(
        op(AiOpKind.shiftSchedule, {'fromPeriod': 5, 'toPeriod': 8}).fromPeriod,
        5,
      );
      expect(
        op(AiOpKind.shiftSchedule, {'fromPeriod': 5, 'toPeriod': 8}).toPeriod,
        8,
      );
      expect(
        op(AiOpKind.shiftSchedule, {'startPeriod': 3, 'endPeriod': 6}).fromPeriod,
        3,
      );
      expect(
        op(AiOpKind.shiftSchedule, {'startPeriod': 3, 'endPeriod': 6}).toPeriod,
        6,
      );
      expect(op(AiOpKind.shiftSchedule, const {}).fromPeriod, isNull);
      expect(op(AiOpKind.shiftSchedule, const {}).toPeriod, isNull);
    });
  });

  group('AiEditPlan 解析作息操作', () {
    test('不需要课程名也能保留作息操作', () {
      final plan = AiEditPlan.fromAiJson({
        'ops': [
          {'kind': 'updatePeriod', 'args': {'period': 3, 'startTime': '10:05'}},
          {'kind': 'shiftSchedule', 'args': {'minutes': 10}},
        ],
      });
      expect(plan.ops, hasLength(2));
      expect(plan.ops.first.kind, AiOpKind.updatePeriod);
      expect(plan.ops.first.courseName, isEmpty);
      expect(plan.ops.last.kind, AiOpKind.shiftSchedule);
      expect(plan.warnings, isEmpty);
    });

    test('课程类操作仍然必须有课程名', () {
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
