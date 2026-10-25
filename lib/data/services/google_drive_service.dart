import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'backup_service.dart';

class GoogleDriveException implements Exception {
  GoogleDriveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Public Google OAuth client values baked into a release build.
///
/// Installed-app client secrets are not confidential in the way server secrets
/// are; Google still expects them to travel with the client. Leaving both
/// values empty keeps the app fully offline and exposes guided setup instead.
class GoogleOAuthDefaults {
  const GoogleOAuthDefaults({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;

  static const empty = GoogleOAuthDefaults(clientId: '', clientSecret: '');

  bool get configured =>
      clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;

  factory GoogleOAuthDefaults.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    return GoogleOAuthDefaults(
      clientId: raw['clientId']?.toString().trim() ?? '',
      clientSecret: raw['clientSecret']?.toString().trim() ?? '',
    );
  }
}

class GoogleDriveAccount {
  const GoogleDriveAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.refreshToken,
    required this.folderId,
    required this.connectedAt,
  });

  final String id;
  final String email;
  final String name;
  final String refreshToken;
  final String? folderId;
  final DateTime connectedAt;

  String get label => name.trim().isEmpty ? email : '$name · $email';

  /// A remembered account can be signed out without being forgotten. The
  /// email, label, and Drive folder stay available for a one-tap return.
  bool get isSignedIn => refreshToken.trim().isNotEmpty;

  GoogleDriveAccount copyWith({
    String? name,
    String? refreshToken,
    bool clearRefreshToken = false,
    String? folderId,
    DateTime? connectedAt,
  }) {
    return GoogleDriveAccount(
      id: id,
      email: email,
      name: name ?? this.name,
      refreshToken: clearRefreshToken
          ? ''
          : (refreshToken ?? this.refreshToken),
      folderId: folderId ?? this.folderId,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'refreshToken': refreshToken,
    'folderId': folderId,
    'connectedAt': connectedAt.toUtc().millisecondsSinceEpoch,
  };

  static GoogleDriveAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final email = raw['email']?.toString();
    final refreshToken = raw['refreshToken']?.toString() ?? '';
    if (id == null || email == null) return null;
    return GoogleDriveAccount(
      id: id,
      email: email,
      name: raw['name']?.toString() ?? '',
      refreshToken: refreshToken,
      folderId: raw['folderId']?.toString(),
      connectedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['connectedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
    );
  }
}

class GoogleDriveConfig {
  const GoogleDriveConfig({
    required this.clientId,
    required this.clientSecret,
    required this.accounts,
    required this.activeAccountId,
    required this.autoUpload,
    required this.keepCount,
    required this.lastUploadAt,
  });

  final String clientId;
  final String clientSecret;
  final List<GoogleDriveAccount> accounts;
  final String? activeAccountId;
  final bool autoUpload;
  final int keepCount;
  final DateTime? lastUploadAt;

  static const empty = GoogleDriveConfig(
    clientId: '',
    clientSecret: '',
    accounts: [],
    activeAccountId: null,
    autoUpload: true,
    keepCount: 7,
    lastUploadAt: null,
  );

  bool get hasClient => clientId.trim().isNotEmpty;
  bool get hasAccount => accounts.isNotEmpty;
  bool get hasSignedInAccount => accounts.any((account) => account.isSignedIn);

  GoogleDriveAccount? get activeAccount {
    if (accounts.isEmpty) return null;
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return accounts.first;
  }

  GoogleDriveConfig copyWith({
    String? clientId,
    String? clientSecret,
    List<GoogleDriveAccount>? accounts,
    String? activeAccountId,
    bool clearActiveAccount = false,
    bool? autoUpload,
    int? keepCount,
    DateTime? lastUploadAt,
    bool clearLastUpload = false,
  }) {
    return GoogleDriveConfig(
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      accounts: accounts ?? this.accounts,
      activeAccountId: clearActiveAccount
          ? null
          : (activeAccountId ?? this.activeAccountId),
      autoUpload: autoUpload ?? this.autoUpload,
      keepCount: keepCount ?? this.keepCount,
      lastUploadAt: clearLastUpload
          ? null
          : (lastUploadAt ?? this.lastUploadAt),
    );
  }

