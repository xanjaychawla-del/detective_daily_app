import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../truth_engine/models.dart';
import 'case_repository_service.dart';
import 'device_id_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final caseRepositoryServiceProvider = Provider<CaseRepositoryService>(
  (ref) => CaseRepositoryService(ref.watch(supabaseClientProvider)),
);

final deviceIdServiceProvider = Provider<DeviceIdService>((ref) => DeviceIdService());

final deviceIdProvider = FutureProvider<String>(
  (ref) => ref.watch(deviceIdServiceProvider).getOrCreateDeviceId(),
);

class CaseListEntry {
  final Case theCase;
  final PlayStatus status;

  const CaseListEntry({required this.theCase, required this.status});
}

final caseListProvider = FutureProvider<List<CaseListEntry>>((ref) async {
  final repo = ref.watch(caseRepositoryServiceProvider);
  final deviceId = await ref.watch(deviceIdProvider.future);
  final cases = await repo.fetchCases();
  final statuses = await repo.fetchPlayStatuses(deviceId);
  return [
    for (final theCase in cases)
      CaseListEntry(theCase: theCase, status: statuses[theCase.id] ?? PlayStatus.unopened),
  ];
});
