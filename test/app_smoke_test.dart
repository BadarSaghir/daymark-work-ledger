import 'dart:io';

import 'package:daymark/app/app.dart';
import 'package:daymark/data/db/app_database.dart';
import 'package:daymark/data/models/app_settings.dart';
import 'package:daymark/data/repositories/settings_repository.dart';
import 'package:daymark/state/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('daymark_widget_test');
    db = AppDatabase(
      path: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    await db.open();
    await SettingsRepository(db).save(
      AppSettings.defaults.copyWith(
        displayName: 'Badar',
        onboarded: true,
        autoBackup: false,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backupDirectoryProvider.overrideWith(
            (ref) async => Directory(p.join(temp.path, 'backups')),
          ),
          remindersEnabledProvider.overrideWithValue(false),
        ],
        child: const DaymarkApp(),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('Today adapts to a phone-sized viewport without overflow', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));

    expect(find.text('Today'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('phone bottom bar opens Nearby without overflow', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Sync'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Nearby'), findsWidgets);
    expect(find.text('Go online'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shell opens with a persistent sidebar', (tester) async {
    await pumpApp(tester, const Size(1440, 900));

    expect(find.text('Planner'), findsWidgets);
    expect(find.text('Insights'), findsWidgets);
    expect(find.text('Nearby & sync'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