  Map<String, Object?> toJson() => {
    'clientId': clientId,
    'clientSecret': clientSecret,
    'accounts': [for (final account in accounts) account.toJson()],
    'activeAccountId': activeAccountId,
    'autoUpload': autoUpload,
    'keepCount': keepCount,
    'lastUploadAt': lastUploadAt?.toUtc().millisecondsSinceEpoch,
  };

  static GoogleDriveConfig fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final accounts = <GoogleDriveAccount>[];
    final rawAccounts = raw['accounts'];
    if (rawAccounts is List) {
      for (final value in rawAccounts) {
        final account = GoogleDriveAccount.fromJson(value);
        if (account != null) accounts.add(account);
      }
    }
    final active = raw['activeAccountId']?.toString();
    return GoogleDriveConfig(
      clientId: raw['clientId']?.toString() ?? '',
      clientSecret: raw['clientSecret']?.toString() ?? '',
      accounts: accounts,
      activeAccountId:
          active != null && accounts.any((account) => account.id == active)
          ? active
          : (accounts.isEmpty ? null : accounts.first.id),
      autoUpload: raw['autoUpload'] as bool? ?? true,
      keepCount: (raw['keepCount'] as num?)?.toInt() ?? 7,
      lastUploadAt: raw['lastUploadAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (raw['lastUploadAt'] as num).toInt(),
              isUtc: true,
            ).toLocal(),
    );
  }
}

class CloudBackupFile {
  const CloudBackupFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final DateTime createdAt;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).ceil()} KB';
  }
}

