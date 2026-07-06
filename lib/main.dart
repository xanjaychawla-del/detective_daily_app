import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'screens/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
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
