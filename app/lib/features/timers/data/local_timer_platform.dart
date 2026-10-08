/// [TimerPlatform] on this device.
///
/// On a phone a timer rings through a **local notification** scheduled for
/// its end when it starts, so the app need not be awake: Android repeats the
/// sound for a minute ([kTimerRingFor]) and carries one ongoing notification
/// counting the soonest timer down; iOS sounds it once and the app chimes
/// over it while open. A notification's Stop and +1 min open the app, so
/// they act on the one set of timers rather than a second copy in a
/// background isolate.
///
/// On the web there is nothing to schedule: the tab chimes, and a hidden tab
/// shows a browser notification as a timer falls due.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/sync/device_prefs.dart';
import '../domain/cook_timer.dart';
import '../domain/timer_platform.dart';
import 'browser_alarm.dart'
    if (dart.library.js_interop) 'browser_alarm_web.dart';

/// The notification that counts the soonest timer down (Android).
const _ongoingId = 1;

const _dueChannel = 'ansi_timer_due';
const _runningChannel = 'ansi_timer_running';
const _darwinCategory = 'ansi_timer';
const _stopAction = 'stop';
const _addAction = 'add_minute';

/// Android's `Notification.FLAG_INSISTENT`: the sound repeats until the
/// notification is answered or withdrawn.
const _flagInsistent = 4;

class LocalTimerPlatform implements TimerPlatform {
  final _notifications = FlutterLocalNotificationsPlugin();
  AudioPlayer? _player;
  bool _ready = false;
  bool _androidGranted = false;

  /// The timer ids the last [sync] knew, so a stopped one is withdrawn.
  Set<String> _known = const {};

  /// The end each running timer is scheduled for, so an unchanged one is
  /// not scheduled again every sync.
  final Map<String, DateTime> _scheduled = {};

  String? _ongoing;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Where notifications are scheduled at all.
  bool get _schedules => _android || _ios;

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get ringsItself => _android && _androidGranted;

