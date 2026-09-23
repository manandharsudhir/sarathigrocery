import 'package:flutter/foundation.dart';

/// A cross-feature "something changed, please rebuild" pulse.
///
/// Each feature owns its own data and its own [ChangeNotifier] controller,
/// but a few widgets (mainly dashboards) show aggregates that span several
/// features — e.g. the notification bell badge, or "today's sales" next to
/// "low stock count". Controllers call [ping] after any mutation that other
/// screens might care about; widgets that need cross-feature reactivity
/// listen to [instance] in addition to their own feature's controller.
///
/// This carries no data of its own — it only signals "read fresh state".
class AppSignal extends ChangeNotifier {
  AppSignal._();

  static final AppSignal instance = AppSignal._();

  void ping() => notifyListeners();
}
