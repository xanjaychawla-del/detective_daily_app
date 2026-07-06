import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is telemetry-only. If it fails to initialize for any reason
  // (misconfigured native project, a platform-specific quirk we haven't
  // hit in testing), the app must still boot and be fully playable
  // without it -- analytics/crash-reporting should never be a single
  // point of failure for the app even starting.
  var firebaseAvailable = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    firebaseAvailable = true;
  } catch (err, stack) {
    debugPrint('Firebase failed to initialize, continuing without it: $err\n$stack');
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  // Anonymous sign-in is a network call and belongs in LoadingScreen (with
  // a timeout and a visible retry state), not here -- awaiting it in main()
  // meant a single slow/unreachable network at startup left the screen
  // completely blank forever, since runApp() never got a chance to fire.
  runApp(ProviderScope(child: DetectiveDailyApp(firebaseAvailable: firebaseAvailable)));
}

class DetectiveDailyApp extends StatelessWidget {
  final bool firebaseAvailable;

  const DetectiveDailyApp({super.key, required this.firebaseAvailable});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detective Daily',
      debugShowCheckedModeBanner: false,
      theme: buildDetectiveDailyTheme(),
      navigatorObservers: [
        if (firebaseAvailable) FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: const LoadingScreen(),
    );
  }
}
