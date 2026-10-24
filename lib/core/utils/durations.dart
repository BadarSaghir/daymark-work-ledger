/// Formatting helpers for clocks, timers, and human durations.
library;

String _two(int value) => value.toString().padLeft(2, '0');

/// `MM:SS`, or `HH:MM:SS` when [alwaysHours] is true or the duration is an
/// hour or longer. Hours can grow beyond 99 without breaking the layout.
String formatClock(Duration duration, {bool alwaysHours = false}) {
  final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (alwaysHours || hours > 0) {
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }
  return '${_two(minutes)}:${_two(seconds)}';
}

/// Always `HH:MM:SS`. Intended for the stopwatch face.
String formatStopwatch(Duration duration) {
  final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  return '${_two(total ~/ 3600)}:${_two((total % 3600) ~/ 60)}:${_two(total % 60)}';
}

/// `2h 40m`, `45m`, `<1m`.
String formatCompact(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes <= 0) {
    return duration.inSeconds > 0 ? '<1m' : '0m';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}

/// Compact duration from milliseconds.
String formatCompactMs(int milliseconds) =>
    formatCompact(Duration(milliseconds: milliseconds));

/// `2h 40m` with a `0m` fallback.
String formatMinutes(int? minutes) {
  if (minutes == null) return '—';
  return formatCompact(Duration(minutes: minutes));
}

/// `25 pts`, `12.4 pts`, `1 pt`.
String formatPoints(double points) {
  final rounded = (points * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text ${rounded == 1 ? 'pt' : 'pts'}';
}

/// A short label for autosave states.
String savedLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Not saved yet';
  final seconds = now.difference(at).inSeconds;
  if (seconds < 10) return 'Saved just now';
  if (seconds < 60) return 'Saved ${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return 'Saved ${minutes}m ago';
  return 'Saved ${now.difference(at).inHours}h ago';
}

/// `+18%`, `−7%`, `0%`.
String formatDelta(double ratio) {
  if (ratio.abs() < 0.005) return '0%';
  final percent = (ratio * 100).round();
  return percent > 0 ? '+$percent%' : '−${percent.abs()}%';
}
