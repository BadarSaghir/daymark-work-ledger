import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Time-sortable enough for local use; UUID v4 keeps imports conflict-safe.
String newId() => _uuid.v4();
