import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'screens/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  // Every player is signed in as a guest so their case progress is tracked
  // against a real Supabase identity (auth.uid()) rather than a locally
  // generated id that resets on reinstall. Registration/upgrade from guest
  // is a later phase -- this just establishes the identity now.
  if (Supabase.instance.client.auth.currentSession == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }
  runApp(const ProviderScope(child: DetectiveDailyApp()));
}

class DetectiveDailyApp extends StatelessWidget {
  const DetectiveDailyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detective Daily',
      debugShowCheckedModeBanner: false,
      theme: buildDetectiveDailyTheme(),
      home: const LoadingScreen(),
    );
  }
}
