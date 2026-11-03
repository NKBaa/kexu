/// JSON 处理的小工具。
///
/// 主要服务于大模型输出：模型经常把 JSON 包在 ```json 代码块里，
/// 或者在前后加一段「好的，这是您的课表：」之类的解释文字。
/// 这里提供容错提取，避免因为一点格式噪音就让整个导入失败。
library;

import 'dart:convert';

/// 从一段可能带「噪音」的文本中提取第一个完整的 JSON 对象/数组字符串。
///
/// 策略：先尝试去掉 Markdown 代码围栏；随后扫描文本，
/// 用括号配对（正确处理字符串内的括号与转义）找出第一个可解析的 JSON 值。
/// 找不到时返回 null。
String? extractJsonBlock(String text) {
  var s = text.trim();
  if (s.isEmpty) return null;

  // 1) 优先取 ```json ... ``` 或 ``` ... ``` 围栏内容
  final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) {
    final inner = fence.group(1)!.trim();
    if (inner.isNotEmpty) s = inner;
  }

  // 2) 整段直接可解析就返回
  if (tryDecodeJson(s) != null) return s;

  // 3) 扫描括号配对，定位第一个 JSON 值
  final startObj = s.indexOf('{');
  final startArr = s.indexOf('[');
  int? start;
  if (startObj >= 0 && startArr >= 0) {
    start = startObj < startArr ? startObj : startArr;
  } else if (startObj >= 0) {
    start = startObj;
  } else if (startArr >= 0) {
    start = startArr;
  }
  if (start == null) return null;

  final open = s[start];
  final close = open == '{' ? '}' : ']';
  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == open) depth++;
    if (ch == close) {
      depth--;
      if (depth == 0) {
        final candidate = s.substring(start, i + 1);
        return tryDecodeJson(candidate) != null ? candidate : null;
      }
    }
  }
  return null;
}

/// 安全解码：失败返回 null，不抛异常。
dynamic tryDecodeJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

/// 读取 JSON 里的字符串，容错各种非字符串类型。
String asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is String) return v.trim();
  if (v is num || v is bool) return v.toString();
  return fallback;
}

/// 读取 JSON 里的整数，容错 `"3"`、`3.0`、`"第3节"` 等写法。
int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) {
    final m = RegExp(r'\d+').firstMatch(v);
    if (m != null) return int.tryParse(m.group(0)!);
    return null;
  }
  return null;
}

/// 读取 JSON 里的 double，容错 `"3.5"` 等写法。
double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// 读取 JSON 里的列表，非列表返回空列表。
List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  return const <dynamic>[];
}

/// 读取 JSON 里的对象，非对象返回空 map。
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return const <String, dynamic>{};
}
