import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'backup_service.dart';

class LanException implements Exception {
  LanException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LanPeer {
  const LanPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;

  String get endpoint => '${address.address}:$port';

  LanPeer copyWith({
    String? name,
    String? platform,
    InternetAddress? address,
    int? port,
    DateTime? lastSeen,
  }) {
    return LanPeer(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      address: address ?? this.address,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// A durable, human-readable audit trail of transfers. It intentionally
/// outlives the inbox so a restored, journaled, or discarded item still has a
/// record of where it came from.
class LanHistoryEntry {
  const LanHistoryEntry({
    required this.id,
    required this.direction,
    required this.kind,
    required this.title,
    required this.peerName,
    required this.createdAt,
    required this.status,
    this.itemId,
    this.sizeBytes = 0,
  });

  final String id;

  /// `sent` or `received`.
  final String direction;

  /// `snapshot`, `text`, `file`, or `task`.
  final String kind;
  final String title;
  final String peerName;
  final DateTime createdAt;
  final String status;
  final String? itemId;
  final int sizeBytes;

  bool get isSent => direction == 'sent';
  bool get isReceived => direction == 'received';

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).ceil()} KB';
  }

  LanHistoryEntry copyWith({String? status}) => LanHistoryEntry(
    id: id,
    direction: direction,
    kind: kind,
    title: title,
    peerName: peerName,
    createdAt: createdAt,
    status: status ?? this.status,
    itemId: itemId,
    sizeBytes: sizeBytes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'direction': direction,
    'kind': kind,
    'title': title,
    'peer': peerName,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
    'status': status,
    'itemId': itemId,
    'sizeBytes': sizeBytes,
  };

  static LanHistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final direction = raw['direction']?.toString();
    final kind = raw['kind']?.toString();
    final title = raw['title']?.toString();
    final peer = raw['peer']?.toString();
    if (id == null ||
        direction == null ||
        kind == null ||
        title == null ||
        peer == null) {
      return null;
    }
    return LanHistoryEntry(
      id: id,
      direction: direction,
      kind: kind,
      title: title,
      peerName: peer,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['createdAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
      status: raw['status']?.toString() ?? 'received',
      itemId: raw['itemId']?.toString(),
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The payload carried by a pairing QR code. It contains the same short-lived
/// code shown on the receiving screen; anyone who can see the screen can use
/// it. Nothing is persisted and the code changes whenever Nearby starts.
class LanPairing {
  const LanPairing({
    required this.host,
    required this.port,
    required this.pin,
    required this.name,
    required this.deviceId,
  });

  final String host;
  final int port;
  final String pin;
  final String name;
  final String deviceId;

  String encode() => Uri(
    scheme: 'daymark',
    host: 'pair',
    queryParameters: {
      'host': host,
      'port': '$port',
      'pin': pin,
      'name': name,
      if (deviceId.isNotEmpty) 'id': deviceId,
    },
  ).toString();

  static LanPairing? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme != 'daymark' || uri.host != 'pair') {
      return null;
    }
    final host = uri.queryParameters['host']?.trim() ?? '';
    final port = int.tryParse(uri.queryParameters['port']?.trim() ?? '');
    final pin = uri.queryParameters['pin']?.trim() ?? '';
    if (host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      return null;
    }
    return LanPairing(
      host: host,
      port: port,
      pin: pin,
      name: uri.queryParameters['name']?.trim().isNotEmpty == true
          ? uri.queryParameters['name']!.trim()
          : 'Daymark device',
      deviceId: uri.queryParameters['id']?.trim() ?? '',
    );
  }
}

class LanInboxItem {
  const LanInboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.fromName,
    required this.receivedAt,
    this.text,
    this.filePath,
    this.sizeBytes = 0,
  });

  final String id;

  /// `snapshot`, `text`, `file`, or `task`.
  final String kind;
  final String title;
  final String fromName;
  final DateTime receivedAt;
  final String? text;
  final String? filePath;
  final int sizeBytes;

