import 'package:course_timetable/core/utils/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractJsonBlock 容错提取', () {
    test('裸 JSON 对象', () {
      expect(extractJsonBlock('{"a":1}'), '{"a":1}');
    });

    test('Markdown 代码围栏包裹', () {
      const raw = '```json\n{"courses":[]}\n```';
      expect(extractJsonBlock(raw), '{"courses":[]}');
    });

    test('无语言标记的围栏', () {
      const raw = '```\n[1,2,3]\n```';
      expect(extractJsonBlock(raw), '[1,2,3]');
    });

    test('前后夹带解释文字（模型常见行为）', () {
      const raw = '好的，这是您的课表：\n{"courses":[{"name":"高数"}]}\n希望对您有帮助！';
      expect(extractJsonBlock(raw), '{"courses":[{"name":"高数"}]}');
    });

    test('字符串值里含花括号时不会误判', () {
      const raw = '{"note":"上课时间 {待定} 见通知"}';
      expect(extractJsonBlock(raw), raw);
    });

    test('字符串值里含转义引号', () {
      const raw = r'{"note":"他说\"你好\""}';
      expect(extractJsonBlock(raw), raw);
    });

    test('嵌套对象正确配对', () {
      const raw = '前言 {"a":{"b":{"c":1}}} 后记';
      expect(extractJsonBlock(raw), '{"a":{"b":{"c":1}}}');
    });

    test('数组形态', () {
      const raw = '结果如下：[{"name":"英语"},{"name":"物理"}] 完毕';
      expect(extractJsonBlock(raw), '[{"name":"英语"},{"name":"物理"}]');
    });

    test('完全无 JSON 时返回 null', () {
      expect(extractJsonBlock('抱歉，我无法识别这张图片。'), isNull);
    });

    test('空字符串返回 null', () {
      expect(extractJsonBlock(''), isNull);
    });
  });

  group('类型转换容错', () {
    test('asString 处理各种类型', () {
      expect(asString('abc'), 'abc');
      expect(asString(3), '3');
      expect(asString(true), 'true');
      expect(asString(null), '');
      expect(asString(null, fallback: '默认'), '默认');
      expect(asString('  x  '), 'x');
    });

    test('asInt 从带噪音的字符串里抠出数字', () {
      expect(asInt(3), 3);
      expect(asInt(3.7), 4);
      expect(asInt('3'), 3);
      expect(asInt('第3节'), 3);
      expect(asInt('abc'), isNull);
      expect(asInt(null), isNull);
    });

    test('asDouble', () {
      expect(asDouble(3), 3.0);
      expect(asDouble('3.5'), 3.5);
      expect(asDouble('x'), isNull);
    });

    test('asList / asMap 对错误类型返回安全默认值', () {
      expect(asList(null), isEmpty);
      expect(asList('not a list'), isEmpty);
      expect(asList([1, 2]), [1, 2]);
      expect(asMap(null), isEmpty);
      expect(asMap({'a': 1}), {'a': 1});
    });

    test('tryDecodeJson 不抛异常', () {
      expect(tryDecodeJson('{"a":1}'), {'a': 1});
      expect(tryDecodeJson('{bad json'), isNull);
    });
  });
}
