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
}
