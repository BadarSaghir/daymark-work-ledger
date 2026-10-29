import 'package:flutter/material.dart';

import '../features/notifications/notifications_page.dart';
import '../features/task/task_detail_page.dart';

Future<void> openTaskDetail(BuildContext context, String taskId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: taskId)),
  );
}

Future<void> openNotifications(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NotificationsPage()));
}
