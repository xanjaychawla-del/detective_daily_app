import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing/purchase_listener.dart';
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

  // Anonymous sign-in is a network call and belongs in LoadingScreen (with
  // a timeout and a visible retry state), not here -- awaiting it in main()
  // meant a single slow/unreachable network at startup left the screen
  // completely blank forever, since runApp() never got a chance to fire.
  //
  // Supabase.initialize() itself is a fast, local-only call *unless*
  // supabaseUrl/supabaseAnonKey are missing (e.g. a build that forgot to
  // pass --dart-define), in which case it throws immediately -- this must
  // never be a silent, undebuggable blank screen, so it's surfaced as a
  // real error screen instead of letting the exception escape main().
  String? bootstrapError;
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  } catch (err) {
    bootstrapError = 'Failed to initialize backend: $err';
  }

  runApp(
    ProviderScope(
      child: DetectiveDailyApp(firebaseAvailable: firebaseAvailable, bootstrapError: bootstrapError),
    ),
  );
}

class DetectiveDailyApp extends ConsumerStatefulWidget {
  final bool firebaseAvailable;
  final String? bootstrapError;

  const DetectiveDailyApp({super.key, required this.firebaseAvailable, this.bootstrapError});

  @override
  ConsumerState<DetectiveDailyApp> createState() => _DetectiveDailyAppState();
}

class _DetectiveDailyAppState extends ConsumerState<DetectiveDailyApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  PurchaseListener? _purchaseListener;

  @override
  void initState() {
    super.initState();
    // Subscribed here, at the app root, rather than from any one screen --
    // see PurchaseListener's doc comment for why that matters (a purchase
    // can be redelivered on a fresh launch, independent of which screen is
    // showing). Only meaningful once Supabase actually initialized.
    if (widget.bootstrapError == null) {
      _purchaseListener = PurchaseListener(ref, _messengerKey)..start();
    }
  }

  @override
  void dispose() {
    _purchaseListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detective Daily',
      debugShowCheckedModeBanner: false,
      theme: buildDetectiveDailyTheme(),
      scaffoldMessengerKey: _messengerKey,
      navigatorObservers: [
        if (widget.firebaseAvailable) FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: widget.bootstrapError == null
          ? const LoadingScreen()
          : Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.bootstrapError!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }
}
