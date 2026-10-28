/// Stable shell destinations. Keeping these as plain integers lets states and
/// deep links refer to a section without importing the widget layer.
class NavTarget {
  NavTarget._();

  static const today = 0;
  static const planner = 1;
  static const calendar = 2;
  static const journal = 3;
  static const focus = 4;
  static const insights = 5;
  static const categories = 6;
  static const settings = 7;
  static const nearby = 8;

  static const all = [
    today,
    planner,
    calendar,
    journal,
    focus,
    insights,
    categories,
    settings,
    nearby,
  ];
}

class NavLabels {
  NavLabels._();

  static const titles = <int, String>{
    NavTarget.today: 'Today',
    NavTarget.planner: 'Planner',
    NavTarget.calendar: 'Calendar',
    NavTarget.journal: 'Journal',
    NavTarget.focus: 'Focus',
    NavTarget.insights: 'Insights',
    NavTarget.categories: 'Categories',
    NavTarget.settings: 'Settings',
    NavTarget.nearby: 'Nearby',
  };

  static String title(int index) => titles[index] ?? 'Daymark';

  /// A short, quiet caption used by the mobile header. Desktop navigation has
  /// room for grouping labels; the phone header gets one line of context.
  static const subtitles = <int, String>{
    NavTarget.today: 'Your day at a glance',
    NavTarget.planner: 'Shape the day',
    NavTarget.calendar: 'Time, at a glance',
    NavTarget.journal: 'Write it down',
    NavTarget.focus: 'One thing at a time',
    NavTarget.insights: 'The honest mirror',
    NavTarget.categories: 'Keep the ledger tidy',
    NavTarget.settings: 'Make it yours',
    NavTarget.nearby: 'Move between devices',
  };

  static String subtitle(int index) =>
      subtitles[index] ?? 'Private work ledger';
}
