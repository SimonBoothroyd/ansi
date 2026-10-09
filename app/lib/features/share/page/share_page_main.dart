/// The share page's one bundle, compiled to JS with `make share-bundle`: the
/// renderer for the server, and the stepper and timers for the browser.
///
/// On the server (the edge function, which has no document) it only exports
/// `ansiSharePage(payloadJson, url, bundleUrl)`, the whole document as a
/// string. In a browser it also wires the page: the page arrives whole from
/// the server, so it reads without this script; the script only makes the
/// stepper and the timers move. It re-renders
/// through the same [renderShareBody] the server used, from the payload the
/// page embeds, so the browser cannot disagree with the server about a number.
///
/// A timer is held by its end time, never a ticking count, as the app holds
/// one: a phone that slept reads the right number when it wakes. Timers are
/// keyed by their place in the page, which re-rendering at new servings keeps.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../timers/domain/cook_timer.dart';
import 'share_page.dart';
import 'share_payload.dart';

@JS('ansiSharePage')
external set _exportPage(JSFunction render);

void main() {
  _exportPage = ((JSString payloadJson, JSString url, JSString bundleUrl) {
    final payload = payloadJson.toDart;
    return renderSharePage(
      ShareTree.fromPayload(
        (jsonDecode(payload) as Map).cast<String, Object?>(),
      ),
      url: url.toDart,
      bundleUrl: bundleUrl.toDart,
      payloadJson: payload,
    ).toJS;
  }).toJS;
  if (!globalContext.has('document')) return;

  final data = web.document.getElementById('ansi-share-data');
  final main = web.document.getElementById('ansi-share');
  if (data == null || main == null) return;
  final ShareTree tree;
  try {
    tree = ShareTree.fromPayload(
      (jsonDecode(data.textContent ?? '') as Map).cast<String, Object?>(),
    );
  } on Object {
    // The served page is already whole; without its data it simply holds
    // still.
    return;
  }
  _Page(tree, main).listen();
}

class _Page {
  _Page(this.tree, this.main);

  final ShareTree tree;
  final web.Element main;

  /// End times of the running timers, by their place among the page's timers.
  final _ends = <int, DateTime>{};
  final _rung = <int>{};
  int? _ticker;

  void listen() {
    main.addEventListener(
      'click',
      ((web.Event event) {
        final target = event.target;
        if (target == null || !target.isA<web.Element>()) return;
        final button = (target as web.Element).closest('button');
        if (button == null) return;
        final servings = button.getAttribute('data-servings');
        if (servings != null) {
          _rescale(double.tryParse(servings));
        } else if (button.classList.contains('timer')) {
          _toggle(button);
        }
      }).toJS,
    );
  }

  void _rescale(double? servings) {
    if (servings == null || servings < 1) return;
    main.innerHTML = renderShareBody(tree, servings).toJS;
    _paint();
  }

  List<web.Element> get _timers {
    final found = main.querySelectorAll('button.timer');
    return [
      for (var i = 0; i < found.length; i++) found.item(i)! as web.Element,
    ];
  }

  void _toggle(web.Element button) {
    final index = _timers.indexOf(button);
    if (index < 0) return;
    if (_ends.remove(index) != null) {
      // A second tap stops it, ringing or not.
      _rung.remove(index);
    } else {
      final seconds = int.tryParse(button.getAttribute('data-seconds') ?? '');
      if (seconds == null) return;
      _ends[index] = DateTime.now().add(Duration(seconds: seconds));
    }
    _paint();
    if (_ends.isEmpty) {
      if (_ticker case final id?) web.window.clearInterval(id);
      _ticker = null;
    } else {
      _ticker ??= web.window.setInterval(_paint.toJS, 250.toJS);
    }
  }

  void _paint() {
    final now = DateTime.now();
    final timers = _timers;
    for (var i = 0; i < timers.length; i++) {
      final button = timers[i];
      final label = button.getAttribute('data-label') ?? button.textContent;
      button.setAttribute('data-label', label ?? '');
      final end = _ends[i];
      if (end == null) {
        button
          ..textContent = label
          ..classList.remove('running')
          ..classList.remove('due');
        continue;
      }
      final left = end.difference(now);
      final running = !left.isNegative;
      button
        ..textContent = formatTimerClock(left)
        ..classList.toggle('running', running)
        ..classList.toggle('due', !running);
      if (!running && _rung.add(i)) {
        web.window.navigator.vibrate(
          [400, 200, 400].map((n) => n.toJS).toList().toJS,
        );
      }
    }
  }
}
