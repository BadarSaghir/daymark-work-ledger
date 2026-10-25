import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/app.dart';
import 'data/db/app_database.dart';
import 'data/services/local_account_store.dart';
import 'state/local_account_controller.dart';

/// Daymark boots its local database before the first frame so every screen can
/// read real data immediately. Desktop platforms use the FFI SQLite build;
/// Android and iOS use the platform plugin.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    final support = await getApplicationSupportDirectory();
    final store = LocalAccountStore(support);
    final registry = await store.load();
    final account = registry.activeAccount;
    if (account == null) {
      throw StateError('No local Daymark account could be found.');
    }
    await store.ensureDirectory(account);
    final database = AppDatabase(path: store.databasePath(account));
    await database.open();

    runApp(
      ProviderScope(
        overrides: [
          localAccountBootProvider.overrideWithValue(
            LocalAccountBoot(
              store: store,
              registry: registry,
              account: account,
              database: database,
            ),
          ),
        ],
        child: const DaymarkApp(),
      ),
    );
  } catch (error, stack) {
    runApp(BootFailureApp(error: error, stack: stack));
  }
}

/// A readable failure screen beats a blank one when the local store cannot
/// open. Exporting the database path helps with support without exposing data.
class BootFailureApp extends StatelessWidget {
  const BootFailureApp({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F0E8),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daymark',
                      style: TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 34,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF171712),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The local ledger could not be opened.',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF171712),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$error',
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 12,
                        height: 1.5,
                        color: Color(0xFFB4556C),
                      ),
                    ),
                    if (stack != null) ...[
                      const SizedBox(height: 16),
                      ExpansionTile(
                        title: const Text('Technical detail'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              '$stack',
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 10.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      'Your data has not been changed. Check that the app has '
                      'write access to its application support folder, then '
                      'restart Daymark. If the problem continues, restore a '
                      'backup after reinstalling.',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13.5,
                        height: 1.55,
                        color: Color(0xFF6F6A5F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
