import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../case_repository/case_repository_providers.dart';
import 'tier_service.dart';

final tierGateServiceProvider = Provider<TierGateService>(
  (ref) => TierGateService(ref.watch(supabaseClientProvider)),
);

/// Null while guest (no profile row); non-null once registered.
final userTierProvider = FutureProvider<UserTier?>((ref) async {
  final service = ref.watch(tierGateServiceProvider);
  if (service.isGuest) return null;
  return service.fetchTier();
});

final guestSolvedCountProvider = FutureProvider<int>((ref) {
  return ref.watch(tierGateServiceProvider).guestSolvedCount();
});

final newCasesOpenedTodayProvider = FutureProvider<int>((ref) {
  return ref.watch(tierGateServiceProvider).newCasesOpenedToday();
});
