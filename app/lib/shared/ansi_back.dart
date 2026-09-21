/// The back rule for a pushed page.
///
/// With something under the page, pop. With nothing under it (a cold deep
/// link, or an arrival by `go`), `context.pop()` throws inside the pointer
/// handler and the chevron does nothing, so go to the page's home instead.
/// Held by `test/shared/ansi_back_test.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'guarded_navigation.dart';

/// Leaves a pushed page: pops what is under it, or goes [home] when nothing is.
///
/// [home] is what the page is a detail of: the branch root, the manager it is
/// a row of, the thing being edited, or the referring tab where the page
/// knows it. [result] is what the pop carries; it is dropped in the [home]
/// case. The fallback goes through [GuardedNavigation.goOnce].
void ansiBack(BuildContext context, {String home = '/', Object? result}) {
  if (context.canPop()) {
    context.pop(result);
    return;
  }
  context.goOnce(home);
}
