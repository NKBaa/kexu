import 'dart:math';

/// 生成一个本地唯一 ID。
///
/// 使用「时间戳（36 进制）+ 随机后缀」的组合，保证离线可用、无需依赖 uuid 包，
/// 同一毫秒内多次调用也不会碰撞。
String newId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = Random().nextInt(1 << 24).toRadixString(36).padLeft(5, '0');
  return '$ts$rnd';
}
