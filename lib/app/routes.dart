import 'package:flutter/material.dart';

import '../features/task/task_detail_page.dart';

Future<void> openTaskDetail(BuildContext context, String taskId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: taskId)),
  );
}
