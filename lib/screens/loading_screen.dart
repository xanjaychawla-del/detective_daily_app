import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../case_repository/case_repository_providers.dart';
import 'case_list_screen.dart';

/// Shown on launch while the player is signed in as a guest and the case
/// list is prefetched from Supabase, so the Case Files screen appears with
/// data already in hand instead of its own spinner. Enforces a short
/// minimum display time so it doesn't just flash by on a fast connection.
///
/// Both steps are network calls with a timeout and a visible retry state --
/// this is deliberately kept out of main(), since awaiting a network call
/// there before runApp() meant a single slow/unreachable network at launch
/// left the screen permanently blank with nothing ever drawn.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final stopwatch = Stopwatch()..start();
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        await auth.signInAnonymously().timeout(const Duration(seconds: 10));
      }
      await ref.read(caseListProvider.future).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not connect. Check your internet connection and try again.');
      }
      return;
    }

    final remaining = const Duration(milliseconds: 900) - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CaseListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/dd_loading.png', fit: BoxFit.cover),
          if (_error != null)
            Container(
              color: Colors.black87,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
