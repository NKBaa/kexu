/// 课程名模糊匹配（纯函数，可单测）。
///
/// 用户说「高数」「英语」「线代」时，课表里的规范名往往是「高等数学」
/// 「大学英语」「线性代数」。这里负责把简称/别名/错别字/带括号的写法
/// 归一到课表里真实存在的课程，供「一句话改课表」在调用模型后做一次
/// **本地校验**：唯一命中才敢改写，多命中/零命中一律交给反问。
library;

import '../../data/models/course.dart';

/// 课程名归一化与模糊匹配工具。
class CourseMatcher {
  const CourseMatcher._();

  /// 归一化课程名：
  /// 1. 全角转半角（含全角空格）；
  /// 2. 去掉括号及其内容（如「高等数学（上）」「大学英语(读写)」）；
  /// 3. 去掉空白与常见标点/书名号/引号；
  /// 4. 去掉「课程 / 课」这类尾缀；
  /// 5. 统一小写。
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // 全角字符转半角（ASCII 可见区 + 全角空格）
    final buf = StringBuffer();
    for (final code in s.runes) {
      if (code >= 0xFF01 && code <= 0xFF5E) {
        buf.writeCharCode(code - 0xFEE0);
      } else if (code == 0x3000) {
        buf.write(' ');
      } else {
        buf.writeCharCode(code);
      }
    }
    s = buf.toString();

    // 去括号内容（半角/全角/书名号/方头括号等成对写法）
    s = s.replaceAll(
      RegExp(r'[\(（\[【「『《<〈][^\)）\]】」』》>〉]*[\)）\]】」』》>〉]'),
      '',
    );

    // 去空白与标点：只保留字母、数字与中日韩汉字
    s = s.replaceAll(RegExp(r'[^0-9A-Za-z\u4e00-\u9fff]'), '');

    // 去「课程 / 课」尾缀（避免「高数课」「高等数学课程」对不上）
    while (s.endsWith('课程') && s.length > 2) {
      s = s.substring(0, s.length - 2);
    }
    if (s.endsWith('课') && s.length > 1) {
      s = s.substring(0, s.length - 1);
    }

    return s.toLowerCase();
  }

  /// 在 [courses] 中按 [keyword] 找候选课程。
  ///
  /// 优先级从高到低，命中某一级就只返回该级结果（避免低级匹配污染高级匹配）：
  /// 1. 原始名称完全相等；
  /// 2. 归一化后完全相等；
  /// 3. 归一化后互相包含（如「英语」⊂「大学英语」）；
  /// 4. 子序列缩写匹配（如「高数」→「高等数学」、「线代」→「线性代数」，
  ///    关键词长度至少 2 个字符才启用）。
  ///
  /// 结果按课表原顺序去重，保证稳定排序；空关键词返回空列表。
  static List<Course> match(String keyword, List<Course> courses) {
    final raw = keyword.trim();
    if (raw.isEmpty || courses.isEmpty) return const <Course>[];

    final norm = normalize(raw);
    final tiers = <List<Course>>[
      <Course>[],
      <Course>[],
      <Course>[],
      <Course>[],
    ];

    for (final c in courses) {
      final n = normalize(c.name);
      if (c.name == raw) {
        tiers[0].add(c);
        continue;
      }
      if (norm.isNotEmpty && n.isNotEmpty && n == norm) {
        tiers[1].add(c);
        continue;
      }
      if (norm.length >= 2 && n.length >= 2 && (n.contains(norm) || norm.contains(n))) {
        tiers[2].add(c);
        continue;
      }
      if (norm.length >= 2 && _isSubsequence(norm, n)) {
        tiers[3].add(c);
      }
    }

    for (final tier in tiers) {
      if (tier.isNotEmpty) return _dedupeStable(tier);
    }
    return const <Course>[];
  }

  /// [keyword] 的字符是否按顺序出现在 [target] 中（子序列缩写匹配）。
  static bool _isSubsequence(String keyword, String target) {
    if (keyword.isEmpty || target.isEmpty) return false;
    final kw = keyword.runes.toList();
    var i = 0;
    for (final r in target.runes) {
      if (r == kw[i]) {
        i++;
        if (i == kw.length) return true;
      }
    }
    return false;
  }

  /// 按课程 id 去重，保留首次出现的顺序。
  static List<Course> _dedupeStable(List<Course> courses) {
    final seen = <String>{};
    final out = <Course>[];
    for (final c in courses) {
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }
}
