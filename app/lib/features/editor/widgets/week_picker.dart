import 'package:flutter/material.dart';

import '../../../core/utils/week_utils.dart';
import '../../../core/widgets/hint_icon.dart';

/// 周次选择器：本项目的灵魂控件。
///
/// 大学课表最麻烦的是「不规律周次」——单周、双周、`3-5,7-9` 这种断续周次。
/// 因此这里同时提供两种输入方式，并且**双向实时同步**：
///
/// 1. 点选网格：`1..totalWeeks` 的方块，点一下切换选中；
/// 2. 文本输入：用户直接打 `1-16`、`1,3,5`、`3-5,7-9`、`1-16周(单)`，
///    用 [parseWeeks] 解析后同步回网格。
///
/// 快捷按钮：全选 / 单周 / 双周 / 清空 / 反选。
/// 底部用 [formatWeeks] 回显人类可读结果（如 `1-16周(单)`），保证用户永远知道
/// 自己到底选了哪些周。
class WeekPicker extends StatefulWidget {
  const WeekPicker({
    super.key,
    required this.totalWeeks,
    required this.selectedWeeks,
    required this.onChanged,
    this.enabled = true,
    this.showTextInput = true,
    this.maxGridHeight,
    this.dense = false,
    this.label = '周次',
    this.helperText,
  });

  /// 学期总周数（决定网格范围）。
  final int totalWeeks;

  /// 当前选中的周次（外部真值；控件内部也会维护一份以便流畅交互）。
  final List<int> selectedWeeks;

  /// 选中集合变化时回调（已排序、已去重、已按 [totalWeeks] 裁剪）。
  final ValueChanged<List<int>> onChanged;

  final bool enabled;

  /// 是否显示文本输入框（批量操作里可能只想要网格）。
  final bool showTextInput;

  /// 非空时把网格放进固定高度区域并可滚动（适合对话框等受限空间）。
  final double? maxGridHeight;

  /// 紧凑模式（批量操作页、时段卡片里用）。
  final bool dense;

  final String label;

  /// 额外说明，展示在标题右侧。
  final String? helperText;

  @override
  State<WeekPicker> createState() => _WeekPickerState();
}

