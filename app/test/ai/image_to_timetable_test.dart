import 'dart:convert';
import 'dart:typed_data';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/draft.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:course_timetable/features/ai/image_to_timetable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 统一入口：16 周学期。
List<DraftCourse> parse(String raw, {int totalWeeks = 16}) =>
    ImageToTimetableService.parseModelOutput(raw, totalWeeks: totalWeeks);

DraftSession onlySession(DraftCourse c) => c.sessions.single;

void main() {
  group('parseModelOutput 基本形态', () {
    test('标准 {"courses":[...]} + markdown 围栏 + 前后说明文字', () {
      const raw = '''
好的，这是识别结果：
```json
{"courses":[{"name":"高等数学","teacher":"张三","credit":4,"sessions":[
  {"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],"location":"A101"}
]}]}
```
希望有帮助！''';
      final courses = parse(raw);
      expect(courses, hasLength(1));
      final c = courses.single;
      expect(c.name, '高等数学');
      expect(c.teacher, '张三');
      expect(c.credit, 4);
      expect(c.sessions, hasLength(1));
      final s = onlySession(c);
      expect(s.dayOfWeek, 1);
      expect(s.startPeriod, 1);
      expect(s.endPeriod, 2);
      expect(s.weeks, List.generate(16, (i) => i + 1));
      expect(s.location, 'A101');
      expect(c.isValid, isTrue);
      expect(c.warnings, isEmpty);
    });

    test('裸数组形态', () {
      final courses = parse(
        '[{"name":"大学英语","sessions":[{"dayOfWeek":"三","startPeriod":3,'
        '"endPeriod":4,"weeks":"1-8周"}]}]',
      );
      expect(courses, hasLength(1));
      final s = onlySession(courses.single);
      expect(s.dayOfWeek, 3);
      expect(s.startPeriod, 3);
      expect(s.endPeriod, 4);
      expect(s.weeks, [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('单个课程对象（没有 courses 包裹）', () {
      final courses = parse(
        '{"name":"线性代数","sessions":[{"dayOfWeek":5,"startPeriod":1,'
        '"endPeriod":2,"weeks":[1,3,5]}]}',
      );
      expect(courses, hasLength(1));
      expect(courses.single.name, '线性代数');
      expect(onlySession(courses.single).weeks, [1, 3, 5]);
    });

    test('嵌套 data 包裹 + 内层 JSON 字符串', () {
      final inner = '{"courses":[{"name":"数据结构","sessions":'
          '[{"dayOfWeek":2,"startPeriod":5,"endPeriod":6,"weeks":[1,2]}]}]}';
      final courses = parse('{"ok":true,"data":${_jsonString(inner)}}');
      expect(courses, hasLength(1));
      expect(courses.single.name, '数据结构');
    });

    test('课程级 sessions 缺失时使用 times 别名', () {
      final courses = parse(
        '{"courses":[{"name":"操作系统","times":[{"dayOfWeek":4,'
        '"startPeriod":7,"endPeriod":8,"weeks":[2,4,6]}]}]}',
      );
      expect(courses.single.sessions, hasLength(1));
      expect(onlySession(courses.single).weeks, [2, 4, 6]);
    });

    test('扁平结构：课程对象直接带 dayOfWeek/节次', () {
      final courses = parse(
        '{"courses":[{"courseName":"编译原理","dayOfWeek":"二","start":9,'
        '"end":10,"weekRange":"1-16周"}]}',
      );
      final c = courses.single;
      expect(c.name, '编译原理');
      final s = onlySession(c);
      expect(s.dayOfWeek, 2);
      expect(s.startPeriod, 9);
      expect(s.endPeriod, 10);
      expect(s.weeks, List.generate(16, (i) => i + 1));
    });

    test('中文键名', () {
      final courses = parse(
        '{"课程":[{"课程名":"概率论","教师":"李四","学分":"3.5","备注":"单周上课",'
        '"星期":"三","开始节次":"5","结束节次":"6","周次":"1-16周(单)","教室":"B202"}]}',
      );
      final c = courses.single;
      expect(c.name, '概率论');
      expect(c.teacher, '李四');
      expect(c.credit, 3.5);
      expect(c.note, '单周上课');
      final s = onlySession(c);
      expect(s.dayOfWeek, 3);
      expect(s.startPeriod, 5);
      expect(s.endPeriod, 6);
      expect(s.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(s.location, 'B202');
    });
  });

  group('周次解析与回退', () {
    test('单周 / 双周展开为显式整数数组', () {
      final courses = parse('''{"courses":[
        {"name":"体育","sessions":[{"dayOfWeek":3,"startPeriod":1,"endPeriod":2,"weekType":"单周"}]},
        {"name":"音乐","sessions":[{"dayOfWeek":4,"startPeriod":1,"endPeriod":2,"weekType":"双周"}]}
      ]}''');
      expect(courses[0].sessions.single.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(courses[1].sessions.single.weeks, [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('断续周次 3-5,7-9', () {
      final courses = parse(
        '{"courses":[{"name":"实验","sessions":[{"dayOfWeek":5,"startPeriod":1,'
        '"endPeriod":3,"weeks":"3-5,7-9周"}]}]}',
      );
      expect(onlySession(courses.single).weeks, [3, 4, 5, 7, 8, 9]);
    });

    test('startWeek/endWeek 起止周写法', () {
      final courses = parse(
        '{"courses":[{"name":"形势与政策","sessions":[{"dayOfWeek":6,"startPeriod":1,'
        '"endPeriod":2,"startWeek":3,"endWeek":6}]}]}',
      );
      expect(onlySession(courses.single).weeks, [3, 4, 5, 6]);
      expect(courses.single.warnings, isEmpty);
    });

    test('缺失周次回退到 1..totalWeeks 并产生警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,"endPeriod":2}]}]}',
        totalWeeks: 12,
      );
      final s = onlySession(courses.single);
      expect(s.weeks, List.generate(12, (i) => i + 1));
      expect(courses.single.warnings.join(), contains('未标注周次'));
      expect(courses.single.warnings.join(), contains('1-12'));
    });

    test('超出学期总周数的周次被截断并警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,'
        '"endPeriod":2,"weeks":[1,8,20,25]}]}]}',
        totalWeeks: 16,
      );
      expect(onlySession(courses.single).weeks, [1, 8]);
      final w = courses.single.warnings.join();
      expect(w, contains('超出学期总周数'));
      expect(w, contains('20'));
    });

    test('周次全部超出范围时回退为全部周次', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,'
        '"endPeriod":2,"weeks":[30,31]}]}]}',
        totalWeeks: 8,
      );
      expect(onlySession(courses.single).weeks, List.generate(8, (i) => i + 1));
      expect(courses.single.warnings.join(), contains('全部超出范围'));
    });

    test('课程级周次应用到所有时段', () {
      final courses = parse(
        '{"courses":[{"name":"英语","weeks":[1,2,3],"sessions":['
        '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2},'
        '{"dayOfWeek":3,"startPeriod":3,"endPeriod":4}]}]}',
      );
      expect(courses.single.sessions, hasLength(2));
      for (final s in courses.single.sessions) {
        expect(s.weeks, [1, 2, 3]);
      }
    });

    test('无法解析的周次字符串回退为全部周次并警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,'
        '"endPeriod":2,"weeks":"待定"}]}]}',
        totalWeeks: 10,
      );
      expect(onlySession(courses.single).weeks, List.generate(10, (i) => i + 1));
      expect(courses.single.warnings.join(), contains('无法解析'));
    });
  });

  group('时段容错', () {
    test('缺失星期默认周一并警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}',
      );
      expect(onlySession(courses.single).dayOfWeek, 1);
      expect(courses.single.warnings.join(), contains('未标注星期'));
    });

    test('同一课程的重复时段被合并', () {
      final courses = parse('''{"courses":[{"name":"高数","sessions":[
        {"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,2]},
        {"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,2]}
      ]}]}''');
      expect(courses.single.sessions, hasLength(1));
      expect(courses.single.warnings.join(), contains('重复的上课时段'));
    });

    test('同名课程被合并', () {
      final courses = parse('''{"courses":[
        {"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1]}]},
        {"name":"高数 ","teacher":"张三","sessions":[{"dayOfWeek":3,"startPeriod":3,"endPeriod":4,"weeks":[1]}]}
      ]}''');
      expect(courses, hasLength(1));
      expect(courses.single.sessions, hasLength(2));
      expect(courses.single.teacher, '张三');
      expect(courses.single.warnings.join(), contains('已合并'));
    });

    test('非对象的时段被忽略并警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":["周一 1-2 节",'
        '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}',
      );
      expect(courses.single.sessions, hasLength(1));
      expect(courses.single.warnings.join(), contains('格式不正确'));
    });

    test('sessions 不是数组时警告', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":"周一1-2节"},'
        '{"name":"英语","sessions":[{"dayOfWeek":2,"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}',
      );
      expect(courses, hasLength(2));
      expect(courses[0].sessions, isEmpty);
      expect(courses[0].warnings.join(), contains('不是数组'));
    });

    test('课程名缺失时保留时段并警告', () {
      final courses = parse(
        '{"courses":[{"sessions":[{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}',
      );
      expect(courses.single.name, isEmpty);
      expect(courses.single.warnings.join(), contains('课程名缺失'));
      expect(courses.single.isValid, isFalse);
    });

    test('完全空白的条目被丢弃', () {
      final courses = parse('{"courses":[{},{},{"name":"高数","sessions":['
          '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}');
      expect(courses, hasLength(1));
      expect(courses.single.name, '高数');
    });

    test('星期用英文缩写与数字字符串均能识别', () {
      final courses = parse('''{"courses":[
        {"name":"A","sessions":[{"dayOfWeek":"Wed","startPeriod":1,"endPeriod":2,"weeks":[1]}]},
        {"name":"B","sessions":[{"dayOfWeek":"4","startPeriod":1,"endPeriod":2,"weeks":[1]}]}
      ]}''');
      expect(courses[0].sessions.single.dayOfWeek, 3);
      expect(courses[1].sessions.single.dayOfWeek, 4);
    });
  });

  group('异常与边界', () {
    test('空文本抛 parse 异常', () {
      expect(() => parse('  '), throwsA(isA<AiException>()));
    });

    test('找不到 JSON 抛 parse 异常', () {
      expect(
        () => parse('抱歉，我无法识别这张图片。'),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.parse)),
      );
    });

    test('JSON 结构完全不对时抛 parse 异常', () {
      expect(
        () => parse('{"foo": 1}'),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('无法识别'),
        )),
      );
    });

    test('模型明确返回空课程数组时返回空列表', () {
      expect(parse('{"courses":[]}'), isEmpty);
      expect(parse('[]'), isEmpty);
    });

    test('totalWeeks < 1 时回退为 16 周', () {
      final courses = parse(
        '{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1,"startPeriod":1,"endPeriod":2}]}]}',
        totalWeeks: 0,
      );
      expect(onlySession(courses.single).weeks, List.generate(16, (i) => i + 1));
    });

    test('模型输出被截断（不完整 JSON）时抛 parse 异常', () {
      expect(
        () => parse('{"courses":[{"name":"高数","sessions":[{"dayOfWeek":1'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('parseImage 端到端（假 HTTP，不联网）', () {
    test('把图片与提示词发给模型，并把返回解析成草稿', () async {
      late http.Request captured;
      final client = AiClient(
        config: const AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'glm-4v-flash',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '{"courses":[{"name":"高等数学","sessions":['
                        '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,'
                        '"weeks":[1,2,3,4,5,6,7,8]}]}]}',
                  },
                },
              ],
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01,
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        [AiImageAttachment(bytes: pngBytes)],
        totalWeeks: 16,
        extraHint: '2025 秋季学期，第 1 周从 9 月 1 日开始',
      );
      final drafts = result.courses;

      expect(drafts, hasLength(1));
      expect(drafts.single.name, '高等数学');
      expect(drafts.single.sessions.single.weeks, [1, 2, 3, 4, 5, 6, 7, 8]);

      // 请求体里应带图片 data URL 与补充说明
      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], 'glm-4v-flash');
      final messages = body['messages'] as List;
      final content = (messages.last as Map)['content'] as List;
      expect(content[1]['type'], 'image_url');
      expect(
        ((content[1]['image_url'] as Map)['url'] as String),
        startsWith('data:image/png;base64,'),
      );
      expect(content[0]['text'], contains('2025 秋季学期'));
      expect(content[0]['text'], contains('1~16'));
    });

    test('空图片字节直接报 invalidInput', () async {
      var called = false;
      final client = AiClient(
        config: const AiModelConfig(baseUrl: 'https://x.com/v1', model: 'm'),
        httpClient: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final service = ImageToTimetableService(client: client);
      await expectLater(
        service.parseImages(
          [AiImageAttachment(bytes: Uint8List(0))],
          totalWeeks: 16,
        ),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      expect(called, isFalse);
    });
  });

  group('parseImages 多图识别（假 HTTP，不联网）', () {
    test('两张图片只发一次请求，两张图都进同一条 user 消息', () async {
      final requests = <http.Request>[];
      final client = _multiClient(requests: requests, responses: [
        _okContent('{"courses":[{"name":"高等数学","sessions":['
            '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,'
            '"weeks":[1,2,3,4,5,6,7,8]}]}]}'),
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        [_img(1), _img(2)],
        totalWeeks: 16,
        extraHint: '2025 秋季学期',
      );

      expect(requests, hasLength(1));
      final content = _userContent(requests.single);
      expect(_imageCount(requests.single), 2);
      expect(content.first['type'], 'text');
      final prompt = _promptText(requests.single);
      expect(prompt, contains('2 张图片'));
      expect(prompt, contains('第 1-2 张'));
      expect(prompt, contains('同一份课表'));
      expect(prompt, contains('2025 秋季学期'));
      expect(prompt, contains('1~16'));

      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '高等数学');
      expect(result.warnings, isEmpty);
    });

    test('超过 4 张自动分批：5 张 → 两次请求（4 + 1）', () async {
      final requests = <http.Request>[];
      final client = _multiClient(requests: requests, responses: [
        _okContent('{"courses":[{"name":"高等数学","sessions":['
            '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1]}]}]}'),
        _okContent('{"courses":[{"name":"大学英语","sessions":['
            '{"dayOfWeek":3,"startPeriod":3,"endPeriod":4,"weeks":[2]}]}]}'),
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        List.generate(5, (i) => _img(i)),
        totalWeeks: 16,
      );

      expect(requests, hasLength(2));
      expect(_imageCount(requests[0]), 4);
      expect(_imageCount(requests[1]), 1);
      expect(_promptText(requests[0]), contains('第 1-4 张'));
      expect(_promptText(requests[1]), contains('第 5 张'));
      expect(_promptText(requests[1]), contains('分批'));

      expect(result.courses.map((c) => c.name), ['高等数学', '大学英语']);
      expect(result.warnings, isEmpty);
    });

    test('恰好 4 张图片时仍只发一次请求', () async {
      final requests = <http.Request>[];
      final client = _multiClient(requests: requests, responses: [
        _okContent('{"courses":[]}'),
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        List.generate(4, (i) => _img(i)),
        totalWeeks: 16,
      );

      expect(requests, hasLength(1));
      expect(_imageCount(requests.single), 4);
      expect(result.courses, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('跨图同名课程合并，单周 + 双周周次取并集', () async {
      final client = _multiClient(requests: [], responses: [
        _okContent('{"courses":[{"name":"高等数学","sessions":['
            '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,'
            '"weeks":[1,3,5,7,9,11,13,15],"location":"A101"}]}]}'),
        _okContent('{"courses":[{"name":"高等数学","teacher":"张三","sessions":['
            '{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,'
            '"weeks":[2,4,6,8,10,12,14,16],"location":"A101"}]}]}'),
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        List.generate(5, (i) => _img(i)),
        totalWeeks: 16,
      );

      expect(result.courses, hasLength(1));
      final course = result.courses.single;
      expect(course.teacher, '张三');
      expect(course.sessions, hasLength(1));
      expect(course.sessions.single.weeks, List.generate(16, (i) => i + 1));
      expect(course.warnings.join(), contains('已合并'));
      expect(result.warnings, isEmpty);
    });

    test('部分批次失败：成功批次照常返回，失败原因写进 warnings', () async {
      final client = _multiClient(requests: [], responses: [
        _serverError(),
        _okContent('{"courses":[{"name":"大学英语","sessions":['
            '{"dayOfWeek":3,"startPeriod":3,"endPeriod":4,"weeks":[1,2]}]}]}'),
      ]);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        List.generate(5, (i) => _img(i)),
        totalWeeks: 16,
      );

      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '大学英语');
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('第 1 批'));
      expect(result.warnings.single, contains('第 1-4 张'));
      expect(result.warnings.single, contains('识别失败'));
      expect(result.warnings.single, contains('HTTP 500'));
    });

    test('全部批次失败时抛出第一个 AiException', () async {
      final client = _multiClient(requests: [], responses: [_serverError()]);
      final service = ImageToTimetableService(client: client);
      await expectLater(
        service.parseImages(List.generate(5, (i) => _img(i)), totalWeeks: 16),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.http)
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('空图片列表与空图片字节直接拒绝，不发请求', () async {
      var called = false;
      final client = AiClient(
        config: const AiModelConfig(baseUrl: 'https://x.com/v1', model: 'm'),
        httpClient: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final service = ImageToTimetableService(client: client);
      await expectLater(
        service.parseImages(const <AiImageAttachment>[], totalWeeks: 16),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      await expectLater(
        service.parseImages(
          [AiImageAttachment(bytes: Uint8List(0))],
          totalWeeks: 16,
        ),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      expect(called, isFalse);
    });
  });

  group('mergeCourses 跨图合并规则', () {
    test('同一天/同起止节/同地点：周次取并集', () {
      final merged = ImageToTimetableService.mergeCourses([
        DraftCourse(name: '高等数学', sessions: [
          _session(1, 1, 2, [1, 3, 5, 7], location: 'A101'),
        ]),
        DraftCourse(name: '高等数学', sessions: [
          _session(1, 1, 2, [2, 4, 6, 8], location: 'A101'),
        ]),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.sessions, hasLength(1));
      expect(merged.single.sessions.single.weeks, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(merged.single.warnings.join(), contains('已合并'));
    });

    test('地点不同则保留为两个时段', () {
      final merged = ImageToTimetableService.mergeCourses([
        DraftCourse(name: '体育', sessions: [
          _session(2, 3, 4, [1, 2], location: '操场'),
        ]),
        DraftCourse(name: '体育', sessions: [
          _session(2, 3, 4, [3, 4], location: '体育馆'),
        ]),
      ]);
      expect(merged.single.sessions, hasLength(2));
    });

    test('一条有地点一条没地点时合并，并保留有地点的', () {
      final merged = ImageToTimetableService.mergeCourses([
        DraftCourse(name: '高等数学', sessions: [
          _session(1, 1, 2, [1, 3]),
        ]),
        DraftCourse(name: '高等数学', sessions: [
          _session(1, 1, 2, [2, 4], location: 'A101'),
        ]),
      ]);
      expect(merged.single.sessions, hasLength(1));
      expect(merged.single.sessions.single.location, 'A101');
      expect(merged.single.sessions.single.weeks, [1, 2, 3, 4]);
    });

    test('不同课程、不同星期不合并', () {
      final merged = ImageToTimetableService.mergeCourses([
        DraftCourse(name: '高数', sessions: [_session(1, 1, 2, [1])]),
        DraftCourse(name: '英语', sessions: [_session(1, 1, 2, [1])]),
        DraftCourse(name: '高数', sessions: [_session(3, 1, 2, [1])]),
      ]);
      expect(merged, hasLength(2));
      expect(merged.first.name, '高数');
      expect(merged.first.sessions, hasLength(2));
      expect(merged.last.name, '英语');
    });
  });
}

/// 构造一个多图识别用的假 HTTP 客户端：按调用顺序返回 [responses]。
AiClient _multiClient({
  required List<http.Request> requests,
  required List<http.Response> responses,
}) {
  var call = 0;
  return AiClient(
    config: const AiModelConfig(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'k',
      model: 'glm-4v-flash',
    ),
    httpClient: MockClient((request) async {
      requests.add(request);
      final index = call < responses.length ? call : responses.length - 1;
      call++;
      return responses[index];
    }),
  );
}

/// 构造 OpenAI 兼容的成功响应。
http.Response _okContent(String content) => http.Response.bytes(
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

/// 构造 OpenAI 兼容的 500 响应（触发 AiException.http）。
http.Response _serverError() => http.Response.bytes(
      utf8.encode(jsonEncode({
        'error': {'message': '模型服务暂时不可用'},
      })),
      500,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 取出请求体里最后一条 user 消息的 content 数组。
List<dynamic> _userContent(http.Request request) {
  final body = jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
  final messages = body['messages'] as List;
  return (messages.last as Map)['content'] as List<dynamic>;
}

/// 请求里带了几个 image_url。
int _imageCount(http.Request request) => _userContent(request)
    .whereType<Map>()
    .where((m) => m['type'] == 'image_url')
    .length;

/// 请求里的提示词文本。
String _promptText(http.Request request) =>
    (_userContent(request).first as Map)['text'] as String;

/// 一张最小的 PNG（文件头 + 一个区分用的字节）。
Uint8List _png([int seed = 0]) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, seed]);

AiImageAttachment _img([int seed = 0]) =>
    AiImageAttachment(bytes: _png(seed), mimeType: 'png', name: 'shot-$seed.png');

/// 构造草稿时段，便于直接测 mergeCourses。
DraftSession _session(
  int dayOfWeek,
  int startPeriod,
  int endPeriod,
  List<int> weeks, {
  String? location,
}) =>
    DraftSession(
      dayOfWeek: dayOfWeek,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: weeks,
      location: location,
    );

/// 把字符串编码成 JSON 字符串字面量（用于构造「JSON 里套 JSON 字符串」的用例）。
String _jsonString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

