import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sankalp_reminder_scheduler.dart';

final _notificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

final sankalpReminderSchedulerProvider = Provider<SankalpReminderScheduler>(
  (ref) => SankalpReminderScheduler(ref.watch(_notificationsPluginProvider)),
);
