import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../case_repository/case_repository_providers.dart';
import '../case_repository/case_repository_service.dart';
import '../core/theme.dart';
import '../game_engine/game_state.dart';
import 'home_shell.dart';

/// The app's launch screen: every case (authored + AI-generated) with its
/// play status, split across Unsolved/New/Archive tabs, plus the "Get New
/// Case" action that has the AI author a brand-new case and persist it to
/// Supabase.
class CaseListScreen extends ConsumerStatefulWidget {
  const CaseListScreen({super.key});

  @override
  ConsumerState<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends ConsumerState<CaseListScreen>
    with SingleTickerProviderStateMixin {
  bool _generating = false;
  bool _didPickInitialTab = false;
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Unsolved is the default tab, but an empty Unsolved list on first load
  // (a fresh player with nothing in progress yet) isn't a useful landing
  // spot -- send them to New instead. Only ever done once per screen
  // lifetime, so it doesn't yank the user back after they switch tabs.
  void _pickInitialTab(List<CaseListEntry> entries) {
    if (_didPickInitialTab) return;
    _didPickInitialTab = true;
    final hasUnsolved = entries.any(
      (e) => e.status == PlayStatus.inProgress || e.status == PlayStatus.gaveUp,
    );
    if (!hasUnsolved) _tabController.index = 1;
  }

  Future<void> _openCase(CaseListEntry entry) async {
    if (entry.status == PlayStatus.unopened) {
      await ref
          .read(caseRepositoryServiceProvider)
          .setPlayStatus(entry.theCase.id, PlayStatus.inProgress);
      ref.invalidate(caseListProvider);
    }
    ref.read(caseProvider.notifier).state = entry.theCase;
    ref.read(homeTabIndexProvider.notifier).state = 0;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HomeShell()));
    ref.invalidate(caseListProvider);
  }

  Future<void> _getNewCase() async {
    setState(() => _generating = true);
    try {
      final newCase = await ref
          .read(caseRepositoryServiceProvider)
          .generateNewCase();
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
      appBar: AppBar(
        title: const Text('Detective Daily - Case Files'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Unsolved'),
            Tab(text: 'New'),
            Tab(text: 'Archive'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: casesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) =>
                    Center(child: Text('Could not load cases: $err')),
                data: (entries) {
                  _pickInitialTab(entries);
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _CaseTab(
                        entries: entries
                            .where(
                              (e) =>
                                  e.status == PlayStatus.inProgress ||
                                  e.status == PlayStatus.gaveUp,
                            )
                            .toList(),
                        emptyMessage: 'No unsolved cases right now.',
                        onOpen: _openCase,
                        onRefresh: () async => ref.invalidate(caseListProvider),
                      ),
                      _CaseTab(
                        entries: entries
                            .where((e) => e.status == PlayStatus.unopened)
                            .toList(),
                        emptyMessage: 'No new cases waiting.',
                        onOpen: _openCase,
                        onRefresh: () async => ref.invalidate(caseListProvider),
                      ),
                      _CaseTab(
                        entries: entries
                            .where((e) => e.status == PlayStatus.solved)
                            .toList(),
                        emptyMessage: 'Solved cases will show up here.',
                        onOpen: _openCase,
                        onRefresh: () async => ref.invalidate(caseListProvider),
                      ),
                    ],
                  );
                },
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
                  label: Text(
                    _generating ? 'Generating case...' : 'Get New Case',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseTab extends StatelessWidget {
  final List<CaseListEntry> entries;
  final String emptyMessage;
  final void Function(CaseListEntry) onOpen;
  final Future<void> Function() onRefresh;

  const _CaseTab({
    required this.entries,
    required this.emptyMessage,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  emptyMessage,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        itemBuilder: (context, index) => _CaseCard(
          entry: entries[index],
          onTap: () => onOpen(entries[index]),
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
        title: Text(
          theCase.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                theCase.briefing,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (entry.ratingStats != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: kAccentAmber),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.ratingStats!.average.toStringAsFixed(1)} '
                      '(${entry.ratingStats!.count})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
      PlayStatus.unopened => ('New', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
