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
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../accounts/local_account_ui.dart';
import 'google_drive_card.dart';
import 'reminders_card.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _name = TextEditingController();
  Timer? _nameDebounce;
  bool _synced = false;
  late double _weight;
  late int _focus;
  bool _busy = false;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).value;
    _weight = settings?.dailyWeightTarget ?? 25;
    _focus = settings?.dailyFocusMinutes ?? 300;
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value;
    if (settings != null && !_synced) {
      _synced = true;
      _name.text = settings.displayName;
      _weight = settings.dailyWeightTarget;
      _focus = settings.dailyFocusMinutes;
    }
    final backupsAsync = ref.watch(backupListProvider);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('Display name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'What should Daymark call you?',
            ),
            onChanged: (value) {
              _nameDebounce?.cancel();
              _nameDebounce = Timer(const Duration(milliseconds: 700), () {
                ref
                    .read(settingsProvider.notifier)
                    .patch(
                      (settings) =>
                          settings.copyWith(displayName: value.trim()),
                    );
              });
            },
          ),
        ],
      ),
    );

    final rhythm = _SettingsCard(
      title: 'Daily rhythm',
      subtitle:
          'Targets are a compass, not a quota. Adjust as the season changes.',
      icon: Icons.waves_rounded,
      child: Column(
        children: [
          _SliderField(
            label: 'Weight target',
            value: '${_weight.round()} pts',
            slider: Slider(
              value: _weight,
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
            value: _focusLabel(_focus),
            slider: Slider(
              value: _focus.toDouble(),
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
      ),
    );

    final appearance = _SettingsCard(
      title: 'Appearance',
      subtitle: 'Warm paper for daylight, deep ink for late hours.',
      icon: Icons.palette_outlined,
      child: Wrap(
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
      ),
    );

    final backup = _SettingsCard(
      title: 'Backup & portability',
      subtitle:
          'A ZIP archive with every table, a checksum, markdown mirrors, and '
          'task attachments. Import a backup or one shared task bundle here.',
      icon: Icons.shield_outlined,
      trailing: _busy && _busyLabel != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
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
            )
          : Text(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                style: AppText.monoData.copyWith(
                  color: colors.ink,
                  fontSize: 12,
                ),
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
                      Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: colors.inkFaint,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'BACKUPS ON THIS DEVICE',
            style: AppText.label.copyWith(
              color: colors.inkFaint,
              fontSize: 8.5,
            ),
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
      ),
    );

    const drive = GoogleDriveCard();
    const reminders = RemindersCard();

    final data = _SettingsCard(
      title: 'Data',
      subtitle: 'Demo content for exploring; a clean reset for a new season.',
      icon: Icons.storage_outlined,
      child: Column(
        children: [
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
      ),
    );

    final about = _SettingsCard(
      title: 'About Daymark',
      subtitle: 'Every effort, marked.',
      icon: Icons.info_outline_rounded,
      child: Column(
        children: [
          _AboutRow(label: 'Version', value: '1.3.0'),
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
      ),
    );

    return PageWidth(
      child: SingleChildScrollView(
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

  String _focusLabel(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
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
    await _refreshEverything();
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
    await _refreshEverything();
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
    await _refreshEverything();
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
    await _refreshEverything();
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
    _name.clear();
    _synced = false;
    await _refreshEverything();
  }

  Future<void> _refreshEverything() async {
    ref.invalidate(settingsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(timerProvider);
    ref.invalidate(backupListProvider);
    invalidateStatsWidget(ref);
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
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
              if (trailing != null) ...[
                const SizedBox(width: AppSpace.sm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          child,
        ],
      ),
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