  bool get isSnapshot => kind == 'snapshot';
  bool get isText => kind == 'text';
  bool get isFile => kind == 'file';
  bool get isTask => kind == 'task';

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).ceil()} KB';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'from': fromName,
    'receivedAt': receivedAt.toUtc().millisecondsSinceEpoch,
    'text': text,
    'filePath': filePath,
    'sizeBytes': sizeBytes,
  };

  static LanInboxItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final kind = raw['kind']?.toString();
    final title = raw['title']?.toString();
    final from = raw['from']?.toString();
    if (id == null || kind == null || title == null || from == null) {
      return null;
    }
    return LanInboxItem(
      id: id,
      kind: kind,
      title: title,
      fromName: from,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['receivedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
      text: raw['text']?.toString(),
      filePath: raw['filePath']?.toString(),
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Discovery + transfer over the local network. There is deliberately no
/// cloud relay: the two devices must be able to reach each other directly.
/// A six-digit code, visible only on the receiving device, guards every
/// transfer. Traffic is not encrypted, so use this on networks you trust.
class LanSyncService {
  LanSyncService({
    required this.backupService,
    required this.directory,
    required this.deviceName,
  });

  final BackupService backupService;
  final Directory directory;
  final String deviceName;

  static const protocol = 1;
  static const discoveryPort = 45913;
  static const multicastAddress = '239.255.73.77';
  static const maxPayloadBytes = 100 * 1024 * 1024;

  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  String? _deviceId;
  String _pin = '000000';
  bool _started = false;
  bool _receiving = true;
  String? discoveryError;

  final Map<String, LanPeer> _peers = {};
  List<LanInboxItem> _items = const [];
  List<LanHistoryEntry> _history = const [];
  final _peerController = StreamController<List<LanPeer>>.broadcast();
  final _inboxController = StreamController<List<LanInboxItem>>.broadcast();
  final _historyController =
      StreamController<List<LanHistoryEntry>>.broadcast();

  bool get isStarted => _started;
  bool get isReceiving => _receiving;
  int? get port => _server?.port;
  String get pin => _pin;
  String get deviceId => _deviceId ?? '';
  List<LanPeer> get peers => List.unmodifiable(
    _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
  List<LanInboxItem> get inbox => List.unmodifiable(_items);
  List<LanHistoryEntry> get history => List.unmodifiable(_history);
  Stream<List<LanPeer>> get peersStream => _peerController.stream;
  Stream<List<LanInboxItem>> get inboxStream => _inboxController.stream;
  Stream<List<LanHistoryEntry>> get historyStream => _historyController.stream;

  String get displayName {
    final clean = deviceName.trim();
    return clean.isEmpty ? 'Daymark device' : clean;
  }

  Future<void> start() async {
    if (_started) return;
    await directory.create(recursive: true);
    _deviceId = await _loadDeviceId();
    _pin = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
    await _loadInbox();
    await _loadHistory();

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((request) {
      unawaited(_handleSafely(request));
    });

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      try {
        socket.joinMulticast(InternetAddress(multicastAddress));
      } catch (_) {
        // Multicast is a bonus. Broadcast still works on most home networks.
      }
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleAnnouncement(datagram);
      }, onError: (_) {});
      _udp = socket;
      _announce();
      _announceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _announce(),
      );
      _pruneTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _prunePeers(),
      );
    } catch (error) {
      discoveryError =
          'Discovery could not start (${_shortError(error)}). You can still '
          'connect manually if the other device shows an address.';
    }

    _started = true;
    _emitPeers();
  }

  Future<void> stop() async {
    _started = false;
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _announceTimer = null;
    _pruneTimer = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _peers.clear();
    if (!_peerController.isClosed) _peerController.add(const []);
    if (!_inboxController.isClosed) {
      _inboxController.add(List.unmodifiable(_items));
    }
    if (!_historyController.isClosed) {
      _historyController.add(List.unmodifiable(_history));
    }
    await _peerController.close();
    await _inboxController.close();
    await _historyController.close();
  }

  void setReceiving(bool value) {
    _receiving = value;
  }

  /// Builds a shareable pairing payload for the current session. Returns null
  /// when no non-loopback IPv4 address is available.
  Future<LanPairing?> pairingInfo() async {
    final serverPort = port;
    if (!_started || serverPort == null) return null;
    final host = await _localAddress();
    if (host == null) return null;
    return LanPairing(
      host: host,
      port: serverPort,
      pin: _pin,
      name: displayName,
      deviceId: deviceId,
    );
  }

  Future<LanPeer?> probe(String host, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri(scheme: 'http', host: host, port: port, path: '/v1/info');
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw LanException(_responseError(body, response.statusCode));
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['app'] != 'daymark.lan') {
        throw LanException('That address does not look like Daymark.');
      }
      final peer = LanPeer(
        id: decoded['deviceId']?.toString() ?? '$host:$port',
        name: decoded['name']?.toString() ?? 'Daymark device',
        platform: decoded['platform']?.toString() ?? 'unknown',
        address: InternetAddress(host),
        port: (decoded['port'] as num?)?.toInt() ?? port,
        lastSeen: DateTime.now(),
      );
      _peers[peer.id] = peer;
      _emitPeers();
      return peer;
    } on LanException {
      rethrow;
    } catch (error) {
      throw LanException(
        'Could not reach $host:$port (${_shortError(error)}).',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> sendSnapshot(LanPeer peer, String pin) async {
    final bytes = await backupService.createBackupBytes();
    await _post(
      peer,
      '/v1/snapshot',
      pin,
      bytes,
      contentType: 'application/zip',
    );
    await _recordHistory(
      direction: 'sent',
      kind: 'snapshot',
      title: 'Ledger snapshot',
      peerName: peer.name,
      sizeBytes: bytes.length,
      status: 'sent',
    );
  }

  /// Exchanges the latest ledger in both directions. Each snapshot waits in
  /// the other device's inbox, so syncing never silently replaces data.
  Future<LanInboxItem> syncWithPeer(LanPeer peer, String pin) async {
    await sendSnapshot(peer, pin);
    return pullSnapshot(peer, pin);
  }

  Future<LanInboxItem> pullSnapshot(LanPeer peer, String pin) async {
    final bytes = await _get(peer, '/v1/snapshot', pin);
    final file = await _snapshotFile('pull', peer.name);
    await file.writeAsBytes(bytes, flush: true);
    final item = LanInboxItem(
      id: const Uuid().v4(),
      kind: 'snapshot',
      title: 'Snapshot pulled from ${peer.name}',
      fromName: peer.name,
      receivedAt: DateTime.now(),
      filePath: file.path,
      sizeBytes: bytes.length,
    );
    await _addInbox(item);
    return item;
  }

  Future<void> sendText(
    LanPeer peer,
    String pin, {
    required String title,
    required String text,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'Shared note' : title.trim();
    final body = jsonEncode({'title': cleanTitle, 'text': text});
    await _post(
      peer,
      '/v1/text',
      pin,
      Uint8List.fromList(utf8.encode(body)),
      contentType: 'application/json; charset=utf-8',
    );
    await _recordHistory(
      direction: 'sent',
      kind: 'text',
      title: cleanTitle,
      peerName: peer.name,
      sizeBytes: utf8.encode(text).length,
      status: 'sent',
    );
  }

  Future<void> sendFile(LanPeer peer, String pin, File file) async {
    final stat = await file.stat();
    if (stat.size > maxPayloadBytes) {
      throw LanException('That file is larger than 100 MB.');
    }
    final bytes = await file.readAsBytes();
    await _post(
      peer,
      '/v1/file',
      pin,
      bytes,
      contentType: 'application/octet-stream',
      extraQuery: {'name': p.basename(file.path), 'from': displayName},
    );
    await _recordHistory(
      direction: 'sent',
      kind: 'file',
      title: p.basename(file.path),
      peerName: peer.name,
      sizeBytes: bytes.length,
      status: 'sent',
    );
  }

  /// Sends a single task bundle. Unlike a ledger snapshot, the receiver can
  /// import this straight into their ledger while both devices keep working.
  Future<void> sendTask(
    LanPeer peer,
    String pin, {
    required Uint8List bytes,
    required String title,
    required String fileName,
  }) async {
    if (bytes.length > maxPayloadBytes) {
      throw LanException('That task bundle is larger than 100 MB.');
    }
    final cleanTitle = _cleanLabel(title, fallback: 'Shared task');
    final safeName = _safeFileName(
      fileName,
      fallback: 'daymark-task.daymark-task',
    );
    await _post(
      peer,
      '/v1/task',
      pin,
      bytes,
      contentType: 'application/zip',
      extraQuery: {'name': safeName, 'title': cleanTitle},
    );
    await _recordHistory(
      direction: 'sent',
      kind: 'task',
      title: cleanTitle,
      peerName: peer.name,
      sizeBytes: bytes.length,
      status: 'sent',
    );
  }

  Future<void> markHistoryForItem(String itemId, String status) async {
    var changed = false;
    _history = [
      for (final entry in _history)
        if (entry.itemId == itemId && entry.status != status)
          () {
            changed = true;
            return entry.copyWith(status: status);
          }()
        else
          entry,
    ];
    if (!changed) return;
    await _saveHistory();
    _emitHistory();
  }

  Future<void> clearHistory() async {
    _history = const [];
    await _saveHistory();
    _emitHistory();
  }

  Future<void> deleteInboxItem(LanInboxItem item) async {
    if (item.filePath != null) {
      try {
        final file = File(item.filePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A missing file should not strand the inbox entry.
      }
    }
    _items = [
      for (final existing in _items)
        if (existing.id != item.id) existing,
    ];
    await _saveInbox();
    await markHistoryForItem(item.id, 'removed');
    _emitInbox();
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handleRequest(request);
    } catch (error) {
      try {
        await _json(request.response, 500, {
          'ok': false,
          'error': 'The transfer failed: ${_shortError(error)}',
        });
      } catch (_) {}
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null || !_isPrivateAddress(remote)) {
      await _json(request.response, 403, {
        'ok': false,
        'error': 'Daymark only accepts transfers from the local network.',
      });
      return;
    }

    final path = request.uri.path;
    final method = request.method;

    if (method == 'GET' && path == '/v1/info') {
      await _json(request.response, 200, {
        'app': 'daymark.lan',
        'protocol': protocol,
        'deviceId': deviceId,
        'name': displayName,
        'platform': Platform.operatingSystem,
        'port': port,
        'pinRequired': true,
        'version': '1.5.0',
      });
      return;
    }

    if (!_checkPin(request)) {
      await _json(request.response, 401, {
        'ok': false,
        'error': 'Wrong code. Ask the other device to show its current code.',
      });
      return;
    }
    if (!_receiving) {
      await _json(request.response, 403, {
        'ok': false,
        'error': 'Receiving is turned off on this device.',
      });
      return;
    }

    if (method == 'GET' && path == '/v1/snapshot') {
      final bytes = await backupService.createBackupBytes();
      final response = request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'zip')
        ..headers.set(
          'content-disposition',
          'attachment; filename="daymark-lan.zip"',
        )
        ..contentLength = bytes.length
        ..add(bytes);
      await response.close();
      return;
    }

    if (method == 'POST' && path == '/v1/snapshot') {
      final bytes = await _readBody(request);
      final from = _cleanLabel(
        request.uri.queryParameters['from'],
        fallback: 'Nearby device',
      );
      final file = await _snapshotFile('lan', from);
      await file.writeAsBytes(bytes, flush: true);
      final item = LanInboxItem(
        id: const Uuid().v4(),
        kind: 'snapshot',
        title: 'Snapshot from $from',
        fromName: from,
        receivedAt: DateTime.now(),
        filePath: file.path,
        sizeBytes: bytes.length,
      );
      await _addInbox(item);
      await _json(request.response, 201, {'ok': true, 'id': item.id});
      return;
    }

    if (method == 'POST' && path == '/v1/text') {
      final raw = await _readBody(request, limit: 2 * 1024 * 1024);
      final decoded = jsonDecode(utf8.decode(raw, allowMalformed: false));
      if (decoded is! Map) {
        throw LanException('The shared note has an unexpected shape.');
      }
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw LanException('The shared note was empty.');
      }
      final from = _cleanLabel(
        request.uri.queryParameters['from'],
        fallback: 'Nearby device',
      );
      final title = _cleanLabel(
        decoded['title']?.toString(),
        fallback: 'Shared note',
        maxLength: 120,
      );
      final item = LanInboxItem(
        id: const Uuid().v4(),
        kind: 'text',
        title: title,
        fromName: from,
        receivedAt: DateTime.now(),
        text: text,
        sizeBytes: utf8.encode(text).length,
      );
      await _addInbox(item);
      await _json(request.response, 201, {'ok': true, 'id': item.id});
      return;
    }

    if (method == 'POST' && path == '/v1/file') {
      final bytes = await _readBody(request);
      final originalName = _safeFileName(
        request.uri.queryParameters['name'],
        fallback: 'shared-file',
      );
      final from = _cleanLabel(
        request.uri.queryParameters['from'],
        fallback: 'Nearby device',
      );
      final files = Directory(p.join(directory.path, 'files'));
      await files.create(recursive: true);
      final stamp = _stamp(DateTime.now());
      final file = File(p.join(files.path, '$stamp-$originalName'));
      await file.writeAsBytes(bytes, flush: true);
      final item = LanInboxItem(
        id: const Uuid().v4(),
        kind: 'file',
        title: originalName,
        fromName: from,
        receivedAt: DateTime.now(),
        filePath: file.path,
        sizeBytes: bytes.length,
      );
      await _addInbox(item);
      await _json(request.response, 201, {'ok': true, 'id': item.id});
      return;
    }

    if (method == 'POST' && path == '/v1/task') {
      final bytes = await _readBody(request);
      final originalName = _safeFileName(
        request.uri.queryParameters['name'],
        fallback: 'daymark-task.daymark-task',
      );
      final from = _cleanLabel(
        request.uri.queryParameters['from'],
        fallback: 'Nearby device',
      );
      final title = _cleanLabel(
        request.uri.queryParameters['title'],
        fallback: 'Shared task',
        maxLength: 160,
      );
      final tasks = Directory(p.join(directory.path, 'tasks'));
      await tasks.create(recursive: true);
      final stamp = _stamp(DateTime.now());
      final safeName = originalName.endsWith('.daymark-task')
          ? originalName
          : '$originalName.daymark-task';
      final file = File(p.join(tasks.path, '$stamp-$safeName'));
      await file.writeAsBytes(bytes, flush: true);
      final item = LanInboxItem(
        id: const Uuid().v4(),
        kind: 'task',
        title: title,
        fromName: from,
        receivedAt: DateTime.now(),
        filePath: file.path,
        sizeBytes: bytes.length,
      );
      await _addInbox(item);
      await _json(request.response, 201, {'ok': true, 'id': item.id});
      return;
    }

    await _json(request.response, 404, {
      'ok': false,
      'error': 'Unknown Daymark transfer endpoint.',
    });
  }

  bool _checkPin(HttpRequest request) {
    final candidate =
        request.headers.value('x-daymark-pin') ??
        request.uri.queryParameters['pin'];
    return candidate != null && candidate == _pin;
  }

  Future<Uint8List> _readBody(
    HttpRequest request, {
    int limit = maxPayloadBytes,
  }) async {
    if (request.contentLength > limit) {
      throw LanException('The transfer is larger than the 100 MB limit.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw LanException('The transfer is larger than the 100 MB limit.');
      }
    }
    return builder.takeBytes();
  }

  Future<void> _post(
    LanPeer peer,
    String path,
    String pin,
    Uint8List bytes, {
    required String contentType,
    Map<String, String> extraQuery = const {},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri(
        scheme: 'http',
        host: peer.address.address,
        port: peer.port,
        path: path,
        queryParameters: {'from': displayName, ...extraQuery},
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-daymark-pin', pin);
      request.headers.contentType = ContentType.parse(contentType);
      request.add(bytes);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LanException(_responseError(body, response.statusCode));
      }
    } on LanException {
      rethrow;
    } catch (error) {
      throw LanException(
        'Could not reach ${peer.name}. Check that both devices are on the '
        'same network and Nearby is open there (${_shortError(error)}).',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _get(LanPeer peer, String path, String pin) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri(
        scheme: 'http',
        host: peer.address.address,
        port: peer.port,
        path: path,
      );
      final request = await client.getUrl(uri);
      request.headers.set('x-daymark-pin', pin);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw LanException(_responseError(body, response.statusCode));
      }
      if (response.contentLength > maxPayloadBytes) {
        throw LanException('The incoming snapshot is larger than 100 MB.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxPayloadBytes) {
          throw LanException('The incoming snapshot is larger than 100 MB.');
        }
      }
      return builder.takeBytes();
    } on LanException {
      rethrow;
    } catch (error) {
      throw LanException(
        'Could not reach ${peer.name} (${_shortError(error)}).',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _handleAnnouncement(Datagram datagram) {
    try {
      final decoded = jsonDecode(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (decoded is! Map) return;
      if (decoded['app'] != 'daymark.lan') return;
      if ((decoded['protocol'] as num?)?.toInt() != protocol) return;
      final id = decoded['deviceId']?.toString();
      final remotePort = (decoded['port'] as num?)?.toInt();
      if (id == null || remotePort == null || id.isEmpty) return;
      if (id == deviceId) return;
      final name = decoded['name']?.toString() ?? 'Daymark device';
      final platform = decoded['platform']?.toString() ?? 'unknown';
      final peer = LanPeer(
        id: id,
        name: name,
        platform: platform,
        address: datagram.address,
        port: remotePort,
        lastSeen: DateTime.now(),
      );
      _peers[id] = peer;
      _emitPeers();
    } catch (_) {
      // Ignore malformed packets from other software on the network.
    }
  }

  void _announce() {
    final socket = _udp;
    final serverPort = port;
    if (socket == null || serverPort == null) return;
    final payload = utf8.encode(
      jsonEncode({
        'app': 'daymark.lan',
        'protocol': protocol,
        'deviceId': deviceId,
        'name': displayName,
        'platform': Platform.operatingSystem,
        'port': serverPort,
      }),
    );
    for (final target in [
      InternetAddress('255.255.255.255'),
      InternetAddress(multicastAddress),
    ]) {
      try {
        socket.send(payload, target, discoveryPort);
      } catch (_) {
        // A network may disallow one of the two mechanisms.
      }
    }
  }

  void _prunePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 12));
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
    if (_peers.length != before) _emitPeers();
  }

  void _emitPeers() {
    if (!_peerController.isClosed) {
      _peerController.add(peers);
    }
  }

  void _emitInbox() {
    if (!_inboxController.isClosed) {
      _inboxController.add(List.unmodifiable(_items));
    }
  }

  Future<String> _loadDeviceId() async {
    final file = File(p.join(directory.path, 'device_id.txt'));
    try {
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return existing;
      }
    } catch (_) {}
    final created = const Uuid().v4();
    await file.writeAsString(created, flush: true);
    return created;
  }

  Future<void> _loadInbox() async {
    final file = _indexFile;
    if (!await file.exists()) {
      _items = const [];
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        _items = [for (final raw in decoded) ?LanInboxItem.fromJson(raw)];
      }
    } catch (_) {
      _items = const [];
    }
  }

  Future<void> _addInbox(LanInboxItem item) async {
    _items = [item, ..._items];
    await _saveInbox();
    _emitInbox();
    await _recordHistory(
      direction: 'received',
      kind: item.kind,
      title: item.title,
      peerName: item.fromName,
      sizeBytes: item.sizeBytes,
      itemId: item.id,
      status: 'received',
    );
  }

  Future<void> _saveInbox() async {
    await directory.create(recursive: true);
    final file = _indexFile;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final item in _items) item.toJson()]),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  File get _indexFile => File(p.join(directory.path, 'inbox.json'));

  File get _historyFile => File(p.join(directory.path, 'history.json'));

  Future<void> _recordHistory({
    required String direction,
    required String kind,
    required String title,
    required String peerName,
    required String status,
    int sizeBytes = 0,
    String? itemId,
  }) async {
    final entry = LanHistoryEntry(
      id: const Uuid().v4(),
      direction: direction,
      kind: kind,
      title: title,
      peerName: peerName,
      createdAt: DateTime.now(),
      status: status,
      itemId: itemId,
      sizeBytes: sizeBytes,
    );
    _history = [entry, ..._history].take(500).toList();
    await _saveHistory();
    _emitHistory();
  }

  Future<void> _loadHistory() async {
    final file = _historyFile;
    if (!await file.exists()) {
      _history = const [];
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        _history = [for (final raw in decoded) ?LanHistoryEntry.fromJson(raw)];
      }
    } catch (_) {
      _history = const [];
    }
  }

  Future<void> _saveHistory() async {
    await directory.create(recursive: true);
    final file = _historyFile;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final entry in _history) entry.toJson()]),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  void _emitHistory() {
    if (!_historyController.isClosed) {
      _historyController.add(List.unmodifiable(_history));
    }
  }

  Future<String?> _localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final candidates = <(int, String)>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final raw = address.address;
          if (!_isPrivateAddress(address)) continue;
          if (raw.startsWith('169.254.')) continue;
          final priority = raw.startsWith('192.168.')
              ? 3
              : raw.startsWith('10.')
              ? 2
              : raw.startsWith('172.')
              ? 1
              : 0;
          candidates.add((priority, raw));
        }
      }
      candidates.sort((a, b) => b.$1.compareTo(a.$1));
      return candidates.isEmpty ? null : candidates.first.$2;
    } catch (_) {
      return null;
    }
  }

  Future<File> _snapshotFile(String prefix, String from) async {
    await backupService.backupDirectory.create(recursive: true);
    final safeFrom = _safeFileName(
      from,
      fallback: 'peer',
    ).replaceAll('.zip', '');
    return File(
      p.join(
        backupService.backupDirectory.path,
        'daymark-lan-$prefix-${_stamp(DateTime.now())}-$safeFrom.zip',
      ),
    );
  }

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    if (address.type == InternetAddressType.IPv4) {
      final parts = address.address.split('.').map(int.tryParse).toList();
      if (parts.length != 4 || parts.any((part) => part == null)) return false;
      final a = parts[0]!;
      final b = parts[1]!;
      if (a == 10) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 169 && b == 254) return true;
      if (a == 100 && b >= 64 && b <= 127) return true;
      return false;
    }
    if (address.type == InternetAddressType.IPv6) {
      final raw = address.rawAddress;
      if (raw.length == 16) {
        // Unique local addresses fc00::/7.
        if ((raw[0] & 0xfe) == 0xfc) return true;
        // IPv4-mapped ::ffff:a.b.c.d
        if (raw.sublist(0, 10).every((byte) => byte == 0) &&
            raw[10] == 0xff &&
            raw[11] == 0xff) {
          return _isPrivateAddress(
            InternetAddress(address.address.split('%').first),
          );
        }
      }
    }
    return false;
  }

  static String _cleanLabel(
    String? value, {
    required String fallback,
    int maxLength = 80,
  }) {
    final clean = (value ?? '').replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    if (clean.isEmpty) return fallback;
    return clean.length > maxLength ? clean.substring(0, maxLength) : clean;
  }

  static String _safeFileName(String? value, {required String fallback}) {
    final base = p.basename((value ?? '').trim());
    final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (clean.isEmpty || clean == '.' || clean == '..') return fallback;
    return clean.length > 140 ? clean.substring(clean.length - 140) : clean;
  }

  static String _stamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  static String _shortError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  static String _responseError(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return 'Transfer failed (HTTP $status).';
  }

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
