import 'package:flutter/material.dart';

/// Keeps popup menus labelled with the same icon language as the rest of the
/// app. Flutter's `PopupMenuItem` has no leading slot, so this is used as its
/// child.
class MenuAction extends StatelessWidget {
  const MenuAction({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? theme.iconTheme.color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
