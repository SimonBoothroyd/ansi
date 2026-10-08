/// The browser's alarm surfaces over `package:web`; see `browser_alarm.dart`.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get browserTabHidden => web.document.hidden;

Future<bool> askBrowserNotifications() async {
  try {
    if (web.Notification.permission == 'granted') return true;
    if (web.Notification.permission == 'denied') return false;
    final answer = await web.Notification.requestPermission().toDart;
    return answer.toDart == 'granted';
    // A browser without the API, or one that refuses outside a gesture.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return false;
  }
}

void showBrowserNotification({required String title, required String body}) {
  try {
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
    // Chrome on Android only shows notifications through a service worker,
    // and throws here; the tab's own chime and title still say it.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {}
}
