import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/google_drive_service.dart';
import '../../state/backup_controller.dart';
import '../../state/categories_controller.dart';
import '../../state/journal_controller.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';

/// Optional Google Drive mirror for the local backup archive. Multiple Google
/// accounts can be connected; one is active for automatic uploads.
class GoogleDriveCard extends ConsumerStatefulWidget {
  const GoogleDriveCard({super.key});

  @override
  ConsumerState<GoogleDriveCard> createState() => _GoogleDriveCardState();
}

class _GoogleDriveCardState extends ConsumerState<GoogleDriveCard> {
  bool _busy = false;
  String? _busyLabel;

  Future<T?> _run<T>(String label, Future<T> Function() action) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      return await action();
    } catch (error) {
      if (mounted) {
        showToast(context, '$error', duration: const Duration(seconds: 5));
      }
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

  Future<GoogleDriveService> _service() =>
      ref.read(googleDriveServiceProvider.future);

  void _refresh() {
    ref.invalidate(googleDriveConfigProvider);
    ref.invalidate(googleDriveBackupsProvider);
  }

  Future<void> _setupClient(GoogleDriveConfig config) async {
    final result = await _showClientDialog(context, existing: config);
    if (result == null) return;
    final service = await _service();
    final saved = await _run<bool>('Saving client…', () async {
      await service.saveClient(clientId: result.$1, clientSecret: result.$2);
      return true;
    });
    if (saved == true) {
      _refresh();
      if (mounted) {
        showToast(context, 'OAuth client saved. Connect an account.');
      }
    }
  }

  Future<void> _connect({String? loginHint}) async {
    final service = await _service();
    final account = await _run<GoogleDriveAccount>(
      'Waiting for Google…',
      () => service.connectAccount(loginHint: loginHint),
    );
    if (account == null) return;
    _refresh();
    if (mounted) showToast(context, 'Connected ${account.email}');
  }

  Future<void> _useAccount(GoogleDriveAccount account) async {
    if (!account.isSignedIn) {
      await _connect(loginHint: account.email);
      return;
    }
    final service = await _service();
    final done = await _run<bool>('Switching account…', () async {
      await service.setActiveAccount(account.id);
      return true;
    });
    if (done == true) _refresh();
  }

  Future<void> _signOutAccount(GoogleDriveAccount account) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out of ${account.email}?',
      message:
          'The account stays remembered here for a quick switch. Cloud files '
          'and the Drive folder are untouched.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    final done = await _run<bool>('Signing out…', () async {
      await service.signOutAccount(account.id);
      return true;
    });
    if (done == true) {
      _refresh();
      if (mounted) {
        showToast(context, 'Google account signed out and remembered');
      }
    }
  }

  Future<void> _removeAccount(GoogleDriveAccount account) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this Google account?',
      message:
          '${account.email} will be disconnected from this device. Cloud files '
          'stay in that Google Drive.',
      confirmLabel: 'Disconnect',
      danger: true,
      icon: Icons.link_off_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    final done = await _run<bool>('Disconnecting…', () async {
      await service.removeAccount(account.id);
      return true;
    });
    if (done == true) {
      _refresh();
      if (mounted) showToast(context, 'Google account disconnected');
    }
  }

  Future<void> _uploadNow() async {
    final service = await _service();
    final uploaded = await _run<CloudBackupFile>(
      'Uploading to Drive…',
      () => service.uploadCurrent(),
    );
    if (uploaded == null) return;
    _refresh();
    if (mounted) {
      showToast(context, 'Uploaded ${uploaded.name} to Google Drive');
    }
  }

  Future<void> _test() async {
    final service = await _service();
    final ok = await _run<bool>('Checking Drive…', () async {
      await service.testConnection();
      return true;
    });
    if (ok == true && mounted) {
      showToast(context, 'Google Drive is reachable');
    }
  }

  Future<void> _setAutoUpload(bool value) async {
    final service = await _service();
    final done = await _run<bool>('Saving…', () async {
      await service.setAutoUpload(value);
      return true;
    });
    if (done == true) _refresh();
  }

  Future<void> _setRetention(int value) async {
    final service = await _service();
    final done = await _run<bool>('Saving…', () async {
      await service.setKeepCount(value);
      return true;
    });
    if (done == true) _refresh();
  }

  Future<void> _restore(CloudBackupFile item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this cloud backup?',
      message:
          '${item.name} will be downloaded and will replace the ledger on this '
          'device. A pre-restore safety copy is written first.',
      confirmLabel: 'Restore',
      icon: Icons.cloud_download_outlined,
    );
    if (!confirmed) return;
    final service = await _service();
    final downloaded = await _run<File>(
      'Downloading…',
      () => service.download(item),
    );
    if (downloaded == null) return;
    final backups = await ref.read(backupServiceProvider.future);
    final result = await _run<BackupResult>(
      'Restoring…',
      () => backups.importFile(downloaded),
    );
    if (result == null) return;
    ref.invalidate(settingsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(timerProvider);
    ref.invalidate(backupListProvider);
    invalidateStatsWidget(ref);
    if (mounted) {
      showToast(
        context,
        result.warning ?? 'Cloud backup restored.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _deleteCloud(CloudBackupFile item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this cloud backup?',
      message: '${item.name} will be removed from Google Drive.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    final service = await _service();
    final done = await _run<bool>('Deleting from Drive…', () async {
      await service.delete(item);
      return true;
    });
    if (done == true) _refresh();
  }

  Future<void> _share(CloudBackupFile item) async {
    final service = await _service();
    final file = await _run<File>('Downloading…', () => service.download(item));
    if (file == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Daymark backup · ${item.name}',
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, 'Could not share this file: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final configAsync = ref.watch(googleDriveConfigProvider);
    final managedSignIn =
        ref.watch(googleOAuthDefaultsProvider).value?.configured ?? false;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(
                  Icons.cloud_outlined,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Drive',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'An optional second home for your archive. Your own '
                      'account, your own Drive folder, no Daymark server.',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.8,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy && _busyLabel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _busyLabel!,
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          configAsync.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stack) => InlineError(
              message: 'Could not load Google Drive settings: $error',
              onRetry: _refresh,
            ),
            data: (value) {
              if (!value.hasClient) {
                return _SetupPrompt(
                  busy: _busy,
                  managedSignIn: managedSignIn,
                  onSetup: () => _setupClient(value),
                  onOpenConsole: _openConsole,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!value.hasAccount)
                    _ConnectPrompt(
                      busy: _busy,
                      managedSignIn: managedSignIn,
                      onConnect: _connect,
                      onChangeClient: () => _setupClient(value),
                    )
                  else ...[
                    if (value.lastUploadAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              size: 14,
                              color: colors.green,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Last mirror ${dateLabel(value.lastUploadAt!)}',
                              style: AppText.bodySmall.copyWith(
                                color: colors.inkFaint,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final account in value.accounts)
                      _AccountRow(
                        account: account,
                        active:
                            account.id == value.activeAccountId ||
                            (value.activeAccountId == null &&
                                account == value.accounts.first),
                        busy: _busy,
                        onUse: () => _useAccount(account),
                        onSignOut: () => _signOutAccount(account),
                        onRemove: () => _removeAccount(account),
                      ),
                    if (value.activeAccount?.isSignedIn != true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: colors.gold,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'The active account is signed out. Sign in or '
                                'choose another remembered account to upload '
                                'or browse Drive.',
                                style: AppText.bodySmall.copyWith(
                                  color: colors.inkMuted,
                                  fontSize: 10.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(
                            Icons.person_add_alt_rounded,
                            size: 16,
                          ),
                          label: const Text('Add another account'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _busy || value.activeAccount?.isSignedIn != true
                              ? null
                              : _test,
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                          ),
                          label: const Text('Test connection'),
                        ),
                        if (!managedSignIn)
                          TextButton(
                            onPressed: _busy ? null : () => _setupClient(value),
                            child: const Text('OAuth client'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: value.autoUpload,
                      onChanged: _busy ? null : _setAutoUpload,
                      title: Text(
                        'Mirror automatic backups',
                        style: AppText.bodySmall.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'At most once every 20 hours, using the active account.',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Keep cloud copies',
                          style: AppText.bodySmall.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                        const Spacer(),
                        DropdownButton<int>(
                          value: value.keepCount,
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
                          onChanged: _busy
                              ? null
                              : (next) {
                                  if (next != null) _setRetention(next);
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
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              _busy || value.activeAccount?.isSignedIn != true
                              ? null
                              : _uploadNow,
                          icon: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 17,
                          ),
                          label: const Text('Back up to Drive'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () =>
                                    ref.invalidate(googleDriveBackupsProvider),
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: const Text('Refresh cloud list'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      'IN GOOGLE DRIVE',
                      style: AppText.label.copyWith(
                        color: colors.inkFaint,
                        fontSize: 8.5,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    _CloudList(
                      busy: _busy,
                      onRestore: _restore,
                      onDelete: _deleteCloud,
                      onShare: _share,
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Daymark uses the drive.file scope: it can only see and '
                    'manage files it creates. Accounts and refresh tokens are '
                    'stored in this local account’s private folder, never inside '
                    'ledger backups.',
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 9.8,
                      height: 1.45,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openConsole() async {
    try {
      await launchUrl(
        Uri.parse('https://console.cloud.google.com/apis/credentials'),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the browser: $error');
    }
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt({
    required this.busy,
    required this.managedSignIn,
    required this.onSetup,
    required this.onOpenConsole,
  });

  final bool busy;
  final bool managedSignIn;
  final VoidCallback onSetup;
  final VoidCallback onOpenConsole;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: colors.surfaceSunken.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                managedSignIn
                    ? 'Google sign-in needs a restart'
                    : 'Google sign-in is not configured in this build',
                style: AppText.bodySmall.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                managedSignIn
                    ? 'The OAuth client embedded in this build could not be '
                          'loaded. Restart Daymark, then try again.'
                    : 'Official Daymark releases use one-tap Google sign-in. '
                          'This build was compiled without the OAuth client, so '
                          'you can add your own free “Desktop app” client to '
                          'connect Drive. It takes about three minutes.',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkMuted,
                  fontSize: 10.8,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onSetup,
              icon: const Icon(Icons.key_rounded, size: 17),
              label: const Text('Set up Google Drive'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenConsole,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open Cloud Console'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt({
    required this.busy,
    required this.managedSignIn,
    required this.onConnect,
    required this.onChangeClient,
  });

  final bool busy;
  final bool managedSignIn;
  final VoidCallback onConnect;
  final VoidCallback onChangeClient;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colors.primarySoft.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.line),
                ),
                child: Center(
                  child: Text(
                    'G',
                    style: AppText.titleM.copyWith(
                      color: colors.blue,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Back up like a message thread',
                      style: AppText.titleM.copyWith(color: colors.ink),
                    ),
                    Text(
                      'Sign in once. Daymark mirrors a fresh archive into a '
                      'private Drive folder and keeps the latest copies.',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkMuted,
                        fontSize: 10.8,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: busy ? null : onConnect,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 6),
          Text(
            'Google asks only for access to files Daymark creates. You can add '
            'more than one account and switch later.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10,
              height: 1.45,
            ),
          ),
          if (!managedSignIn)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : onChangeClient,
                child: const Text('Change OAuth client'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.active,
    required this.busy,
    required this.onUse,
    required this.onSignOut,
    required this.onRemove,
  });

  final GoogleDriveAccount account;
  final bool active;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback onSignOut;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: active
            ? colors.primarySoft.withValues(alpha: 0.55)
            : colors.surfaceSunken.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: active ? colors.primary.withValues(alpha: 0.35) : colors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: active ? colors.primary : colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.line),
            ),
            child: Icon(
              !account.isSignedIn
                  ? Icons.logout_rounded
                  : (active
                        ? Icons.check_rounded
                        : Icons.person_outline_rounded),
              size: 15,
              color: active && account.isSignedIn
                  ? Colors.white
                  : colors.inkFaint,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  !account.isSignedIn
                      ? 'Signed out · remembered for a quick switch'
                      : active
                      ? 'Active for uploads'
                      : 'Connected ${dateLabel(account.connectedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!account.isSignedIn)
            TextButton(
              onPressed: busy ? null : onUse,
              child: const Text('Sign in'),
            )
          else if (!active)
            TextButton(onPressed: busy ? null : onUse, child: const Text('Use'))
          else
            TextButton(
              onPressed: busy ? null : onSignOut,
              child: const Text('Sign out'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            enabled: !busy,
            icon: Icon(
              Icons.more_vert_rounded,
              size: 17,
              color: colors.inkFaint,
            ),
            onSelected: (value) {
              if (value == 'signout') onSignOut();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (context) => [
              if (account.isSignedIn)
                const PopupMenuItem(
                  value: 'signout',
                  child: MenuAction(
                    icon: Icons.logout_rounded,
                    label: 'Sign out (remember account)',
                  ),
                ),
              const PopupMenuItem(
                value: 'remove',
                child: MenuAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Forget this account',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudList extends ConsumerWidget {
  const _CloudList({
    required this.busy,
    required this.onRestore,
    required this.onDelete,
    required this.onShare,
  });

  final bool busy;
  final ValueChanged<CloudBackupFile> onRestore;
  final ValueChanged<CloudBackupFile> onDelete;
  final ValueChanged<CloudBackupFile> onShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final async = ref.watch(googleDriveBackupsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpace.md),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, stack) => InlineError(
        message: 'Could not read Drive backups: $error',
        onRetry: () => ref.invalidate(googleDriveBackupsProvider),
      ),
      data: (files) {
        if (files.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text(
              'No Daymark archives in this Drive folder yet.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final file in files.take(8))
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceSunken.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 15,
                      color: colors.green,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodySmall.copyWith(
                              color: colors.ink,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${dateLabel(file.createdAt)}'
                            '${file.sizeLabel.isEmpty ? '' : ' · ${file.sizeLabel}'}',
                            style: AppText.monoData.copyWith(
                              color: colors.inkFaint,
                              fontSize: 8.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Restore',
                      onPressed: busy ? null : () => onRestore(file),
                      icon: Icon(
                        Icons.restore_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Cloud backup options',
                      enabled: !busy,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 16,
                        color: colors.inkFaint,
                      ),
                      onSelected: (value) {
                        if (value == 'share') onShare(file);
                        if (value == 'delete') onDelete(file);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'share',
                          child: MenuAction(
                            icon: Icons.download_rounded,
                            label: 'Download & share',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: MenuAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete from Drive',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<(String, String)?> _showClientDialog(
  BuildContext context, {
  required GoogleDriveConfig existing,
}) async {
  final id = TextEditingController(text: existing.clientId);
  final secret = TextEditingController(text: existing.clientSecret);
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        title: const Text('Google Drive setup'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'In Google Cloud Console: create or choose a project, enable '
                  'the Google Drive API, then create an OAuth client of type '
                  '“Desktop app”. Paste its client ID and secret below.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: id,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'OAuth client ID',
                    hintText: '…apps.googleusercontent.com',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'OAuth client secret',
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Stored locally in a 0600 file. It is never included in a '
                  'ledger backup. Changing the client may require reconnecting '
                  'existing accounts.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final clientId = id.text.trim();
              final clientSecret = secret.text.trim();
              if (clientId.isEmpty || clientSecret.isEmpty) return;
              Navigator.of(dialogContext).pop((clientId, clientSecret));
            },
            child: const Text('Save client'),
          ),
        ],
      );
    },
  );
  id.dispose();
  secret.dispose();
  return result;
}
