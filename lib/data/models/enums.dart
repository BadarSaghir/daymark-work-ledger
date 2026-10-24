/// Domain enums shared by the database, services, and UI.
library;

enum WorkKind {
  official('official', 'Official'),
  adhoc('adhoc', 'Ad-hoc'),
  personal('personal', 'Personal');

  const WorkKind(this.db, this.label);

  final String db;
  final String label;

  static WorkKind fromDb(String? value) => values.firstWhere(
    (kind) => kind.db == value,
    orElse: () => WorkKind.official,
  );
}

enum TaskStatus {
  inbox('inbox', 'Inbox'),
  planned('planned', 'Planned'),
  inProgress('in_progress', 'In progress'),
  blocked('blocked', 'Blocked'),
  done('done', 'Done');

  const TaskStatus(this.db, this.label);

  final String db;
  final String label;

  bool get isDone => this == TaskStatus.done;

  static TaskStatus fromDb(String? value) => values.firstWhere(
    (status) => status.db == value,
    orElse: () => TaskStatus.inbox,
  );
}

enum Priority {
  low('low', 'Low', 0.8),
  normal('normal', 'Normal', 1.0),
  high('high', 'High', 1.3),
  urgent('urgent', 'Urgent', 1.6);

  const Priority(this.db, this.label, this.multiplier);

  final String db;
  final String label;
  final double multiplier;

  static Priority fromDb(String? value) => values.firstWhere(
    (priority) => priority.db == value,
    orElse: () => Priority.normal,
  );
}

enum TimerKind {
  general('general'),
  task('task');

  const TimerKind(this.db);

  final String db;

  static TimerKind fromDb(String? value) => values.firstWhere(
    (kind) => kind.db == value,
    orElse: () => TimerKind.general,
  );
}

enum EntrySource {
  timer('timer'),
  manual('manual');

  const EntrySource(this.db);

  final String db;

  static EntrySource fromDb(String? value) => values.firstWhere(
    (source) => source.db == value,
    orElse: () => EntrySource.manual,
  );
}
