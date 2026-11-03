import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // ProviderScope 是 Riverpod 的根容器，必须包住整个 App。
  runApp(const ProviderScope(child: CourseTimetableApp()));
}
