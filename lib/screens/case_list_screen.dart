import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../case_repository/case_repository_providers.dart';
import '../case_repository/case_repository_service.dart';
import '../game_engine/game_state.dart';
import 'home_shell.dart';

/// The app's launch screen: every case (authored + AI-generated) with its
/// play status, plus the "Get New Case" action that has the AI author a
/// brand-new case and persist it to Supabase.
class CaseListScreen extends ConsumerStatefulWidget {
  const CaseListScreen({super.key});

  @override
  ConsumerState<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends ConsumerState<CaseListScreen> {
  bool _generating = false;

  Future<void> _openCase(CaseListEntry entry) async {
    if (entry.status == PlayStatus.unopened) {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref
          .read(caseRepositoryServiceProvider)
          .setPlayStatus(deviceId, entry.theCase.id, PlayStatus.inProgress);
      ref.invalidate(caseListProvider);
    }
    ref.read(caseProvider.notifier).state = entry.theCase;
    ref.read(homeTabIndexProvider.notifier).state = 0;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeShell()));
    ref.invalidate(caseListProvider);
  }

  Future<void> _getNewCase() async {
    setState(() => _generating = true);
    try {
      final newCase = await ref.read(caseRepositoryServiceProvider).generateNewCase();
      ref.invalidate(caseListProvider);
      final entries = await ref.read(caseListProvider.future);
      final entry = entries.firstWhere((e) => e.theCase.id == newCase.id);
      if (!mounted) return;
      await _openCase(entry);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate a new case: $err')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final casesAsync = ref.watch(caseListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detective Daily')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: casesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Could not load cases: $err')),
                data: (entries) => entries.isEmpty
                    ? const Center(child: Text('No cases yet.'))
                    : RefreshIndicator(
                        onRefresh: () async => ref.invalidate(caseListProvider),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: entries.length,
                          itemBuilder: (context, index) => _CaseCard(
                            entry: entries[index],
                            onTap: () => _openCase(entries[index]),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _getNewCase,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_generating ? 'Generating case...' : 'Get New Case'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final CaseListEntry entry;
  final VoidCallback onTap;

  const _CaseCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theCase = entry.theCase;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        title: Text(theCase.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            theCase.briefing,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: _StatusPill(status: entry.status),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final PlayStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PlayStatus.solved => ('Solved', Colors.green),
      PlayStatus.gaveUp => ('Unsolved', Colors.orange),
      PlayStatus.inProgress => ('Unsolved', Colors.orange),
      PlayStatus.unopened => ('Unopened', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
