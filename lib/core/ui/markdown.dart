import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'layout.dart';

MarkdownStyleSheet markdownStyleSheet(BuildContext context) {
  final colors = context.colors;
  return MarkdownStyleSheet(
    p: AppText.body.copyWith(color: colors.ink, height: 1.62),
    a: AppText.body.copyWith(
      color: colors.accent,
      decoration: TextDecoration.underline,
      decorationColor: colors.accent,
    ),
    em: AppText.body.copyWith(color: colors.ink, fontStyle: FontStyle.italic),
    strong: AppText.body.copyWith(
      color: colors.ink,
      fontWeight: FontWeight.w700,
    ),
    del: AppText.body.copyWith(
      color: colors.inkFaint,
      decoration: TextDecoration.lineThrough,
    ),
    h1: AppText.displayM.copyWith(color: colors.ink, height: 1.2),
    h2: AppText.titleL.copyWith(color: colors.ink, height: 1.3),
    h3: AppText.titleM.copyWith(color: colors.ink),
    blockquote: AppText.body.copyWith(
      color: colors.inkMuted,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.accent, width: 2.5)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    code: AppText.monoData.copyWith(
      color: colors.ink,
      backgroundColor: colors.surfaceSunken,
      fontSize: 12.5,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceSunken,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: colors.line),
    ),
    codeblockPadding: const EdgeInsets.all(14),
    listBullet: AppText.body.copyWith(color: colors.accent),
    listIndent: 20,
    blockSpacing: 10,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.line)),
    ),
    tableHead: AppText.bodySmall.copyWith(
      color: colors.ink,
      fontWeight: FontWeight.w700,
    ),
    tableBody: AppText.bodySmall.copyWith(color: colors.inkMuted),
    tableBorder: TableBorder.all(color: colors.line, width: 1),
    tableCellsPadding: const EdgeInsets.all(8),
    checkbox: TextStyle(color: colors.primary, fontSize: 14),
  );
}

class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.onTapLink,
    this.selectable = true,
  });

  final String data;
  final void Function(String text, String? href, String title)? onTapLink;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (data.trim().isEmpty) {
      return Text(
        'Nothing written yet.',
        style: AppText.body.copyWith(
          color: colors.inkFaint,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: markdownStyleSheet(context),
      onTapLink: onTapLink,
    );
  }
}

/// Write/preview markdown editor with a small formatting palette. The raw
/// markdown is the source of truth; saving flushes the controller text.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Write in markdown…',
    this.minLines = 6,
    this.autofocus = false,
    this.enabled = true,
    this.padding = const EdgeInsets.all(14),
    this.showToolbar = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final int minLines;
  final bool autofocus;
  final bool enabled;
  final EdgeInsets padding;
  final bool showToolbar;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  bool _preview = false;
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focusNode.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted && _preview) setState(() {});
  }

  void _insert(String before, String after, {String placeholder = ''}) {
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final text = selected.isEmpty ? placeholder : selected;
    final newText = value.text.replaceRange(start, end, '$before$text$after');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + text.length,
      ),
    );
    widget.onChanged(widget.controller.text);
    _focusNode.requestFocus();
  }

  void _prefixLines(String prefix) {
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final block = value.text.substring(start, end);
    final lines = block
        .split('\n')
        .map((line) {
          if (line.startsWith(prefix)) return line.substring(prefix.length);
          return '$prefix$line';
        })
        .join('\n');
    final newText = value.text.replaceRange(start, end, lines);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + lines.length,
      ),
    );
    widget.onChanged(widget.controller.text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = Layout.isCompact(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showToolbar) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolButton(
                            icon: Icons.format_bold_rounded,
                            tooltip: compact ? 'Bold' : 'Bold (Ctrl+B)',
                            onTap: () =>
                                _insert('**', '**', placeholder: 'bold'),
                          ),
                          _ToolButton(
                            icon: Icons.format_italic_rounded,
                            tooltip: compact ? 'Italic' : 'Italic (Ctrl+I)',
                            onTap: () =>
                                _insert('_', '_', placeholder: 'italic'),
                          ),
                          _ToolButton(
                            icon: Icons.title_rounded,
                            tooltip: 'Heading',
                            onTap: () => _prefixLines('## '),
                          ),
                          _ToolButton(
                            icon: Icons.format_list_bulleted_rounded,
                            tooltip: 'List',
                            onTap: () => _prefixLines('- '),
                          ),
                          _ToolButton(
                            icon: Icons.checklist_rounded,
                            tooltip: 'Checklist',
                            onTap: () => _prefixLines('- [ ] '),
                          ),
                          _ToolButton(
                            icon: Icons.format_quote_rounded,
                            tooltip: 'Quote',
                            onTap: () => _prefixLines('> '),
                          ),
                          _ToolButton(
                            icon: Icons.code_rounded,
                            tooltip: 'Code',
                            onTap: () => _insert('`', '`', placeholder: 'code'),
                          ),
                          _ToolButton(
                            icon: Icons.link_rounded,
                            tooltip: 'Link',
                            onTap: () => _insert(
                              '[',
                              '](https://)',
                              placeholder: 'link text',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ModeToggle(
                    preview: _preview,
                    onChange: (preview) {
                      setState(() => _preview = preview);
                      if (!preview) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _focusNode.requestFocus(),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: colors.line),
          ],
          if (_preview)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Padding(
                padding: widget.padding,
                child: MarkdownView(data: widget.controller.text),
              ),
            )
          else
            Padding(
              padding: widget.padding,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                minLines: widget.minLines,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: AppText.body.copyWith(color: colors.ink),
                cursorColor: colors.primary,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: AppText.body.copyWith(color: colors.inkFaint),
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onChanged,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = Layout.isCompact(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          width: compact ? 40 : 32,
          height: compact ? 40 : 32,
          child: Icon(
            icon,
            size: compact ? 19 : 17,
            color: colors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.preview, required this.onChange});

  final bool preview;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          _ToggleItem(
            label: 'Write',
            selected: !preview,
            onTap: () => onChange(false),
          ),
          _ToggleItem(
            label: 'Preview',
            selected: preview,
            onTap: () => onChange(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: selected ? colors.ink : colors.inkFaint,
            letterSpacing: 0.4,
            fontSize: 9.5,
          ),
        ),
      ),
    );
  }
}

/// Copies a link target because Daymark has no in-app browser.
void copyMarkdownLink(BuildContext context, String? href) {
  if (href == null || href.isEmpty) return;
  Clipboard.setData(ClipboardData(text: href));
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Link copied: $href')));
}
