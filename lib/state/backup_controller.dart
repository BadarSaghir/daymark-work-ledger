import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/backup_service.dart';
import 'repository_providers.dart';

final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final service = await ref.watch(backupServiceProvider.future);
  return service.listBackups();
});
