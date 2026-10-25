import 'dart:convert';

import 'package:daymark/data/services/google_drive_service.dart';
import 'package:daymark/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoogleDriveConfig', () {
    final first = GoogleDriveAccount(
      id: 'account-1',
      email: 'first@example.com',
      name: 'First',
      refreshToken: 'refresh-1',
      folderId: 'folder-1',
      connectedAt: DateTime.utc(2026, 10, 20, 9, 30),
    );
    final second = GoogleDriveAccount(
      id: 'account-2',
      email: 'second@example.com',
      name: '',
      refreshToken: 'refresh-2',
      folderId: null,
      connectedAt: DateTime.utc(2026, 10, 21, 12),
    );

    test('round-trips multiple accounts and the active choice', () {
      final config = GoogleDriveConfig(
        clientId: 'client.apps.googleusercontent.com',
        clientSecret: 'secret',
        accounts: [first, second],
        activeAccountId: second.id,
        autoUpload: false,
        keepCount: 14,
        lastUploadAt: DateTime.utc(2026, 10, 24, 8, 15),
      );

      final decoded = GoogleDriveConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())),
      );

      expect(decoded.clientId, config.clientId);
      expect(decoded.clientSecret, config.clientSecret);
      expect(decoded.accounts, hasLength(2));
      expect(decoded.accounts.first.email, 'first@example.com');
      expect(decoded.accounts.first.folderId, 'folder-1');
      expect(decoded.accounts.last.folderId, isNull);
      expect(decoded.activeAccountId, second.id);
      expect(decoded.activeAccount?.email, 'second@example.com');
      expect(decoded.autoUpload, isFalse);
      expect(decoded.keepCount, 14);
      expect(decoded.lastUploadAt?.toUtc(), DateTime.utc(2026, 10, 24, 8, 15));
    });

    test('falls back to the first account when the active one is missing', () {
      final decoded = GoogleDriveConfig.fromJson({
        'clientId': 'client',
        'clientSecret': 'secret',
        'accounts': [first.toJson(), second.toJson()],
        'activeAccountId': 'gone',
        'autoUpload': true,
        'keepCount': 7,
      });

      expect(decoded.activeAccountId, first.id);
      expect(decoded.activeAccount?.email, first.email);
    });

    test('ignores malformed accounts and supplies defaults', () {
      final decoded = GoogleDriveConfig.fromJson({
        'clientId': 'client',
        'accounts': [
          {'id': 'broken'},
          first.toJson(),
        ],
      });

      expect(decoded.accounts, hasLength(1));
      expect(decoded.activeAccountId, first.id);
      expect(decoded.autoUpload, isTrue);
      expect(decoded.keepCount, 7);
      expect(decoded.lastUploadAt, isNull);
    });

    test('labels an account without a name by its email', () {
      expect(second.label, 'second@example.com');
      expect(first.label, 'First · first@example.com');
    });
  });

  group('ReminderPreferences', () {
    test('round-trips every setting', () {
      const preferences = ReminderPreferences(
        enabled: true,
        taskReminders: false,
        leadMinutes: 30,
        dailyReview: true,
        reviewHour: 21,
        reviewMinute: 5,
      );

      final decoded = ReminderPreferences.fromJson(
        jsonDecode(jsonEncode(preferences.toJson())),
      );

      expect(decoded.enabled, isTrue);
      expect(decoded.taskReminders, isFalse);
      expect(decoded.leadMinutes, 30);
      expect(decoded.dailyReview, isTrue);
      expect(decoded.reviewHour, 21);
      expect(decoded.reviewMinute, 5);
      expect(decoded.reviewLabel, '9:05 PM');
    });

    test('clamps out-of-range saved values and defaults malformed input', () {
      final clamped = ReminderPreferences.fromJson({
        'leadMinutes': 900,
        'reviewHour': -3,
        'reviewMinute': 99,
      });
      expect(clamped.leadMinutes, 120);
      expect(clamped.reviewHour, 0);
      expect(clamped.reviewMinute, 59);
      expect(clamped.enabled, isFalse);

      expect(ReminderPreferences.fromJson(null).enabled, isFalse);
      expect(ReminderPreferences.fromJson('nonsense').dailyReview, isTrue);
    });

    test('formats midnight and noon without a leading zero', () {
      expect(
        ReminderPreferences.defaults
            .copyWith(reviewHour: 0, reviewMinute: 0)
            .reviewLabel,
        '12:00 AM',
      );
      expect(
        ReminderPreferences.defaults
            .copyWith(reviewHour: 12, reviewMinute: 30)
            .reviewLabel,
        '12:30 PM',
      );
    });
  });
}
