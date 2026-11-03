import 'dart:convert';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/ai_ops.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:course_timetable/features/ai/nl_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Timetable sampleTimetable() => Timetable(
      semester: Semester(
        id: 's1',
        name: '2025 秋季学期',
        startMonday: DateTime(2025, 9, 1),
        totalWeeks: 16,
      ),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          teacher: '张三',
          sessions: [
            Session(
              id: 'ss1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: List.generate(16, (i) => i + 1),
              location: 'A101',
            ),
          ],
        ),
      ],
    );

void main() {
  group('parseModelOutput 基本形态', () {
    test('标准 {summary, ops} 计划', () {
      final plan = NlEditService.parseModelOutput('''```json
{"summary":"把高等数学改成单周上课","ops":[
  {"kind":"updateSession","courseName":"高等数学",
   "args":{"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"weeks":[1,3,5,7,9,11,13,15]}},
   "summary":"高等数学周一第1-2节改为单周"}
]}```''');
      expect(plan.summary, '把高等数学改成单周上课');
      expect(plan.ops, hasLength(1));
      final op = plan.ops.single;
      expect(op.kind, AiOpKind.updateSession);
      expect(op.courseName, '高等数学');
      expect(op.summary, '高等数学周一第1-2节改为单周');
      expect(op.matchSpec['dayOfWeek'], 1);
      expect(op.patchSpec['weeks'], [1, 3, 5, 7, 9, 11, 13, 15]);
      // patch 已平铺到 args 顶层，方便直接读 op.weeks 的消费方
      expect(op.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(plan.warnings, isEmpty);
    });

    test('直接输出操作数组', () {
      final plan = NlEditService.parseModelOutput(
        '[{"type":"delete_course","course":"大学英语","summary":"删除大学英语"}]',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.kind, AiOpKind.deleteCourse);
      expect(plan.summary, '删除大学英语');
    });

    test('单个操作对象', () {
      final plan = NlEditService.parseModelOutput(
        '{"kind":"addSession","courseName":"高等数学","args":{"dayOfWeek":3,'
        '"startPeriod":5,"endPeriod":6,"weeks":[1,2,3]}}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.kind, AiOpKind.addSession);
      expect(plan.ops.single.dayOfWeek, 3);
      expect(plan.ops.single.startPeriod, 5);
      // 没有 summary 时回退为第一条操作的描述
      expect(plan.summary, contains('新增时段'));
    });

    test('嵌套 data 包裹', () {
      final plan = NlEditService.parseModelOutput(
        '{"data":{"summary":"删除时段","ops":[{"kind":"deleteSession",'
        '"courseName":"高等数学","args":{"match":{"dayOfWeek":1,"startPeriod":1}}}]}}',
      );
      expect(plan.summary, '删除时段');
      expect(plan.ops.single.kind, AiOpKind.deleteSession);
    });

    test('嵌套 data 包裹 + 内层 operations 别名', () {
      final plan = NlEditService.parseModelOutput(
        '{"data":{"reply":"好的","operations":[{"kind":"deleteCourse","courseName":"高等数学"}]}}',
      );
      expect(plan.summary, '好的');
      expect(plan.ops.single.kind, AiOpKind.deleteCourse);
    });

    test('操作列表放在 operations 键下', () {
      final plan = NlEditService.parseModelOutput(
        '{"reply":"已生成","operations":[{"kind":"deleteCourse","courseName":"高等数学"}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.summary, '已生成');
    });
  });

  group('parseModelOutput 容错与校验', () {
    test('未知操作被忽略并警告', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"explode","courseName":"高等数学"},'
        '{"kind":"deleteCourse","courseName":"高等数学"}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.warnings.join(), contains('无法识别'));
    });

    test('非新增操作缺少课程名被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"deleteCourse"}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('未指明课程名'));
    });

    test('新增课程从 args.name 补全课程名', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"addCourse","args":{"name":"人工智能导论","sessions":['
        '{"dayOfWeek":2,"startPeriod":1,"endPeriod":2,"weeks":[1,2]}]}}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.courseName, '人工智能导论');
      expect(plan.warnings, isEmpty);
    });

    test('新增课程没有任何名称时被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"addCourse","args":{"teacher":"王五"}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('未指明课程名'));
    });

    test('修改课程缺少要改的字段被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"updateCourse","courseName":"高等数学"}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('没有说明要改什么'));
    });

    test('修改课程带 patch 时保留', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"updateCourse","courseName":"高等数学",'
        '"args":{"patch":{"teacher":"李四"}}}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.patchSpec['teacher'], '李四');
    });

    test('时段操作缺少定位信息被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"moveSession","courseName":"高等数学",'
        '"args":{"patch":{"dayOfWeek":3}}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('缺少定位信息'));
    });

    test('调课只给 match 没给 patch 被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"moveSession","courseName":"高等数学",'
        '"args":{"match":{"dayOfWeek":1,"startPeriod":1}}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('没有说明要改成什么'));
    });

    test('调课 match + patch 完整时保留', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"moveSession","courseName":"高等数学",'
        '"args":{"match":{"dayOfWeek":1,"startPeriod":1},'
        '"patch":{"dayOfWeek":3,"startPeriod":5,"endPeriod":6}}}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.kind, AiOpKind.moveSession);
      expect(plan.ops.single.patchSpec['dayOfWeek'], 3);
      // match 与 patch 同时保留：matchSpec 仍是原时段，顶层 getter 是新值
      expect(plan.ops.single.matchSpec['dayOfWeek'], 1);
      expect(plan.ops.single.dayOfWeek, 3);
      expect(plan.ops.single.startPeriod, 5);
      expect(plan.ops.single.endPeriod, 6);
    });

    test('删除时段只需 match', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"deleteSession","courseName":"高等数学",'
        '"args":{"match":{"dayOfWeek":1,"startPeriod":1}}}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.warnings, isEmpty);
    });

    test('删除整门课程无需 args', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"deleteCourse","courseName":"高等数学"}]}',
      );
      expect(plan.ops, hasLength(1));
    });

    test('新增时段缺少星期/节次被忽略', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"addSession","courseName":"高等数学","args":{"location":"A101"}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('缺少星期/节次'));
    });

    test('空 ops 时给出提示性警告', () {
      final plan = NlEditService.parseModelOutput('{"summary":"信息不足，请补充具体课程","ops":[]}');
      expect(plan.ops, isEmpty);
      expect(plan.summary, '信息不足，请补充具体课程');
      expect(plan.warnings.join(), contains('没有给出任何可执行操作'));
    });

    test('操作过多时截断到 100 条并警告', () {
      final ops = List.generate(105, (i) {
        return '{"kind":"deleteCourse","courseName":"课程$i"}';
      }).join(',');
      final plan = NlEditService.parseModelOutput('{"ops":[$ops]}');
      expect(plan.ops, hasLength(100));
      expect(plan.warnings.join(), contains('操作过多'));
    });

    test('警告去重', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"deleteSession","courseName":"高等数学","args":{}},'
        '{"kind":"deleteSession","courseName":"高等数学","args":{}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.where((w) => w.contains('缺少定位信息')).length, 1);
    });
  });

  group('非结构化回复', () {
    test('模型用自然语言要求补充信息时，作为 summary 返回', () {
      final plan = NlEditService.parseModelOutput('请告诉我你要修改的是哪一门课程？');
      expect(plan.ops, isEmpty);
      expect(plan.summary, '请告诉我你要修改的是哪一门课程？');
      expect(plan.warnings.join(), contains('原样显示'));
    });

    test('响应是 markdown 列表（无 JSON 花括号）时也原样返回', () {
      final plan = NlEditService.parseModelOutput('1. 说清课程名\n2. 说清目标时间');
      expect(plan.summary, contains('说清课程名'));
    });

    test('完全空文本抛 parse 异常', () {
      expect(
        () => NlEditService.parseModelOutput('   '),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.parse)),
      );
    });

    test('缺少 JSON 但含花括号的乱码抛 parse 异常', () {
      expect(
        () => NlEditService.parseModelOutput('这是坏掉的输出：{"ops": [}'),
        throwsA(isA<AiException>()),
      );
    });

    test('JSON 解析失败抛 parse 异常', () {
      expect(
        () => NlEditService.parseModelOutput('{"ops":[{"kind":"deleteCourse",}]}'),
        throwsA(isA<AiException>()),
      );
    });

    test('JSON 里既无 ops 也无 summary 时抛 parse 异常', () {
      expect(
        () => NlEditService.parseModelOutput('{"foo":"bar"}'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('NlEditService.plan', () {
    test('把指令与当前课表上下文一起发给模型，并解析返回计划', () async {
      late http.Request captured;
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '{"summary":"已调整","ops":[{"kind":"updateSession",'
                        '"courseName":"高等数学","args":{"match":{"dayOfWeek":1,'
                        '"startPeriod":1},"patch":{"weeks":[1,3,5]}}}]}',
                  },
                },
              ],
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final service = NlEditService(client: client);
      final plan = (await service.planTurn(
        '把高等数学改到单周',
        current: sampleTimetable(),
      ))
          .plan;

      expect(plan.summary, '已调整');
      expect(plan.ops, hasLength(1));

      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final system = (messages.first as Map)['content'] as String;
      final userPrompt = (messages.last as Map)['content'] as String;
      expect(system, contains('JSON'));
      expect(messages.last['role'], 'user');
      expect(userPrompt, contains('把高等数学改到单周'));
      expect(userPrompt, contains('高等数学'));
      expect(userPrompt, contains('2025 秋季学期'));
      expect(userPrompt, contains('周一'));
      expect(userPrompt, contains('1-16周'));
    });

    test('空指令直接报 invalidInput，不发请求', () async {
      var called = false;
      final client = AiClient(
        config: const AiModelConfig(baseUrl: 'https://x.com/v1', model: 'm'),
        httpClient: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final service = NlEditService(client: client);
      await expectLater(
        service.planTurn('   ', current: sampleTimetable()),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      expect(called, isFalse);
    });
  });

  group('parseModelOutput 追问（ask / options）', () {
    test('解析 ask 与字符串数组 options，且不误报「没有可执行操作」', () {
      final plan = NlEditService.parseModelOutput(
        '{"summary":"","ask":"你要改哪一门高数？","options":["高等数学（上）","高等数学（下）"],"ops":[]}',
      );
      expect(plan.hasQuestion, isTrue);
      expect(plan.ops, isEmpty);
      expect(plan.question, '你要改哪一门高数？');
      expect(plan.options, ['高等数学（上）', '高等数学（下）']);
      expect(plan.warnings.join(), isNot(contains('没有给出任何可执行操作')));
    });

    test('兼容 question / clarify / needInfo 与 choices / candidates 别名', () {
      final a = NlEditService.parseModelOutput(
        '{"question":"改哪门？","choices":["甲","乙"],"ops":[]}',
      );
      expect(a.question, '改哪门？');
      expect(a.options, ['甲', '乙']);

      final b = NlEditService.parseModelOutput('{"clarify":"补充一下","ops":[]}');
      expect(b.question, '补充一下');

      final c = NlEditService.parseModelOutput('{"needInfo":"说清楚点","ops":[]}');
      expect(c.question, '说清楚点');
    });

    test('options 支持 {name/label/value} 对象数组', () {
      final plan = NlEditService.parseModelOutput(
        '{"ask":"选一个","candidates":[{"name":"高等数学（上）"},{"label":"高等数学（下）"},'
        '{"value":"大学英语"}],"ops":[]}',
      );
      expect(plan.options, ['高等数学（上）', '高等数学（下）', '大学英语']);
    });

    test('嵌套包裹层里的 ask 不会丢', () {
      final plan = NlEditService.parseModelOutput(
        '{"data":{"ask":"你要改哪一门？","options":["甲","乙"],"ops":[]}}',
      );
      expect(plan.question, '你要改哪一门？');
      expect(plan.options, ['甲', '乙']);
    });

    test('ask 与 ops 同时存在时都保留', () {
      final plan = NlEditService.parseModelOutput(
        '{"summary":"先改能确定的","ask":"另一门要不要也改？",'
        '"ops":[{"kind":"deleteCourse","courseName":"高等数学"}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.question, '另一门要不要也改？');
    });

    test('toJson 带上 question 与 options', () {
      final plan = NlEditService.parseModelOutput('{"ask":"哪门？","options":["甲"],"ops":[]}');
      final json = plan.toJson();
      expect(json['question'], '哪门？');
      expect(json['options'], ['甲']);
    });
  });

  group('planTurn 多轮与课程名归一', () {
    test('请求体带历史 messages，且历史正文不重复塞进 prompt', () async {
      late http.Request captured;
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse(
            '{"summary":"已调整","ops":[{"kind":"updateSession","courseName":"高等数学",'
            '"args":{"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"weeks":[1,3,5]}}}]}',
          );
        }),
      );

      final service = NlEditService(client: client);
      final turn = await service.planTurn(
        '就改高等数学',
        current: sampleTimetable(),
        history: const [
          AiChatMessage.user('把高数改成单周'),
          AiChatMessage.assistant(
            '{"ask":"你要改哪一门？HISTORY-ONLY-TOKEN","options":["高等数学"],"ops":[]}',
          ),
        ],
      );

      expect(turn.instruction, '就改高等数学');
      expect(turn.rawOutput, contains('已调整'));

      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages.map((m) => (m as Map)['role']), ['system', 'user', 'assistant', 'user']);
      expect((messages[1] as Map)['content'], '把高数改成单周');
      expect((messages[2] as Map)['content'], contains('你要改哪一门？'));
      final prompt = (messages[3] as Map)['content'] as String;
      expect(prompt, contains('就改高等数学'));
      expect(prompt, contains('多轮对话'));
      // 历史正文只作为独立 message 发送，不重复拼进 prompt 文本。
      expect(prompt, isNot(contains('HISTORY-ONLY-TOKEN')));
    });

    test('高数 → 高等数学：课程名归一成课表里的规范全名', () async {
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async => _chatResponse(
              '{"summary":"改单周","ops":[{"kind":"updateSession","courseName":"高数",'
              '"args":{"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"weeks":[1,3,5]}}}]}',
            )),
      );

      final plan = (await NlEditService(client: client).planTurn(
        '把高数改成单周',
        current: sampleTimetable(),
      ))
          .plan;
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.courseName, '高等数学');
      expect(plan.question, isEmpty);
    });

    test('简称命中多门课：移除操作并生成反问 + 候选', () async {
      final timetable = Timetable(
        semester: Semester(
          id: 's1',
          name: '2025 秋季学期',
          startMonday: DateTime(2025, 9, 1),
          totalWeeks: 16,
        ),
        courses: [
          Course(id: 'c1', semesterId: 's1', name: '高等数学（上）'),
          Course(id: 'c2', semesterId: 's1', name: '高等数学（下）'),
        ],
      );
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async => _chatResponse(
              '{"summary":"删除高数","ops":[{"kind":"deleteCourse","courseName":"高数"}]}',
            )),
      );

      final plan = (await NlEditService(client: client)
              .planTurn('删掉高数', current: timetable))
          .plan;
      expect(plan.ops, isEmpty);
      expect(plan.hasQuestion, isTrue);
      expect(plan.question, contains('多门课'));
      expect(plan.options, containsAll(['高等数学（上）', '高等数学（下）']));
      expect(plan.warnings.join(), contains('已移除无法确定课程的操作'));
    });

    test('零命中：移除操作并提示课表里没有', () async {
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async => _chatResponse(
              '{"ops":[{"kind":"deleteCourse","courseName":"大学物理"}]}',
            )),
      );

      final plan = (await NlEditService(client: client).planTurn(
        '删掉物理',
        current: sampleTimetable(),
      ))
          .plan;
      expect(plan.ops, isEmpty);
      expect(plan.hasQuestion, isTrue);
      expect(plan.question, contains('没有找到'));
      expect(plan.question, contains('大学物理'));
    });

    test('模型自己给了 ask 时保留原追问', () async {
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async => _chatResponse(
              '{"ask":"你说的是哪门课？","options":["高等数学"],'
              '"ops":[{"kind":"deleteCourse","courseName":"物理"}]}',
            )),
      );

      final plan = (await NlEditService(client: client).planTurn(
        '删掉物理',
        current: sampleTimetable(),
      ))
          .plan;
      expect(plan.ops, isEmpty);
      expect(plan.question, '你说的是哪门课？');
      expect(plan.options, ['高等数学']);
    });
  });

  group('parseModelOutput 作息操作（updatePeriod / shiftSchedule）', () {
    test('解析 updatePeriod，不需要课程名', () {
      final plan = NlEditService.parseModelOutput(
        '{"summary":"第3节改为10:05上课","ops":[{"kind":"updatePeriod",'
        '"args":{"period":3,"startTime":"10:05"}}]}',
      );
      expect(plan.ops, hasLength(1));
      final op = plan.ops.single;
      expect(op.kind, AiOpKind.updatePeriod);
      expect(op.courseName, isEmpty);
      expect(op.period, 3);
      expect(op.startTime, '10:05');
      expect(plan.warnings, isEmpty);
    });

    test('kind 别名（修改作息 / 整体平移）都能识别', () {
      final a = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"修改作息","args":{"period":1,"startTime":"8:10"}}]}',
      );
      expect(a.ops.single.kind, AiOpKind.updatePeriod);

      final b = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"整体平移","args":{"minutes":10}}]}',
      );
      expect(b.ops.single.kind, AiOpKind.shiftSchedule);
      expect(b.ops.single.shiftMinutes, 10);
    });

    test('updatePeriod 的 patch 子对象被平铺到顶层', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"update_period","args":{"period":3,'
        '"patch":{"start":"10:05","end":"10:50"}}}]}',
      );
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.startTime, '10:05');
      expect(plan.ops.single.endTime, '10:50');
    });

    test('shiftSchedule 支持方案名与负数分钟', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"shift_schedule",'
        '"args":{"minutes":-5,"scheduleName":"夏季作息"}}]}',
      );
      expect(plan.ops.single.kind, AiOpKind.shiftSchedule);
      expect(plan.ops.single.shiftMinutes, -5);
      expect(plan.ops.single.scheduleName, '夏季作息');
    });

    test('缺少节次的 updatePeriod 被移除并警告', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"updatePeriod","args":{"startTime":"10:05"}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('缺少节次'));
    });

    test('没有时间的 updatePeriod 被移除并警告', () {
      final plan = NlEditService.parseModelOutput(
        '{"ops":[{"kind":"updatePeriod","args":{"period":3}}]}',
      );
      expect(plan.ops, isEmpty);
      expect(plan.warnings.join(), contains('没有说明第3节改成什么时间'));
    });

    test('缺少分钟数或为 0 的 shiftSchedule 被移除并警告', () {
      for (final args in ['{}', '{"minutes":0}']) {
        final plan = NlEditService.parseModelOutput(
          '{"ops":[{"kind":"shiftSchedule","args":$args}]}',
        );
        expect(plan.ops, isEmpty, reason: args);
        expect(plan.warnings.join(), contains('缺少要平移的分钟数'), reason: args);
      }
    });

    test('planTurn 保留作息操作，且提示词带上作息方案', () async {
      late http.Request captured;
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse(
            '{"summary":"第3节改为10:05上课","ops":[{"kind":"updatePeriod",'
            '"args":{"period":3,"startTime":"10:05"},"summary":"第3节改为 10:05 上课"}]}',
          );
        }),
      );

      final plan = (await NlEditService(client: client).planTurn(
        '第3节改成10:05上课',
        current: sampleTimetable(),
      ))
          .plan;
      expect(plan.ops, hasLength(1));
      expect(plan.ops.single.kind, AiOpKind.updatePeriod);
      expect(plan.question, isEmpty);

      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      final prompt = ((body['messages'] as List).last as Map)['content'] as String;
      expect(prompt, contains('作息方案'));
      expect(prompt, contains('第1节 08:00-08:45'));
    });
  });
}

/// 构造一个 OpenAI 兼容的 Chat Completions 响应。
http.Response _chatResponse(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      })),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

