import 'db_values.dart';

/// A colour-coded bucket of work with an importance weight.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.weight,
    required this.position,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// ARGB integer, safe for persistence.
  final int color;

  /// Stable semantic icon key (see `CategoryIcons` in the UI layer).
  final String icon;

  /// 0.5–2.0 multiplier used in the weightage formula.
  final double weight;
  final int position;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category copyWith({
    String? name,
    int? color,
    String? icon,
    double? weight,
    int? position,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      weight: weight ?? this.weight,
      position: position ?? this.position,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: stringFromDb(map['id']),
      name: stringFromDb(map['name'], 'Untitled'),
      color: intFromDb(map['color'], 0xFF1D5B4F),
      icon: stringFromDb(map['icon'], 'layers'),
      weight: doubleFromDb(map['weight'], 1.0),
      position: intFromDb(map['position']),
      archived: boolFromDb(map['archived']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
      updatedAt: dateFromMs(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'weight': weight,
      'position': position,
      'archived': archived ? 1 : 0,
      'created_at': msFromDate(createdAt),
      'updated_at': msFromDate(updatedAt),
    };
  }
}
