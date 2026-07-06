import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../case_repository/case_repository_providers.dart';
import 'case_list_screen.dart';

/// Shown on launch while the case list is prefetched from Supabase, so the
/// Case Files screen appears with data already in hand instead of its own
/// spinner. Enforces a short minimum display time so it doesn't just flash
/// by on a fast connection.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    try {
      await ref.read(caseListProvider.future);
    } catch (_) {
      // Ignore -- CaseListScreen shows its own error state if this fails.
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
      body: SizedBox.expand(
        child: Image.asset('assets/images/dd_loading.png', fit: BoxFit.cover),
      ),
    );
  }
}
