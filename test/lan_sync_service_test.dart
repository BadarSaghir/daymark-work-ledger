import 'package:daymark/data/services/lan_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanPairing', () {
    test('round-trips a pairing QR payload', () {
      const pairing = LanPairing(
        host: '192.168.1.24',
        port: 41234,
        pin: '042781',
        name: 'Badar’s laptop',
        deviceId: 'device-1',
      );

      final parsed = LanPairing.parse(pairing.encode());

      expect(parsed, isNotNull);
      expect(parsed!.host, pairing.host);
      expect(parsed.port, pairing.port);
      expect(parsed.pin, pairing.pin);
      expect(parsed.name, pairing.name);
      expect(parsed.deviceId, pairing.deviceId);
    });

    test('rejects unrelated and malformed links', () {
      expect(LanPairing.parse('https://example.com'), isNull);
      expect(
        LanPairing.parse('daymark://pair?host=192.168.1.2&port=0&pin=123456'),
        isNull,
      );
      expect(
        LanPairing.parse('daymark://pair?host=192.168.1.2&port=45913&pin=123'),
        isNull,
      );
    });
  });

  group('LanHistoryEntry', () {
    test('serializes the transfer audit trail', () {
      final entry = LanHistoryEntry(
        id: 'event-1',
        direction: 'received',
        kind: 'text',
        title: 'Shared note',
        peerName: 'Phone',
        createdAt: DateTime(2026, 10, 24, 18, 30),
        status: 'received',
        itemId: 'item-1',
        sizeBytes: 2048,
      );

      final restored = LanHistoryEntry.fromJson(entry.toJson());

      expect(restored, isNotNull);
      expect(restored!.direction, 'received');
      expect(restored.kind, 'text');
      expect(restored.title, 'Shared note');
      expect(restored.peerName, 'Phone');
      expect(restored.itemId, 'item-1');
      expect(restored.sizeBytes, 2048);
      expect(restored.status, 'received');
    });

    test('marks directional helpers correctly', () {
      final sent = LanHistoryEntry(
        id: '1',
        direction: 'sent',
        kind: 'file',
        title: 'brief.pdf',
        peerName: 'Desktop',
        createdAt: DateTime(2026),
        status: 'sent',
      );
      final received = LanHistoryEntry(
        id: '2',
        direction: 'received',
        kind: 'snapshot',
        title: 'Snapshot',
        peerName: 'Phone',
        createdAt: DateTime(2026),
        status: 'restored',
      );

      expect(sent.isSent, isTrue);
      expect(received.isReceived, isTrue);
      expect(received.copyWith(status: 'journaled').status, 'journaled');
    });
  });
}
