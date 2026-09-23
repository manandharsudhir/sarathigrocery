import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/app.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/firestore_remote_store.dart';
import 'package:sarathigrocery/core/services/error_reporter.dart' as errors;
import 'package:sarathigrocery/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:sarathigrocery/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crashlytics has no web SDK; there errors stay on the console.
  if (!kIsWeb) {
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
    errors.reportError = (error, stack, context) {
      debugPrint('$context: $error');
      crashlytics.recordError(error, stack, reason: context);
    };
  }

  // The only line that picks the backend — swap these two for your own.
  runApp(SarathiGroceryApp(scope: AppScope(store: FirestoreRemoteStore(), authRepository: FirebaseAuthRepository())));
}
