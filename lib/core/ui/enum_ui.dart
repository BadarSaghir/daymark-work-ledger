import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../theme/app_colors.dart';

extension WorkKindUi on WorkKind {
  IconData get icon => switch (this) {
    WorkKind.official => Icons.work_outline_rounded,
    WorkKind.adhoc => Icons.bolt_rounded,
    WorkKind.personal => Icons.wb_sunny_outlined,
  };

  Color color(AppColors colors) => switch (this) {
    WorkKind.official => colors.primary,
    WorkKind.adhoc => colors.accent,
    WorkKind.personal => colors.gold,
  };
}

extension TaskStatusUi on TaskStatus {
  IconData get icon => switch (this) {
    TaskStatus.inbox => Icons.inbox_outlined,
    TaskStatus.planned => Icons.event_available_outlined,
    TaskStatus.inProgress => Icons.play_circle_outline_rounded,
    TaskStatus.blocked => Icons.block_rounded,
    TaskStatus.done => Icons.check_circle_outline_rounded,
  };

  Color color(AppColors colors) => switch (this) {
    TaskStatus.inbox => colors.inkMuted,
    TaskStatus.planned => colors.blue,
    TaskStatus.inProgress => colors.accent,
    TaskStatus.blocked => colors.rose,
    TaskStatus.done => colors.green,
  };
}

extension PriorityUi on Priority {
  IconData get icon => switch (this) {
    Priority.low => Icons.flag_outlined,
    Priority.normal => Icons.flag_outlined,
    Priority.high => Icons.flag_rounded,
    Priority.urgent => Icons.local_fire_department_outlined,
  };

  Color color(AppColors colors) => switch (this) {
    Priority.low => colors.inkFaint,
    Priority.normal => colors.blue,
    Priority.high => colors.gold,
    Priority.urgent => colors.rose,
  };
}

extension CategoryIconUi on Category {
  IconData get iconData => CategoryIcons.fromKey(icon);

  Color get colorValue => Color(color);
}

class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> _icons = {
    'target': Icons.gps_fixed_rounded,
    'users': Icons.groups_2_outlined,
    'inbox': Icons.inbox_outlined,
    'book': Icons.menu_book_outlined,
    'sun': Icons.wb_sunny_outlined,
    'briefcase': Icons.work_outline_rounded,
    'layers': Icons.layers_outlined,
    'code': Icons.code_rounded,
    'palette': Icons.palette_outlined,
    'heart': Icons.favorite_border_rounded,
    'home': Icons.home_outlined,
    'star': Icons.star_border_rounded,
    'chart': Icons.bar_chart_rounded,
    'pen': Icons.edit_outlined,
    'clock': Icons.schedule_rounded,
  };

  static const List<String> keys = [
    'target',
    'users',
    'inbox',
    'book',
    'sun',
    'briefcase',
    'layers',
    'code',
    'palette',
    'heart',
    'home',
    'star',
    'chart',
    'pen',
    'clock',
  ];

  static IconData fromKey(String? key) => _icons[key] ?? Icons.layers_outlined;
}