  @override
  Future<void> init({
    required void Function(TimerAction action) onAction,
  }) async {
    if (!_schedules || _ready) return;
    void answer(NotificationResponse response) {
      final id = response.payload;
      if (id == null) return;
      onAction(
        TimerAction(switch (response.actionId) {
          _stopAction => TimerActionKind.stop,
          _addAction => TimerActionKind.addMinute,
          _ => TimerActionKind.open,
        }, id),
      );
    }

    await _guard(() async {
      await _notifications.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_timer'),
          iOS: DarwinInitializationSettings(
            // Asked on the first timer instead ([askOnce]).
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
            notificationCategories: [
              DarwinNotificationCategory(
                _darwinCategory,
                actions: [
                  DarwinNotificationAction.plain(
                    _addAction,
                    '+1 min',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                  DarwinNotificationAction.plain(
                    _stopAction,
                    'Stop',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: answer,
      );
      _ready = true;
      await _refreshGranted();
      final launch = await _notifications.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        answer(response);
      }
    });
  }

  @override
  Future<void> askOnce() async {
    final prefs = await SharedPreferences.getInstance();
    const key = '${DevicePrefs.timerAlarmPrefix}notifications_asked';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (kIsWeb) {
      await askBrowserNotifications();
      return;
    }
    await _guard(() async {
      if (_android) {
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.requestNotificationsPermission();
        // Without it Android may hold a timer's ring back by minutes.
        if (!(await android?.canScheduleExactNotifications() ?? true)) {
          await android?.requestExactAlarmsPermission();
        }
        await _refreshGranted();
      } else if (_ios) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      }
    });
  }

  Future<void> _refreshGranted() async {
    if (!_android) return;
    _androidGranted =
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        false;
  }

  @override
  Future<void> sync(List<CookTimer> timers, DateTime now) async {
    if (!_schedules || !_ready) return;
    await _guard(() async {
      // Notifications can be turned off in settings at any time; when they
      // are, the app chimes for itself.
      await _refreshGranted();
      final ids = {for (final t in timers) t.id};
      for (final gone in _known.difference(ids)) {
        _scheduled.remove(gone);
        await _notifications.cancel(id: notificationIdFor(gone));
      }
      _known = ids;
      for (final t in timers) {
        final state = t.stateAt(now);
        if (state == CookTimerState.running) {
          if (_scheduled[t.id] != t.endsAt) await _schedule(t);
        } else if (state == CookTimerState.paused &&
            _scheduled.containsKey(t.id)) {
          _scheduled.remove(t.id);
          await _notifications.cancel(id: notificationIdFor(t.id));
        }
        // A due timer's notification has fired: it stays until stopped.
      }
      if (_android) await _showOngoing(timers, now);
    });
  }

  Future<void> _schedule(CookTimer timer) async {
    final endsAt = timer.endsAt!;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    await _notifications.zonedSchedule(
      id: notificationIdFor(timer.id),
      scheduledDate: tz.TZDateTime.from(endsAt.toUtc(), tz.UTC),
      title: 'Step ${timer.step + 1} is done',
      body: timer.recipeTitle,
      payload: timer.id,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _dueChannel,
          'Timer done',
          channelDescription: 'A kitchen timer reaching zero.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          additionalFlags: Int32List.fromList([_flagInsistent]),
          // The ring is a minute; the timer stays due in the app after.
          timeoutAfter: kTimerRingFor.inMilliseconds,
          actions: const [
            AndroidNotificationAction(
              _addAction,
              '+1 min',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              _stopAction,
              'Stop',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _darwinCategory,
          // In the foreground the app chimes for the whole minute instead.
          presentSound: false,
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
    );
    _scheduled[timer.id] = endsAt;
  }

  /// One quiet notification while anything runs, counting the soonest down
  /// with Android's own chronometer, so the number is right while the app
  /// sleeps without the app drawing it.
  Future<void> _showOngoing(List<CookTimer> timers, DateTime now) async {
    final live = [
      for (final t in dockOrder(timers, now))
        if (!t.paused) t,
    ];
    if (live.isEmpty) {
      if (_ongoing != null) await _notifications.cancel(id: _ongoingId);
      _ongoing = null;
      return;
    }
    final first = live.first;
    final title = live.length == 1
        ? first.recipeTitle
        : '${live.length} timers running';
    final body = live.length == 1
        ? 'Step ${first.step + 1}'
        : '${first.recipeTitle} · step ${first.step + 1}';
    final key = '$title|$body|${first.endsAt}';
    if (key == _ongoing) return;
    _ongoing = key;
    await _notifications.show(
      id: _ongoingId,
      title: title,
      body: body,
      payload: first.id,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _runningChannel,
          'Timers running',
          channelDescription: 'The kitchen timers counting down.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          usesChronometer: true,
          chronometerCountDown: true,
          when: first.endsAt!.millisecondsSinceEpoch,
        ),
      ),
    );
  }

  @override
  Future<void> announceDue(CookTimer timer) async {
    if (!kIsWeb || !browserTabHidden) return;
    showBrowserNotification(
      title: 'Step ${timer.step + 1} is done',
      body: timer.recipeTitle,
    );
  }

  @override
  Future<void> chime() => _guard(() async {
    final player = _player ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('sounds/timer_chime.wav'));
  });

  @override
  Future<void> hush() => _guard(() async => _player?.stop());

  @override
  Future<void> buzz() => _guard(HapticFeedback.heavyImpact);

  @override
  Future<void> keepAwake({required bool on}) =>
      _guard(() => WakelockPlus.toggle(enable: on));

  /// A device surface that fails must not take a timer with it: the count on
  /// screen is the timer, and it carries on regardless.
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
      // Plugins throw platform, state and argument errors alike; every one
      // is reported and none reaches the cook.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      debugPrint('timer platform: $error\n$stack');
    }
  }
}

/// A notification id for a timer: stable across launches, which
/// `String.hashCode` is not promised to be. FNV-1a, kept clear of the
/// ongoing notification's id.
@visibleForTesting
int notificationIdFor(String timerId) {
  var hash = 0x811c9dc5;
  for (final unit in timerId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return 1000 + (hash & 0x3fffffff);
}
