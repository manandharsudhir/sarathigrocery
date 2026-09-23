import 'package:flutter/foundation.dart';

/// Where non-fatal errors (failed syncs, rejected writes) go. Defaults to
/// the console; `main.dart` points it at Crashlytics. A plain function so
/// the data layer doesn't depend on any particular monitoring vendor.
void Function(Object error, StackTrace? stack, String context) reportError =
    (error, stack, context) => debugPrint('$context: $error');
