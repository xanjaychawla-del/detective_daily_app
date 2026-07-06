import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_engine/game_state.dart';
import 'screens/home_shell.dart';
import 'truth_engine/case_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cases = await Future.wait([
    loadCase('assets/cases/museum_diamond.json'),
    loadCase('assets/cases/flight_914.json'),
    loadCase('assets/cases/meridian_station.json'),
  ]);
  runApp(
    ProviderScope(
      overrides: [
        allCasesProvider.overrideWithValue(cases),
        caseProvider.overrideWith((ref) => cases.first),
      ],
      child: const DetectiveDailyApp(),
    ),
  );
}

class DetectiveDailyApp extends StatelessWidget {
  const DetectiveDailyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detective Daily',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}
