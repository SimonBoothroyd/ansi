/// The browser's own alarm surfaces, which only exist on the web. This is the
/// stub every other platform compiles; `browser_alarm_web.dart` is the real
/// one, chosen by the conditional import in `local_timer_platform.dart`.
library;

/// Whether the tab is out of sight, where only a notification can be seen.
bool get browserTabHidden => false;

/// Asks the browser for notifications. True once granted.
Future<bool> askBrowserNotifications() async => false;

/// Shows one notification, if the browser has granted them.
void showBrowserNotification({required String title, required String body}) {}
