import 'db_values.dart';

/// Append-only audit trail. Powers the activity feed on task details and the
/// "what happened" story in reviews.
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.summary,
    required this.metadataJson,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String? entityId;
  final String action;
  final String summary;
  final String? metadataJson;
  final DateTime createdAt;

  factory ActivityEvent.fromMap(Map<String, Object?> map) {
    return ActivityEvent(
      id: stringFromDb(map['id']),
      entityType: stringFromDb(map['entity_type']),
      entityId: map['entity_id'] as String?,
      action: stringFromDb(map['action']),
      summary: stringFromDb(map['summary']),
      metadataJson: map['metadata'] as String?,
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action,
      'summary': summary,
      'metadata': metadataJson,
      'created_at': msFromDate(createdAt),
    };
  }
}