class _WeekPickerState extends State<WeekPicker> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late Set<int> _selected;

  /// 上一次由本控件 emit 出去的集合，用来区分「外部改的」和「自己改的」。
  List<int> _lastEmitted = const [];

  /// 文本解析失败时的提示。
  String? _textError;

  /// 文本里有超出总周数的周次。
  bool _textOverflow = false;

  int get _total => widget.totalWeeks < 1 ? 1 : widget.totalWeeks;

  @override
  void initState() {
    super.initState();
    _selected = _normalize(widget.selectedWeeks);
    _lastEmitted = _sorted(_selected);
    _textCtrl.text = _describe(_selected);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant WeekPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = _normalize(widget.selectedWeeks);
    // 外部（父级）改了周次，且不是本控件刚 emit 出去的那一份 -> 采纳外部值。
    if (!_sameSet(incoming, _selected) && !_sameList(_sorted(incoming), _lastEmitted)) {
      _selected = incoming;
      _lastEmitted = _sorted(incoming);
      if (!_focusNode.hasFocus) {
        _textCtrl.text = _describe(_selected);
        _textError = null;
        _textOverflow = false;
      }
      return;
    }
    if (oldWidget.totalWeeks != widget.totalWeeks) {
      _selected = _normalize(_selected);
      if (!_focusNode.hasFocus) _textCtrl.text = _describe(_selected);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 数据工具

  Set<int> _normalize(Iterable<int> weeks) => {
        for (final w in weeks)
          if (w >= 1 && w <= _total) w,
      };

  List<int> _sorted(Set<int> s) => s.toList()..sort();

  bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 回显文案：`1-16周(单)`，空时给一句人话。
  String _describe(Set<int> weeks) {
    if (weeks.isEmpty) return '';
    return formatWeeks(_sorted(weeks));
  }

  void _emit() {
    final list = _sorted(_selected);
    _lastEmitted = list;
    widget.onChanged(list);
    if (!_focusNode.hasFocus) {
      _textCtrl.text = _describe(_selected);
    }
    setState(() {});
  }

  // ------------------------------------------------------------------ 交互

  void _toggle(int week) {
    if (!widget.enabled) return;
    setState(() {
      if (!_selected.remove(week)) _selected.add(week);
    });
    _textError = null;
    _emit();
  }

  void _setAll(Iterable<int> weeks) {
    if (!widget.enabled) return;
    setState(() {
      _selected = _normalize(weeks);
      _textError = null;
      _textOverflow = false;
    });
    _textCtrl.text = _describe(_selected);
    _emit();
  }

  void _selectAll() => _setAll(List<int>.generate(_total, (i) => i + 1));

  void _selectOdd() =>
      _setAll(List<int>.generate((_total + 1) ~/ 2, (i) => i * 2 + 1));

  void _selectEven() => _setAll(List<int>.generate(_total ~/ 2, (i) => (i + 1) * 2));

  void _clear() => _setAll(const <int>[]);

  void _invert() => _setAll([
        for (var w = 1; w <= _total; w++)
          if (!_selected.contains(w)) w,
      ]);

  /// 解析用户输入。
  ///
  /// 统一交给 core 的 [parseWeeks]，它已能识别 `1-16周(单)`（正是 [formatWeeks]
  /// 的输出格式）等写法，因此「显示成什么就能原样输回去」。
  /// 这里只在它返回空、但文本里确实有数字时区分「全部超出总周数」的情况。
  List<int> _parseWeeksInput(String raw) => parseWeeks(raw, maxWeek: _total);

  /// 文本 -> 网格。允许用户随时打文字，解析成功就实时同步。
  void _onTextChanged(String raw) {
    if (!widget.enabled) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _selected = <int>{};
        _textError = null;
        _textOverflow = false;
      });
      _emit();
      return;
    }

    final parsed = _parseWeeksInput(raw);
    final tokens = _weekTokensOf(raw);
    if (parsed.isEmpty) {
      if (tokens.isNotEmpty) {
        // 有数字但全部超出总周数（例如总周数 16 却输入 17-20）。
        setState(() {
          _selected = <int>{};
          _textError = null;
          _textOverflow = true;
        });
        _emit();
        return;
      }
      setState(() {
        _textError = '无法识别，试试：1-16、1-8,10-16、单周、1-16周(双)';
        _textOverflow = false;
      });
      return;
    }

    final overflow = tokens.any((w) => w > _total);
    final next = _normalize(parsed);
    setState(() {
      _selected = next;
      _textError = null;
      _textOverflow = overflow;
    });
    // 注意：不覆写输入框，避免打断用户输入；失焦时再规整。
    _lastEmitted = _sorted(next);
    widget.onChanged(_sorted(next));
  }

  /// 从任意文本里粗暴提取所有周次数字（仅用于判断「是否超出总周数」）。
  static List<int> _weekTokensOf(String raw) {
    final cleaned = raw
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        .replaceAll('~', '-')
        .replaceAll('～', '-');
    final out = <int>[];
    for (final m in RegExp(r'\d+').allMatches(cleaned)) {
      final v = int.tryParse(m.group(0)!);
      if (v != null && v > 0) out.add(v);
    }
    return out;
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // 失焦后把文本规整成标准写法，保证两种输入方式看起来一致。
      setState(() {
        _textCtrl.text = _describe(_selected);
        _textError = null;
        _textOverflow = false;
      });
    }
  }

  void _quickText(String text) {
    _textCtrl.text = text;
    _onTextChanged(text);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _selected.length;
    final summary = _describe(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context, count, summary),
        if (widget.showTextInput) ...[
          const SizedBox(height: 8),
          _buildTextField(context),
        ],
        const SizedBox(height: 8),
        _buildQuickActions(context),
        const SizedBox(height: 8),
        _buildGrid(context),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              count == 0 ? Icons.info_outline : Icons.check_circle_outline,
              size: 16,
              color: count == 0 ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                count == 0
                    ? '未选择任何周次（该时段不会出现在课表里）'
                    : '$summary · 共 $count 周',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: count == 0
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: count == 0 ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int count, String summary) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          widget.label,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        if (summary.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              summary,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const Spacer(),
        if (widget.helperText != null)
          HintIcon(message: widget.helperText!),
      ],
    );
  }

  Widget _buildTextField(BuildContext context) {
    return TextField(
      controller: _textCtrl,
      focusNode: _focusNode,
      enabled: widget.enabled,
      textInputAction: TextInputAction.done,
      onChanged: _onTextChanged,
      onSubmitted: (_) => _focusNode.unfocus(),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      decoration: InputDecoration(
        isDense: true,
        labelText: '直接输入周次',
        hintText: '例如 1-16、1-8,10-16、单周、3-5,7-9',
        errorText: _textError,
        errorMaxLines: 2,
        prefixIcon: const Icon(Icons.edit_calendar_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HintIcon(
              message: _textOverflow
                  ? '已忽略超出总周数（$_total 周）的部分。'
                  : '支持 - 区间、逗号分隔、单/双周；与上方点选实时同步。',
            ),
            if (_textCtrl.text.isNotEmpty)
              IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: widget.enabled ? () => _quickText('') : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = <Widget>[
      _action(context, '全选', Icons.select_all, _selectAll),
      _action(context, '单周', Icons.filter_1, _selectOdd),
      _action(context, '双周', Icons.filter_2, _selectEven),
      _action(context, '反选', Icons.flip, _invert),
      _action(context, '清空', Icons.clear_all, _clear, destructive: true),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: actions);
  }

  Widget _action(
    BuildContext context,
    String text,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: widget.dense ? 30 : 34,
      child: OutlinedButton.icon(
        onPressed: widget.enabled ? onTap : null,
        icon: Icon(icon, size: widget.dense ? 14 : 16),
        label: Text(text, style: TextStyle(fontSize: widget.dense ? 12 : 13)),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 10),
          visualDensity: VisualDensity.compact,
          foregroundColor: destructive ? theme.colorScheme.error : null,
          side: destructive
              ? BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5))
              : null,
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final grid = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var w = 1; w <= _total; w++) _buildCell(context, w),
      ],
    );

    if (widget.maxGridHeight == null) return grid;
    // 用 ConstrainedBox 而非 SizedBox：周数少时不留大片空白，周数多时内部滚动。
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxGridHeight!),
      child: SingleChildScrollView(child: grid),
    );
  }

  Widget _buildCell(BuildContext context, int week) {
    final theme = Theme.of(context);
    final selected = _selected.contains(week);
    final isOdd = week.isOdd;
    final size = widget.dense ? 34.0 : 40.0;

    final Color bg;
    final Color fg;
    if (selected) {
      bg = theme.colorScheme.primary;
      fg = theme.colorScheme.onPrimary;
    } else {
      // 未选中时用极淡的奇偶底色，帮助肉眼找单双周。
      bg = isOdd
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25);
      fg = theme.colorScheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '第$week周',
      child: Tooltip(
        message: selected ? '取消第$week周' : '选择第$week周',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: widget.enabled ? () => _toggle(week) : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              '$week',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: widget.dense ? 13 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}