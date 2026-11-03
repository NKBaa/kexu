import '../../core/utils/ids.dart';
import '../../core/utils/json_utils.dart';

/// 节假日：某一天放假（不上课），因此只需要「年月日」，不需要时间。
///
/// 节假日与课表分开建模的原因：课表本身是按周次排的，而法定节假日
/// 是按公历日期定的，二者维度不同；把节假日存成日期列表后，
/// 上课提醒、今日视图、小组件都能统一按日期判断「今天是否放假」。
class Holiday {
  /// 构造时把 [date] 归一化到当天零点，避免同一日期因时分秒不同而匹配失败。
  Holiday({
    required this.id,
    required DateTime date,
    required this.name,
  }) : date = DateTime(date.year, date.month, date.day);

  /// 本地唯一 ID（用于删除与去重）。
  final String id;

  /// 放假的日期（只取年月日）。
  final DateTime date;

  /// 节日名称，如「国庆节」「校运会」。
  final String name;

  /// 形如 `2026-10-01` 的日期键，用于比较、持久化与展示。
  String get dateKey => formatDateKey(date);

  Holiday copyWith({String? id, DateTime? date, String? name}) => Holiday(
        id: id ?? this.id,
        date: date ?? this.date,
        name: name ?? this.name,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': dateKey,
        'name': name,
      };

  /// 容错解析：`date` 支持 `2026-10-01` 或完整 ISO 字符串；
  /// 缺少 id 时自动补一个，缺少名称时回退为「节假日」。
  static Holiday fromJson(Map<String, dynamic> j) {
    final rawDate = asString(j['date']);
    final rawDateKey = asString(j['dateKey']);
    final parsed = DateTime.tryParse(rawDate) ??
        DateTime.tryParse(rawDateKey) ??
        DateTime.now();
    final rawName = asString(j['name']);
    return Holiday(
      id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
      date: parsed,
      name: rawName.isEmpty ? '节假日' : rawName,
    );
  }

  /// 把日期格式化成 `yyyy-MM-dd`（本地日期，不含时间）。
  static String formatDateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  bool operator ==(Object other) =>
      other is Holiday &&
      other.id == id &&
      other.dateKey == dateKey &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, dateKey, name);

  @override
  String toString() => 'Holiday($dateKey $name)';
}
