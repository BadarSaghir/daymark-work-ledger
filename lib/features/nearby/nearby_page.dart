import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../app/routes.dart';
import '../../data/models/journal_entry.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/lan_sync_service.dart';
import '../../data/services/task_bundle_service.dart';
import '../../state/backup_controller.dart';
import '../../state/categories_controller.dart';
import '../../state/journal_controller.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/task_picker.dart';

class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  LanSyncService? _service;
  StreamSubscription<List<LanPeer>>? _peerSub;
  StreamSubscription<List<LanInboxItem>>? _inboxSub;
  StreamSubscription<List<LanHistoryEntry>>? _historySub;
  List<LanPeer> _peers = const [];
  List<LanInboxItem> _inbox = const [];
  List<LanHistoryEntry> _history = const [];
  final _knownInbox = <String>{};
  bool _starting = false;
  bool _busy = false;
  String? _busyLabel;
  String? _error;
  String? _pairedPeerId;
  String? _pairedPin;
  int _tab = 0;

  LanPeer? get _pairedPeer {
    for (final peer in _peers) {
      if (peer.id == _pairedPeerId) return peer;
    }
    return null;
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _inboxSub?.cancel();
    _historySub?.cancel();
    unawaited(_service?.stop());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _service != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    await _requestNetworkPermission();
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
                : newest.isTask
                ? 'A task from ${newest.fromName} is ready to import.'
                : 'Received “${newest.title}” from ${newest.fromName}.',
            duration: const Duration(seconds: 4),
          );
        }
      });
      _historySub = service.historyStream.listen((history) {
        if (mounted) setState(() => _history = history);
      });
      setState(() {
        _service = service;
        _peers = service.peers;
        _inbox = service.inbox;
        _history = service.history;
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

  Future<void> _requestNetworkPermission() async {
    if (!Platform.isAndroid) return;
    final sdk = _androidSdkVersion;
    try {
      if (sdk == null || sdk >= 33) {
        await Permission.nearbyWifiDevices.request();
      }
      if (sdk == null || sdk >= 37) {
        final local = await Permission.accessLocalNetwork.request();
        if (!local.isGranted && mounted) {
          showToast(
            context,
            'Local network access is off. Allow Nearby devices for Daymark in '
            'system settings if discovery cannot find your other device.',
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (_) {
      // Older Android releases do not expose these runtime permissions.
    }
  }

  int? get _androidSdkVersion {
    final match = RegExp(r'SDK (\d+)')
        .firstMatch(Platform.operatingSystemVersion);
    return int.tryParse(match?.group(1) ?? '');
  }

  Future<void> _stop() async {
    final service = _service;
    await _peerSub?.cancel();
    await _inboxSub?.cancel();
    await _historySub?.cancel();
    _peerSub = null;
    _inboxSub = null;
    _historySub = null;
    if (mounted) {
      setState(() {
        _service = null;
        _peers = const [];
        _inbox = const [];
        _history = const [];
        _pairedPeerId = null;
        _pairedPin = null;
        _tab = 0;
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

  Future<String?> _pinFor(LanPeer peer) async {
    if (_pairedPeerId == peer.id && _pairedPin != null) return _pairedPin;
    return _askPin(context, peer, action: 'Connect');
  }

  Future<void> _rememberPair(LanPeer peer, String pin) async {
    if (_pairedPeerId == peer.id && _pairedPin == pin) return;
    if (!mounted) return;
    setState(() {
      _pairedPeerId = peer.id;
      _pairedPin = pin;
    });
  }

  Future<void> _sendSnapshot(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final pin = await _pinFor(peer);
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending…', () async {
      await service.sendSnapshot(peer, pin);
      return true;
    });
    if (done == true) {
      await _rememberPair(peer, pin);
      if (mounted) {
        showToast(
          context,
          'Snapshot sent to ${peer.name}. It waits there for confirmation.',
        );
      }
    }
  }

  Future<void> _pullSnapshot(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final pin = await _pinFor(peer);
    if (pin == null) return;
    final item = await _runBusy<LanInboxItem>(
      'Pulling…',
      () => service.pullSnapshot(peer, pin),
    );
    if (item != null) {
      await _rememberPair(peer, pin);
      if (mounted) {
        showToast(
          context,
          'Snapshot received. Restore it from the inbox when you are ready.',
        );
      }
    }
  }

  Future<void> _sendText(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final shared = await _composeText(context);
    if (shared == null || !mounted) return;
    final pin = await _pinFor(peer);
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending note…', () async {
      await service.sendText(peer, pin, title: shared.title, text: shared.text);
      return true;
    });
    if (done == true) {
      await _rememberPair(peer, pin);
      if (mounted) showToast(context, 'Note sent to ${peer.name}.');
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
    final pin = await _pinFor(peer);
    if (pin == null) return;
    final done = await _runBusy<bool>('Sending file…', () async {
      await service.sendFile(peer, pin, File(picked!.path));
      return true;
    });
    if (done == true) {
      await _rememberPair(peer, pin);
      if (mounted) showToast(context, 'File sent to ${peer.name}.');
    }
  }

  Future<void> _sendTask(LanPeer peer) async {
    final service = _service;
    if (service == null) return;
    final views = await ref.read(tasksProvider.future);
    if (!mounted) return;
    final view = await showTaskPicker(context, views);
    if (view == null || !mounted) return;
    final pin = await _pinFor(peer);
    if (pin == null) return;
    final done = await _runBusy<bool>('Packing task…', () async {
      final bundles = await ref.read(taskBundleServiceProvider.future);
      final export = await bundles.exportTask(view.task.id);
      await service.sendTask(
        peer,
        pin,
        bytes: export.bytes,
        title: export.title,
        fileName: export.fileName,
      );
      return true;
    });
    if (done == true) {
      await _rememberPair(peer, pin);
      if (mounted) {
        showToast(
          context,
          '“${view.task.title}” sent to ${peer.name}. Import it from their '
          'inbox whenever they are ready.',
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<LanPeer?> _choosePeer() async {
    if (_peers.isEmpty) return null;
    if (_peers.length == 1) return _peers.first;
    return showDialog<LanPeer>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.colors;
        return SimpleDialog(
          title: const Text('Sync with which device?'),
          children: [
            for (final peer in _peers)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(peer),
                child: Row(
                  children: [
                    Icon(
                      _platformIcon(peer.platform),
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.name,
                            style: AppText.bodyMedium.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            '${_platformLabel(peer.platform)} · ${peer.endpoint}',
                            style: AppText.monoData.copyWith(
                              color: colors.inkFaint,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _syncNow() async {
    final service = _service;
    if (service == null) return;
    var peer = _pairedPeer;
    peer ??= await _choosePeer();
    if (peer == null) {
      if (mounted) {
        showToast(
          context,
          'Pair or discover a device first. Show your QR and scan it on the '
          'other device.',
          duration: const Duration(seconds: 4),
        );
        _setTab(0);
      }
      return;
    }
    if (!mounted) return;
    final target = peer;
    final pin = await _pinFor(target);
    if (pin == null) return;
    final item = await _runBusy<LanInboxItem>(
      'Syncing both ways…',
      () => service.syncWithPeer(target, pin),
    );
    if (item == null) return;
    await _rememberPair(target, pin);
    if (!mounted) return;
    _setTab(2);
    showToast(
      context,
      'Ledger exchanged with ${target.name}. Their snapshot is in Inbox.',
      duration: const Duration(seconds: 5),
    );
  }

  void _setTab(int index) {
    if (!mounted || _tab == index) return;
    setState(() => _tab = index);
  }

  Future<void> _pairDevice() async {
    final canScan = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    if (!canScan) {
      await _pastePairingLink();
      return;
    }
    final granted = await _requestCameraPermission();
    if (!granted || !mounted) return;
    final raw = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _QrScannerDialog(),
    );
    if (raw == null || !mounted) return;
    await _applyPairing(raw);
  }

  Future<bool> _requestCameraPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.camera.request();
      if (status.isGranted) return true;
      if (mounted) {
        await _showPermissionHelp(
          title: 'Camera access is needed',
          message:
              'Daymark uses the camera only while this scanner is open. Allow '
              'Camera for Daymark in system settings, then try again.',
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _showPermissionHelp({
    required String title,
    required String message,
  }) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await openAppSettings();
  }

  Future<void> _pastePairingLink() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paste a pairing link'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'On the other device choose “Show pairing QR”, then copy its '
                'pairing link and paste it here.',
                style: AppText.bodySmall.copyWith(
                  color: dialogContext.colors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'daymark://pair?…',
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
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || !mounted) return;
    await _applyPairing(raw);
  }

  Future<void> _applyPairing(String raw) async {
    final pairing = LanPairing.parse(raw);
    if (pairing == null) {
      if (mounted) {
        showToast(
          context,
          'That is not a Daymark pairing code. Show a fresh QR and try again.',
        );
      }
      return;
    }
    final service = _service;
    if (service == null) return;
    final peer = await _runBusy<LanPeer?>(
      'Pairing…',
      () => service.probe(pairing.host, pairing.port),
    );
    if (peer == null) return;
    if (!mounted) return;
    setState(() {
      _pairedPeerId = peer.id;
      _pairedPin = pairing.pin;
      _tab = 1;
    });
    showToast(
      context,
      'Paired with ${peer.name}. The transfer code is remembered until you go '
      'offline.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _showPairingQr() async {
    final service = _service;
    if (service == null) return;
    final pairing = await service.pairingInfo();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _PairingQrDialog(
        pairing: pairing,
        pin: service.pin,
        port: service.port,
      ),
    );
  }

  Future<void> _clearHistory() async {
    final service = _service;
    if (service == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear transfer history?',
      message:
          'Received items in the inbox stay put. Only the audit trail of what '
          'was sent, received, restored, or journaled is removed.',
      confirmLabel: 'Clear history',
      danger: true,
      icon: Icons.history_toggle_off_rounded,
    );
    if (confirmed) await service.clearHistory();
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
    await _service?.markHistoryForItem(item.id, 'restored');
    _refreshAll();
    if (!mounted) return;
    showToast(
      context,
      result.warning ?? 'The snapshot was restored into this device.',
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _importTask(LanInboxItem item) async {
    final path = item.filePath;
    if (path == null || !await File(path).exists()) {
      if (mounted) showToast(context, 'That task bundle is no longer here.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Import this task?',
      message:
          'Notes, steps, tracked time, reminders, and files arrive with it. If '
          'the same task exists here, Daymark updates it when the incoming copy '
          'is newer. Every other task stays untouched.',
      confirmLabel: 'Import task',
      icon: Icons.task_alt_rounded,
    );
    if (!confirmed) return;
    final bundles = await ref.read(taskBundleServiceProvider.future);
    final result = await _runBusy<TaskBundleImportResult>(
      'Importing task…',
      () => bundles.importFile(File(path)),
    );
    if (result == null || !mounted) return;
    await _service?.markHistoryForItem(
      item.id,
      result.keptLocal ? 'kept-local' : 'imported',
    );
    _refreshAll();
    if (!mounted) return;
    if (result.keptLocal) {
      showToast(
        context,
        'Your local copy of “${result.title}” is newer, so it was kept. '
        'Share it back to bring the other device up to date.',
        duration: const Duration(seconds: 5),
      );
      return;
    }
    showToast(
      context,
      result.isNew
          ? '“${result.title}” imported as a new task.'
          : '“${result.title}” updated on this device.',
      duration: const Duration(seconds: 3),
    );
    await openTaskDetail(context, result.taskId);
  }

  Future<void> _saveTextToJournal(LanInboxItem item) async {
    final text = item.text?.trim() ?? '';
    if (text.isEmpty) return;
    final entries = ref.read(journalProvider).value ?? const [];
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
      await _service?.markHistoryForItem(item.id, 'journaled');
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'Close range, no cloud',
              title: 'Nearby',
              subtitle:
                  'Sync a ledger, send a note or file, and keep a clear record '
                  'of everything that moved between your devices.',
              actions: [
                if (online) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _syncNow,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sync now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _stop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Go offline'),
                  ),
                ] else
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
              _NearbyTabs(
                index: _tab,
                inboxCount: _inbox.length,
                historyCount: _history.length,
                onChanged: _setTab,
              ),
              const SizedBox(height: AppSpace.lg),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: _tabContent(service, wide),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _PrivacyNote(colors: colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabContent(LanSyncService service, bool wide) {
    switch (_tab) {
      case 1:
        return _sendTab(service, wide);
      case 2:
        return _InboxPanel(
          items: _inbox,
          busy: _busy,
          onRestoreSnapshot: _restoreSnapshot,
          onImportTask: _importTask,
          onSaveText: _saveTextToJournal,
          onTextToTask: _textToTask,
          onDelete: _deleteInboxItem,
        );
      case 3:
        return _HistoryPanel(
          entries: _history,
          busy: _busy,
          onClear: _clearHistory,
          onOpenInbox: () => _setTab(2),
        );
      default:
        return _syncTab(service, wide);
    }
  }

  Widget _syncTab(LanSyncService service, bool wide) {
    final device = _DeviceCard(
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
    );
    final pairing = _PairingCard(
      pairedPeer: _pairedPeer,
      canScan: Platform.isAndroid || Platform.isIOS || Platform.isMacOS,
      busy: _busy,
      onShowQr: _showPairingQr,
      onScan: _pairDevice,
      onPaste: _pastePairingLink,
      onManual: _manualConnect,
      onForget: () {
        setState(() {
          _pairedPeerId = null;
          _pairedPin = null;
        });
      },
    );
    final sync = _SyncNowCard(
      pairedPeer: _pairedPeer,
      peers: _peers.length,
      busy: _busy,
      busyLabel: _busyLabel,
      onSync: _syncNow,
      onPair: _pairDevice,
    );
    const permissions = _PermissionNotice();
    if (!wide) {
      return Column(
        children: [
          device,
          const SizedBox(height: AppSpace.lg),
          sync,
          const SizedBox(height: AppSpace.lg),
          pairing,
          const SizedBox(height: AppSpace.lg),
          permissions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            children: [
              device,
              const SizedBox(height: AppSpace.lg),
              pairing,
            ],
          ),
        ),
        const SizedBox(width: AppSpace.x3),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              sync,
              const SizedBox(height: AppSpace.lg),
              permissions,
            ],
          ),
        ),
      ],
    );
  }

  Widget _sendTab(LanSyncService service, bool wide) {
    final paired = _pairedPeer;
    final left = Column(
      children: [
        if (paired != null) ...[
          _PairedSendCard(
            peer: paired,
            busy: _busy,
            onLedger: () => _sendSnapshot(paired),
            onPull: () => _pullSnapshot(paired),
            onNote: () => _sendText(paired),
            onFile: () => _sendFile(paired),
            onTask: () => _sendTask(paired),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        _PeersCard(
          peers: _peers,
          busy: _busy,
          busyLabel: _busyLabel,
          onSendSnapshot: _sendSnapshot,
          onPullSnapshot: _pullSnapshot,
          onSendText: _sendText,
          onSendFile: _sendFile,
          onSendTask: _sendTask,
          onManual: _manualConnect,
        ),
      ],
    );
    final guide = _SendGuideCard(
      paired: paired,
      onPair: _pairDevice,
      onShareText: () => _shareTextStandalone(context),
      onShareFile: () => _shareFileStandalone(context),
    );
    if (!wide) {
      return Column(
        children: [
          left,
          const SizedBox(height: AppSpace.lg),
          guide,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: left),
        const SizedBox(width: AppSpace.x3),
        Expanded(flex: 4, child: guide),
      ],
    );
  }
}

class _NearbyTabs extends StatelessWidget {
  const _NearbyTabs({
    required this.index,
    required this.inboxCount,
    required this.historyCount,
    required this.onChanged,
  });

  final int index;
  final int inboxCount;
  final int historyCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _NearbyTabButton(
              label: 'Sync',
              icon: Icons.sync_rounded,
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
            _NearbyTabButton(
              label: 'Send',
              icon: Icons.north_east_rounded,
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
            _NearbyTabButton(
              label: inboxCount == 0 ? 'Inbox' : 'Inbox · $inboxCount',
              icon: Icons.move_to_inbox_outlined,
              selected: index == 2,
              onTap: () => onChanged(2),
            ),
            _NearbyTabButton(
              label: historyCount == 0 ? 'History' : 'History · $historyCount',
              icon: Icons.history_rounded,
              selected: index == 3,
              onTap: () => onChanged(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyTabButton extends StatelessWidget {
  const _NearbyTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.badge),
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.badge),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? colors.primary : colors.inkFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppText.bodySmall.copyWith(
                    color: selected ? colors.primary : colors.inkMuted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({
    required this.pairedPeer,
    required this.canScan,
    required this.busy,
    required this.onShowQr,
    required this.onScan,
    required this.onPaste,
    required this.onManual,
    required this.onForget,
  });

  final LanPeer? pairedPeer;
  final bool canScan;
  final bool busy;
  final VoidCallback onShowQr;
  final VoidCallback onScan;
  final VoidCallback onPaste;
  final VoidCallback onManual;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 18, color: colors.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Pairing',
                  style: AppText.titleM.copyWith(
                    color: colors.ink,
                    fontSize: 15.5,
                  ),
                ),
              ),
              if (pairedPeer != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.green.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'PAIRED',
                    style: AppText.label.copyWith(
                      color: colors.green,
                      fontSize: 8,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (pairedPeer != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: colors.primarySoft.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  Icon(
                    _platformIcon(pairedPeer!.platform),
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pairedPeer!.name,
                          style: AppText.bodyMedium.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_platformLabel(pairedPeer!.platform)} · '
                          '${pairedPeer!.endpoint}',
                          style: AppText.monoData.copyWith(
                            color: colors.inkFaint,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onForget,
                    child: const Text('Forget'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ] else
            Text(
              'Pair once, then Sync now reuses the code until you go offline. '
              'The QR contains the same six-digit code shown on this screen.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkMuted,
                fontSize: 10.8,
                height: 1.5,
              ),
            ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onShowQr,
                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                label: const Text('Show pairing QR'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : (canScan ? onScan : onPaste),
                icon: Icon(
                  canScan
                      ? Icons.qr_code_scanner_rounded
                      : Icons.content_paste_rounded,
                  size: 16,
                ),
                label: Text(canScan ? 'Scan QR' : 'Paste link'),
              ),
              if (canScan)
                TextButton(
                  onPressed: busy ? null : onPaste,
                  child: const Text('Paste link'),
                ),
              TextButton(
                onPressed: busy ? null : onManual,
                child: const Text('Manual address'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncNowCard extends StatelessWidget {
  const _SyncNowCard({
    required this.pairedPeer,
    required this.peers,
    required this.busy,
    required this.busyLabel,
    required this.onSync,
    required this.onPair,
  });

  final LanPeer? pairedPeer;
  final int peers;
  final bool busy;
  final String? busyLabel;
  final VoidCallback onSync;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = pairedPeer?.name;
    return SurfaceCard(
      color: colors.primarySoft.withValues(alpha: 0.28),
      borderColor: colors.primary.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Icon(
                Icons.sync_rounded,
                size: 21,
                color: colors.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'One-tap sync',
            style: AppText.titleM.copyWith(color: colors.ink, fontSize: 17),
          ),
          const SizedBox(height: 3),
          Text(
            target != null
                ? 'Exchange the latest ledger with $target. Their copy waits '
                      'in Inbox; nothing is overwritten automatically.'
                : peers > 0
                ? 'Choose a nearby device, exchange both ledgers, and review '
                      'their copy in Inbox.'
                : 'Pair a device first. Show this device’s QR and scan it on '
                      'the other device, then sync with one tap.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkMuted,
              fontSize: 11.2,
              height: 1.5,
            ),
          ),
          if (busy && busyLabel != null) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpace.sm),
                Text(
                  busyLabel!,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: busy
                ? null
                : (pairedPeer == null && peers == 0 ? onPair : onSync),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            icon: Icon(
              pairedPeer == null && peers == 0
                  ? Icons.qr_code_scanner_rounded
                  : Icons.sync_rounded,
              size: 18,
            ),
            label: Text(
              pairedPeer == null && peers == 0 ? 'Pair a device' : 'Sync now',
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final copy = switch (Platform.operatingSystem) {
      'android' =>
        'Allow Camera for QR scanning. Android may also ask for Nearby devices '
            'or Local network access; both are used only for device-to-device '
            'transfers.',
      'ios' =>
        'Allow Local Network to discover another Daymark device and Camera to '
            'scan a pairing QR. Transfers never leave your Wi-Fi.',
      'macos' =>
        'Allow Camera for QR scanning. Approve incoming connections if macOS '
            'asks; the LAN server binds only to your local network.',
      'windows' =>
        'Allow Daymark through Windows Firewall on private networks. If '
            'discovery stays empty, use Manual address.',
      'linux' =>
        'Allow Daymark through your firewall on trusted networks. If '
            'discovery stays empty, use Manual address.',
      _ => 'Camera is used only while scanning. Nothing is sent to the cloud.',
    };
    final canOpenSettings = Platform.isAndroid || Platform.isIOS;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 16, color: colors.blue),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permissions on this device',
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  copy,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
                if (canOpenSettings)
                  TextButton(
                    onPressed: openAppSettings,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Open system settings'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedSendCard extends StatelessWidget {
  const _PairedSendCard({
    required this.peer,
    required this.busy,
    required this.onLedger,
    required this.onPull,
    required this.onNote,
    required this.onFile,
    required this.onTask,
  });

  final LanPeer peer;
  final bool busy;
  final VoidCallback onLedger;
  final VoidCallback onPull;
  final VoidCallback onNote;
  final VoidCallback onFile;
  final VoidCallback onTask;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _platformIcon(peer.platform),
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Send to ${peer.name}',
                  style: AppText.titleM.copyWith(
                    color: colors.ink,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Text(
                'PAIRED',
                style: AppText.label.copyWith(color: colors.green, fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'The transfer code is already remembered for this session.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onTask,
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                label: const Text('Send task'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onNote,
                icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
                label: const Text('Send note'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onFile,
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: const Text('Send file'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onLedger,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Send ledger'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onPull,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Pull theirs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SendGuideCard extends StatelessWidget {
  const _SendGuideCard({
    required this.paired,
    required this.onPair,
    required this.onShareText,
    required this.onShareFile,
  });

  final LanPeer? paired;
  final VoidCallback onPair;
  final VoidCallback onShareText;
  final VoidCallback onShareFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What can I send?',
            style: AppText.titleM.copyWith(color: colors.ink, fontSize: 15.5),
          ),
          const SizedBox(height: AppSpace.md),
          const _GuideRow(
            icon: Icons.sticky_note_2_outlined,
            title: 'A note',
            body:
                'Markdown text lands in the other device’s Inbox, ready for '
                'the journal or a task.',
          ),
          const _GuideRow(
            icon: Icons.attach_file_rounded,
            title: 'A file',
            body:
                'Any file up to 100 MB. It stays in Inbox until you share or '
                'copy it.',
          ),
          const _GuideRow(
            icon: Icons.inventory_2_outlined,
            title: 'The ledger',
            body:
                'A full snapshot. The other device reviews it before any '
                'restore happens.',
          ),
          if (paired == null) ...[
            const SizedBox(height: AppSpace.sm),
            FilledButton.tonalIcon(
              onPressed: onPair,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
              label: const Text('Pair a device'),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Divider(color: colors.line),
          const SizedBox(height: AppSpace.sm),
          Text(
            'No receiver? Use the system share sheet.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkMuted,
              fontSize: 10.8,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              OutlinedButton.icon(
                onPressed: onShareText,
                icon: const Icon(Icons.text_snippet_outlined, size: 15),
                label: const Text('Share text'),
              ),
              OutlinedButton.icon(
                onPressed: onShareFile,
                icon: const Icon(Icons.attach_file_rounded, size: 15),
                label: const Text('Share file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
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
                  title,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  body,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel({
    required this.entries,
    required this.busy,
    required this.onClear,
    required this.onOpenInbox,
  });

  final List<LanHistoryEntry> entries;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onOpenInbox;

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  int _filter = 0; // 0 all, 1 sent, 2 received

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = widget.entries.where((entry) {
      if (_filter == 1) return entry.isSent;
      if (_filter == 2) return entry.isReceived;
      return true;
    }).toList();
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
                      'Transfer history',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      'A durable record of ledgers, notes, and files. It stays '
                      'after an item leaves the inbox.',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.entries.isNotEmpty)
                TextButton(
                  onPressed: widget.busy ? null : widget.onClear,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _HistoryFilter(
                label: 'All',
                count: widget.entries.length,
                selected: _filter == 0,
                onTap: () => setState(() => _filter = 0),
              ),
              _HistoryFilter(
                label: 'Sent',
                count: widget.entries.where((entry) => entry.isSent).length,
                selected: _filter == 1,
                onTap: () => setState(() => _filter = 1),
              ),
              _HistoryFilter(
                label: 'Received',
                count: widget.entries.where((entry) => entry.isReceived).length,
                selected: _filter == 2,
                onTap: () => setState(() => _filter = 2),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (entries.isEmpty)
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
                  Icon(Icons.history_rounded, size: 26, color: colors.inkFaint),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'No transfers recorded yet',
                    style: AppText.bodyMedium.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Send or receive a ledger, note, or file and it will appear '
                    'here with its status.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.8,
                    ),
                  ),
                  if (_filter == 2) ...[
                    const SizedBox(height: AppSpace.md),
                    TextButton(
                      onPressed: widget.onOpenInbox,
                      child: const Text('Open inbox'),
                    ),
                  ],
                ],
              ),
            )
          else
            for (final entry in entries) _HistoryRow(entry: entry),
        ],
      ),
    );
  }
}

class _HistoryFilter extends StatelessWidget {
  const _HistoryFilter({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected
          ? colors.primarySoft
          : colors.surfaceSunken.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '$label · $count',
            style: AppText.bodySmall.copyWith(
              color: selected ? colors.primary : colors.inkMuted,
              fontSize: 10.8,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final LanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = switch (entry.kind) {
      'snapshot' => Icons.inventory_2_outlined,
      'text' => Icons.sticky_note_2_outlined,
      'task' => Icons.task_alt_rounded,
      _ => Icons.attach_file_rounded,
    };
    final (statusLabel, statusColor) = switch (entry.status) {
      'sent' => ('Sent', colors.blue),
      'received' => ('In inbox', colors.accent),
      'restored' => ('Restored', colors.green),
      'imported' => ('Imported', colors.green),
      'kept-local' => ('Local kept', colors.gold),
      'journaled' => ('In journal', colors.gold),
      'removed' => ('Removed', colors.inkFaint),
      _ => (entry.status, colors.inkFaint),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
            child: Icon(icon, size: 16, color: colors.primary),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      entry.isSent
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      size: 12,
                      color: entry.isSent ? colors.blue : colors.accent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.isSent ? 'To' : 'From'} ${entry.peerName} · '
                  '${savedLabel(entry.createdAt, DateTime.now())}'
                  '${entry.sizeLabel.isEmpty ? '' : ' · ${entry.sizeLabel}'}',
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              statusLabel,
              style: AppText.label.copyWith(color: statusColor, fontSize: 7.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingQrDialog extends StatelessWidget {
  const _PairingQrDialog({
    required this.pairing,
    required this.pin,
    required this.port,
  });

  final LanPairing? pairing;
  final String pin;
  final int? port;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = pairing?.encode();
    return AlertDialog(
      title: const Text('Scan to pair'),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pairing == null
                    ? 'Daymark could not detect a LAN address. Use Manual '
                          'address on the other device with the port below.'
                    : 'Open Daymark on the other device, choose Nearby → Sync → '
                          'Scan QR, and point the camera here.',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              if (data != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: colors.line),
                    ),
                    child: QrImageView(
                      data: data,
                      size: 226,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        size: 54,
                        color: colors.inkFaint,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'No LAN address detected',
                        style: AppText.bodyMedium.copyWith(color: colors.ink),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.md),
              Center(
                child: SelectableText(
                  pin.split('').join(' '),
                  style: AppText.monoLarge.copyWith(
                    color: colors.ink,
                    fontSize: 24,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Center(
                child: Text(
                  pairing == null
                      ? 'Port ${port ?? 'unknown'}'
                      : '${pairing!.host}:${pairing!.port}',
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'The QR carries this session’s six-digit code. Treat it like '
                'the code itself and show it only to your own device.',
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (data != null)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data));
              showToast(context, 'Pairing link copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copy link'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  bool _handled = false;

  void _detected(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(AppSpace.lg),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SizedBox(
          height: 480,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                onDetect: _detected,
                fit: BoxFit.cover,
                errorBuilder: (context, error) {
                  final denied =
                      error.errorCode ==
                      MobileScannerErrorCode.permissionDenied;
                  final canOpenSettings = Platform.isAndroid || Platform.isIOS;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.no_photography_outlined,
                            color: Colors.white70,
                            size: 34,
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Text(
                            denied
                                ? 'Camera access is off'
                                : 'The camera could not start',
                            textAlign: TextAlign.center,
                            style: AppText.titleM.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            denied
                                ? 'Allow Camera for Daymark in system settings, '
                                      'then reopen the scanner.'
                                : '$error',
                            textAlign: TextAlign.center,
                            style: AppText.bodySmall.copyWith(
                              color: Colors.white60,
                              fontSize: 10.8,
                            ),
                          ),
                          if (denied && canOpenSettings) ...[
                            const SizedBox(height: AppSpace.md),
                            OutlinedButton(
                              onPressed: openAppSettings,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                              ),
                              child: const Text('Open settings'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Scan a Daymark pairing QR',
                        style: AppText.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close scanner',
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: AppSpace.lg,
                right: AppSpace.lg,
                bottom: AppSpace.lg,
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Text(
                    'Point at the QR on the other device’s Sync tab.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: Colors.white,
                      fontSize: 10.8,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.primarySoft, width: 3),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    required this.onSendTask,
    required this.onManual,
  });

  final List<LanPeer> peers;
  final bool busy;
  final String? busyLabel;
  final ValueChanged<LanPeer> onSendSnapshot;
  final ValueChanged<LanPeer> onPullSnapshot;
  final ValueChanged<LanPeer> onSendText;
  final ValueChanged<LanPeer> onSendFile;
  final ValueChanged<LanPeer> onSendTask;
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
                onSendTask: () => onSendTask(peer),
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
    required this.onSendTask,
  });

  final LanPeer peer;
  final bool busy;
  final VoidCallback onSendSnapshot;
  final VoidCallback onPullSnapshot;
  final VoidCallback onSendText;
  final VoidCallback onSendFile;
  final VoidCallback onSendTask;

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
                    case 'task':
                      onSendTask();
                      break;
                    case 'text':
                      onSendText();
                      break;
                    case 'file':
                      onSendFile();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'task',
                    child: MenuAction(
                      icon: Icons.task_alt_rounded,
                      label: 'Send one task',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'text',
                    child: MenuAction(
                      icon: Icons.notes_rounded,
                      label: 'Send a note',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'file',
                    child: MenuAction(
                      icon: Icons.attach_file_rounded,
                      label: 'Send a file',
                    ),
                  ),
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
                onPressed: busy ? null : onSendTask,
                icon: const Icon(Icons.task_alt_rounded, size: 15),
                label: const Text('Send task'),
              ),
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
    required this.onImportTask,
    required this.onSaveText,
    required this.onTextToTask,
    required this.onDelete,
  });

  final List<LanInboxItem> items;
  final bool busy;
  final ValueChanged<LanInboxItem> onRestoreSnapshot;
  final ValueChanged<LanInboxItem> onImportTask;
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
                onImportTask: () => onImportTask(item),
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
    required this.onImportTask,
    required this.onSaveText,
    required this.onTextToTask,
    required this.onDelete,
  });

  final LanInboxItem item;
  final bool busy;
  final VoidCallback onRestoreSnapshot;
  final VoidCallback onImportTask;
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
        : item.isTask
        ? Icons.task_alt_rounded
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
                  PopupMenuItem(
                    value: 'share',
                    child: MenuAction(
                      icon: Icons.ios_share_rounded,
                      label: 'Share copy',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: MenuAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                    ),
                  ),
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
          else if (item.isTask)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onImportTask,
                  icon: const Icon(Icons.download_done_rounded, size: 15),
                  label: const Text('Import task'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _shareItem(context),
                  icon: const Icon(Icons.ios_share_rounded, size: 15),
                  label: const Text('Share bundle'),
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
