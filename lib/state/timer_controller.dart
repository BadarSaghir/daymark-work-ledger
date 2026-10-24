import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/task.dart';
import '../data/models/timer_session.dart';
import 'repository_providers.dart';
import 'stats_providers.dart';
import 'tasks_controller.dart';

class TimerState {
  const TimerState({
    required this.session,
    required this.now,
    this.recovered = false,
  });

  final TimerSession? session;
  final DateTime now;

  /// True when a live session was found at launch, implying the app closed or
  /// crashed while it was running.
  final bool recovered;

  bool get hasSession => session != null;
  bool get isRunning => session?.isRunning ?? false;
  bool get isPaused => session != null && !session!.isRunning;
  Duration get elapsed => session?.elapsedAt(now) ?? Duration.zero;
  String get label => session?.label ?? '';
  String? get taskId => session?.taskId;
  TimerKind? get kind => session?.kind;

  TimerState copyWith({TimerSession? session, DateTime? now}) =>
      TimerState(session: session, now: now ?? this.now, recovered: recovered);
}

class TimerController extends AsyncNotifier<TimerState> {
  Timer? _ticker;

  @override
  Future<TimerState> build() async {
    final launch = DateTime.now();
    final session = await ref.watch(timerRepositoryProvider).liveSession();
    final recovered =
        session != null &&
        session.isRunning &&
        session.startedAt.isBefore(launch.subtract(const Duration(minutes: 2)));
    final initial = TimerState(
      session: session,
      now: launch,
      recovered: recovered,
    );
    _schedule(session);
    ref.onDispose(() => _ticker?.cancel());
    return initial;
  }

  void _schedule(TimerSession? session) {
    _ticker?.cancel();
    _ticker = null;
    if (session == null || !session.isRunning) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state.value;
      if (current == null || current.session == null) return;
      state = AsyncData(
        TimerState(
          session: current.session,
          now: DateTime.now(),
          recovered: current.recovered,
        ),
      );
    });
  }

  void _apply(TimerSession? session) {
    state = AsyncData(
      TimerState(
        session: session,
        now: DateTime.now(),
        recovered: session == null ? false : (state.value?.recovered ?? false),
      ),
    );
    _schedule(session);
  }

  Future<void> _afterCommit() async {
    ref.invalidate(tasksProvider);
    invalidateStats(ref);
  }

  Future<void> startForTask(Task task) async {
    final session = await ref
        .read(timerRepositoryProvider)
        .start(taskId: task.id, label: task.title, kind: TimerKind.task);
    _apply(session);
    await _afterCommit();
  }

  Future<void> startGeneral(String label) async {
    final session = await ref
        .read(timerRepositoryProvider)
        .start(
          label: label.trim().isEmpty ? 'Focus' : label.trim(),
          kind: TimerKind.general,
        );
    _apply(session);
    await _afterCommit();
  }

  Future<void> pause() async {
    final current = state.value?.session;
    if (current == null || !current.isRunning) return;
    final paused = await ref.read(timerRepositoryProvider).pause(current);
    _apply(paused);
    await _afterCommit();
  }

  Future<void> resume() async {
    final current = state.value?.session;
    if (current == null || current.isRunning) return;
    final resumed = await ref.read(timerRepositoryProvider).resume(current);
    _apply(resumed);
  }

  Future<void> stop({String? assignTaskId, String? label, String? note}) async {
    final current = state.value?.session;
    if (current == null) return;
    await ref
        .read(timerRepositoryProvider)
        .stop(current, assignTaskId: assignTaskId, label: label, note: note);
    _apply(null);
    await _afterCommit();
  }

  Future<void> discard() async {
    final current = state.value?.session;
    if (current == null) return;
    await ref.read(timerRepositoryProvider).discard(current);
    _apply(null);
    await _afterCommit();
  }

  Future<void> rename(String label) async {
    final current = state.value?.session;
    if (current == null) return;
    await ref.read(timerRepositoryProvider).renameLive(current.id, label);
    _apply(
      TimerSession(
        id: current.id,
        taskId: current.taskId,
        label: label.trim(),
        kind: current.kind,
        isRunning: current.isRunning,
        startedAt: current.startedAt,
        segmentStartedAt: current.segmentStartedAt,
        accumulatedMs: current.accumulatedMs,
        createdAt: current.createdAt,
      ),
    );
  }

  /// Clear the "recovered" badge without changing the stopwatch.
  void acknowledgeRecovery() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      TimerState(session: current.session, now: DateTime.now()),
    );
  }
}

final timerProvider = AsyncNotifierProvider<TimerController, TimerState>(
  TimerController.new,
);
