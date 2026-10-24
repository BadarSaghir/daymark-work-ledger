import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/journal_entry.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/lan_sync_service.dart';
import '../../state/backup_controller.dart';
import '../../state/categories_controller.dart';
import '../../state/journal_controller.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../widgets/quick_capture.dart';

class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  LanSyncService? _service;
  StreamSubscription<List<LanPeer>>? _peerSub;
  StreamSubscription<List<LanInboxItem>>? _inboxSub;
  List<LanPeer> _peers = const [];
  List<LanInboxItem> _inbox = const [];
  final _knownInbox = <String>{};
  bool _starting = false;
  bool _busy = false;
  String? _busyLabel;
  String? _error;

  @override
  void dispose() {
    _peerSub?.cancel();
    _inboxSub?.cancel();
    unawaited(_service?.stop());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _service != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final backup = await ref.read(backupServiceProvider.future);
      final directory = Directory(
        p.join(backup.backupDirectory.parent.path, 'nearby'),
      );
      final service = LanSyncService(
        backupService: backup,
        directory: directory,
        deviceName: settings.displayName,
      );
      await service.start();
      if (!mounted) {
        await service.stop();
        return;
      }
      _knownInbox
        ..clear()
        ..addAll(service.inbox.map((item) => item.id));
      _peerSub = service.peersStream.listen((peers) {
        if (mounted) setState(() => _peers = peers);
      });
      _inboxSub = service.inboxStream.listen((items) {
        if (!mounted) return;
        final fresh = items.where((item) => !_knownInbox.contains(item.id));
        final newest = fresh.isEmpty ? null : fresh.first;
        _knownInbox.addAll(items.map((item) => item.id));
        setState(() => _inbox = items);
        if (newest != null) {
          showToast(
            context,
            newest.isSnapshot
                ? 'A snapshot from ${newest.fromName} arrived.'
                : 'Received “${newest.title}” from ${newest.fromName}.',
            duration: const Duration(seconds: 4),
          );
        }
      });
      setState(() {
        _service = service;
        _peers = service.peers;
        _inbox = service.inbox;
        _starting = false;
        _error = service.discoveryError;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _stop() async {
    final service = _service;
    await _peerSub?.cancel();
    await _inboxSub?.cancel();
    _peerSub = null;
    _inboxSub = null;
    if (mounted) {
      setState(() {
        _service = null;
        _peers = const [];
        _inbox = const [];
      });
    }
    await service?.stop();
  }

  Future<T?> _runBusy<T>(String label, Future<T> Function() action) async {
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

  Future<void> _sendSnapshot(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final pin = await _askPin(context, peer, action: 'Send my ledger');
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending…', () async {
      await service.sendSnapshot(peer, pin);
      return true;
    });
    if (done == true && mounted) {
      showToast(
        context,
        'Snapshot sent to ${peer.name}. It waits there for confirmation.',
      );
    }
  }

  Future<void> _pullSnapshot(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final pin = await _askPin(context, peer, action: 'Pull their ledger');
    if (pin == null) return;
    final item = await _runBusy<LanInboxItem>(
      'Pulling…',
      () => service.pullSnapshot(peer, pin),
    );
    if (item != null && mounted) {
      showToast(
        context,
        'Snapshot received. Restore it from the inbox when you are ready.',
      );
    }
  }

  Future<void> _sendText(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final shared = await _composeText(context);
    if (shared == null || !mounted) return;
    final pin = await _askPin(context, peer, action: 'Send note');
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending note…', () async {
      await service.sendText(peer, pin, title: shared.title, text: shared.text);
      return true;
    });
    if (done == true && mounted) {
      showToast(context, 'Note sent to ${peer.name}.');
    }
  }

  Future<void> _sendFile(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    XFile? picked;
    try {
      picked = await openFile();
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the file picker: $error');
      return;
    }
    if (picked == null || !mounted) return;
    final pin = await _askPin(context, peer, action: 'Send file');
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending file…', () async {
      await service.sendFile(peer, pin, File(picked!.path));
      return true;
    });
    if (done == true && mounted) {
      showToast(context, 'File sent to ${peer.name}.');
    }
  }

  Future<void> _manualConnect() async {
    final service = _service;
    if (service == null) return;
    final result = await _askAddress(context);
    if (result == null) return;
    final peer = await _runBusy<LanPeer?>(
      'Connecting…',
      () => service.probe(result.$1, result.$2),
    );
    if (peer != null && mounted) {
      showToast(context, 'Found ${peer.name} at ${peer.endpoint}.');
    }
  }

  Future<void> _restoreSnapshot(LanInboxItem item) async {
    final path = item.filePath;
    if (path == null || !await File(path).exists()) {
      if (mounted) showToast(context, 'That snapshot file is no longer here.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this snapshot?',
      message:
          'The ledger on this device will be replaced by ${item.title}. A '
          'pre-restore safety copy is written first.',
      confirmLabel: 'Restore',
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;
    final backup = await ref.read(backupServiceProvider.future);
    final result = await _runBusy<BackupResult>(
      'Restoring…',
      () => backup.importFile(File(path)),
    );
    if (result == null) return;
    _refreshAll();
    if (!mounted) return;
    showToast(
      context,
      result.warning ?? 'The snapshot was restored into this device.',
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _saveTextToJournal(LanInboxItem item) async {
    final text = item.text?.trim() ?? '';
    if (text.isEmpty) return;
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    final key = dateKey(DateTime.now());
    JournalEntry? existing;
    for (final entry in entries) {
      if (entry.dateKey == key) {
        existing = entry;
        break;
      }
    }
    final block = '## Shared from ${item.fromName}\n\n$text';
    final existingBody = existing?.bodyMd.trimRight() ?? '';
    final merged = existingBody.isEmpty
        ? block
        : '$existingBody\n\n---\n\n$block';
    try {
      await ref
          .read(journalProvider.notifier)
          .save(
            dateKey: key,
            bodyMd: merged,
            mood: existing?.mood,
            energy: existing?.energy,
          );
      if (mounted) {
        showToast(context, 'Added to today’s journal.');
      }
    } catch (error) {
      if (mounted) showToast(context, 'Could not save the note: $error');
    }
  }

  void _textToTask(LanInboxItem item) {
    showQuickCapture(
      context,
      plannedDate: DateTime.now(),
      initialTitle: item.title,
      initialNotes: item.text,
    );
  }

  Future<void> _deleteInboxItem(LanInboxItem item) async {
    final service = _service;
    if (service == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this received item?',
      message: item.isSnapshot
          ? 'The snapshot file will be deleted. Your current ledger is not touched.'
          : 'The received copy will be deleted from this device.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await service.deleteInboxItem(item);
    _knownInbox.remove(item.id);
  }

  void _refreshAll() {
    ref.invalidate(settingsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(timerProvider);
    ref.invalidate(backupListProvider);
    invalidateStatsWidget(ref);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = _service;
    final online = service != null;
    final wide = MediaQuery.sizeOf(context).width >= 1020;

    return PageWidth(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'Close range, no cloud',
              title: 'Nearby',
              subtitle:
                  'Move a ledger snapshot, a file, or a note between devices on '
                  'the same network. Direct, ephemeral, and yours.',
              actions: [
                if (online)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _stop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Go offline'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _starting ? null : _start,
                    icon: _starting
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: Text(_starting ? 'Opening…' : 'Go online'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.lg),
              InlineError(message: _error!, onRetry: online ? null : _start),
            ],
            const SizedBox(height: AppSpace.xl),
            if (!online)
              _OfflineIntro(
                starting: _starting,
                onStart: _start,
                onShareText: () => _shareTextStandalone(context),
                onShareFile: () => _shareFileStandalone(context),
              )
            else ...[
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          _DeviceCard(
                            service: service,
                            onStop: _busy ? null : _stop,
                            onReceivingChanged: (value) {
                              service.setReceiving(value);
                              setState(() {});
                            },
                            onCopyPin: () {
                              Clipboard.setData(
                                ClipboardData(text: service.pin),
                              );
                              showToast(context, 'Code copied');
                            },
                          ),
                          const SizedBox(height: AppSpace.lg),
                          _PeersCard(
                            peers: _peers,
                            busy: _busy,
                            busyLabel: _busyLabel,
                            onSendSnapshot: _sendSnapshot,
                            onPullSnapshot: _pullSnapshot,
                            onSendText: _sendText,
                            onSendFile: _sendFile,
                            onManual: _manualConnect,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.x3),
                    Expanded(
                      flex: 5,
                      child: _InboxPanel(
                        items: _inbox,
                        busy: _busy,
                        onRestoreSnapshot: _restoreSnapshot,
                        onSaveText: _saveTextToJournal,
                        onTextToTask: _textToTask,
                        onDelete: _deleteInboxItem,
                      ),
                    ),
                  ],
                )
              else ...[
                _DeviceCard(
                  service: service,
                  onStop: _busy ? null : _stop,
                  onReceivingChanged: (value) {
                    service.setReceiving(value);
                    setState(() {});
                  },
                  onCopyPin: () {
                    Clipboard.setData(ClipboardData(text: service.pin));
                    showToast(context, 'Code copied');
                  },
                ),
                const SizedBox(height: AppSpace.lg),
                _PeersCard(
                  peers: _peers,
                  busy: _busy,
                  busyLabel: _busyLabel,
                  onSendSnapshot: _sendSnapshot,
                  onPullSnapshot: _pullSnapshot,
                  onSendText: _sendText,
                  onSendFile: _sendFile,
                  onManual: _manualConnect,
                ),
                const SizedBox(height: AppSpace.lg),
                _InboxPanel(
                  items: _inbox,
                  busy: _busy,
                  onRestoreSnapshot: _restoreSnapshot,
                  onSaveText: _saveTextToJournal,
                  onTextToTask: _textToTask,
                  onDelete: _deleteInboxItem,
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              _PrivacyNote(colors: colors),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineIntro extends StatelessWidget {
  const _OfflineIntro({
    required this.starting,
    required this.onStart,
    required this.onShareText,
    required this.onShareFile,
  });

  final bool starting;
  final VoidCallback onStart;
  final VoidCallback onShareText;
  final VoidCallback onShareFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(AppSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  size: 28,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                'Bring your devices close',
                textAlign: TextAlign.center,
                style: AppText.displayM.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpace.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Go online on both devices while this screen is open. Daymark '
                  'announces itself on the local network, then waits for you to '
                  'choose what to send. Nothing is uploaded.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(
                    color: colors.inkMuted,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              FilledButton.icon(
                onPressed: starting ? null : onStart,
                icon: starting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: Text(
                  starting ? 'Opening…' : 'Go online on this network',
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpace.xl,
                runSpacing: AppSpace.lg,
                children: const [
                  _Promise(
                    icon: Icons.lock_outline_rounded,
                    title: 'Direct',
                    body: 'Device to device on your LAN.',
                  ),
                  _Promise(
                    icon: Icons.pin_outlined,
                    title: 'Guarded',
                    body: 'A six-digit code for every transfer.',
                  ),
                  _Promise(
                    icon: Icons.cloud_off_outlined,
                    title: 'Ephemeral',
                    body: 'No relay, account, or cloud copy.',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share without a receiver',
                style: AppText.titleM.copyWith(
                  color: colors.ink,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Use the system share sheet to send a note or file to another '
                'app, a person, or a device. This works even when Nearby is off.',
                style: AppText.bodySmall.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.lg),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: onShareText,
                    icon: const Icon(Icons.text_snippet_outlined, size: 17),
                    label: const Text('Share text'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onShareFile,
                    icon: const Icon(Icons.attach_file_rounded, size: 17),
                    label: const Text('Share a file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 170,
      child: Column(
        children: [
          Icon(icon, size: 18, color: colors.accent),
          const SizedBox(height: 6),
          Text(
            title,
            style: AppText.bodySmall.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.service,
    required this.onStop,
    required this.onReceivingChanged,
    required this.onCopyPin,
  });

  final LanSyncService service;
  final VoidCallback? onStop;
  final ValueChanged<bool> onReceivingChanged;
  final VoidCallback onCopyPin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pin = service.pin;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.green.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  size: 17,
                  color: colors.green,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName,
                      style: AppText.titleM.copyWith(color: colors.ink),
                    ),
                    Text(
                      '${_platformLabel(Platform.operatingSystem)} · '
                      'port ${service.port}',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.green.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'ONLINE',
                      style: AppText.label.copyWith(
                        color: colors.green,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: colors.surfaceSunken.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR TRANSFER CODE',
                  style: AppText.label.copyWith(
                    color: colors.inkFaint,
                    fontSize: 8.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        pin.split('').join(' '),
                        style: AppText.monoLarge.copyWith(
                          color: colors.ink,
                          fontSize: 30,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      onPressed: onCopyPin,
                      icon: const Icon(Icons.copy_rounded, size: 17),
                    ),
                  ],
                ),
                Text(
                  'Type this on the other device when it asks. It changes each '
                  'time Nearby opens.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: service.isReceiving,
            onChanged: onReceivingChanged,
            title: Text(
              'Allow incoming transfers',
              style: AppText.bodySmall.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'You still confirm every ledger restore after it arrives.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeersCard extends StatelessWidget {
  const _PeersCard({
    required this.peers,
    required this.busy,
    required this.busyLabel,
    required this.onSendSnapshot,
    required this.onPullSnapshot,
    required this.onSendText,
    required this.onSendFile,
    required this.onManual,
  });

  final List<LanPeer> peers;
  final bool busy;
  final String? busyLabel;
  final ValueChanged<LanPeer> onSendSnapshot;
  final ValueChanged<LanPeer> onPullSnapshot;
  final ValueChanged<LanPeer> onSendText;
  final ValueChanged<LanPeer> onSendFile;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nearby devices',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      peers.isEmpty
                          ? 'Looking for other Daymark ledgers…'
                          : '${peers.length} ${peers.length == 1 ? 'device' : 'devices'} on this network',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy && busyLabel != null)
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
                      busyLabel!,
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                )
              else
                TextButton.icon(
                  onPressed: onManual,
                  icon: const Icon(Icons.add_link_rounded, size: 15),
                  label: const Text('Manual'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (peers.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpace.xl),
              decoration: BoxDecoration(
                color: colors.surfaceSunken.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                children: [
                  Icon(Icons.radar_rounded, size: 26, color: colors.inkFaint),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'No one in range yet',
                    style: AppText.bodyMedium.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Open Nearby on the other device and keep both on the same '
                    'Wi-Fi. If discovery is blocked, use Manual with the address '
                    'and port shown there.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.8,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final peer in peers)
              _PeerRow(
                peer: peer,
                busy: busy,
                onSendSnapshot: () => onSendSnapshot(peer),
                onPullSnapshot: () => onPullSnapshot(peer),
                onSendText: () => onSendText(peer),
                onSendFile: () => onSendFile(peer),
              ),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.busy,
    required this.onSendSnapshot,
    required this.onPullSnapshot,
    required this.onSendText,
    required this.onSendFile,
  });

  final LanPeer peer;
  final bool busy;
  final VoidCallback onSendSnapshot;
  final VoidCallback onPullSnapshot;
  final VoidCallback onSendText;
  final VoidCallback onSendFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(
                  _platformIcon(peer.platform),
                  size: 17,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyMedium.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${_platformLabel(peer.platform)} · ${peer.address.address}',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More ways to send',
                enabled: !busy,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: colors.inkFaint,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'text':
                      onSendText();
                      break;
                    case 'file':
                      onSendFile();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'text', child: Text('Send a note')),
                  PopupMenuItem(value: 'file', child: Text('Send a file')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onSendSnapshot,
                icon: const Icon(Icons.upload_file_rounded, size: 15),
                label: const Text('Send my ledger'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onPullSnapshot,
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text('Pull their ledger'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxPanel extends StatelessWidget {
  const _InboxPanel({
    required this.items,
    required this.busy,
    required this.onRestoreSnapshot,
    required this.onSaveText,
    required this.onTextToTask,
    required this.onDelete,
  });

  final List<LanInboxItem> items;
  final bool busy;
  final ValueChanged<LanInboxItem> onRestoreSnapshot;
  final ValueChanged<LanInboxItem> onSaveText;
  final ValueChanged<LanInboxItem> onTextToTask;
  final ValueChanged<LanInboxItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Received here',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      'Transfers land here first. Nothing replaces your ledger '
                      'until you say so.',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.8,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${items.length}',
                style: AppText.monoData.copyWith(
                  color: colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpace.xxl,
                horizontal: AppSpace.lg,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceSunken.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.move_to_inbox_outlined,
                    size: 26,
                    color: colors.inkFaint,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Nothing received yet',
                    style: AppText.bodyMedium.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Send a snapshot, note, or file from another device. It will '
                    'wait here.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.8,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final item in items)
              _InboxRow(
                item: item,
                busy: busy,
                onRestoreSnapshot: () => onRestoreSnapshot(item),
                onSaveText: () => onSaveText(item),
                onTextToTask: () => onTextToTask(item),
                onDelete: () => onDelete(item),
              ),
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.item,
    required this.busy,
    required this.onRestoreSnapshot,
    required this.onSaveText,
    required this.onTextToTask,
    required this.onDelete,
  });

  final LanInboxItem item;
  final bool busy;
  final VoidCallback onRestoreSnapshot;
  final VoidCallback onSaveText;
  final VoidCallback onTextToTask;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = item.isSnapshot
        ? Icons.inventory_2_outlined
        : item.isText
        ? Icons.sticky_note_2_outlined
        : Icons.attach_file_rounded;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(icon, size: 15, color: colors.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${item.fromName} · '
                      '${savedLabel(item.receivedAt, DateTime.now())}'
                      '${item.sizeLabel.isEmpty ? '' : ' · ${item.sizeLabel}'}',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Options',
                enabled: !busy,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 17,
                  color: colors.inkFaint,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      _shareItem(context);
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'share', child: Text('Share copy')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ],
          ),
          if (item.isText && (item.text?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: colors.canvas.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Text(
                item.text!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          if (item.isSnapshot)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onRestoreSnapshot,
                  icon: const Icon(Icons.restore_rounded, size: 15),
                  label: const Text('Restore'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _shareItem(context),
                  icon: const Icon(Icons.ios_share_rounded, size: 15),
                  label: const Text('Share'),
                ),
              ],
            )
          else if (item.isText)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.text ?? ''));
                    showToast(context, 'Note copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onSaveText,
                  icon: const Icon(Icons.edit_note_rounded, size: 15),
                  label: const Text('To journal'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onTextToTask,
                  icon: const Icon(Icons.add_task_rounded, size: 15),
                  label: const Text('To task'),
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _shareItem(context),
                  icon: const Icon(Icons.ios_share_rounded, size: 15),
                  label: const Text('Share file'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final path = item.filePath;
                    if (path != null) {
                      Clipboard.setData(ClipboardData(text: path));
                      showToast(context, 'File path copied');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy path'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _shareItem(BuildContext context) async {
    try {
      final path = item.filePath;
      if (path == null) {
        await SharePlus.instance.share(
          ShareParams(text: item.text ?? item.title, subject: item.title),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], subject: item.title),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showToast(context, 'Could not share this item: $error');
      }
    }
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colors.gold),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'LAN transfers are direct and unencrypted. Use them on a network '
              'you trust, keep the six-digit code private, and restore snapshots '
              'only when you mean to replace this device’s ledger.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkMuted,
                fontSize: 10.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askPin(
  BuildContext context,
  LanPeer peer, {
  required String action,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        title: Text('$action · ${peer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask ${peer.name} for the six-digit code on its Nearby screen.',
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppText.monoLarge.copyWith(
                color: colors.ink,
                fontSize: 24,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.length != 6) return;
              Navigator.of(dialogContext).pop(code);
            },
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Future<({String title, String text})?> _composeText(
  BuildContext context,
) async {
  final title = TextEditingController(text: 'A note from the desk');
  final body = TextEditingController();
  final result = await showDialog<({String title, String text})>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        title: const Text('Send a note'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: body,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Markdown note',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The note waits in the other device’s Nearby inbox.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (body.text.trim().isEmpty) return;
              Navigator.of(dialogContext)
                  .pop((title: title.text.trim(), text: body.text));
            },
            child: const Text('Send'),
          ),
        ],
      );
    },
  );
  title.dispose();
  body.dispose();
  return result;
}

Future<(String, int)?> _askAddress(BuildContext context) async {
  final host = TextEditingController();
  final port = TextEditingController(text: '45913');
  final result = await showDialog<(String, int)>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        title: const Text('Connect manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the LAN address and port shown on the other device’s '
              'Nearby screen.',
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: host,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: '192.168.1.20',
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cleanHost = host.text.trim();
              final cleanPort = int.tryParse(port.text.trim());
              if (cleanHost.isEmpty || cleanPort == null) return;
              Navigator.of(dialogContext).pop((cleanHost, cleanPort));
            },
            child: const Text('Connect'),
          ),
        ],
      );
    },
  );
  host.dispose();
  port.dispose();
  return result;
}

Future<void> _shareTextStandalone(BuildContext context) async {
  final shared = await _composeText(context);
  if (shared == null || !context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: shared.text,
      subject: shared.title,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

Future<void> _shareFileStandalone(BuildContext context) async {
  XFile? picked;
  try {
    picked = await openFile();
  } catch (error) {
    if (context.mounted) {
      showToast(context, 'Could not open the file picker: $error');
    }
    return;
  }
  if (picked == null || !context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(picked.path)],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

String _platformLabel(String platform) {
  return switch (platform) {
    'android' => 'Android',
    'ios' => 'iPhone',
    'linux' => 'Linux',
    'macos' => 'Mac',
    'windows' => 'Windows',
    _ => 'Device',
  };
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'android' => Icons.phone_android_rounded,
    'ios' => Icons.phone_iphone_rounded,
    'linux' => Icons.computer_rounded,
    'macos' => Icons.laptop_mac_rounded,
    'windows' => Icons.desktop_windows_rounded,
    _ => Icons.devices_other_rounded,
  };
}
