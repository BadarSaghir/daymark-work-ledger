import 'db_values.dart';

/// A file attached to a task. The bytes live under the active local profile's
/// `task_files` directory; this row is the portable metadata.
class TaskAttachment {
  const TaskAttachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.relativePath,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Path relative to the profile's `task_files` root.
  final String relativePath;
  final DateTime createdAt;

  String get sizeLabel {
    if (sizeBytes <= 0) return '0 KB';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).ceil()} KB';
  }

  factory TaskAttachment.fromMap(Map<String, Object?> map) {
    return TaskAttachment(
      id: stringFromDb(map['id']),
      taskId: stringFromDb(map['task_id']),
      fileName: stringFromDb(map['file_name'], 'Attachment'),
      mimeType: stringFromDb(map['mime_type']),
      sizeBytes: intFromDb(map['size_bytes']),
      relativePath: stringFromDb(map['relative_path']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'task_id': taskId,
    'file_name': fileName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'relative_path': relativePath,
    'created_at': msFromDate(createdAt),
  };
}
