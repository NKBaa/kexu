import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/features/ai/course_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Course _c(String id, String name) =>
    Course(id: id, semesterId: 's1', name: name);

void main() {
  group('CourseMatcher.normalize', () {
    test('全角转半角并去空白', () {
      expect(CourseMatcher.normalize('  ＭＡＴＨ１０１ '), 'math101');
    });

    test('去括号及其内容', () {
      expect(CourseMatcher.normalize('高等数学（上）'), '高等数学');
      expect(CourseMatcher.normalize('大学英语(读写)'), '大学英语');
      expect(CourseMatcher.normalize('大学物理【实验】'), '大学物理');
    });

    test('去常见标点与「课程/课」尾缀', () {
      expect(CourseMatcher.normalize('高等数学·上册'), '高等数学上册');
      expect(CourseMatcher.normalize('高数课'), '高数');
      expect(CourseMatcher.normalize('大学英语课程'), '大学英语');
    });

    test('空输入返回空串', () {
      expect(CourseMatcher.normalize('   '), '');
    });
  });

  group('CourseMatcher.match 优先级', () {
    test('原始名称完全相等优先级最高', () {
      final courses = [_c('1', '高等数学'), _c('2', '高等数学（上）')];
      final matched = CourseMatcher.match('高等数学', courses);
      expect(matched, hasLength(1));
      expect(matched.single.id, '1');
    });

    test('归一化后相等（去括号）也能命中', () {
      final courses = [_c('1', '高等数学（上）')];
      final matched = CourseMatcher.match('高等数学', courses);
      expect(matched, hasLength(1));
      expect(matched.single.id, '1');
    });

    test('互相包含：简称/全称都能对上', () {
      expect(
        CourseMatcher.match('英语', [_c('1', '大学英语')]).single.id,
        '1',
      );
      expect(
        CourseMatcher.match('大学英语', [_c('1', '英语')]).single.id,
        '1',
      );
    });

    test('子序列缩写：高数 → 高等数学、线代 → 线性代数', () {
      final courses = [_c('1', '高等数学'), _c('2', '线性代数'), _c('3', '大学英语')];
      expect(CourseMatcher.match('高数', courses).single.id, '1');
      expect(CourseMatcher.match('线代', courses).single.id, '2');
    });

    test('同一简称命中多门课：返回全部候选（歧义交给反问）', () {
      final courses = [_c('1', '高等数学'), _c('2', '数学分析'), _c('3', '大学英语')];
      final matched = CourseMatcher.match('数学', courses);
      expect(matched.map((c) => c.id), ['1', '2']);
    });

    test('去括号后同名的两门课都算候选', () {
      final courses = [_c('1', '高等数学（上）'), _c('2', '高等数学（下）')];
      final matched = CourseMatcher.match('高数', courses);
      expect(matched.map((c) => c.id), ['1', '2']);
    });

    test('零命中返回空列表', () {
      expect(
        CourseMatcher.match('物理', [_c('1', '高等数学'), _c('2', '大学英语')]),
        isEmpty,
      );
    });

    test('单字关键词不启用子序列匹配', () {
      expect(CourseMatcher.match('数', [_c('1', '高等数学')]), isEmpty);
    });

    test('空关键词返回空列表', () {
      expect(CourseMatcher.match('   ', [_c('1', '高等数学')]), isEmpty);
    });

    test('结果按课表顺序去重', () {
      final courses = [
        _c('1', '高等数学'),
        _c('2', '高等数学'),
        _c('3', '大学英语'),
      ];
      final matched = CourseMatcher.match('高等数学', courses);
      expect(matched.map((c) => c.id), ['1', '2']);
    });
  });
}
