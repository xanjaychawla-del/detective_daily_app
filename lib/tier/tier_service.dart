import 'package:supabase_flutter/supabase_flutter.dart';

enum UserTier { free, lite, premium }

UserTier _tierFromDb(String value) => switch (value) {
      'lite' => UserTier.lite,
      'premium' => UserTier.premium,
      _ => UserTier.free,
    };

String _tierToDb(UserTier tier) => switch (tier) {
      UserTier.free => 'free',
      UserTier.lite => 'lite',
      UserTier.premium => 'premium',
    };

/// Per-tier limits on new cases. `dailyNewCaseCap` is null for unlimited.
/// `getNewCaseAlwaysVisible` -- Free/Lite only surface "Get New Case" once
/// the New tab is empty (play what's already waiting first); Premium always
/// shows it.
class TierLimits {
  final int? dailyNewCaseCap;
  final bool getNewCaseAlwaysVisible;
  const TierLimits({required this.dailyNewCaseCap, required this.getNewCaseAlwaysVisible});
}

const kGuestSolvedCap = 3;

const Map<UserTier, TierLimits> kTierLimits = {
  UserTier.free: TierLimits(dailyNewCaseCap: 1, getNewCaseAlwaysVisible: false),
  UserTier.lite: TierLimits(dailyNewCaseCap: 3, getNewCaseAlwaysVisible: false),
  UserTier.premium: TierLimits(dailyNewCaseCap: null, getNewCaseAlwaysVisible: true),
};

/// Reads/writes the tier-gating state: whether the current user is a guest
/// (anonymous Supabase session, never given a profiles row) or registered
/// (has a profiles row with a tier), and how many cases they've
/// solved/opened against their limit.
class TierGateService {
  TierGateService(this._client);

  final SupabaseClient _client;

  bool get isGuest => _client.auth.currentUser?.isAnonymous ?? true;

  Future<UserTier> fetchTier() async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client.from('profiles').select('tier').eq('user_id', userId).maybeSingle();
    if (row == null) return UserTier.free;
    return _tierFromDb(row['tier'] as String);
  }

  Future<void> createProfile(UserTier tier) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('profiles').upsert({'user_id': userId, 'tier': _tierToDb(tier)});
  }

  Future<int> guestSolvedCount() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client.from('plays').select('id').eq('user_id', userId).eq('status', 'solved');
    return (rows as List).length;
  }

  /// Logs a tap on "Select Lite"/"Select Premium" so demand for the
  /// not-yet-purchasable tiers can be measured. Best-effort -- never
  /// blocks showing the "not available yet" dialog.
  Future<void> logTierInterest(UserTier tier) async {
    try {
      final userId = _client.auth.currentUser!.id;
      await _client.from('tier_interest').insert({'user_id': userId, 'tier': _tierToDb(tier)});
    } catch (_) {
      // Non-critical telemetry -- swallow failures.
    }
  }

  Future<int> newCasesOpenedToday() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client.from('plays').select('opened_at').eq('user_id', userId);
    final now = DateTime.now();
    bool isToday(DateTime dt) => dt.year == now.year && dt.month == now.month && dt.day == now.day;
    return (rows as List).where((row) {
      final raw = (row as Map<String, dynamic>)['opened_at'] as String?;
      if (raw == null) return false;
      return isToday(DateTime.parse(raw).toLocal());
    }).length;
  }

  /// Links the current anonymous guest session to an OAuth identity,
  /// preserving the same user id (and therefore their existing play
  /// history/ratings). Completes asynchronously via browser redirect --
  /// call [createProfile] once `auth.currentUser!.isAnonymous` flips to
  /// false (see the app's onAuthStateChange listener). Each provider needs
  /// its own OAuth client configured in Supabase's Auth providers before
  /// it actually works end to end.
  Future<void> registerWithProvider(OAuthProvider provider) async {
    await _client.auth.linkIdentity(
      provider,
      redirectTo: 'io.supabase.detectivedaily://login-callback',
    );
  }

  /// Passwordless upgrade path: attaches [email] to the current anonymous
  /// session and sends a confirmation link. Clicking it confirms the
  /// email and flips `is_anonymous` to false, same as an OAuth link.
  Future<void> registerWithEmail(String email) async {
    await _client.auth.updateUser(
      UserAttributes(email: email),
      emailRedirectTo: 'io.supabase.detectivedaily://login-callback',
    );
  }

  /// Permanently deletes the signed-in user's account and all owned data
  /// (profile, plays, tier interest) via the delete-account Edge Function,
  /// then signs out locally (which drops back to a fresh anonymous
  /// session on next launch). There is no undo -- the caller is
  /// responsible for confirming with the user first.
  Future<void> deleteAccount() async {
    final response = await _client.functions.invoke('delete-account');
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final error = data is Map ? data['error'] : 'unknown_error';
      throw Exception('Account deletion failed: $error');
    }
    await _client.auth.signOut();
  }
}
