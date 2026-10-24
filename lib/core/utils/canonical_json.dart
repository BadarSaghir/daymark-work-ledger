import 'dart:convert';

/// Deterministic JSON used for backup checksums. Maps are key-sorted at every
/// depth; lists keep their order.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonical).toList();
  }
  return value;
}
