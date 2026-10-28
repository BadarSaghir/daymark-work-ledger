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

    await tester.tap(find.text('More'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Nearby & sync'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Nearby'), findsWidgets);
    expect(find.text('Go online'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone settings opens a section sheet without overflow', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('More'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Settings'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Daily rhythm'), findsOneWidget);
    expect(find.text('Backup & portability'), findsOneWidget);

    await tester.tap(find.text('Daily rhythm'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Weight target'), findsOneWidget);
    expect(find.text('Focus target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone journal keeps history in a sheet', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('More'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.widgetWithText(ListTile, 'Journal'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Journal history'), findsNothing);
    await tester.tap(find.byTooltip('Journal history'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Journal history'), findsOneWidget);
    expect(find.text('Search the journal…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone focus keeps the ritual in a sheet', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Focus'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('A quiet clock for deep work'), findsOneWidget);

    await tester.tap(find.byTooltip('Before you start'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Name the one thing you are doing.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone focus fits on screen without page scrolling', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Focus'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Today’s log'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone focus still fits without overflow', (tester) async {
    await pumpApp(tester, const Size(360, 640));

    await tester.tap(find.text('Focus'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Today’s log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom sheet menu stays reachable with system insets', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await pumpApp(tester, const Size(360, 640));

    await tester.tap(find.text('More'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final scrollable = find.byType(SingleChildScrollView).last;
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Daily rhythm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape phone focus lays the clock out sideways', (
    tester,
  ) async {
    await pumpApp(tester, const Size(844, 390));

    await tester.tap(find.text('Focus'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byTooltip('Today’s log'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape sheet scrolls above the home indicator', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 0, bottom: 21);
    await pumpApp(tester, const Size(844, 390));

    await tester.tap(find.text('More'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Search Daymark'), findsOneWidget);
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
