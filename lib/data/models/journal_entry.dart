import 'db_values.dart';

/// One markdown journal per local date.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.dateKey,
    required this.bodyMd,
    required this.mood,
    required this.energy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Local `YYYY-MM-DD`.
  final String dateKey;
  final String bodyMd;

  /// Optional 1–5 self-report.
  final int? mood;
  final int? energy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => bodyMd.trim().isEmpty;

  JournalEntry copyWith({
    String? bodyMd,
    Object? mood = _unset,
    Object? energy = _unset,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id,
      dateKey: dateKey,
      bodyMd: bodyMd ?? this.bodyMd,
      mood: identical(mood, _unset) ? this.mood : mood as int?,
      energy: identical(energy, _unset) ? this.energy : energy as int?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _unset = Object();

  factory JournalEntry.fromMap(Map<String, Object?> map) {
    return JournalEntry(
      id: stringFromDb(map['id']),
      dateKey: stringFromDb(map['date_key']),
      bodyMd: stringFromDb(map['body_md']),
      mood: (map['mood'] as num?)?.toInt(),
      energy: (map['energy'] as num?)?.toInt(),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
      updatedAt: dateFromMs(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date_key': dateKey,
      'body_md': bodyMd,
      'mood': mood,
      'energy': energy,
      'created_at': msFromDate(createdAt),
      'updated_at': msFromDate(updatedAt),
    };
  }
}
