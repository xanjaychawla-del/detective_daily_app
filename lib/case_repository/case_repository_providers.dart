import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../truth_engine/models.dart';
import 'case_repository_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final caseRepositoryServiceProvider = Provider<CaseRepositoryService>(
  (ref) => CaseRepositoryService(ref.watch(supabaseClientProvider)),
);

class CaseListEntry {
  final Case theCase;
  final PlayStatus status;
  final CaseRatingStats? ratingStats;

  const CaseListEntry({required this.theCase, required this.status, this.ratingStats});
}

final caseListProvider = FutureProvider<List<CaseListEntry>>((ref) async {
  final repo = ref.watch(caseRepositoryServiceProvider);
  final cases = await repo.fetchCases();
  final statuses = await repo.fetchPlayStatuses();
  final ratingStats = await repo.fetchRatingStats();
  return [
    for (final theCase in cases)
      CaseListEntry(
        theCase: theCase,
        status: statuses[theCase.id] ?? PlayStatus.unopened,
        ratingStats: ratingStats[theCase.id],
      ),
  ];
});
