import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/form.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/db/migrations.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/backup_service.dart';
import '../../state/backup_controller.dart';
import '../../state/categories_controller.dart';
import '../../state/journal_controller.dart';
import '../../state/local_account_controller.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../accounts/local_account_ui.dart';
import 'google_drive_card.dart';
import 'reminders_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value;
    final local = ref.watch(localAccountProvider);
    final compact = Layout.isCompact(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    if (settings == null) {
      return PageWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 100),
            settingsAsync.hasError
                ? InlineError(
                    message: 'Could not load settings: ${settingsAsync.error}',
                  )
                : const LoadingBlock(height: 320),
          ],
        ),
      );
    }

    final profile = _SettingsCard(
      title: 'You',
      subtitle: 'The name used in greetings and the local ledger.',
      icon: Icons.person_outline_rounded,
      child: const _ProfilePanel(),
    );

    final rhythm = _SettingsCard(
      title: 'Daily rhythm',
      subtitle:
          'Targets are a compass, not a quota. Adjust as the season changes.',
      icon: Icons.waves_rounded,
      child: const _RhythmPanel(),
    );

    final appearance = _SettingsCard(
      title: 'Appearance',
      subtitle: 'Warm paper for daylight, deep ink for late hours.',
      icon: Icons.palette_outlined,
      child: const _AppearancePanel(),
    );

    final backup = _SettingsCard(
      title: 'Backup & portability',
      subtitle:
          'A ZIP archive with every table, a checksum, markdown mirrors, and '
          'task attachments. Import a backup or one shared task bundle here.',
      icon: Icons.shield_outlined,
      child: const _BackupPanel(),
    );

    const drive = GoogleDriveCard();
    const reminders = RemindersCard();

    final data = _SettingsCard(
      title: 'Data',
      subtitle: 'Demo content for exploring; a clean reset for a new season.',
      icon: Icons.storage_outlined,
      child: const _DataPanel(),
    );

    final about = _SettingsCard(
      title: 'About Daymark',
      subtitle: 'Every effort, marked.',
      icon: Icons.info_outline_rounded,
      child: const _AboutPanel(),
    );

    if (compact) {
      final entries = <_SettingsMenuEntry>[
        _SettingsMenuEntry(
          title: 'Local account',
          summary: local == null
              ? 'Profiles on this device'
              : '${local.active.name} · local only',
          icon: Icons.account_circle_outlined,
          tone: colors.primary,
          sheetChild: const LocalAccountCard(),
        ),
        _SettingsMenuEntry(
          title: 'You',
          summary: settings.displayName.trim().isEmpty
              ? 'Set the name used in greetings'
              : 'Greeting as ${settings.displayName.trim()}',
          icon: Icons.person_outline_rounded,
          tone: colors.primary,
          sheetChild: profile.embeddedCopy(),
        ),
        _SettingsMenuEntry(
          title: 'Daily rhythm',
          summary:
              '${settings.dailyWeightTarget.round()} pts · '
              '${_focusLabel(settings.dailyFocusMinutes)} focus',
          icon: Icons.waves_rounded,
          tone: colors.primary,
          sheetChild: rhythm.embeddedCopy(),
        ),
        _SettingsMenuEntry(
          title: 'Appearance',
          summary: '${_themeLabel(settings.themeMode)} theme',
          icon: Icons.palette_outlined,
          tone: colors.primary,
          sheetChild: appearance.embeddedCopy(),
        ),
        _SettingsMenuEntry(
          title: 'Backup & portability',
          summary: settings.lastBackupAt == null
              ? 'Never backed up'
              : 'Last backup · ${dateLabel(settings.lastBackupAt!)}',
          icon: Icons.shield_outlined,
          tone: colors.green,
          sheetChild: backup.embeddedCopy(),
        ),
        _SettingsMenuEntry(
          title: 'Google Drive',
          summary: 'Optional cloud mirror for backups',
          icon: Icons.cloud_outlined,
          tone: colors.primary,
          sheetChild: drive,
        ),
        _SettingsMenuEntry(
          title: 'Reminders',
          summary: 'Gentle nudges for open loops',
          icon: Icons.notifications_none_rounded,
          tone: colors.gold,
          sheetChild: reminders,
        ),
        _SettingsMenuEntry(
          title: 'Data',
          summary: 'Load a demo or reset the workspace',
          icon: Icons.storage_outlined,
          tone: colors.rose,
          sheetChild: data.embeddedCopy(),
        ),
        _SettingsMenuEntry(
          title: 'About Daymark',
          summary: 'Version 1.4.0 · local only',
          icon: Icons.info_outline_rounded,
          tone: colors.inkMuted,
          sheetChild: about.embeddedCopy(),
        ),
      ];

      void openSection(_SettingsMenuEntry entry) {
        showAppSheet<void>(
          context,
          (sheetContext) => _SettingsSheetBody(
            onClose: () => Navigator.of(sheetContext).pop(),
            child: entry.sheetChild,
          ),
          maxWidth: 640,
        );
      }

      return PageWidth(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (settingsAsync.hasError) ...[
                InlineError(
                  message:
                      'Some settings could not be read: ${settingsAsync.error}',
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              _SettingsMenuGroup(
                label: 'Ledger',
                entries: [entries[0]],
                onOpen: openSection,
              ),
              _SettingsMenuGroup(
                label: 'You',
                entries: entries.sublist(1, 4),
                onOpen: openSection,
              ),
              _SettingsMenuGroup(
                label: 'Archive',
                entries: entries.sublist(4, 7),
                onOpen: openSection,
              ),
              _SettingsMenuGroup(
                label: 'Workspace',
                entries: entries.sublist(7, 8),
                onOpen: openSection,
              ),
              _SettingsMenuGroup(
                label: 'About',
                entries: entries.sublist(8),
                onOpen: openSection,
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                'Daymark 1.4.0 · every effort, marked',
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PageWidth(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              eyebrow: 'The private ledger',
              title: 'Settings',
              subtitle:
                  'Tune the rhythm, keep the archive safe, and decide how much '
                  'you want Daymark to know about your day.',
            ),
            if (settingsAsync.hasError) ...[
              const SizedBox(height: AppSpace.lg),
              InlineError(
                message:
                    'Some settings could not be read: ${settingsAsync.error}',
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        const LocalAccountCard(),
                        const SizedBox(height: AppSpace.lg),
                        profile,
                        const SizedBox(height: AppSpace.lg),
                        rhythm,
                        const SizedBox(height: AppSpace.lg),
                        appearance,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.x3),
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        backup,
                        const SizedBox(height: AppSpace.lg),
                        drive,
                        const SizedBox(height: AppSpace.lg),
                        reminders,
                        const SizedBox(height: AppSpace.lg),
                        data,
                        const SizedBox(height: AppSpace.lg),
                        about,
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  const LocalAccountCard(),
                  const SizedBox(height: AppSpace.lg),
                  profile,
                  const SizedBox(height: AppSpace.lg),
                  rhythm,
                  const SizedBox(height: AppSpace.lg),
                  appearance,
                  const SizedBox(height: AppSpace.lg),
                  backup,
                  const SizedBox(height: AppSpace.lg),
                  drive,
                  const SizedBox(height: AppSpace.lg),
                  reminders,
                  const SizedBox(height: AppSpace.lg),
                  data,
                  const SizedBox(height: AppSpace.lg),
                  about,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _focusLabel(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String _themeLabel(String mode) => switch (mode) {
  'light' => 'Light',
  'dark' => 'Dark',
  _ => 'System',
};

class _SettingsMenuEntry {
  const _SettingsMenuEntry({
    required this.title,
    required this.summary,
    required this.icon,
    required this.tone,
    required this.sheetChild,
  });

  final String title;
  final String summary;
  final IconData icon;
  final Color tone;
  final Widget sheetChild;
}

/// Groups tappable summary rows so the phone settings screen stays one screen
/// of decisions instead of a long wall of controls.
class _SettingsMenuGroup extends StatelessWidget {
  const _SettingsMenuGroup({
    required this.label,
    required this.entries,
    required this.onOpen,
  });

  final String label;
  final List<_SettingsMenuEntry> entries;
  final void Function(_SettingsMenuEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.xs,
            top: AppSpace.lg,
            bottom: AppSpace.sm,
          ),
          child: Text(
            label.toUpperCase(),
            style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 9),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 62, color: colors.line),
                _SettingsMenuTile(
                  entry: entries[i],
                  onTap: () => onOpen(entries[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({required this.entry, required this.onTap});

  final _SettingsMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '${entry.title}. ${entry.summary}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: entry.tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(entry.icon, size: 17, color: entry.tone),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      entry.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet with a drag handle and close affordance. The section card
/// keeps its own heading, so the sheet does not repeat the title.
class _SettingsSheetBody extends StatelessWidget {
  const _SettingsSheetBody({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = Layout.isCompact(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (compact)
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.lineStrong,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              if (compact)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.embedded = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final bool embedded;

  _SettingsCard embeddedCopy() => _SettingsCard(
    title: title,
    subtitle: subtitle,
    icon: icon,
    embedded: true,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Icon(icon, size: 17, color: colors.primary),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.titleM.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        child,
      ],
    );
    if (embedded) return body;
    return SurfaceCard(child: body);
  }
}

/// Self-contained so the same section can live inline on desktop or inside a
/// bottom sheet on mobile without losing its edit state.
class _ProfilePanel extends ConsumerStatefulWidget {
  const _ProfilePanel();

  @override
  ConsumerState<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends ConsumerState<_ProfilePanel> {
  final _name = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).value;
    if (settings != null) _name.text = settings.displayName;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final value = next.value;
      if (value == null || _focusNode.hasFocus) return;
      if (_name.text != value.displayName) _name.text = value.displayName;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormLabel('Display name'),
        TextField(
          controller: _name,
          focusNode: _focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'What should Daymark call you?',
          ),
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 700), () {
              ref
                  .read(settingsProvider.notifier)
                  .patch(
                    (settings) => settings.copyWith(displayName: value.trim()),
                  );
            });
          },
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Kept on this device. Used in greetings and the ledger.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _RhythmPanel extends ConsumerStatefulWidget {
  const _RhythmPanel();

  @override
  ConsumerState<_RhythmPanel> createState() => _RhythmPanelState();
}

class _RhythmPanelState extends ConsumerState<_RhythmPanel> {
  double? _weight;
  int? _focus;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    _weight ??= settings.dailyWeightTarget;
    _focus ??= settings.dailyFocusMinutes;
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final value = next.value;
      if (value == null) return;
      if (_weight != value.dailyWeightTarget ||
          _focus != value.dailyFocusMinutes) {
        setState(() {
          _weight = value.dailyWeightTarget;
          _focus = value.dailyFocusMinutes;
        });
      }
    });

    final weight = _weight!;
    final focus = _focus!;
    return Column(
      children: [
        _SliderField(
          label: 'Weight target',
          value: '${weight.round()} pts',
          slider: Slider(
            value: weight,
            min: 6,
            max: 60,
            divisions: 54,
            onChanged: (value) => setState(() => _weight = value),
            onChangeEnd: (value) => ref
                .read(settingsProvider.notifier)
                .patch(
                  (s) => s.copyWith(dailyWeightTarget: value.roundToDouble()),
                ),
          ),
          hint: 'The weight you aim to earn in a day.',
        ),
        const SizedBox(height: AppSpace.lg),
        _SliderField(
          label: 'Focus target',
          value: _focusLabel(focus),
          slider: Slider(
            value: focus.toDouble(),
            min: 60,
            max: 600,
            divisions: 18,
            onChanged: (value) => setState(() => _focus = value.round()),
            onChangeEnd: (value) => ref
                .read(settingsProvider.notifier)
                .patch((s) => s.copyWith(dailyFocusMinutes: value.round())),
          ),
          hint: 'How much deliberate attention a good day holds.',
        ),
        const SizedBox(height: AppSpace.md),
        ToggleRow(
          label: 'Monday-first weeks',
          subtitle: 'Used by the calendar and weekly insights.',
          icon: Icons.view_week_outlined,
          value: settings.weekStartsMonday,
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .patch((s) => s.copyWith(weekStartsMonday: value)),
        ),
      ],
    );
  }
}

class _AppearancePanel extends ConsumerWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final (value, label, icon) in [
          ('system', 'System', Icons.brightness_auto_outlined),
          ('light', 'Light', Icons.light_mode_outlined),
          ('dark', 'Dark', Icons.dark_mode_outlined),
        ])
          ChoicePill(
            label: label,
            icon: icon,
            selected: settings.themeMode == value,
            onTap: () =>
                ref.read(settingsProvider.notifier).setThemeMode(value),
          ),
      ],
    );
  }
}

class _BackupPanel extends ConsumerStatefulWidget {
  const _BackupPanel();

  @override
  ConsumerState<_BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends ConsumerState<_BackupPanel> {
  bool _busy = false;
  String? _busyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = ref.watch(settingsProvider).value;
    final backupsAsync = ref.watch(backupListProvider);
    if (settings == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_busy && _busyLabel != null) ...[
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              Text(
                _busyLabel!,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ] else
              Text(
                settings.lastBackupAt == null
                    ? 'Never backed up'
                    : 'Last · ${dateLabel(settings.lastBackupAt!)}',
                style: AppText.bodySmall.copyWith(
                  color: settings.lastBackupAt == null
                      ? colors.rose
                      : colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _createBackup,
              icon: const Icon(Icons.backup_outlined, size: 17),
              label: const Text('Create backup'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importBackup,
              icon: const Icon(Icons.file_open_outlined, size: 17),
              label: const Text('Import backup'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importTaskBundle,
              icon: const Icon(Icons.task_alt_rounded, size: 17),
              label: const Text('Import task bundle'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportMarkdown,
              icon: const Icon(Icons.download_outlined, size: 17),
              label: const Text('Markdown export'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        ToggleRow(
          label: 'Automatic daily backup',
          subtitle: 'Once per 24 hours, kept on this device.',
          icon: Icons.autorenew_rounded,
          value: settings.autoBackup,
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .patch((s) => s.copyWith(autoBackup: value)),
        ),
        Row(
          children: [
            Text(
              'Keep automatic copies',
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
            const Spacer(),
            DropdownButton<int>(
              value: settings.backupRetention,
              underline: const SizedBox.shrink(),
              style: AppText.monoData.copyWith(color: colors.ink, fontSize: 12),
              items: const [
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 7, child: Text('7')),
                DropdownMenuItem(value: 14, child: Text('14')),
                DropdownMenuItem(value: 30, child: Text('30')),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .patch((s) => s.copyWith(backupRetention: value));
              },
            ),
            const SizedBox(width: 4),
            Text(
              'backups',
              style: AppText.bodySmall.copyWith(
                color: colors.inkMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        FutureBuilder(
          future: ref.read(backupServiceProvider.future),
          builder: (context, snapshot) {
            final directory = snapshot.data?.backupDirectory.path;
            if (directory == null) return const SizedBox.shrink();
            return InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: directory));
                showToast(context, 'Backup folder path copied');
              },
              borderRadius: BorderRadius.circular(AppRadius.badge),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 14,
                      color: colors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        directory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.monoData.copyWith(
                          color: colors.inkFaint,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    Icon(Icons.copy_rounded, size: 13, color: colors.inkFaint),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'BACKUPS ON THIS DEVICE',
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 8.5),
        ),
        const SizedBox(height: AppSpace.sm),
        backupsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, stack) => InlineError(
            message: 'Could not list backups: $error',
            onRetry: () => ref.invalidate(backupListProvider),
          ),
          data: (backups) {
            if (backups.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Text(
                  'No backups yet. Create one before you need it.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final info in backups.take(8))
                  _BackupRow(
                    info: info,
                    onRestore: _busy ? null : () => _restoreBackup(info),
                    onDelete: _busy ? null : () => _deleteBackup(info),
                    onShare: _busy ? null : () => _shareBackup(info),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<T?> _withBusy<T>(String label, Future<T> Function() action) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      return await action();
    } catch (error) {
      if (mounted) showToast(context, '$error');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<BackupService> _service() => ref.read(backupServiceProvider.future);

  Future<void> _createBackup() async {
    final service = await _service();
    final result = await _withBusy('Backing up…', () => service.createBackup());
    if (result == null) return;
    await ref.read(settingsProvider.notifier).markBackupAt(DateTime.now());
    ref.invalidate(backupListProvider);
    if (!mounted) return;
    showToast(
      context,
      'Backup created · ${p.basename(result.file?.path ?? 'archive.zip')}',
    );
  }

  Future<void> _exportMarkdown() async {
    final service = await _service();
    final directory = await _withBusy(
      'Exporting…',
      () => service.exportMarkdown(),
    );
    if (directory == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: directory.path));
    if (!mounted) return;
    showToast(context, 'Markdown exported · path copied to clipboard');
  }

  Future<void> _importBackup() async {
    const typeGroup = XTypeGroup(
      label: 'Daymark backup',
      extensions: ['zip', 'json'],
    );
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the file picker: $error');
      return;
    }
    if (file == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          'Current data will be replaced by the contents of ${p.basename(file.path)}. '
          'A pre-restore snapshot is written automatically first.',
      confirmLabel: 'Restore',
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    final result = await _withBusy(
      'Restoring…',
      () => service.importFile(File(file!.path)),
    );
    if (result == null) return;
    _refreshEverything();
    if (!mounted) return;
    showToast(
      context,
      result.warning ?? 'Backup restored. Your ledger is back.',
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _importTaskBundle() async {
    const typeGroup = XTypeGroup(
      label: 'Daymark task bundle',
      extensions: ['daymark-task', 'zip'],
    );
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the file picker: $error');
      return;
    }
    if (file == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Import this task?',
      message:
          '${p.basename(file.path)} brings one task with its notes, steps, '
          'tracked time, reminders, and files. If that task already exists, '
          'Daymark updates it when the incoming copy is newer. Nothing else in '
          'your ledger is replaced.',
      confirmLabel: 'Import task',
      icon: Icons.task_alt_rounded,
    );
    if (!confirmed) return;
    final service = await ref.read(taskBundleServiceProvider.future);
    final result = await _withBusy(
      'Importing task…',
      () => service.importFile(File(file!.path)),
    );
    if (result == null) return;
    _refreshEverything();
    if (!mounted) return;
    if (result.keptLocal) {
      showToast(
        context,
        'Your local copy of “${result.title}” is newer, so it was kept.',
        duration: const Duration(seconds: 4),
      );
      return;
    }
    showToast(
      context,
      result.isNew
          ? '“${result.title}” imported as a new task.'
          : '“${result.title}” updated on this device.',
    );
    await openTaskDetail(context, result.taskId);
  }

  Future<void> _restoreBackup(BackupInfo info) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          '${info.name} from ${savedLabel(info.modifiedAt, DateTime.now())} will '
          'replace the current data. A pre-restore snapshot is written first.',
      confirmLabel: 'Restore',
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    final result = await _withBusy(
      'Restoring…',
      () => service.importFile(info.file),
    );
    if (result == null) return;
    _refreshEverything();
    if (!mounted) return;
    showToast(
      context,
      result.warning ?? 'Backup restored.',
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _deleteBackup(BackupInfo info) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this backup file?',
      message: '${info.name} will be removed from disk.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    await _withBusy('Deleting…', () => service.deleteBackup(info));
    ref.invalidate(backupListProvider);
  }

  Future<void> _shareBackup(BackupInfo info) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(info.file.path)],
          subject: 'Daymark backup · ${info.name}',
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, 'Could not share the file: $error');
    }
  }

  void _refreshEverything() {
    ref.invalidate(settingsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(timerProvider);
    ref.invalidate(backupListProvider);
    invalidateStatsWidget(ref);
  }
}

class _DataPanel extends ConsumerStatefulWidget {
  const _DataPanel();

  @override
  ConsumerState<_DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends ConsumerState<_DataPanel> {
  bool _busy = false;
  String? _busyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        if (_busy && _busyLabel != null) ...[
          Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              Text(
                _busyLabel!,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.auto_awesome_outlined,
            size: 19,
            color: colors.gold,
          ),
          title: Text(
            'Load the demo workspace',
            style: AppText.bodyMedium.copyWith(color: colors.ink),
          ),
          subtitle: Text(
            'Replaces current data with realistic tasks, notes, and time.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.8,
            ),
          ),
          onTap: _busy ? null : _loadDemo,
        ),
        Divider(color: colors.line),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.restart_alt_rounded,
            size: 19,
            color: colors.rose,
          ),
          title: Text(
            'Reset the workspace',
            style: AppText.bodyMedium.copyWith(color: colors.ink),
          ),
          subtitle: Text(
            'Removes tasks, steps, time, journals, and activity. Categories '
            'and backups remain.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.8,
            ),
          ),
          onTap: _busy ? null : _resetWorkspace,
        ),
      ],
    );
  }

  Future<T?> _withBusy<T>(String label, Future<T> Function() action) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      return await action();
    } catch (error) {
      if (mounted) showToast(context, '$error');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _loadDemo() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Load the demo workspace?',
      message:
          'This replaces tasks, steps, time, journals, and categories with a '
          'realistic demo. Back up first if you want to keep the current state.',
      confirmLabel: 'Load demo',
      icon: Icons.auto_awesome_outlined,
    );
    if (!confirmed) return;
    final loaded = await _withBusy<bool>('Loading demo…', () async {
      await ref.read(demoServiceProvider).load();
      final attachments = await ref.read(taskAttachmentServiceProvider.future);
      await attachments.deleteAllFiles();
      return true;
    });
    if (loaded != true) return;
    _refreshEverything();
    if (mounted) showToast(context, 'Demo workspace loaded');
  }

  Future<void> _resetWorkspace() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset the workspace?',
      message:
          'This removes all tasks, steps, attached files, time entries, '
          'journals, and activity. Categories and backup files are kept. You '
          'will return to setup.',
      confirmLabel: 'Erase data',
      danger: true,
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed) return;
    final done = await _withBusy('Erasing…', () async {
      final db = ref.read(databaseProvider).db;
      await ref.read(timerProvider.notifier).discard();
      await db.transaction((txn) async {
        await txn.delete('time_entries');
        await txn.delete('subtasks');
        await txn.delete('tasks');
        await txn.delete('journal_entries');
        await txn.delete('activity_events');
        await txn.delete('timer_sessions');
        for (final entry in AppSettings.defaults.toMap().entries) {
          await txn.insert('settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      final attachments = await ref.read(taskAttachmentServiceProvider.future);
      await attachments.deleteAllFiles();
      return true;
    });
    if (done != true) return;
    _refreshEverything();
  }

  void _refreshEverything() {
    ref.invalidate(settingsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(timerProvider);
    ref.invalidate(backupListProvider);
    invalidateStatsWidget(ref);
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _AboutRow(label: 'Version', value: '1.4.0'),
        _AboutRow(label: 'Schema', value: 'v${Migrations.latestVersion}'),
        _AboutRow(
          label: 'Backup format',
          value: 'v${BackupService.formatVersion}',
        ),
        _AboutRow(label: 'Storage', value: 'SQLite · local only'),
        const SizedBox(height: AppSpace.md),
        Text(
          'Daymark does not create an account, phone home, or sync. Your '
          'notes are markdown; your backups are ZIP files with a plain JSON '
          'snapshot and a SHA-256 checksum.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 10.8,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.slider,
    required this.hint,
  });

  final String label;
  final String value;
  final Widget slider;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppText.bodySmall.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: AppText.monoData.copyWith(
                color: colors.primary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        slider,
        Text(
          hint,
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.info,
    required this.onRestore,
    required this.onDelete,
    required this.onShare,
  });

  final BackupInfo info;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final automatic = info.isAutomatic;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(
            automatic
                ? Icons.autorenew_rounded
                : info.isPreRestore
                ? Icons.health_and_safety_outlined
                : Icons.archive_outlined,
            size: 16,
            color: automatic ? colors.inkFaint : colors.primary,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
                Text(
                  '${savedLabel(info.modifiedAt, DateTime.now())} · ${info.sizeLabel}',
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Backup options',
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 17,
              color: colors.inkFaint,
            ),
            onSelected: (value) {
              switch (value) {
                case 'restore':
                  onRestore?.call();
                  break;
                case 'share':
                  onShare?.call();
                  break;
                case 'delete':
                  onDelete?.call();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'restore',
                child: MenuAction(
                  icon: Icons.restore_rounded,
                  label: 'Restore',
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: MenuAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Share / export file',
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: MenuAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete file',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.bodySmall.copyWith(color: colors.inkMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: AppText.monoData.copyWith(color: colors.ink, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