/// Uploads Daymark archives to a user-owned Google Drive folder.
///
/// A release build can embed a Google OAuth client so the normal path is one
/// tap: continue with Google, approve Drive access, and start mirroring. Builds
/// without embedded credentials keep a guided "bring your own client" fallback.
/// Refresh tokens and the client configuration live in a separate 0600 file
/// under the app support directory, never in the ledger or its backups.
class GoogleDriveService {
  GoogleDriveService({
    required this.backupService,
    required this.configDirectory,
    this.defaults = GoogleOAuthDefaults.empty,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final BackupService backupService;
  final Directory configDirectory;
  final GoogleOAuthDefaults defaults;
  final http.Client _client;

  final Map<String, _AccessToken> _tokens = {};
  GoogleDriveConfig? _config;

  bool get hasBuiltInClient => defaults.configured;

  static const _scopes =
      'openid email profile https://www.googleapis.com/auth/drive.file';
  static const _folderName = 'Daymark Backups';
  static const _prefix = 'daymark-';

  File get _configFile =>
      File(p.join(configDirectory.path, 'google_drive.json'));

  Future<GoogleDriveConfig> loadConfig() async {
    final existing = _config;
    if (existing != null) return existing;
    var loaded = GoogleDriveConfig.empty;
    if (await _configFile.exists()) {
      try {
        final decoded = jsonDecode(await _configFile.readAsString());
        loaded = GoogleDriveConfig.fromJson(decoded);
      } catch (_) {
        loaded = GoogleDriveConfig.empty;
      }
    }
    if (!loaded.hasClient && defaults.configured) {
      loaded = loaded.copyWith(
        clientId: defaults.clientId,
        clientSecret: defaults.clientSecret,
      );
    }
    return _config = loaded;
  }

  Future<void> saveClient({
    required String clientId,
    required String clientSecret,
  }) async {
    final config = await loadConfig();
    final cleanId = clientId.trim();
    final cleanSecret = clientSecret.trim();
    if (cleanId.isEmpty) {
      throw GoogleDriveException('An OAuth client ID is required.');
    }
    await _save(config.copyWith(clientId: cleanId, clientSecret: cleanSecret));
  }

  Future<GoogleDriveAccount> connectAccount({String? loginHint}) async {
    final config = await loadConfig();
    if (!config.hasClient) {
      throw GoogleDriveException(
        'Google sign-in is not configured in this build. Add an OAuth client '
        'in Settings, or use a release build with Google sign-in enabled.',
      );
    }

    final verifier = _randomUrlSafe(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomUrlSafe(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/oauth2callback';
    final completer = Completer<String>();

    server.listen((request) async {
      if (request.uri.path != '/oauth2callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final returnedState = request.uri.queryParameters['state'];
      final error = request.uri.queryParameters['error'];
      final code = request.uri.queryParameters['code'];
      if (returnedState != state || error != null || code == null) {
        if (!completer.isCompleted) {
          completer.completeError(
            GoogleDriveException(
              error ?? 'Google did not return an authorization code.',
            ),
          );
        }
      } else if (!completer.isCompleted) {
        completer.complete(code);
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write('''
<!doctype html><html><head><meta charset="utf-8">
<title>Daymark · Google Drive</title>
<style>body{background:#f4f0e8;color:#171712;font-family:system-ui,sans-serif;
display:grid;place-items:center;min-height:100vh;margin:0}main{max-width:440px;
padding:40px;text-align:center}h1{font-family:Georgia,serif;font-weight:500}
p{color:#6d685f;line-height:1.6}</style></head>
<body><main><h1>Daymark is connected.</h1>
<p>You can close this tab and return to the app.</p></main></body></html>
''');
      await request.response.close();
    });

    try {
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': config.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': _scopes,
        'access_type': 'offline',
        'prompt': 'select_account consent',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        if (loginHint != null && loginHint.trim().isNotEmpty)
          'login_hint': loginHint.trim(),
      });
      final opened = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw GoogleDriveException(
          'Could not open the browser. Open this URL manually:\n$authUrl',
        );
      }
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw GoogleDriveException(
          'The Google sign-in window timed out. Try again.',
        ),
      );
      final token = await _exchangeCode(
        config: config,
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
      final refreshToken = token['refresh_token']?.toString();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw GoogleDriveException(
          'Google did not return a refresh token. Remove the app from your '
          'Google account permissions and try again.',
        );
      }
      final profile = await _profile(token['access_token']?.toString() ?? '');
      final email = profile.$1;
      final name = profile.$2;
      final now = DateTime.now();
      final existing = config.accounts
          .where((a) => a.email == email)
          .firstOrNull;
      final account = GoogleDriveAccount(
        id: existing?.id ?? const Uuid().v4(),
        email: email,
        name: name,
        refreshToken: refreshToken,
        folderId: existing?.folderId,
        connectedAt: existing?.connectedAt ?? now,
      );
      final accounts = [
        for (final item in config.accounts)
          if (item.id != account.id) item,
        account,
      ];
      await _save(
        config.copyWith(accounts: accounts, activeAccountId: account.id),
      );
      _tokens[account.id] = _AccessToken(
        token['access_token']?.toString() ?? '',
        _expiryFor(token),
      );
      return account;
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> removeAccount(String id) async {
    final config = await loadConfig();
    final accounts = config.accounts
        .where((account) => account.id != id)
        .toList();
    final active = config.activeAccountId == id
        ? (accounts.isEmpty ? null : accounts.first.id)
        : config.activeAccountId;
    await _save(
      GoogleDriveConfig(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        accounts: accounts,
        activeAccountId: active,
        autoUpload: config.autoUpload,
        keepCount: config.keepCount,
        lastUploadAt: config.lastUploadAt,
      ),
    );
    _tokens.remove(id);
  }

  /// Clears the refresh token but keeps the account row and Drive folder. The
  /// next sign-in can use the remembered email as a login hint.
  Future<void> signOutAccount(String id) async {
    final config = await loadConfig();
    if (!config.accounts.any((account) => account.id == id)) {
      throw GoogleDriveException('That Google account is not connected.');
    }
    await _save(
      config.copyWith(
        accounts: [
          for (final account in config.accounts)
            if (account.id == id)
              account.copyWith(clearRefreshToken: true)
            else
              account,
        ],
      ),
    );
    _tokens.remove(id);
  }

  Future<void> setActiveAccount(String id) async {
    final config = await loadConfig();
    if (!config.accounts.any((account) => account.id == id)) {
      throw GoogleDriveException('That Google account is not connected.');
    }
    await _save(config.copyWith(activeAccountId: id));
  }

  Future<void> setAutoUpload(bool value) async {
    final config = await loadConfig();
    await _save(config.copyWith(autoUpload: value));
  }

  Future<void> setKeepCount(int value) async {
    final config = await loadConfig();
    await _save(config.copyWith(keepCount: value.clamp(1, 60)));
  }

  Future<CloudBackupFile> uploadBackup(
    File localFile, {
    String? accountId,
  }) async {
    final config = await loadConfig();
    final account = _account(config, accountId);
    final folderId = await _ensureFolder(account);
    final bytes = await localFile.readAsBytes();
    if (bytes.length > BackupService.maxImportBytes) {
      throw GoogleDriveException(
        'That backup is larger than the 100 MB limit.',
      );
    }
    final name = p.basename(localFile.path);
    final uploaded = await _uploadBytes(account, folderId, name, bytes);
    final next = await loadConfig();
    await _save(next.copyWith(lastUploadAt: DateTime.now()));
    await _cleanupCloud(next, account);
    return uploaded;
  }

  /// Uploads the current database directly after creating a local safety copy.
  Future<CloudBackupFile> uploadCurrent({String? accountId}) async {
    final config = await loadConfig();
    final account = _account(config, accountId);
    final backup = await backupService.createBackup(prefix: 'daymark-drive');
    final file = backup.file;
    if (file == null) {
      throw GoogleDriveException('Could not create a local backup first.');
    }
    final folderId = await _ensureFolder(account);
    final bytes = await file.readAsBytes();
    final uploaded = await _uploadBytes(
      account,
      folderId,
      p.basename(file.path),
      bytes,
    );
    final next = await loadConfig();
    await _save(next.copyWith(lastUploadAt: DateTime.now()));
    await _cleanupCloud(next, account);
    return uploaded;
  }

  /// Called at launch. It uploads at most once every 20 hours when enabled.
  Future<CloudBackupFile?> autoUploadIfDue() async {
    final config = await loadConfig();
    if (!config.autoUpload || !config.hasAccount) return null;
    if (config.activeAccount?.isSignedIn != true) return null;
    final last = config.lastUploadAt;
    if (last != null && DateTime.now().difference(last).inHours < 20) {
      return null;
    }
    return uploadCurrent();
  }

  Future<List<CloudBackupFile>> listBackups({String? accountId}) async {
    final config = await loadConfig();
    if (!config.hasAccount) return const [];
    final account = _account(config, accountId);
    final folderId = await _ensureFolder(account);
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': "'$folderId' in parents and trashed = false",
      'orderBy': 'createdTime desc',
      'pageSize': '50',
      'fields': 'files(id,name,size,createdTime)',
    });
    final response = await _authorizedGet(account, uri);
    final files = <CloudBackupFile>[];
    final rawFiles = response?['files'];
    if (rawFiles is List) {
      for (final raw in rawFiles) {
        if (raw is! Map) continue;
        final name = raw['name']?.toString() ?? '';
        if (!name.startsWith(_prefix)) continue;
        files.add(
          CloudBackupFile(
            id: raw['id']?.toString() ?? '',
            name: name,
            sizeBytes: int.tryParse(raw['size']?.toString() ?? '') ?? 0,
            createdAt:
                DateTime.tryParse(raw['createdTime']?.toString() ?? '')
                    ?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }
    return files;
  }

  Future<File> download(CloudBackupFile item, {String? accountId}) async {
    final config = await loadConfig();
    final account = _account(config, accountId);
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/${item.id}', {
      'alt': 'media',
    });
    final response = await _authorizedRawGet(account, uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(_httpError(response));
    }
    await backupService.backupDirectory.create(recursive: true);
    final safeName = p
        .basename(item.name)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      p.join(backupService.backupDirectory.path, 'drive-$safeName'),
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  Future<void> delete(CloudBackupFile item, {String? accountId}) async {
    final config = await loadConfig();
    final account = _account(config, accountId);
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/${item.id}');
    final response = await _authorizedDelete(account, uri);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw GoogleDriveException(_httpError(response));
    }
  }

  Future<bool> testConnection({String? accountId}) async {
    final config = await loadConfig();
    final account = _account(config, accountId);
    await _accessToken(account, force: true);
    return true;
  }

  GoogleDriveAccount _account(GoogleDriveConfig config, String? accountId) {
    if (config.accounts.isEmpty) {
      throw GoogleDriveException('Connect a Google account first.');
    }
    GoogleDriveAccount? selected;
    if (accountId != null) {
      for (final account in config.accounts) {
        if (account.id == accountId) selected = account;
      }
    }
    selected ??= config.activeAccount;
    if (selected == null) {
      throw GoogleDriveException('Connect a Google account first.');
    }
    if (!selected.isSignedIn) {
      throw GoogleDriveException(
        '${selected.email} is signed out. Sign in again to use Google Drive.',
      );
    }
    return selected;
  }

  void close() => _client.close();

  Future<void> _save(GoogleDriveConfig config) async {
    _config = config;
    await configDirectory.create(recursive: true);
    final temp = File('${_configFile.path}.tmp');
    await temp.writeAsString(jsonEncode(config.toJson()), flush: true);
    if (await _configFile.exists()) await _configFile.delete();
    await temp.rename(_configFile.path);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', _configFile.path]);
      } catch (_) {
        // Windows and unusual sandboxes may not have chmod.
      }
    }
  }

  Future<String> _ensureFolder(GoogleDriveAccount account) async {
    final config = await loadConfig();
    if (account.folderId != null && account.folderId!.isNotEmpty) {
      return account.folderId!;
    }
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q':
          "name = '${_folderName.replaceAll("'", r"\'")}' and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      'fields': 'files(id,name)',
      'pageSize': '10',
    });
    final listing = await _authorizedGet(account, uri);
    String? folderId;
    final rawFolders = listing?['files'];
    if (rawFolders is List) {
      for (final raw in rawFolders) {
        if (raw is Map && raw['id'] != null) {
          folderId = raw['id'].toString();
          break;
        }
      }
    }
    if (folderId == null) {
      final created = await _authorizedJson(
        account,
        'POST',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'fields': 'id,name',
        }),
        body: jsonEncode({
          'name': _folderName,
          'mimeType': 'application/vnd.google-apps.folder',
        }),
      );
      folderId = created?['id']?.toString();
    }
    if (folderId == null || folderId.isEmpty) {
      throw GoogleDriveException('Could not create the Daymark Drive folder.');
    }
    final next = config.copyWith(
      accounts: [
        for (final item in config.accounts)
          if (item.id == account.id)
            item.copyWith(folderId: folderId)
          else
            item,
      ],
    );
    await _save(next);
    return folderId;
  }

  Future<CloudBackupFile> _uploadBytes(
    GoogleDriveAccount account,
    String folderId,
    String name,
    List<int> bytes,
  ) async {
    final token = await _accessToken(account);
    final boundary = 'daymark_${_randomUrlSafe(18)}';
    final metadata = jsonEncode({
      'name': name,
      'parents': [folderId],
      'mimeType': 'application/zip',
    });
    final body = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$metadata\r\n'
          '--$boundary\r\n'
          'Content-Type: application/zip\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final payload = body.takeBytes();
    final uri = Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
      'uploadType': 'multipart',
      'fields': 'id,name,size,createdTime',
    });
    var response = await _client.post(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'multipart/related; boundary=$boundary',
      },
      body: payload,
    );
    if (response.statusCode == 401) {
      final fresh = await _accessToken(account, force: true);
      response = await _client.post(
        uri,
        headers: {
          'authorization': 'Bearer $fresh',
          'content-type': 'multipart/related; boundary=$boundary',
        },
        body: payload,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(_httpError(response));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw GoogleDriveException('Google Drive returned an empty upload.');
    }
    return CloudBackupFile(
      id: decoded['id']?.toString() ?? '',
      name: decoded['name']?.toString() ?? name,
      sizeBytes:
          int.tryParse(decoded['size']?.toString() ?? '') ?? bytes.length,
      createdAt:
          DateTime.tryParse(decoded['createdTime']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Future<void> _cleanupCloud(
    GoogleDriveConfig config,
    GoogleDriveAccount account,
  ) async {
    try {
      final files = await listBackups(accountId: account.id);
      for (final file in files.skip(config.keepCount)) {
        await delete(file, accountId: account.id);
      }
    } catch (_) {
      // Retention is a convenience. A failed cleanup must not fail the upload.
    }
  }

  Future<Map<String, Object?>?> _authorizedGet(
    GoogleDriveAccount account,
    Uri uri,
  ) async {
    final response = await _authorizedRawGet(account, uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(_httpError(response));
    }
    return jsonDecode(response.body) as Map<String, Object?>?;
  }

  Future<http.Response> _authorizedRawGet(
    GoogleDriveAccount account,
    Uri uri,
  ) async {
    var token = await _accessToken(account);
    var response = await _client.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401) {
      token = await _accessToken(account, force: true);
      response = await _client.get(
        uri,
        headers: {'authorization': 'Bearer $token'},
      );
    }
    return response;
  }

  Future<Map<String, Object?>?> _authorizedJson(
    GoogleDriveAccount account,
    String method,
    Uri uri, {
    String? body,
  }) async {
    var token = await _accessToken(account);
    var response = await _client
        .send(
          http.Request(method, uri)
            ..headers['authorization'] = 'Bearer $token'
            ..headers['content-type'] = 'application/json; charset=UTF-8'
            ..body = body ?? '',
        )
        .then(http.Response.fromStream);
    if (response.statusCode == 401) {
      token = await _accessToken(account, force: true);
      response = await _client
          .send(
            http.Request(method, uri)
              ..headers['authorization'] = 'Bearer $token'
              ..headers['content-type'] = 'application/json; charset=UTF-8'
              ..body = body ?? '',
          )
          .then(http.Response.fromStream);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(_httpError(response));
    }
    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Future<http.Response> _authorizedDelete(
    GoogleDriveAccount account,
    Uri uri,
  ) async {
    var token = await _accessToken(account);
    var response = await _client.delete(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401) {
      token = await _accessToken(account, force: true);
      response = await _client.delete(
        uri,
        headers: {'authorization': 'Bearer $token'},
      );
    }
    return response;
  }

  Future<String> _accessToken(
    GoogleDriveAccount account, {
    bool force = false,
  }) async {
    if (!account.isSignedIn) {
      throw GoogleDriveException(
        '${account.email} is signed out. Sign in again to use Google Drive.',
      );
    }
    final cached = _tokens[account.id];
    if (!force &&
        cached != null &&
        cached.expiresAt.isAfter(
          DateTime.now().add(const Duration(seconds: 60)),
        )) {
      return cached.value;
    }
    final config = await loadConfig();
    final response = await _client.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'refresh_token': account.refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Google rejected the saved connection. Reconnect the account '
        '(${_httpError(response)}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['access_token'] == null) {
      throw GoogleDriveException('Google returned no access token.');
    }
    final rotated = decoded['refresh_token']?.toString();
    if (rotated != null &&
        rotated.isNotEmpty &&
        rotated != account.refreshToken) {
      final config = await loadConfig();
      await _save(
        config.copyWith(
          accounts: [
            for (final item in config.accounts)
              if (item.id == account.id)
                item.copyWith(refreshToken: rotated)
              else
                item,
          ],
        ),
      );
    }
    final token = decoded['access_token'].toString();
    _tokens[account.id] = _AccessToken(token, _expiryFor(decoded));
    return token;
  }

  Future<Map<String, Object?>> _exchangeCode({
    required GoogleDriveConfig config,
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await _client.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Google refused the sign-in (${_httpError(response)}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw GoogleDriveException('Google returned an unknown token response.');
    }
    return decoded;
  }

  Future<(String, String)> _profile(String accessToken) async {
    final response = await _client.get(
      Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Could not read the Google profile (${_httpError(response)}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw GoogleDriveException('Google returned an unknown profile.');
    }
    final email = decoded['email']?.toString() ?? 'Google account';
    final name = decoded['name']?.toString() ?? '';
    return (email, name);
  }

  DateTime _expiryFor(Map<dynamic, dynamic> token) {
    final seconds = int.tryParse(token['expires_in']?.toString() ?? '') ?? 3600;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  String _httpError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (error != null) return error.toString();
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  static String _randomUrlSafe(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, length);
  }
}

class _AccessToken {
  const _AccessToken(this.value, this.expiresAt);
  final String value;
  final DateTime expiresAt;
}
